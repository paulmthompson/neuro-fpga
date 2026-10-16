// Host contract programming for stream-16 (prog_module == 16).
// Register images match Step 4:
//   validateAndQuantizeRhsDigOutConfiguration
//   rhsDigOutTriggerWord / rhsDigOutStimWord
//   setDigitalOutSequenceParameters
//
// SAMPLE_RATE_HZ must match the nominal rate used in host golden tests (30 kHz).

`ifndef RHS_DIGOUT_HOST_PROGRAMMING_VH
`define RHS_DIGOUT_HOST_PROGRAMMING_VH

`define RHS_DIGOUT_EVENT_NEVER 32'hffff_ffff

function [31:0] rhs_digout_us_to_ticks;
    input integer sample_rate_hz;
    input integer microseconds;
    integer numerator;
    begin
        numerator = microseconds * sample_rate_hz;
        rhs_digout_us_to_ticks = (numerator + 500_000) / 1_000_000;
    end
endfunction

// Sequencer + Single pulse + Manual (GUI button) Fire, enabled or not.
task rhs_digout_program_single_manual_fire;
    input integer sample_rate_hz;
    input [3:0] ch;
    input integer delay_us;
    input integer high_us;
    input integer refractory_us;
    input bit enabled;
    reg [31:0] delay_ticks;
    reg [31:0] high_ticks;
    reg [31:0] refractory_ticks;
    reg [31:0] start_tick;
    reg [31:0] end_stim_tick;
    reg [31:0] end_tick;
    reg [31:0] trigger_word;
    begin
        delay_ticks = rhs_digout_us_to_ticks(sample_rate_hz, delay_us);
        high_ticks = rhs_digout_us_to_ticks(sample_rate_hz, high_us);
        refractory_ticks = rhs_digout_us_to_ticks(sample_rate_hz, refractory_us);
        start_tick = delay_ticks;
        end_stim_tick = delay_ticks + high_ticks;
        end_tick = end_stim_tick + refractory_ticks;
        trigger_word = 32'h0000_0100; // Manual Fire bit 8
        if (enabled) begin
            trigger_word = trigger_word | 32'h0000_0080; // trigger enable bit 7
        end
        program_reg(ch, 0, trigger_word);
        program_reg(ch, 1, 32'h0000_0000);
        program_reg(ch, 4, start_tick);
        program_reg(ch, 7, end_stim_tick);
        program_reg(ch, 8, `RHS_DIGOUT_EVENT_NEVER);
        program_reg(ch, 13, end_tick);
    end
endtask

// Sequencer + external trigger (edge, rising, source index), Single pulse, enabled.
task rhs_digout_program_single_external_trigger;
    input integer sample_rate_hz;
    input [3:0] ch;
    input [4:0] trigger_source;
    input integer delay_us;
    input integer high_us;
    input integer refractory_us;
    reg [31:0] delay_ticks;
    reg [31:0] high_ticks;
    reg [31:0] refractory_ticks;
    reg [31:0] start_tick;
    reg [31:0] end_stim_tick;
    reg [31:0] end_tick;
    reg [31:0] trigger_word;
    begin
        delay_ticks = rhs_digout_us_to_ticks(sample_rate_hz, delay_us);
        high_ticks = rhs_digout_us_to_ticks(sample_rate_hz, high_us);
        refractory_ticks = rhs_digout_us_to_ticks(sample_rate_hz, refractory_us);
        start_tick = delay_ticks;
        end_stim_tick = delay_ticks + high_ticks;
        end_tick = end_stim_tick + refractory_ticks;
        trigger_word = 32'h0000_00a0 | trigger_source; // enabled + edge + source
        program_reg(ch, 0, trigger_word);
        program_reg(ch, 1, 32'h0000_0000);
        program_reg(ch, 4, start_tick);
        program_reg(ch, 7, end_stim_tick);
        program_reg(ch, 8, `RHS_DIGOUT_EVENT_NEVER);
        program_reg(ch, 13, end_tick);
    end
endtask

// Sequencer + Continuous train (GUI Start/Stop). Matches validateAndQuantizeRhsDigOutConfiguration
// for Continuous mode: repeat = delay+period ticks, end_stim = delay+high (refractory only in event_end).
task rhs_digout_program_continuous;
    input integer sample_rate_hz;
    input [3:0] ch;
    input integer delay_us;
    input integer high_us;
    input integer period_us;
    input integer refractory_us;
    input bit enabled;
    reg [31:0] delay_ticks;
    reg [31:0] high_ticks;
    reg [31:0] period_ticks;
    reg [31:0] refractory_ticks;
    reg [31:0] start_tick;
    reg [31:0] end_stim_tick;
    reg [31:0] repeat_tick;
    reg [31:0] end_tick;
    reg [31:0] trigger_word;
    begin
        delay_ticks = rhs_digout_us_to_ticks(sample_rate_hz, delay_us);
        high_ticks = rhs_digout_us_to_ticks(sample_rate_hz, high_us);
        period_ticks = rhs_digout_us_to_ticks(sample_rate_hz, period_us);
        refractory_ticks = rhs_digout_us_to_ticks(sample_rate_hz, refractory_us);
        start_tick = delay_ticks;
        end_stim_tick = delay_ticks + high_ticks;
        repeat_tick = delay_ticks + period_ticks;
        end_tick = end_stim_tick + refractory_ticks;
        trigger_word = 32'h0000_0080; // enabled, software-triggered continuous
        if (!enabled) begin
            trigger_word = 32'h0000_0000;
        end
        program_reg(ch, 0, trigger_word);
        program_reg(ch, 1, enabled ? 32'h0000_0100 : 32'h0000_0000);
        program_reg(ch, 4, start_tick);
        program_reg(ch, 7, end_stim_tick);
        program_reg(ch, 8, repeat_tick);
        program_reg(ch, 13, end_tick);
    end
endtask

// Manual Level: trigger disabled; timing registers cleared (host validate early-out).
task rhs_digout_program_manual_level_config;
    input [3:0] ch;
    begin
        program_reg(ch, 0, 32'h0000_0000);
        program_reg(ch, 1, 32'h0000_0000);
        program_reg(ch, 4, 32'd0);
        program_reg(ch, 7, 32'd0);
        program_reg(ch, 8, `RHS_DIGOUT_EVENT_NEVER);
        program_reg(ch, 13, 32'd0);
    end
endtask

`endif
