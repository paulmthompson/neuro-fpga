`timescale 1ns / 1ps

// Standalone, self-checking baseline for the unmodified RHS digital sequencer.
// Emulates the main.v states used by this module, one state per dataclk edge and
// 20 channels per sampling frame.
module rhs_digout_sequencer_tb;
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
    wire [15:0] digout;
    wire [15:0] digout_enabled;
    reg shutdown = 0;
    reg amp_maintenance = 0;
    reg reset_sequencer = 0;

    integer frame = 0;
    integer rises [0:15];
    integer falls [0:15];
    integer first_rise [0:15];
    integer second_rise [0:15];
    integer last_rise [0:15];
    integer i;

    digout_sequencer #(.MODULE(16)) dut (
        .reset(reset), .dataclk(dataclk), .main_state(main_state),
        .channel(channel), .prog_channel(prog_channel),
        .prog_address(prog_address), .prog_module(prog_module),
        .prog_word(prog_word), .prog_trig(prog_trig), .triggers(triggers),
        .digout(digout), .digout_enabled(digout_enabled),
        .shutdown(shutdown), .amp_maintenance(amp_maintenance),
        .reset_sequencer(reset_sequencer)
    );

    // Check all 16 pins after every clock, not only at expected transitions.
    reg [15:0] previous_digout = 0;
    always @(negedge dataclk) begin
        if (!reset) begin
            for (integer pin = 0; pin < 16; pin = pin + 1) begin
                if (digout[pin] !== previous_digout[pin]) begin
                    if (digout[pin] === 1'b1) begin
                        rises[pin] = rises[pin] + 1;
                        if (first_rise[pin] == -1) first_rise[pin] = frame;
                        else if (second_rise[pin] == -1) second_rise[pin] = frame;
                        last_rise[pin] = frame;
                    end else if (digout[pin] === 1'b0) begin
                        falls[pin] = falls[pin] + 1;
                    end else begin
                        $fatal(1, "X/Z on pin %0d at frame %0d", pin, frame);
                    end
                end
            end
        end
        previous_digout = digout;
    end

    // Drive one sample interval: states 99 and 100 sample triggers, while
    // 102/106/110/114/118 process each channel in turn (see main.v).
    task tick;
        input [31:0] state_value;
        input [5:0] channel_value;
        begin
            @(negedge dataclk);
            main_state = state_value;
            channel = channel_value;
            @(posedge dataclk);
            #1;
        end
    endtask

    task sample_frame;
        integer c;
        begin
            tick(99, 0);
            tick(100, 0);
            for (c = 0; c < 20; c = c + 1) begin
                tick(102, c);
                tick(106, c);
                tick(110, c);
                tick(114, c);
                tick(118, c);
            end
            frame = frame + 1;
        end
    endtask

    task program_reg;
        input [3:0] ch;
        input [3:0] address;
        input [31:0] value;
        begin
            prog_channel = ch;
            prog_address = address;
            prog_word = value;
            #2;
            prog_trig = 1;
            #2;
            prog_trig = 0;
            #2;
        end
    endtask

    task configure_pin;
        input [3:0] ch;
        input [4:0] source;
        input [7:0] additional_pulses;
        input [31:0] start_tick;
        input [31:0] width;
        input [31:0] period;
        begin
            // Trigger enabled, rising edge, selected source. Pulse count stores N-1.
            program_reg(ch, 0, 32'h000000a0 | source);
            program_reg(ch, 1, {24'b0, additional_pulses});
            program_reg(ch, 4, start_tick);
            program_reg(ch, 7, start_tick + width);
            program_reg(ch, 8, start_tick + period);
            program_reg(ch, 13, start_tick + width + 2);
        end
    endtask

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) $fatal(1, "frame %0d: %0s", frame, message);
        end
    endtask

    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            rises[i] = 0;
            falls[i] = 0;
            first_rise[i] = -1;
            second_rise[i] = -1;
            last_rise[i] = -1;
        end
        #2;
        tick(99, 0);
        reset = 0;

        // Independent channels: one pulse on 0, two pulses on 1, three on 15.
        // Extra sources 2 and 3 stay low; unconfigured channels must stay low.
        configure_pin(0, 0, 0, 0, 2, 5);
        configure_pin(1, 1, 1, 0, 2, 5);
        configure_pin(15, 2, 2, 0, 2, 5);
        check(digout_enabled[0] && digout_enabled[1] && digout_enabled[15],
              "programmed outputs not enabled");
        sample_frame(); // establish an inactive level before a rising edge
        triggers[0] = 1;
        triggers[1] = 1;
        triggers[2] = 1;
        repeat (30) sample_frame();
        check(rises[0] == 1 && falls[0] == 1, "single-pulse count incorrect");
        check(rises[1] == 2 && falls[1] == 2, "two-pulse count incorrect");
        check(rises[15] == 3 && falls[15] == 3, "three-pulse count incorrect");
        // The existing counter jumps back to start_tick at the repeat event;
        // a programmed period of five ticks currently gives six frames.
        $display("Baseline spacing: pin 1 = %0d frames; pin 15 = %0d frames",
                 second_rise[1] - first_rise[1],
                 second_rise[15] - first_rise[15]);
        check(second_rise[1] - first_rise[1] == 6,
              "two-pulse baseline spacing changed");
        check(second_rise[15] - first_rise[15] == 6,
              "three-pulse baseline spacing changed");
        check(digout == 16'b0, "pins did not return low after finite trains");
        $display("PASS: single/finite pulse counts, per-channel isolation, period");

        // Edge-triggered channel must rearm only after seeing the trigger low.
        repeat (8) sample_frame();
        check(rises[0] == 1 && rises[1] == 2,
              "held-high edge trigger restarted a train");
        triggers[0] = 0;
        sample_frame();
        triggers[0] = 1;
        repeat (8) sample_frame();
        check(rises[0] == 2 && falls[0] == 2,
              "edge-triggered channel failed to rearm");
        $display("PASS: edge-trigger rearming");

        // The current FPGA explicitly clears digout during maintenance. This
        // baseline pins that behavior so a later change can replace this test.
        triggers[3] = 0;
        configure_pin(2, 3, 0, 0, 100, 200);
        sample_frame();
        triggers[3] = 1;
        sample_frame();
        check(digout[2] === 1'b1, "long pulse did not begin");
        amp_maintenance = 1;
        sample_frame();
        check(digout[2] === 1'b0, "baseline maintenance did not clear output");
        amp_maintenance = 0;
        $display("PASS: recorded existing maintenance-low behavior");

        // Also check the global sequencer reset used by maintenance in host
        // code; reset must clear output and allow a future fresh trigger.
        triggers[4] = 0;
        configure_pin(3, 4, 0, 0, 100, 200);
        sample_frame();
        triggers[4] = 1;
        sample_frame();
        check(digout[3] === 1'b1, "long pulse for reset test did not begin");
        reset_sequencer = 1;
        tick(99, 0);
        reset_sequencer = 0;
        check(digout[3] === 1'b0, "baseline reset did not clear output");
        $display("PASS: recorded existing shared-reset behavior");
        $display("PASS: RHS digital sequencer baseline");
        $finish;
    end

    always #5 dataclk = ~dataclk;
endmodule
