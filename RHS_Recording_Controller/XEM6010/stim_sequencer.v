`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 		 Intan Technologies, LLC
// 
// Design Name: 	 RHS2000 Rhythm Stim Interface
// Module Name:    stim_sequencer 
// Project Name:   Opal Kelly FPGA/USB RHS2000 Interface
// Target Devices: 
// Tool versions: 
// Description:    Generate stimulation control bits for 16 specified stimulation
//                 waveforms. Program storage in block RAM (Phase 1).
//
// Dependencies: 
//
// Revision:       1.0 (26 October 2016)
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

module stim_sequencer #(
	parameter MODULE = 0
	)
	(
	input wire			reset,
	input wire			dataclk,
	input wire			ti_clk,
	input wire [31:0] main_state,
	input wire [5:0]	channel,
	input wire [3:0]  prog_channel,
	input wire [3:0]	prog_address,
	input wire [4:0]  prog_module,
	input wire [31:0] prog_word,
	input wire			prog_trig,
	input wire [31:0] triggers,
	input wire			amp_maintenance,
	output reg [15:0] stim_on,
	output reg [15:0] stim_pol,
	output reg [15:0] amp_settle,
	output reg [15:0] charge_recov,
	output reg        amp_settle_changed,
	input	 wire			reset_sequencer
   );

	reg [31:0] counter[15:0];

	// Reg 0 trigger configuration (mirrored from BRAM on host write; used at channel == 0)
	reg [4:0] trigger_source[15:0];
	reg [15:0] trigger_on_edge;
	reg [15:0] trigger_polarity;
	reg [15:0] trigger_enable;

	reg [15:0] waiting_for_trigger, waiting_for_edge;
	reg [7:0] stim_counter[15:0];

	// Active-channel program fields (latched from BRAM during states 100-114)
	reg [7:0]  cur_number_of_stim_pulses;
	reg [1:0]  cur_stim_shape;
	reg        cur_neg_stim_first;
	reg [31:0] cur_event_amp_settle_on;
	reg [31:0] cur_event_amp_settle_off;
	reg [31:0] cur_event_start_stim;
	reg [31:0] cur_event_stim_phase2;
	reg [31:0] cur_event_stim_phase3;
	reg [31:0] cur_event_end_stim;
	reg [31:0] cur_event_repeat_stim;
	reg [31:0] cur_event_charge_recov_on;
	reg [31:0] cur_event_charge_recov_off;
	reg [31:0] cur_event_amp_settle_on_repeat;
	reg [31:0] cur_event_amp_settle_off_repeat;
	reg [31:0] cur_event_end;

	localparam
		BIPHASIC =           2'b00,
		BIPHASIC_DEAD_ZONE = 2'b01,
		TRIPHASIC =          2'b10,
		UNUSED =             2'b11;

	reg [15:0] trigger_in;

	wire [3:0] addr;
	assign addr = channel[3:0];

	wire [9:0] ram_addr_a;
	wire [9:0] ram_addr_b;
	wire [31:0] ram_data_b;
	wire ram_we_a;

	assign ram_addr_a = { prog_channel, 2'b00, prog_address };
	assign ram_we_a = prog_trig && (prog_module == MODULE);

	wire in_stim_scan;
	assign in_stim_scan = (main_state >= 100) && (main_state <= 115);

	wire [3:0] scan_reg_addr;
	assign scan_reg_addr = main_state[7:0] - 8'd100;

	assign ram_addr_b = in_stim_scan ? { addr, 2'b00, scan_reg_addr } : 10'b0;

	stim_program_ram stim_program_ram_inst (
		.clk_A(ti_clk),
		.clk_B(dataclk),
		.addr_A(ram_addr_a),
		.addr_B(ram_addr_b),
		.data_in(prog_word),
		.data_out_B(ram_data_b),
		.we_A(ram_we_a),
		.reset(reset)
	);

	// Mirror reg 0 into flip-flops on host write (BRAM holds canonical image).
	// posedge prog_trig matches stock sequencers; avoids host_dcm_clk0 -> dataclk STA paths.
	always @(posedge prog_trig) begin
		if ((prog_module == MODULE) && (prog_address == 4'd0)) begin
			trigger_source[prog_channel] <= prog_word[4:0];
			trigger_on_edge[prog_channel] <= prog_word[5];
			trigger_polarity[prog_channel] <= prog_word[6];
			trigger_enable[prog_channel] <= prog_word[7];
		end
	end

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

	always @(posedge dataclk) begin
		if (reset) begin
			stim_on <= 16'b0;
			stim_pol <= 16'b0;
			amp_settle <= 16'b0;
			charge_recov <= 16'b0;
			amp_settle_changed <= 1'b1;
			waiting_for_trigger <=16'hffff;
			waiting_for_edge <=16'hffff;
		end else if (amp_maintenance) begin
			// docs/amp-maintenance-mode.md §3.5: hold sequencers; deassert stim outputs
			stim_on <= 16'b0;
			stim_pol <= 16'b0;
			amp_settle <= 16'b0;
			charge_recov <= 16'b0;
		end else begin
			if (channel[5:4] == 2'b00) begin
				// Latch BRAM read data (1-cycle latency after address on prior state)
				if (main_state >= 103 && main_state <= 114) begin
					case (main_state)
						103: cur_event_amp_settle_on <= ram_data_b;
						104: cur_event_amp_settle_off <= ram_data_b;
						105: cur_event_start_stim <= ram_data_b;
						106: cur_event_stim_phase2 <= ram_data_b;
						107: cur_event_stim_phase3 <= ram_data_b;
						108: cur_event_end_stim <= ram_data_b;
						109: cur_event_repeat_stim <= ram_data_b;
						110: cur_event_charge_recov_on <= ram_data_b;
						111: cur_event_charge_recov_off <= ram_data_b;
						112: cur_event_amp_settle_on_repeat <= ram_data_b;
						113: cur_event_amp_settle_off_repeat <= ram_data_b;
						114: cur_event_end <= ram_data_b;
						default: begin end
					endcase
				end

				case (main_state)
					99: begin
						if (reset_sequencer) begin
							stim_on <= 16'b0;
							stim_pol <= 16'b0;
							amp_settle <= 16'b0;
							charge_recov <= 16'b0;
							amp_settle_changed <= 1'b1;
							waiting_for_trigger <=16'hffff;
							waiting_for_edge <=16'hffff;
						end
					end
					102: begin
						if (waiting_for_edge[addr] && waiting_for_trigger[addr] && trigger_on_edge[addr]) begin
							if (~trigger_in[addr]) begin
								waiting_for_edge[addr] <= 1'b0;
							end
						end
						if (waiting_for_trigger[addr]) begin
							counter[addr] <= 32'b0;
							stim_counter[addr] <= ram_data_b[7:0];
							cur_number_of_stim_pulses <= ram_data_b[7:0];
							cur_stim_shape <= ram_data_b[9:8];
							cur_neg_stim_first <= ram_data_b[10];
							if (trigger_enable[addr] && trigger_in[addr] && (~trigger_on_edge[addr] || ~waiting_for_edge[addr])) begin
								waiting_for_trigger[addr] <= 1'b0;
							end else begin
								stim_on[addr] <= 1'b0;
								stim_pol[addr] <= 1'b0;
								amp_settle[addr] <= 1'b0;
								charge_recov[addr] <= 1'b0;
							end
						end
						if (channel[3:0] == 4'b0000) begin
							amp_settle_changed <= 1'b0;
						end
					end

					115: begin
						if (~waiting_for_trigger[addr]) begin
							if (cur_event_amp_settle_on == counter[addr] ||
								 (cur_event_amp_settle_on_repeat == counter[addr] && stim_counter[addr] != 8'b0)) begin
								amp_settle[addr] <= 1'b1;
								amp_settle_changed <= 1'b1;
							end else if ((cur_event_amp_settle_off == counter[addr] && stim_counter[addr] == 8'b0) ||
								 (cur_event_amp_settle_off_repeat == counter[addr] && stim_counter[addr] != 8'b0)) begin
								amp_settle[addr] <= 1'b0;
								amp_settle_changed <= 1'b1;
							end

							if (cur_event_charge_recov_on == counter[addr] && stim_counter[addr] == 8'b0) begin
								charge_recov[addr] <= 1'b1;
							end else if (cur_event_charge_recov_off == counter[addr] && stim_counter[addr] == 8'b0) begin
								charge_recov[addr] <= 1'b0;
							end
						end
					end

					119: begin
						if (~waiting_for_trigger[addr]) begin
							if (cur_event_start_stim == counter[addr]) begin
								stim_on[addr] <= 1'b1;
								stim_pol[addr] <= ~cur_neg_stim_first;
							end
						end
					end

					123: begin
						if (~waiting_for_trigger[addr]) begin
							if (cur_event_stim_phase2 == counter[addr]) begin
								if (cur_stim_shape == BIPHASIC_DEAD_ZONE) begin
									stim_on[addr] <= 1'b0;
								end else begin
									stim_on[addr] <= 1'b1;
									stim_pol[addr] <= cur_neg_stim_first;
								end
							end
						end
					end

					127: begin
						if (~waiting_for_trigger[addr]) begin
							if (cur_event_stim_phase3 == counter[addr]) begin
								if (cur_stim_shape == BIPHASIC_DEAD_ZONE) begin
									stim_on[addr] <= 1'b1;
									stim_pol[addr] <= cur_neg_stim_first;
								end else if (cur_stim_shape == TRIPHASIC) begin
									stim_on[addr] <= 1'b1;
									stim_pol[addr] <= ~cur_neg_stim_first;
								end
							end
						end
					end

					131: begin
						if (~waiting_for_trigger[addr]) begin
							if (cur_event_end_stim == counter[addr]) begin
								stim_on[addr] <= 1'b0;
								stim_pol[addr] <= ~cur_neg_stim_first;
							end
						end
					end

					135: begin
						if (cur_event_repeat_stim == counter[addr] && stim_counter[addr] != 8'b0) begin
							counter[addr] <= cur_event_start_stim;
							stim_counter[addr] <= stim_counter[addr] - 1;
						end else if (cur_event_end == counter[addr] && stim_counter[addr] == 8'b0) begin
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

endmodule
