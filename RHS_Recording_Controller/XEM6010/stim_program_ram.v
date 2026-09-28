`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Dual-port 1024 x 32-bit stimulation program RAM (per stim_sequencer instance).
// Port A: host write on ti_clk. Port B: rhythm read on dataclk.
//////////////////////////////////////////////////////////////////////////////////

module stim_program_ram(
	input wire        clk_A,
	input wire        clk_B,
	input wire [9:0]  addr_A,
	input wire [9:0]  addr_B,
	input wire [31:0] data_in,
	output wire [31:0] data_out_B,
	input wire        we_A,
	input wire        reset
);

	wire [15:0] data_out_B_lo;
	wire [15:0] data_out_B_hi;

	RAM_1024x16bit stim_program_ram_lo (
		.clk_A(clk_A),
		.clk_B(clk_B),
		.RAM_addr_A(addr_A),
		.RAM_addr_B(addr_B),
		.RAM_data_in(data_in[15:0]),
		.RAM_data_out_A(),
		.RAM_data_out_B(data_out_B_lo),
		.RAM_we(we_A),
		.reset(reset)
	);

	RAM_1024x16bit stim_program_ram_hi (
		.clk_A(clk_A),
		.clk_B(clk_B),
		.RAM_addr_A(addr_A),
		.RAM_addr_B(addr_B),
		.RAM_data_in(data_in[31:16]),
		.RAM_data_out_A(),
		.RAM_data_out_B(data_out_B_hi),
		.RAM_we(we_A),
		.reset(reset)
	);

	assign data_out_B = {data_out_B_hi, data_out_B_lo};

endmodule
