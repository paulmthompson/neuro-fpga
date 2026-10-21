`timescale 1ns / 1ps
// Legacy RHD digout_sequencer smoke test (ENABLE_EXTENDED_COMMANDS = 0).
module rhd_digout_sequencer_tb;
    reg reset = 1'b1;
    reg dataclk = 1'b0;
    reg [31:0] main_state = 99;
    reg [5:0] channel = 0;
    reg [3:0] prog_channel = 0;
    reg [3:0] prog_address = 0;
    reg [4:0] prog_module = 16;
    reg [31:0] prog_word = 0;
    reg prog_trig = 0;
    reg [31:0] triggers = 0;
    reg shutdown = 0;
    reg reset_sequencer = 0;
    wire [15:0] digout;
    wire [15:0] digout_enabled;
    wire command_accepted;

    digout_sequencer #(
        .MODULE(16),
        .ENABLE_EXTENDED_COMMANDS(1'b0)
    ) dut (
        .reset(reset), .dataclk(dataclk), .main_state(main_state), .channel(channel),
        .prog_channel(prog_channel), .prog_address(prog_address), .prog_module(prog_module),
        .prog_word(prog_word), .prog_trig(prog_trig), .triggers(triggers),
        .command_strobe(1'b0), .command_word(7'b0), .acquisition_running(1'b1),
        .threshold_mode(8'b0),
        .digout(digout), .digout_enabled(digout_enabled), .command_accepted(command_accepted),
        .shutdown(shutdown), .reset_sequencer(reset_sequencer), .amp_maintenance(1'b0)
    );

    initial begin
        #100 reset = 0;
        #200;
        reset_sequencer = 1;
        main_state = 99;
        #20 reset_sequencer = 0;
        if (digout !== 16'b0) begin
            $display("FAIL: expected digout low after reset_sequencer");
            $finish(1);
        end
        $display("PASS: rhd_digout_sequencer_tb");
        $finish(0);
    end

    always #5 dataclk = ~dataclk;
endmodule
