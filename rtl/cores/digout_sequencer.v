`timescale 1ns / 1ps
`default_nettype none

/**
 * @module digout_sequencer
 * @brief Programmable pulse sequences for 16 digital outputs (TDM on main_state).
 *
 * @param MODULE Hardware module ID matched against prog_module on programming writes.
 * @param ENABLE_EXTENDED_COMMANDS 1 = RHS (live commands, continuous mode); 0 = RHD legacy.
 *
 * @pre prog_channel, prog_address, prog_word, and prog_module are stable before each
 *      host ActivateTriggerIn on endpoint 0x42 bit 1 (prog_trig).
 * @pre command_strobe is a single-cycle pulse on dataclk while acquisition_running.
 * @post Config registers latch on prog_trig; digout
 *       clears on reset or when RHS acquisition_running is low.
 */
//////////////////////////////////////////////////////////////////////////////////
// Shared digital-output sequencer (RHD legacy + RHS extended via ENABLE_EXTENDED_COMMANDS).
// Optional paths are selected at elaboration time (generate), not runtime if (parameter).
//////////////////////////////////////////////////////////////////////////////////

module digout_sequencer #(
	parameter MODULE = 0,
	parameter [0:0] ENABLE_EXTENDED_COMMANDS = 1'b1
	)
	(
	input wire			reset,
	input wire			dataclk,
	input wire [31:0] main_state,
	input wire [5:0]	channel,
	input wire [3:0]  prog_channel,
	input wire [3:0]	prog_address,
	input wire [4:0]  prog_module,
	input wire [31:0] prog_word,
	input wire			prog_trig,
	input wire [31:0] triggers,
	input wire			command_strobe,
	input wire [6:0]	command_word,
	input wire			acquisition_running,
	input wire [7:0]	threshold_mode,
	output reg [15:0] digout,
	output wire [15:0] digout_enabled,
	output wire			command_accepted,
	input wire			shutdown,
	input wire			reset_sequencer,
	input wire			amp_maintenance
   );

	reg [31:0] counter[15:0];

	reg [4:0] trigger_source[15:0];
	reg [15:0] trigger_on_edge;
	reg [15:0] trigger_polarity;
	reg [15:0] trigger_enable;
	reg [15:0] manual_fire_trigger;

	reg [7:0] number_of_stim_pulses[15:0];
	reg [15:0] continuous_repeat;

	reg [15:0] waiting_for_trigger, waiting_for_edge;
	reg [15:0] continuous_running, fire_pending;
	reg [7:0] stim_counter[15:0];

	reg [31:0] event_start_stim[15:0];
	reg [31:0] event_end_stim[15:0];
	reg [31:0] event_repeat_stim[15:0];
	reg [31:0] event_end[15:0];

	assign digout_enabled = trigger_enable;

	localparam [2:0] CMD_MANUAL_HIGH   = 3'd0;
	localparam [2:0] CMD_MANUAL_LOW    = 3'd1;
	localparam [2:0] CMD_CONTINUOUS_ON = 3'd2;
	localparam [2:0] CMD_SEQUENCE_STOP = 3'd3;
	localparam [2:0] CMD_FIRE          = 3'd4;

	localparam [31:0] STATE_SYNC_A     = 32'd99;
	localparam [31:0] STATE_SYNC_B     = 32'd100;
	localparam [31:0] STATE_EVAL_TRIG  = 32'd102;
	localparam [31:0] STATE_PULSE_ON   = 32'd106;
	localparam [31:0] STATE_PULSE_OFF  = 32'd110;
	localparam [31:0] STATE_SHUTDOWN = 32'd114;
	localparam [31:0] STATE_ADVANCE   = 32'd118;

	localparam [3:0] REG_TRIG_CFG    = 4'd0;
	localparam [3:0] REG_PULSE_CFG   = 4'd1;
	localparam [3:0] REG_START_STIM  = 4'd4;
	localparam [3:0] REG_END_STIM    = 4'd7;
	localparam [3:0] REG_REPEAT_STIM = 4'd8;
	localparam [3:0] REG_EVENT_END   = 4'd13;

	reg [15:0] trigger_in;
	integer trig_i;

	always @(posedge dataclk) begin
		if (channel == 0 && (main_state == STATE_SYNC_A || main_state == STATE_SYNC_B)) begin
			for (trig_i = 0; trig_i < 16; trig_i = trig_i + 1) begin
				trigger_in[trig_i] <= triggers[trigger_source[trig_i]] ^ trigger_polarity[trig_i];
			end
		end
	end

	wire [3:0] addr;
	assign addr = channel[3:0];

	generate
		if (ENABLE_EXTENDED_COMMANDS) begin : gen_rhs

			wire [3:0] command_channel = command_word[3:0];
			wire [2:0] command_opcode = command_word[6:4];
			wire command_threshold_owned =
				(command_channel < 8) ? threshold_mode[command_channel] : 1'b0;
			wire continuous_start_eligible =
				trigger_enable[command_channel] &&
				continuous_repeat[command_channel] &&
				waiting_for_trigger[command_channel] &&
				!amp_maintenance && !command_threshold_owned;
			wire fire_eligible =
				trigger_enable[command_channel] &&
				manual_fire_trigger[command_channel] &&
				!continuous_repeat[command_channel] &&
				waiting_for_trigger[command_channel] &&
				!amp_maintenance && !command_threshold_owned;

			assign command_accepted =
				command_strobe && acquisition_running &&
				((command_opcode == CMD_SEQUENCE_STOP) ||
				 (command_opcode == CMD_CONTINUOUS_ON && continuous_start_eligible) ||
				 (command_opcode == CMD_FIRE && fire_eligible));

			always @(posedge prog_trig) begin
				if (prog_module == MODULE) begin
					case (prog_address)
						REG_TRIG_CFG: begin
							trigger_source[prog_channel] <= prog_word[4:0];
							trigger_on_edge[prog_channel] <= prog_word[5];
							trigger_polarity[prog_channel] <= prog_word[6];
							trigger_enable[prog_channel] <= prog_word[7];
							manual_fire_trigger[prog_channel] <= prog_word[8];
						end
						REG_PULSE_CFG: begin
							number_of_stim_pulses[prog_channel] <= prog_word[7:0];
							continuous_repeat[prog_channel] <= prog_word[8];
						end
						REG_START_STIM: event_start_stim[prog_channel] <= prog_word;
						REG_END_STIM: event_end_stim[prog_channel] <= prog_word;
						REG_REPEAT_STIM: event_repeat_stim[prog_channel] <= prog_word;
						REG_EVENT_END: event_end[prog_channel] <= prog_word;
						default: begin
						end
					endcase
				end
			end

			always @(posedge dataclk) begin
				if (reset || !acquisition_running) begin
					digout <= 16'b0;
					waiting_for_trigger <=16'hffff;
					waiting_for_edge <=16'hffff;
					continuous_running <= 16'b0;
					fire_pending <= 16'b0;
				end else begin
					if (channel[5:4] == 2'b00) begin
						case (main_state)
							STATE_EVAL_TRIG: begin
								if (waiting_for_edge[addr] && waiting_for_trigger[addr] &&
									trigger_on_edge[addr] && !manual_fire_trigger[addr] &&
									!continuous_repeat[addr]) begin
									if (~trigger_in[addr]) begin
										waiting_for_edge[addr] <= 1'b0;
									end
								end
								if (waiting_for_trigger[addr]) begin
									counter[addr] <= 32'b0;
									stim_counter[addr] <= number_of_stim_pulses[addr];
									if (trigger_enable[addr] && continuous_repeat[addr] &&
										continuous_running[addr]) begin
										waiting_for_trigger[addr] <= 1'b0;
									end else if (trigger_enable[addr] && manual_fire_trigger[addr] &&
										!continuous_repeat[addr] && fire_pending[addr]) begin
										waiting_for_trigger[addr] <= 1'b0;
										fire_pending[addr] <= 1'b0;
									end else if (trigger_enable[addr] &&
										!manual_fire_trigger[addr] && !continuous_repeat[addr] &&
										trigger_in[addr] &&
										(~trigger_on_edge[addr] || ~waiting_for_edge[addr])) begin
										waiting_for_trigger[addr] <= 1'b0;
									end else begin
										digout[addr] <= 1'b0;
									end
								end
							end

							STATE_PULSE_ON: begin
								if (~waiting_for_trigger[addr]) begin
									if (event_start_stim[addr] == counter[addr]) begin
										digout[addr] <= 1'b1;
									end
								end
							end

							STATE_PULSE_OFF: begin
								if (~waiting_for_trigger[addr]) begin
									if (event_end_stim[addr] == counter[addr]) begin
										digout[addr] <= 1'b0;
									end
								end
							end

							STATE_SHUTDOWN: begin
								if (shutdown) begin
									digout[addr] <= 1'b0;
								end
							end

							STATE_ADVANCE: begin
								if (continuous_repeat[addr] && continuous_running[addr]) begin
									if (counter[addr] + 1'b1 == event_repeat_stim[addr]) begin
										counter[addr] <= event_start_stim[addr];
									end else begin
										counter[addr] <= counter[addr] + 1;
									end
								end else if (event_repeat_stim[addr] == counter[addr] &&
									stim_counter[addr] != 8'b0) begin
									counter[addr] <= event_start_stim[addr];
									stim_counter[addr] <= stim_counter[addr] - 1;
								end else if (event_end[addr] == counter[addr] &&
									stim_counter[addr] == 8'b0) begin
									counter[addr] <= 32'b0;
									waiting_for_trigger[addr] <= 1'b1;
									waiting_for_edge[addr] <= trigger_on_edge[addr];
									continuous_running[addr] <= 1'b0;
								end else begin
									counter[addr] <= counter[addr] + 1;
								end
							end
							default: begin
							end
						endcase
					end

					if (command_strobe) begin
						case (command_opcode)
							CMD_MANUAL_HIGH, CMD_MANUAL_LOW: begin
								digout[command_channel] <= 1'b0;
								waiting_for_trigger[command_channel] <= 1'b1;
								waiting_for_edge[command_channel] <=
									trigger_on_edge[command_channel];
								continuous_running[command_channel] <= 1'b0;
								fire_pending[command_channel] <= 1'b0;
							end
							CMD_CONTINUOUS_ON: begin
								if (continuous_start_eligible) begin
									digout[command_channel] <= 1'b0;
									continuous_running[command_channel] <= 1'b1;
									fire_pending[command_channel] <= 1'b0;
								end
							end
							CMD_SEQUENCE_STOP: begin
								digout[command_channel] <= 1'b0;
								waiting_for_trigger[command_channel] <= 1'b1;
								waiting_for_edge[command_channel] <=
									trigger_on_edge[command_channel];
								continuous_running[command_channel] <= 1'b0;
								fire_pending[command_channel] <= 1'b0;
							end
							CMD_FIRE: begin
								if (fire_eligible) begin
									fire_pending[command_channel] <= 1'b1;
								end
							end
							default: begin
							end
						endcase
					end
				end
			end

		end else begin : gen_rhd

			assign command_accepted = 1'b0;

			always @(posedge prog_trig) begin
				if (prog_module == MODULE) begin
					case (prog_address)
						0: begin
							trigger_source[prog_channel] <= prog_word[4:0];
							trigger_on_edge[prog_channel] <= prog_word[5];
							trigger_polarity[prog_channel] <= prog_word[6];
							trigger_enable[prog_channel] <= prog_word[7];
						end
						1: begin
							number_of_stim_pulses[prog_channel] <= prog_word[7:0];
						end
						4: event_start_stim[prog_channel] <= prog_word;
						7: event_end_stim[prog_channel] <= prog_word;
						8: event_repeat_stim[prog_channel] <= prog_word;
						13: event_end[prog_channel] <= prog_word;
					endcase
				end
			end

			always @(posedge dataclk) begin
				if (reset) begin
					digout <= 16'b0;
					waiting_for_trigger <=16'hffff;
					waiting_for_edge <=16'hffff;
				end else begin
					if (channel[5:4] == 2'b00) begin
						case (main_state)
							99: begin
								if (reset_sequencer) begin
									digout <= 16'b0;
									waiting_for_trigger <=16'hffff;
									waiting_for_edge <=16'hffff;
								end
							end
							102: begin
								if (waiting_for_edge[addr] && waiting_for_trigger[addr] &&
									trigger_on_edge[addr]) begin
									if (~trigger_in[addr]) begin
										waiting_for_edge[addr] <= 1'b0;
									end
								end
								if (waiting_for_trigger[addr]) begin
									counter[addr] <= 32'b0;
									stim_counter[addr] <= number_of_stim_pulses[addr];
									if (trigger_enable[addr] && trigger_in[addr] &&
										(~trigger_on_edge[addr] || ~waiting_for_edge[addr])) begin
										waiting_for_trigger[addr] <= 1'b0;
									end else begin
										digout[addr] <= 1'b0;
									end
								end
							end

							106: begin
								if (~waiting_for_trigger[addr]) begin
									if (event_start_stim[addr] == counter[addr]) begin
										digout[addr] <= 1'b1;
									end
								end
							end

							110: begin
								if (~waiting_for_trigger[addr]) begin
									if (event_end_stim[addr] == counter[addr]) begin
										digout[addr] <= 1'b0;
									end
								end
							end

							114: begin
								if (shutdown) begin
									digout[addr] <= 1'b0;
								end
							end

							118: begin
								if (event_repeat_stim[addr] == counter[addr] &&
									stim_counter[addr] != 8'b0) begin
									counter[addr] <= event_start_stim[addr];
									stim_counter[addr] <= stim_counter[addr] - 1;
								end else if (event_end[addr] == counter[addr] &&
									stim_counter[addr] == 8'b0) begin
									counter[addr] <= 32'b0;
									waiting_for_trigger[addr] <= 1'b1;
									waiting_for_edge[addr] <= trigger_on_edge[addr];
								end else begin
									counter[addr] <= counter[addr] + 1;
								end
							end
							default: begin
							end
						endcase
					end
				end
			end

		end
	endgenerate

endmodule

`default_nettype wire
