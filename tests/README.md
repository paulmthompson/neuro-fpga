# RHS FPGA simulation tests

Run from the `neuro-fpga` repository root with Icarus Verilog (`iverilog` and `vvp`):

```sh
bash tests/run-rhs-digout.sh
```

On Ubuntu, `sudo apt install iverilog` installs both tools. The runner writes compiled output to a temporary directory and exits nonzero on a failed assertion. These are **module-level** tests of `RHS_Recording_Controller/XEM6010/digout_sequencer.v` and `digout_output_control.v`. The sequencer bench approximates the states/channels it receives from `main.v`; the output-control bench checks command decoding and source priority. They do not simulate Opal Kelly, the complete top-level design, USB transfers, or ISE 14.7 synthesis. Measure physical pins after building a matching bitfile.

The runner executes `rhs_digout_sequencer_tb.v` and `rhs_digout_output_control_tb.v`. The sequencer bench retains 1/2/3/256-pulse, edge/level, pulse-width, and shutdown regressions. Finite trains preserve their historical six-frame rise-to-rise interval for a programmed five-tick repeat. Continuous mode instead requires the requested five-frame period and tests per-channel Start/Stop, fresh restart, ignored external triggers, Manual Fire isolation/busy rejection/rearm, threshold ownership, acquisition Stop clearing, concurrent modes, and maintenance-transparent phase and edge counts. The shared amplifier/analog reset is intentionally absent from the digital module interface.

`rhs_digout_output_control_tb.v` checks the physical output foundation: commands are ignored and every source stays low while acquisition is stopped; during Run, independent manual pins, DAC-threshold priority, and sequencer outputs operate. It checks that Stop needs no USB command, an old manual high does not return on a later Run, rejected sequencer requests retain Manual Level ownership, and accepted Start/Stop/Fire actions release stale manual ownership.
