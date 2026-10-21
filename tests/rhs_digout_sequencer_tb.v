`timescale 1ns / 1ps

// Standalone, self-checking baseline for the RHS digital sequencer.
// Emulates the main.v states used by this module, one state per dataclk edge and
// 20 channels per sampling frame.
//
// configure_pin / configure_manual_fire_pin use historical finite-train repeat
// timing (event_repeat = start + period). Step 4 host Single-pulse programming
// uses EventRepeatStim = Never; see rhs_digout_host_programming.vh and the
// integration bench for the in-contract host register image.
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
    reg command_strobe = 0;
    reg [6:0] command_word = 0;
    reg acquisition_running = 1;
    reg [7:0] threshold_mode = 0;
    wire [15:0] digout;
    wire [15:0] digout_enabled;
    wire command_accepted;
    reg shutdown = 0;
    reg amp_maintenance = 0;

    integer frame = 0;
    integer rises [0:15];
    integer falls [0:15];
    integer first_rise [0:15];
    integer second_rise [0:15];
    integer last_rise [0:15];
    integer first_fall [0:15];
    integer i;
    integer before_rises;
    integer maintenance_rise;
    reg accepted;

    digout_sequencer #(.MODULE(16)) dut (
        .reset(reset), .dataclk(dataclk), .main_state(main_state),
        .channel(channel), .prog_channel(prog_channel),
        .prog_address(prog_address), .prog_module(prog_module),
        .prog_word(prog_word), .prog_trig(prog_trig), .triggers(triggers),
        .command_strobe(command_strobe), .command_word(command_word),
        .acquisition_running(acquisition_running), .threshold_mode(threshold_mode),
        .digout(digout), .digout_enabled(digout_enabled),
        .command_accepted(command_accepted),
        .shutdown(shutdown), .reset_sequencer(1'b0), .amp_maintenance(amp_maintenance)
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
                        if (first_fall[pin] == -1) first_fall[pin] = frame;
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

    task configure_level_pin;
        input [3:0] ch;
        input [4:0] source;
        input [7:0] additional_pulses;
        input [31:0] width;
        input [31:0] period;
        begin
            configure_pin(ch, source, additional_pulses, 0, width, period);
            // The same trigger register, without bit 5 (edge detection).
            program_reg(ch, 0, 32'h00000080 | source);
        end
    endtask

    task configure_continuous_pin;
        input [3:0] ch;
        input [31:0] width;
        input [31:0] period;
        begin
            // Enabled + continuous bit. Trigger source is intentionally zero:
            // external trigger state must have no effect in this mode.
            program_reg(ch, 0, 32'h00000080);
            program_reg(ch, 1, 32'h00000100);
            program_reg(ch, 4, 0);
            program_reg(ch, 7, width);
            program_reg(ch, 8, period);
            program_reg(ch, 13, width + 2);
        end
    endtask

    // Legacy finite-train style (repeat at start+period). Not Step 4 Single host contract.
    task configure_manual_fire_pin;
        input [3:0] ch;
        input [7:0] additional_pulses;
        input [31:0] width;
        input [31:0] period;
        begin
            // Enabled + Manual Fire bit; trigger index zero must be ignored.
            program_reg(ch, 0, 32'h00000180);
            program_reg(ch, 1, {24'b0, additional_pulses});
            program_reg(ch, 4, 0);
            program_reg(ch, 7, width);
            program_reg(ch, 8, period);
            program_reg(ch, 13, width + 2);
        end
    endtask

    `include "rhs_digout_host_programming.vh"

    task live_command;
        input [2:0] opcode;
        input [3:0] ch;
        output was_accepted;
        begin
            @(negedge dataclk);
            command_word = {opcode, ch};
            command_strobe = 1;
            #1;
            was_accepted = command_accepted;
            @(negedge dataclk);
            command_strobe = 0;
            #1;
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
            first_fall[i] = -1;
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
        check(first_fall[1] - first_rise[1] == 2,
              "two-tick pulse width changed");
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

        // A held level starts a new single-pulse program after completion.
        configure_level_pin(4, 5, 0, 2, 5);
        triggers[5] = 1;
        repeat (12) sample_frame();
        check(rises[4] >= 2, "level trigger did not retrigger");
        triggers[5] = 0;
        repeat (8) sample_frame();
        check(digout[4] === 1'b0, "level output did not return low");
        $display("PASS: held-level retrigger");

        // 255 additional repeats give the full 256-pulse range.
        configure_pin(5, 6, 8'hff, 0, 2, 5);
        sample_frame();
        triggers[6] = 1;
        repeat (1550) sample_frame();
        check(rises[5] == 256 && falls[5] == 256,
              "256-pulse train count incorrect");
        check(digout[5] === 1'b0, "256-pulse train did not end low");
        $display("PASS: 256 pulses");

        // Amplifier maintenance is output-transparent for the digital
        // sequencer. The shared amplifier/analog reset pulse has no digital
        // DUT input, so neither maintenance entry nor that pulse can reset it.
        triggers[3] = 0;
        configure_pin(2, 3, 0, 0, 100, 200);
        sample_frame();
        triggers[3] = 1;
        sample_frame();
        check(digout[2] === 1'b1, "long pulse did not begin");
        amp_maintenance = 1;
        repeat (3) sample_frame();
        check(digout[2] === 1'b1, "maintenance interrupted digital output");
        amp_maintenance = 0;
        repeat (3) sample_frame();
        check(digout[2] === 1'b1, "maintenance exit interrupted digital output");
        $display("PASS: maintenance entry/reset/exit are output-transparent");

        // shutdown forces a currently high output low at state 114.
        configure_pin(6, 7, 0, 0, 100, 200);
        sample_frame();
        triggers[7] = 1;
        sample_frame();
        check(digout[6] === 1'b1, "shutdown-test pulse did not begin");
        shutdown = 1;
        sample_frame();
        check(digout[6] === 1'b0, "shutdown did not clear output");
        shutdown = 0;
        $display("PASS: shutdown forces output low");

        // Continuous mode ignores external triggers and starts only from its
        // per-channel command. It uses exact period semantics (five frames,
        // unlike the preserved six-frame finite baseline above).
        triggers[0] = 1;
        configure_continuous_pin(7, 2, 5);
        repeat (3) sample_frame();
        check(rises[7] == 0, "external trigger started continuous mode");
        live_command(2, 7, accepted);
        check(accepted, "eligible continuous Start was rejected");
        repeat (15) sample_frame();
        check(rises[7] >= 3, "continuous train did not repeat");
        check(second_rise[7] - first_rise[7] == 5,
              "continuous period is not exact");

        // Stop while high is prompt, disarms the channel, and a later Start
        // begins a fresh waveform. A repeated Start while busy is ignored.
        while (digout[7] !== 1'b1) sample_frame();
        live_command(2, 7, accepted);
        check(!accepted, "busy continuous Start was accepted");
        live_command(3, 7, accepted);
        check(accepted && digout[7] === 1'b0,
              "continuous Stop did not force low");
        before_rises = rises[7];
        repeat (7) sample_frame();
        check(rises[7] == before_rises, "stopped continuous train revived");
        live_command(2, 7, accepted);
        check(accepted, "fresh continuous restart was rejected");
        while (digout[7] !== 1'b1) sample_frame();
        repeat (2) sample_frame();
        check(digout[7] === 1'b0, "continuous output did not enter low phase");
        live_command(3, 7, accepted);
        check(accepted && digout[7] === 1'b0, "Stop during low phase failed");
        $display("PASS: continuous Start/Stop/restart and exact period");

        // Step 4 host contract: Single pulse + Manual Fire (Never repeat).
        rhs_digout_program_single_manual_fire(30000, 4'd13, 0, 100, 1000, 1'b1);
        repeat (2) sample_frame();
        live_command(4, 13, accepted);
        check(accepted, "host Single Manual Fire was rejected");
        repeat (20) sample_frame();
        check(rises[13] == 1 && falls[13] == 1,
              "host Single Manual Fire pulse count incorrect");
        check(digout[13] === 1'b0, "host Single Manual Fire did not end low");
        $display("PASS: host Single Manual Fire (Never repeat)");

        // Manual Fire finite train (legacy repeat timing), exclusive from external
        // triggers, retained until consumed, ignored while busy.
        configure_manual_fire_pin(8, 1, 2, 5);
        repeat (3) sample_frame();
        check(rises[8] == 0, "external trigger started Manual Fire mode");
        live_command(4, 8, accepted);
        check(accepted, "eligible Fire was rejected");
        repeat (2) sample_frame();
        live_command(4, 8, accepted);
        check(!accepted, "busy Fire was accepted");
        repeat (15) sample_frame();
        check(rises[8] == 2 && falls[8] == 2,
              "Manual Fire finite pulse count incorrect");
        live_command(4, 8, accepted);
        check(accepted, "Manual Fire did not rearm after completion");
        repeat (15) sample_frame();
        check(rises[8] == 4 && falls[8] == 4,
              "rearmed Manual Fire pulse count incorrect");

        amp_maintenance = 1;
        live_command(4, 8, accepted);
        check(!accepted, "Fire during maintenance was accepted");
        amp_maintenance = 0;
        repeat (4) sample_frame();
        check(rises[8] == 4, "maintenance Fire was queued");

        // DAC-threshold ownership rejects Start/Fire before either can become
        // pending. Stop remains available as a safety/disarm command.
        configure_continuous_pin(3, 2, 5);
        threshold_mode[3] = 1;
        live_command(2, 3, accepted);
        check(!accepted, "threshold-owned continuous Start was accepted");
        live_command(3, 3, accepted);
        check(accepted, "threshold-owned Stop was rejected");
        threshold_mode[3] = 0;
        $display("PASS: Manual Fire eligibility, rearm, and ownership");

        // Stop acquisition clears an accepted-but-unconsumed Fire and an
        // active continuous train. Neither may return on a later Run.
        live_command(4, 8, accepted);
        check(accepted, "pending-Fire setup failed");
        acquisition_running = 0;
        tick(99, 0);
        check(digout === 16'b0, "acquisition Stop did not force all low");
        acquisition_running = 1;
        before_rises = rises[8];
        repeat (8) sample_frame();
        check(rises[8] == before_rises, "pending Fire survived Stop");

        configure_continuous_pin(7, 2, 5);
        live_command(2, 7, accepted);
        repeat (2) sample_frame();
        acquisition_running = 0;
        tick(99, 0);
        acquisition_running = 1;
        before_rises = rises[7];
        repeat (8) sample_frame();
        check(rises[7] == before_rises, "continuous state survived Stop");
        $display("PASS: acquisition Stop discards all software starts");

        // A continuous waveform advances through both maintenance phases with
        // no missing period. The amplifier reset pulse is intentionally absent
        // from this digital module's interface.
        configure_continuous_pin(9, 2, 5);
        live_command(2, 9, accepted);
        while (digout[9] !== 1'b1) sample_frame();
        maintenance_rise = last_rise[9];
        amp_maintenance = 1;
        repeat (7) sample_frame();
        amp_maintenance = 0;
        repeat (5) sample_frame();
        check(rises[9] >= 3, "continuous timing stopped in maintenance");
        check(last_rise[9] - maintenance_rise == 10,
              "maintenance changed continuous phase or period");
        live_command(3, 9, accepted);
        $display("PASS: continuous timing survives maintenance entry/exit");

        // Independent software modes may run together. Manual source commands
        // disarm only their selected sequencer channel.
        configure_continuous_pin(11, 1, 4);
        rhs_digout_program_single_manual_fire(30000, 4'd12, 0, 100, 1000, 1'b1);
        live_command(2, 11, accepted);
        live_command(4, 12, accepted);
        repeat (12) sample_frame();
        check(rises[11] >= 3, "independent continuous channel failed");
        check(rises[12] == 1 && falls[12] == 1,
              "independent host Single Manual Fire failed");
        while (digout[11] !== 1'b1) sample_frame();
        live_command(0, 11, accepted);
        check(digout[11] === 1'b0, "Manual source did not disarm sequencer");
        before_rises = rises[11];
        repeat (6) sample_frame();
        check(rises[11] == before_rises, "manual-disarmed sequencer revived");
        $display("PASS: concurrent channels and source-transition disarm");

        $display("PASS: RHS digital sequencer baseline");
        $finish;
    end

    always #5 dataclk = ~dataclk;
endmodule
