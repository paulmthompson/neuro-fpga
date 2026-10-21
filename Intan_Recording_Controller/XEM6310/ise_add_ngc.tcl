# Register precompiled netlists for ISE (Edalize ise backend does not add .ngc).
# Do not add main.ngc; top is main.v.
set _ngc_dir [file dirname [info script]]
foreach ngc {
    fifo_w16_4096_r32_2048.ngc
    fifo_w32_2048_r32_2048.ngc
    multiplier_18x18.ngc
    multiplier.ngc
    okBTPipeIn.ngc
    okBTPipeOut.ngc
    okCoreHarness.ngc
    okCoreHarnessNoAuth.ngc
    okPipeIn.ngc
    okPipeOut.ngc
    okRegisterBridge.ngc
    okTriggerIn.ngc
    okTriggerOut.ngc
    okWireIn.ngc
    okWireOut.ngc
    TFIFO64x8a_64x8b.ngc
} {
    xfile_add_exist_ok [file join $_ngc_dir $ngc]
}
