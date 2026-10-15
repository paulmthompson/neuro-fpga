`timescale 1ns / 1ps

// Standalone Step 2 test: physical TTL gating and per-pin manual commands.
module rhs_digout_output_control_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;
    reg strobe = 0;
    reg sequencer_command_accepted = 0;
    reg [6:0] word = 0;
    reg running = 0;
    reg [7:0] threshold_mode = 0, threshold_out = 0;
    reg [15:0] sequencer_out = 0;
    wire [15:0] ttl_out;

    digout_output_control dut (
        .dataclk(clk), .reset(reset), .command_strobe(strobe),
        .sequencer_command_accepted(sequencer_command_accepted),
        .command_word(word), .acquisition_running(running),
        .threshold_mode(threshold_mode), .threshold_out(threshold_out),
        .sequencer_out(sequencer_out), .ttl_out(ttl_out)
    );

    task command(input [2:0] opcode, input [3:0] channel);
        begin
            @(negedge clk);
            word = {opcode, channel};
            strobe = 1;
            @(negedge clk);
            strobe = 0;
            #1;
        end
    endtask

    task sequencer_command(
        input [2:0] opcode,
        input [3:0] channel,
        input accepted
    );
        begin
            @(negedge clk);
            word = {opcode, channel};
            sequencer_command_accepted = accepted;
            strobe = 1;
            @(negedge clk);
            strobe = 0;
            sequencer_command_accepted = 0;
            #1;
        end
    endtask

    task assert_out(input [15:0] expected);
        begin
            #1;
            if (ttl_out !== expected)
                $fatal(1, "TTL output = %04h, expected %04h", ttl_out, expected);
        end
    endtask

    initial begin
        @(negedge clk);
        reset = 0;
        assert_out(16'h0000);

        // No live action may energize TTL pins when acquisition is stopped.
        command(0, 15);
        command(0, 0);
        threshold_mode[0] = 1;
        threshold_out[0] = 1;
        sequencer_out[1] = 1;
        assert_out(16'h0000);
        running = 1;
        assert_out(16'h0003); // threshold and existing sequencer, no stale manual high
        $display("PASS: stopped pins low; idle commands ignored");

        // DAC threshold on TTL 1 has priority. Other pins are independent.
        command(0, 0); // ignored: threshold mode owns TTL 1
        assert_out(16'h0003);
        command(0, 15);
        assert_out(16'h8003);
        command(0, 2);
        assert_out(16'h8007);
        command(1, 15);
        assert_out(16'h0007);
        $display("PASS: individual manual levels and threshold priority");

        // Changing the payload alone cannot execute a command.
        word = {3'd0, 4'd15};
        #12;
        assert_out(16'h0007);
        $display("PASS: command needs execute strobe");

        // Stop forces ALL sources low without a USB Stop command. Clearing
        // acquired manual state prevents an old high from returning on Run.
        command(0, 15);
        assert_out(16'h8007);
        running = 0;
        assert_out(16'h0000);
        repeat (2) @(negedge clk);
        command(0, 15); // still stopped; ignored
        assert_out(16'h0000);
        running = 1;
        assert_out(16'h0003); // threshold/seq return; old manual TTL 3 stays low
        $display("PASS: Stop clears manual state; automatic sources follow Run");

        // This mux has no amplifier-maintenance input; test its steady state.
        repeat (8) @(negedge clk);
        assert_out(16'h0003);
        $display("PASS: no extra maintenance gating in output mux");

        // Rejected sequencer commands retain Manual Level ownership. Accepted
        // Start, Fire, and generic Stop/disarm release it without affecting
        // another channel.
        command(0, 15);
        assert_out(16'h8003);
        sequencer_command(4, 15, 0);
        assert_out(16'h8003);
        sequencer_out[15] = 1;
        sequencer_command(2, 15, 1);
        assert_out(16'h8003); // now high from sequencer, not stale manual
        sequencer_out[15] = 0;
        assert_out(16'h0003);
        command(0, 14);
        assert_out(16'h4003);
        sequencer_command(3, 14, 1);
        assert_out(16'h0003);
        $display("PASS: accepted sequencer commands release manual ownership");

        reset = 1;
        assert_out(16'h0000);
        @(negedge clk);
        reset = 0;
        assert_out(16'h0003);
        $display("PASS: reset forces pins low and clears manual state");
        $finish;
    end
endmodule
