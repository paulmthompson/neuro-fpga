#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core="$root/rtl/cores"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

iverilog -g2012 -I"$root/tests" -s rhs_digout_sequencer_tb -o "$tmp/rhs_digout_sequencer.vvp" \
    "$root/tests/rhs_digout_sequencer_tb.v" \
    "$core/digout_sequencer.v"
vvp "$tmp/rhs_digout_sequencer.vvp"

iverilog -g2012 -s rhs_digout_output_control_tb -o "$tmp/rhs_digout_output_control.vvp" \
    "$root/tests/rhs_digout_output_control_tb.v" \
    "$core/digout_output_control.v"
vvp "$tmp/rhs_digout_output_control.vvp"

iverilog -g2012 -I"$root/tests" -s rhs_digout_integration_tb -o "$tmp/rhs_digout_integration.vvp" \
    "$root/tests/rhs_digout_integration_tb.v" \
    "$core/digout_sequencer.v" \
    "$core/digout_output_control.v"
vvp "$tmp/rhs_digout_integration.vvp"

iverilog -g2012 -s rhd_digout_sequencer_tb -o "$tmp/rhd_digout_sequencer.vvp" \
    "$root/tests/rhd_digout_sequencer_tb.v" \
    "$core/digout_sequencer.v"
vvp "$tmp/rhd_digout_sequencer.vvp"
