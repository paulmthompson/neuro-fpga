These are the verilog files necessary for building custom bitfiles for the FPGAs in the Intan Recording Controller.

You will need to use my custom IntanRHX implementation as well to take advantage of these:
https://github.com/paulmthompson/Intan-RHX


## Summary of Changes:

### RHS Stimulation Controller Summary of Changes:

Stimulation parameters like pulse duration, delay etc were communicated to the FPGA with 16-bit numbers. This limited the maximum value to be very short (~ 5ms). The fpga was modified to accept 32-bit unsigned integers, allowing for significantly longer stimulation values (10s is now set as maximum duration for these values instead of 5 ms). The GUI was updated to accomodate these limits.

## Building bitstreams (FuseSoC + ISE 14.7)

Prerequisites: [uv](https://docs.astral.sh/uv/), Xilinx ISE 14.7 (`xtclsh` on `PATH`, or set `XILINX_ISE_SETTINGS` to `settings64.sh`).

```sh
cd FPGA-bitfiles/neuro-fpga   # or clone neuro-fpga repo root
uv sync
uv run fusesoc list-cores
```

RHS (XEM6010):

```sh
export XILINX_ISE_SETTINGS=/path/to/Xilinx/14.7/ISE_DS/settings64.sh   # if needed
source /path/to/Xilinx/14.7/ISE_DS/settings64.sh
bash scripts/fuse-build.sh rhs
# Logs xtclsh/ISE output to the terminal and build/rhs-xem6010/fuse-build.log (uses fusesoc --verbose).
# or: uv run fusesoc --verbose run --work-root=build/rhs-xem6010 --target=bitstream paulmthompson:neuro-fpga:rhs_xem6010:0.1.0
```

RHD (XEM6310):

```sh
bash scripts/fuse-build.sh rhd
```

Expected artifact: `build/<rhs-xem6010|rhd-xem6310>/main.bit`.

RTL simulation (no ISE): see [tests/README.md](tests/README.md).

## Future Directions


Shared digital-output RTL lives under [`rtl/cores/`](rtl/cores/) (`digout_sequencer.v`, `digout_output_control.v`), built via FuseSoC core `paulmthompson:neuro-fpga:rhythm_shared:0.1.0`. RHS uses WireIn `0x0e` and TriggerIn `0x41[2]` for live commands, WireIn `0x06`/`0x07`/`0x0b` plus TriggerIn `0x42[1]` for stream-16 programming, and WireIn `0x0f` for the shared analog-IN comparator threshold. RHD (XEM6310) uses WireIn `0x15[6:0]` and TriggerIn `0x41[2]` for live commands, `0x15[31:16]` for the same analog threshold, WireIn `0x12[7:0]` for F1–F8 manual triggers, WireIn `0x10`/`0x11` plus TriggerIn `0x43[1]` for stream-16 programming, packed aux max/loop on `0x0b`/`0x0c`, DAC threshold via WireIn `0x1f` and TriggerIn `0x42`, with WireOut `0x27 = 0x4453` on both boards. IntanRHX remaps aux length and DAC threshold USB traffic when that signature is present.
