These are the verilog files necessary for building custom bitfiles for the FPGAs in the Intan Recording Controller.

You will need to use my custom IntanRHX implementation as well to take advantage of these:
https://github.com/paulmthompson/Intan-RHX


## Summary of Changes:

### RHS Stimulation Controller Summary of Changes:

Stimulation parameters like pulse duration, delay etc were communicated to the FPGA with 16-bit numbers. This limited the maximum value to be very short (~ 5ms). The fpga was modified to accept 32-bit unsigned integers, allowing for significantly longer stimulation values (10s is now set as maximum duration for these values instead of 5 ms). The GUI was updated to accomodate these limits.

## Future Directions

