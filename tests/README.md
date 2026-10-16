# RHS FPGA simulation tests

Run from the `neuro-fpga` repository root with Icarus Verilog (`iverilog` and `vvp`):

```sh
bash tests/run-rhs-digout.sh
```

On Ubuntu, `sudo apt install iverilog` installs both tools. The runner writes compiled output to a temporary directory and exits nonzero on a failed assertion.

## What these tests are for

FPGA benches verify **in-contract** behavior: the host sends valid stream-16 programming (`programStimReg` / Step 4 `setDigitalOutSequenceParameters`) and valid live opcodes on WireIn `0x0e` + TriggerIn `0x41[2]`. They do **not** deliberately under-program the FPGA or leave factory-init event registers in place.

Shared register images live in [`rhs_digout_host_programming.vh`](rhs_digout_host_programming.vh). Keep this file aligned with [`rhsdigoutconfiguration.cpp`](../../../Engine/Processing/rhsdigoutconfiguration.cpp) in the Intan-RHX tree (30 kHz nominal rate in sim).

Host-only golden checks (no Verilog), from the **Intan-RHX** repository root:

```sh
bash tests/run-rhs-digout-host-golden.sh
```

Requires Qt5Core (`pkg-config Qt5Core`).

## Benches

| Bench | Scope |
| --- | --- |
| `rhs_digout_sequencer_tb.v` | `digout_sequencer.v` — pulse trains, continuous, Manual Fire, maintenance, Stop |
| `rhs_digout_output_control_tb.v` | `digout_output_control.v` — mux, manual level, threshold, command acceptance |
| `rhs_digout_integration_tb.v` | Both modules — **`ttl_out`**, manual prelude → Apply → Manual Fire; host Single/Continuous with **exact** high/period checks on **ttl_out[5] and ttl_out[3]** (DIGITAL-OUT-5 / DIGITAL-OUT-4) |

The sequencer bench still includes **legacy** `configure_pin` / `configure_manual_fire_pin` helpers (finite-train repeat tick). New **host contract** cases use `rhs_digout_host_programming.vh` (Single pulse, `EventRepeatStim = Never`).

**Waveform assertions:** `rhs_digout_sequencer_tb` checks finite pulse **counts** and **legacy** continuous period (repeat register = period ticks, start = 0). Only `rhs_digout_integration_tb` checks the **Step 4** continuous image (repeat = delay + period): each pulse high for `high_ticks` frames, rise-to-rise spacing `period_ticks` frames at 30 kHz. Host golden tests verify **register ticks only**, not `ttl_out` timing.

They do not simulate Opal Kelly USB, the full top-level design, or ISE synthesis. Measure physical pins after building a matching bitfile.
