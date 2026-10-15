#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

iverilog -g2012 -s rhs_digout_sequencer_tb -o "$tmp/rhs_digout_sequencer.vvp" \
    "$root/tests/rhs_digout_sequencer_tb.v" \
    "$root/RHS_Recording_Controller/XEM6010/digout_sequencer.v"
vvp "$tmp/rhs_digout_sequencer.vvp"
