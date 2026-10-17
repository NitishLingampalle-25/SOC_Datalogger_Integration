/* soc_link.ld — Linker script for VeeR EL2 SoC firmware
 *
 * Memory map:
 *   ICCM  0x0000_0000  32 KB  (instruction + read-only data)
 *   DCCM  0xF004_0000  64 KB  (stack + BSS + data)
 *
 * Generate hex:
 *   riscv32-unknown-elf-objcopy -O ihex soc_full_test.elf soc_full_test.hex
 */

MEMORY {
    ICCM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    DCCM (rwx) : ORIGIN = 0xF0040000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS {
    .text : {
        *(.text.startup)
        *(.text*)
        *(.rodata*)
    } > ICCM

    .data : {
        *(.data*)
    } > DCCM AT > ICCM

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > DCCM

    /* Stack — grows down from top of DCCM */
    __stack_top = ORIGIN(DCCM) + LENGTH(DCCM);
}
