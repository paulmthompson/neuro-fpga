`timescale 1ns / 1ps
`default_nettype none

// RHS board TTL source selection and live output controls. The host sends a
// channel/opcode on WireIn 0x0e, then strobes TriggerIn 0x41[2] (dataclk).
// A command changes one latched output, not a stream of timed USB edges.
//
// Command word 0x0e: [3:0] zero-based channel, [6:4] opcode, [15:7] reserved.
//  0 Manual High; 1 Manual Low; 2 Continuous Start; 3 Sequencer Stop/disarm;
//  4 Manual Fire; 5-7 reserved. Live commands are ignored while stopped.
// Threshold selection (0x13[7:0]) has priority over manual source on pins 1-8.
// All physical TTL pins are held low while acquisition_running is low. Manual
// state is cleared on Stop so a later Run cannot restore an old high level.
// amp_maintenance is deliberately not an input: it must not gate the pins.
// WireOut 0x27 = 0x4453 ('DS') in main.v identifies the Step 3 protocol.
// As with the other RHS controls, this is for the XEM6010 project only.
module digout_output_control (
    input wire dataclk,
    input wire reset,
    input wire command_strobe,
    input wire sequencer_command_accepted,
    input wire [6:0] command_word,
    input wire acquisition_running,
    input wire [7:0] threshold_mode,
    input wire [7:0] threshold_out,
    input wire [15:0] sequencer_out,
    output wire [15:0] ttl_out
);
    localparam [2:0] CMD_MANUAL_HIGH   = 3'd0;
    localparam [2:0] CMD_MANUAL_LOW    = 3'd1;
    localparam [2:0] CMD_CONTINUOUS_ON = 3'd2;
    localparam [2:0] CMD_SEQUENCE_STOP = 3'd3;
    localparam [2:0] CMD_FIRE          = 3'd4;

    reg [15:0] manual_source;
    reg [15:0] manual_level;

    wire [3:0] selected_channel = command_word[3:0];
    wire [2:0] opcode = command_word[6:4];
    wire [15:0] threshold_selected = {8'b0, threshold_mode & threshold_out};
    wire [15:0] sequencer_selected = sequencer_out & ~{8'b0, threshold_mode};
    wire [15:0] automatic_out = threshold_selected | sequencer_selected;
    // A previously selected manual level cannot hide a newly selected
    // DAC-threshold source; do not give two controls ownership of the pin.
    wire [15:0] active_manual_source = manual_source & ~{8'b0, threshold_mode};

    assign ttl_out = (!acquisition_running || reset) ? 16'b0 :
                     ((active_manual_source & manual_level) | (~active_manual_source & automatic_out));

    always @(posedge dataclk) begin
        if (reset || !acquisition_running) begin
            manual_source <= 16'b0;
            manual_level <= 16'b0;
        end else begin
            if (command_strobe) begin
                case (opcode)
                CMD_MANUAL_HIGH: begin
                    // Threshold mode owns TTL 1-8; do not override it.
                    if (selected_channel >= 8 || !threshold_mode[selected_channel]) begin
                        manual_level[selected_channel] <= 1'b1;
                        manual_source[selected_channel] <= 1'b1;
                    end
                end
                CMD_MANUAL_LOW: begin
                    if (selected_channel >= 8 || !threshold_mode[selected_channel]) begin
                        manual_level[selected_channel] <= 1'b0;
                        manual_source[selected_channel] <= 1'b1;
                    end
                end
                CMD_CONTINUOUS_ON, CMD_SEQUENCE_STOP, CMD_FIRE: begin
                    // Release stale Manual Level ownership only when the
                    // sequencer accepted this action. Stop is always accepted
                    // while running and is also the source-transition disarm.
                    if (sequencer_command_accepted) begin
                        manual_level[selected_channel] <= 1'b0;
                        manual_source[selected_channel] <= 1'b0;
                    end
                end
                default: begin
                end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
