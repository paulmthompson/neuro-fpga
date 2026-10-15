# RHS FPGA simulation tests

The tests in this directory exercise standalone RHS Verilog modules. 

## Requirements

On Ubuntu, install Icarus Verilog if necessary:

```sh
sudo apt install iverilog
```

This provides `iverilog` (compiler) and `vvp` (simulator). The test was developed with Icarus Verilog 12.0.

## Run

From the root of the `neuro-fpga` repository:

```sh
bash tests/run-rhs-digout.sh
```

The script compiles into a temporary directory, runs a self-checking testbench, and deletes its build artifacts. It exits nonzero on an assertion failure; a successful run ends with `PASS: RHS digital sequencer baseline`.

`rhs_digout_sequencer_tb.v` drives the current `RHS_Recording_Controller/XEM6010/digout_sequencer.v` directly, supplying the relevant `main.v` states and channel progression. It checks independent single/finite pulses, edge-trigger rearming, pulse spacing, and the current behavior of maintenance and shared sequencer reset. 
