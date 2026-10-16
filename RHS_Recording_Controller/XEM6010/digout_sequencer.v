`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 		 Intan Technologies, LLC
// 
// Design Name: 	 RHS2000 Rhythm Stim Interface
// Module Name:    digout_sequencer 
// Project Name:   Opal Kelly FPGA/USB RHS2000 Interface
// Target Devices: 
// Tool versions: 
// Description:    Generate pulse control signals for 16 digital outputs.
//
// Dependencies: 
//
// Revision:       1.0 (26 October 2016)
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

module digout_sequencer #(
	parameter MODULE = 0
	)
	(
	input wire			reset,
	input wire			dataclk,
	input wire [31:0] main_state,
	input wire [5:0]	channel,
	input wire [3:0]  prog_channel,
	input wire [3:0]	prog_address,
	input wire [4:0]  prog_module,
	input wire [31:0] prog_word, // PMT
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
	input wire			amp_maintenance
   );

	reg [31:0] counter[15:0]; // PMT
	
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
	
	// PMT
	reg [31:0] event_start_stim[15:0];
	reg [31:0] event_end_stim[15:0];
	reg [31:0] event_repeat_stim[15:0];
	reg [31:0] event_end[15:0];
	
	assign digout_enabled = trigger_enable;

	// RHS digital-output live command protocol:
	// WireIn 0x0e [3:0] channel, [6:4] opcode; TriggerIn 0x41[2] executes.
	// 0/1 select Manual High/Low and disarm sequencing; 2 starts continuous
	// mode; 3 stops/disarms any sequence; 4 fires an idle Manual-trigger
	// single/finite program. Commands 2 and 4 are rejected during amplifier
	// maintenance and while DAC-threshold mode owns outputs 1-8. Stop remains
	// available during maintenance. TriggerIn is synchronous to dataclk.
	localparam CMD_MANUAL_HIGH   = 3'd0;
	localparam CMD_MANUAL_LOW    = 3'd1;
	localparam CMD_CONTINUOUS_ON = 3'd2;
	localparam CMD_SEQUENCE_STOP = 3'd3;
	localparam CMD_FIRE          = 3'd4;

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

	assign command_accepted = command_strobe && acquisition_running &&
		((command_opcode == CMD_SEQUENCE_STOP) ||
		 (command_opcode == CMD_CONTINUOUS_ON && continuous_start_eligible) ||
		 (command_opcode == CMD_FIRE && fire_eligible));
	
	// Trigger selection
	reg [15:0] trigger_in;

	always @(posedge dataclk) begin
		if (channel == 0 && (main_state == 99 || main_state == 100)) begin
			trigger_in[0] <= triggers[trigger_source[0]] ^ trigger_polarity[0];
			trigger_in[1] <= triggers[trigger_source[1]] ^ trigger_polarity[1];
			trigger_in[2] <= triggers[trigger_source[2]] ^ trigger_polarity[2];
			trigger_in[3] <= triggers[trigger_source[3]] ^ trigger_polarity[3];
			trigger_in[4] <= triggers[trigger_source[4]] ^ trigger_polarity[4];
			trigger_in[5] <= triggers[trigger_source[5]] ^ trigger_polarity[5];
			trigger_in[6] <= triggers[trigger_source[6]] ^ trigger_polarity[6];
			trigger_in[7] <= triggers[trigger_source[7]] ^ trigger_polarity[7];
			trigger_in[8] <= triggers[trigger_source[8]] ^ trigger_polarity[8];
			trigger_in[9] <= triggers[trigger_source[9]] ^ trigger_polarity[9];
			trigger_in[10] <= triggers[trigger_source[10]] ^ trigger_polarity[10];
			trigger_in[11] <= triggers[trigger_source[11]] ^ trigger_polarity[11];
			trigger_in[12] <= triggers[trigger_source[12]] ^ trigger_polarity[12];
			trigger_in[13] <= triggers[trigger_source[13]] ^ trigger_polarity[13];
			trigger_in[14] <= triggers[trigger_source[14]] ^ trigger_polarity[14];
			trigger_in[15] <= triggers[trigger_source[15]] ^ trigger_polarity[15];
		end
	end
	
	// Register programming
	always @(posedge prog_trig) begin
		if (prog_module == MODULE) begin
			case (prog_address)
				0: begin
						trigger_source[prog_channel] <= prog_word[4:0];
						trigger_on_edge[prog_channel] <= prog_word[5];
						trigger_polarity[prog_channel] <= prog_word[6];
						trigger_enable[prog_channel] <= prog_word[7];
						manual_fire_trigger[prog_channel] <= prog_word[8];
					end
				1: begin
						number_of_stim_pulses[prog_channel] <= prog_word[7:0];
						continuous_repeat[prog_channel] <= prog_word[8];
					end
				4: event_start_stim[prog_channel] <= prog_word;
				7: event_end_stim[prog_channel] <= prog_word;
				8: event_repeat_stim[prog_channel] <= prog_word;
				13: event_end[prog_channel] <= prog_word;
			endcase
		end
	end
	
	wire [3:0] addr;
	assign addr = channel[3:0];
	
	// State machine for stim sequencing
	
	always @(posedge dataclk) begin
		if (reset || !acquisition_running) begin
			digout <= 16'b0;
			waiting_for_trigger <=16'hffff;
			waiting_for_edge <=16'hffff;
			continuous_running <= 16'b0;
			fire_pending <= 16'b0;
		end else begin
			if (channel[5:4] == 2'b00) begin // only for channel = 0-15
				case (main_state)
					102: begin
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
						if (continuous_repeat[addr] && continuous_running[addr]) begin
							if (counter[addr] + 1'b1 == event_repeat_stim[addr]) begin
								// Continuous mode uses exact period semantics:
								// start+period repeats after exactly period frames.
								counter[addr] <= event_start_stim[addr];
							end else begin
								counter[addr] <= counter[addr] + 1;
							end
						end else if (event_repeat_stim[addr] == counter[addr] && stim_counter[addr] != 8'b0) begin
							counter[addr] <= event_start_stim[addr];
							stim_counter[addr] <= stim_counter[addr] - 1;
						end else if (event_end[addr] == counter[addr] && stim_counter[addr] == 8'b0) begin
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

			// Live commands have priority over a coincident sequencer state for
			// the selected channel. Continuous Start and Fire are retained until
			// state 102 resets counter[addr] and consumes the start transition.
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
	
endmodule
