// Seed and capture x8 around the *production* trampoline; all argument regs survive.
.text
.p2align 2
.macro PROBE name, callback
.globl _Probe\name
_Probe\name:
    mov x8, #0x5678
    b _H120Range\name
.globl _Capture\name
_Capture\name:
    adrp x16, _H120ObservedX8@PAGE
    str x8, [x16, _H120ObservedX8@PAGEOFF]
    b _\callback
.endmacro
PROBE TimingsBB, H120TestBB
PROBE TimingsB, H120TestOne
PROBE Convert, H120TestConvert
PROBE Source, H120TestOne
PROBE ItemLocked, H120TestOne
PROBE Item, H120TestBB
