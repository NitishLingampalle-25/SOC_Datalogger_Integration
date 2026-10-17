# crt0.s — Minimal startup for VeeR EL2 (RV32IMC, no OS)
# Sets up stack, zeroes BSS, then jumps to main.

    .section .text.startup
    .globl  _start
    .type   _start, @function

_start:
    # Set stack pointer to top of DCCM
    la      sp, __stack_top

    # Zero BSS
    la      t0, __bss_start
    la      t1, __bss_end
    beq     t0, t1, .Lbss_done
.Lbss_loop:
    sw      zero, 0(t0)
    addi    t0, t0, 4
    blt     t0, t1, .Lbss_loop
.Lbss_done:

    # Call main
    call    main

    # Halt — should never return
.Lhalt:
    nop
    j       .Lhalt

    .size _start, . - _start
