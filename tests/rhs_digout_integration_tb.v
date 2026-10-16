`timescale 1ns / 1ps

// Integration bench: digout_sequencer + digout_output_control (as in main.v).
// Only in-contract host sequences: live opcodes 0-4 and full stream-16 programming
// from rhs_digout_host_programming.vh (Step 4 setDigitalOutSequenceParameters).
module rhs_digout_integration_tb;
    localparam integer SAMPLE_RATE_HZ = 30000;

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
    reg [7:0] threshold_out = 0;
    reg shutdown = 0;
    reg amp_maintenance = 0;

    wire [15:0] digout_sequencer_out;
    wire [15:0] digout_enabled;
    wire command_accepted;
    wire [15:0] ttl_out;

    integer frame = 0;
    integer ttl_rises [0:15];
    integer ttl_falls [0:15];
    integer ttl_first_rise [0:15];
    integer ttl_second_rise [0:15];
    integer ttl_third_rise [0:15];
    integer ttl_first_fall [0:15];
    integer i;
    reg accepted;

    // Must match rhs_digout_program_continuous args below (100 us high, 1000 us period).
    localparam integer HOST_CONT_HIGH_US = 100;
    localparam integer HOST_CONT_PERIOD_US = 1000;
    localparam integer HOST_CONT_HIGH_TICKS =
        (HOST_CONT_HIGH_US * SAMPLE_RATE_HZ + 500_000) / 1_000_000;
    localparam integer HOST_CONT_PERIOD_TICKS =
        (HOST_CONT_PERIOD_US * SAMPLE_RATE_HZ + 500_000) / 1_000_000;

    digout_sequencer #(.MODULE(16)) digout_sequencer_inst (
        .reset(reset), .dataclk(dataclk), .main_state(main_state),
        .channel(channel), .prog_channel(prog_channel),
        .prog_address(prog_address), .prog_module(prog_module),
        .prog_word(prog_word), .prog_trig(prog_trig), .triggers(triggers),
        .command_strobe(command_strobe), .command_word(command_word),
        .acquisition_running(acquisition_running), .threshold_mode(threshold_mode),
        .digout(digout_sequencer_out), .digout_enabled(digout_enabled),
        .command_accepted(command_accepted),
        .shutdown(shutdown), .amp_maintenance(amp_maintenance)
    );

    digout_output_control digout_output_control_inst (
        .dataclk(dataclk), .reset(reset),
        .command_strobe(command_strobe),
        .sequencer_command_accepted(command_accepted),
        .command_word(command_word),
        .acquisition_running(acquisition_running),
        .threshold_mode(threshold_mode),
        .threshold_out(threshold_out),
        .sequencer_out(digout_sequencer_out),
        .ttl_out(ttl_out)
    );

    reg [15:0] previous_ttl_out = 0;
    always @(negedge dataclk) begin
        if (!reset) begin
            for (integer pin = 0; pin < 16; pin = pin + 1) begin
                if (ttl_out[pin] !== previous_ttl_out[pin]) begin
                    if (ttl_out[pin] === 1'b1) begin
                        ttl_rises[pin] = ttl_rises[pin] + 1;
                        if (ttl_first_rise[pin] < 0) begin
                            ttl_first_rise[pin] = frame;
                        end else if (ttl_second_rise[pin] < 0) begin
                            ttl_second_rise[pin] = frame;
                        end else if (ttl_third_rise[pin] < 0) begin
                            ttl_third_rise[pin] = frame;
                        end
                    end else if (ttl_out[pin] === 1'b0) begin
                        ttl_falls[pin] = ttl_falls[pin] + 1;
                        if (ttl_first_fall[pin] < 0) begin
                            ttl_first_fall[pin] = frame;
                        end
                    end else begin
                        $fatal(1, "X/Z on TTL pin %0d at frame %0d", pin, frame);
                    end
                end
            end
        end
        previous_ttl_out = ttl_out;
    end

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
        input [8*120-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $fatal(1, "frame %0d: %0s", frame, message);
            end
        end
    endtask

    task reset_ttl_counters;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                ttl_rises[i] = 0;
                ttl_falls[i] = 0;
                ttl_first_rise[i] = -1;
                ttl_second_rise[i] = -1;
                ttl_third_rise[i] = -1;
                ttl_first_fall[i] = -1;
            end
        end
    endtask

    // Step 4 host continuous on one TTL index; same register image as golden/sim README.
    task check_host_continuous_on_channel;
        input [3:0] ch;
        begin
            reset_ttl_counters();
            live_command(3'd3, ch, accepted);
            rhs_digout_program_continuous(
                SAMPLE_RATE_HZ, ch, 0,
                HOST_CONT_HIGH_US, HOST_CONT_PERIOD_US, 1000, 1'b1);
            sample_frame();
            live_command(3'd2, ch, accepted);
            check(accepted, "host Continuous Start was rejected");
            repeat (200) sample_frame();
            check(ttl_rises[ch] >= 5,
                  "host Continuous did not produce rising edges");
            check(ttl_falls[ch] >= 5,
                  "host Continuous did not return low between pulses");
            check(ttl_falls[ch] == ttl_rises[ch] || ttl_falls[ch] + 1 == ttl_rises[ch],
                  "host Continuous rise/fall counts diverged");
            check(ttl_first_rise[ch] >= 0, "host Continuous missing first rise");
            check(ttl_first_fall[ch] >= 0, "host Continuous missing first fall");
            check(ttl_second_rise[ch] >= 0, "host Continuous missing second rise");
            check(ttl_third_rise[ch] >= 0, "host Continuous missing third rise");
            check(ttl_first_fall[ch] - ttl_first_rise[ch] == HOST_CONT_HIGH_TICKS,
                  "host Continuous high phase is not high_ticks sample frames");
            check(ttl_second_rise[ch] - ttl_first_rise[ch] == HOST_CONT_PERIOD_TICKS,
                  "host Continuous period is not period_ticks sample frames");
            check(ttl_third_rise[ch] - ttl_second_rise[ch] == HOST_CONT_PERIOD_TICKS,
                  "host Continuous second period differs from first");
            check(ttl_out[ch] === 1'b0 || ttl_falls[ch] > ttl_rises[ch],
                  "host Continuous appears stuck high (no low phase)");
            live_command(3'd3, ch, accepted);
            check(accepted && ttl_out[ch] === 1'b0,
                  "host Continuous Stop did not force low");
        end
    endtask

    // commitRhsDigOutConfiguration while running: Manual Low, Sequencer Stop, full program.
    task apply_sequencer_config_running;
        input [3:0] ch;
        begin
            live_command(3'd1, ch, accepted);
            live_command(3'd3, ch, accepted);
            check(accepted, "Sequencer Stop during Apply was rejected");
            rhs_digout_program_single_manual_fire(
                SAMPLE_RATE_HZ, ch, 0, 100, 1000, 1'b1);
        end
    endtask

    task fire_and_expect_return_low;
        input [3:0] ch;
        input integer wait_frames;
        begin
            live_command(3'd4, ch, accepted);
            check(accepted, "Manual Fire was rejected");
            repeat (wait_frames) sample_frame();
            check(ttl_out[ch] === 1'b0,
                  "TTL did not return low after Manual Fire single pulse");
            check(ttl_rises[ch] >= 1, "Manual Fire did not produce a rising edge");
            check(ttl_falls[ch] >= 1, "Manual Fire did not produce a falling edge");
        end
    endtask

    initial begin
        reset_ttl_counters();
        #2;
        tick(99, 0);
        reset = 0;
        acquisition_running = 1;
        sample_frame();

        // User path: Manual Level high/low, then Sequencer Apply, then Fire.
        reset_ttl_counters();
        rhs_digout_program_manual_level_config(4'd7);
        sample_frame();
        live_command(3'd0, 4'd7, accepted);
        sample_frame();
        check(ttl_out[7] === 1'b1, "Manual High did not drive TTL");
        live_command(3'd1, 4'd7, accepted);
        sample_frame();
        check(ttl_out[7] === 1'b0, "Manual Low did not drive TTL");
        apply_sequencer_config_running(4'd7);
        sample_frame();
        fire_and_expect_return_low(4'd7, 40);
        live_command(3'd4, 4'd7, accepted);
        check(accepted, "rearmed Manual Fire was rejected");
        fire_and_expect_return_low(4'd7, 40);
        $display("PASS: manual toggle then Apply-equivalent then Manual Fire");

        // Host contract: Single + Manual Fire without manual prelude.
        reset_ttl_counters();
        rhs_digout_program_single_manual_fire(
            SAMPLE_RATE_HZ, 4'd6, 0, 100, 1000, 1'b1);
        sample_frame();
        fire_and_expect_return_low(4'd6, 40);
        live_command(3'd4, 4'd6, accepted);
        check(accepted, "second Manual Fire without Apply was rejected");
        fire_and_expect_return_low(4'd6, 40);
        $display("PASS: host Single Manual Fire twice without Apply");

        // Step 4 host contract: Continuous on DIGITAL-OUT-5 and DIGITAL-OUT-4 (ch 5 / ch 3).
        check_host_continuous_on_channel(4'd5);
        $display("PASS: host Continuous train on ttl_out[5] (DIGITAL-OUT-5)");
        check_host_continuous_on_channel(4'd3);
        $display("PASS: host Continuous train on ttl_out[3] (DIGITAL-OUT-4)");

        // Spec: ineligible Fire is rejected; Manual Level ownership unchanged.
        reset_ttl_counters();
        live_command(3'd0, 4'd8, accepted);
        sample_frame();
        check(ttl_out[8] === 1'b1, "Manual High setup failed");
        rhs_digout_program_single_external_trigger(
            SAMPLE_RATE_HZ, 4'd8, 0, 0, 100, 1000);
        sample_frame();
        live_command(3'd4, 4'd8, accepted);
        check(!accepted, "Fire without Manual Fire mode was accepted");
        sample_frame();
        check(ttl_out[8] === 1'b1, "rejected Fire retains Manual Level high");
        live_command(3'd1, 4'd8, accepted);
        sample_frame();
        check(ttl_out[8] === 1'b0, "Manual Low clears TTL");
        $display("PASS: rejected Fire retains manual ownership");

        // Spec: Sequencer Stop and disabled trigger clear / disarm.
        reset_ttl_counters();
        rhs_digout_program_single_manual_fire(
            SAMPLE_RATE_HZ, 4'd9, 0, 100, 1000, 1'b1);
        sample_frame();
        live_command(3'd4, 4'd9, accepted);
        check(accepted, "Fire setup failed");
        repeat (5) sample_frame();
        live_command(3'd3, 4'd9, accepted);
        check(accepted, "Sequencer Stop was rejected");
        sample_frame();
        check(ttl_out[9] === 1'b0, "Sequencer Stop must force TTL low");
        rhs_digout_program_single_manual_fire(
            SAMPLE_RATE_HZ, 4'd9, 0, 100, 1000, 1'b0);
        sample_frame();
        check(digout_enabled[9] === 1'b0, "disabled config clears trigger enable");
        $display("PASS: Stop and disable programming");

        $display("PASS: RHS digital-output integration (in-contract only)");
        $finish;
    end

    always #5 dataclk = ~dataclk;
endmodule
