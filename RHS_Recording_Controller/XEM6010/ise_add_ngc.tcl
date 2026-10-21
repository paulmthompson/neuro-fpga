# Register precompiled netlists for ISE (Edalize ise backend does not add .ngc).
# Do not add main.ngc; top is main.v.
set _ngc_dir [file dirname [info script]]
foreach ngc {
    fifo_w16_2048_r64_512.ngc
    fifo_w64_512_r16_2048.ngc
    multiplier_18x18.ngc
    multiplier.ngc
    okBTPipeIn.ngc
    okBTPipeOut.ngc
    okCoreHarness.ngc
    okPipeIn.ngc
    okPipeOut.ngc
    okTriggerIn.ngc
    okTriggerOut.ngc
    okWireIn.ngc
    okWireOut.ngc
    TFIFO64x8a_64x8b.ngc
} {
    xfile_add_exist_ok [file join $_ngc_dir $ngc]
}
