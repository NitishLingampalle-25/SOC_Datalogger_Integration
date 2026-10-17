/* =============================================================================
 * soc_full_test.c  –  Full-SoC firmware for veer2_dma_aes_wdt_uart_gpio_timer
 *
 * Target  : RV32IMC  (VeeR EL2, reset vec 0x0000_0000)
 * Compile :
 *   riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -O1 -nostdlib \
 *       -Wl,--script=soc_link.ld -o soc_full_test.elf soc_full_test.c crt0.s
 *   riscv32-unknown-elf-objcopy -O ihex soc_full_test.elf soc_full_test.hex
 *
 * Coverage (mirrors TB TCs 01-28):
 *   1.  UART  – LCR (8N1), BAUD, IER, THR write, LSR poll, RBR read-back
 *   2.  Timer – CFG0, CMP_LO/HI, CTRL enable, interrupt-status poll
 *   3.  AES   – NIST FIPS-197 key+plaintext load, START, busy poll, CT read
 *   4.  DMA   – CSR version read, descriptor write (SRC/DST), START
 *   5.  WDT   – LOAD, CTRL enable, SW ping, timeout/IRQ, NMI/reset escalation
 *   6.  GPIO  – EN write, OUT write, IN read, rising-edge IRQ enable
 *
 * Pass/fail is reported by writing a magic word to a "tohost" memory-mapped
 * location (0xF000_0000) — the testbench can monitor that address.
 * Additionally, any FAIL causes the VeeR core to spin in an infinite loop so
 * the simulator watchdog kills it, making failures visible as timeouts.
 * =============================================================================
 */

#include <stdint.h>

/* -------------------------------------------------------------------------
 * Memory-mapped peripheral base addresses
 * ------------------------------------------------------------------------- */
#define UART_BASE   0x40000000u
#define TIMER_BASE  0x40001000u
#define AES_BASE    0x40002000u
#define DMA_BASE    0x40003000u
#define WDT_BASE    0x40004000u
#define GPIO_BASE   0x40005000u

/* -------------------------------------------------------------------------
 * UART registers (offsets from UART_BASE)
 * ------------------------------------------------------------------------- */
#define UART_THR   (*(volatile uint32_t *)(UART_BASE + 0x00))  /* TX holding  */
#define UART_RBR   (*(volatile uint32_t *)(UART_BASE + 0x00))  /* RX buffer   */
#define UART_IER   (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_BAUD  (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_LCR   (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_LSR   (*(volatile uint32_t *)(UART_BASE + 0x14))

#define LSR_DATA_RDY  (1u << 0)
#define LSR_THRE      (1u << 5)
#define LSR_TEMT      (1u << 6)
#define SIM_BAUD_DIV  10u

/* -------------------------------------------------------------------------
 * System Timer registers
 * ------------------------------------------------------------------------- */
#define TIMER_CTRL      (*(volatile uint32_t *)(TIMER_BASE + 0x000))
#define TIMER_INTR_EN   (*(volatile uint32_t *)(TIMER_BASE + 0x100))
#define TIMER_INTR_ST   (*(volatile uint32_t *)(TIMER_BASE + 0x104))
#define TIMER_CFG0      (*(volatile uint32_t *)(TIMER_BASE + 0x10C))
#define TIMER_VAL_LO    (*(volatile uint32_t *)(TIMER_BASE + 0x110))
#define TIMER_VAL_HI    (*(volatile uint32_t *)(TIMER_BASE + 0x114))
#define TIMER_CMP_LO    (*(volatile uint32_t *)(TIMER_BASE + 0x118))
#define TIMER_CMP_HI    (*(volatile uint32_t *)(TIMER_BASE + 0x11C))

/* -------------------------------------------------------------------------
 * AES Engine registers
 * ------------------------------------------------------------------------- */
#define AES_CTRL_REG (*(volatile uint32_t *)(AES_BASE + 0x00))
#define AES_STATUS   (*(volatile uint32_t *)(AES_BASE + 0x04))
#define AES_KEY0     (*(volatile uint32_t *)(AES_BASE + 0x08))
#define AES_KEY1     (*(volatile uint32_t *)(AES_BASE + 0x0C))
#define AES_KEY2     (*(volatile uint32_t *)(AES_BASE + 0x10))
#define AES_KEY3     (*(volatile uint32_t *)(AES_BASE + 0x14))
#define AES_TXTIN0   (*(volatile uint32_t *)(AES_BASE + 0x18))
#define AES_TXTIN1   (*(volatile uint32_t *)(AES_BASE + 0x1C))
#define AES_TXTIN2   (*(volatile uint32_t *)(AES_BASE + 0x20))
#define AES_TXTIN3   (*(volatile uint32_t *)(AES_BASE + 0x24))
#define AES_TXTOUT0  (*(volatile uint32_t *)(AES_BASE + 0x28))
#define AES_TXTOUT1  (*(volatile uint32_t *)(AES_BASE + 0x2C))
#define AES_TXTOUT2  (*(volatile uint32_t *)(AES_BASE + 0x30))
#define AES_TXTOUT3  (*(volatile uint32_t *)(AES_BASE + 0x34))

#define AES_STATUS_IDLE       0u
#define AES_STATUS_PROCESSING 1u
#define AES_STATUS_COMPLETE   2u

/* -------------------------------------------------------------------------
 * DMA Controller CSRs
 * ------------------------------------------------------------------------- */
#define DMA_CTRL_REG  (*(volatile uint32_t *)(DMA_BASE + 0x00))
#define DMA_STAT_REG  (*(volatile uint32_t *)(DMA_BASE + 0x08))
#define DMA_ERR_REG   (*(volatile uint32_t *)(DMA_BASE + 0x10))
#define DMA_DESC0_SRC (*(volatile uint32_t *)(DMA_BASE + 0x20))
#define DMA_DESC0_DST (*(volatile uint32_t *)(DMA_BASE + 0x30))

#define DMA_CTRL_START   (1u << 0)
#define DMA_CTRL_IRQ_EN  (1u << 1)
#define DMA_STAT_BUSY    (1u << 0)
#define DMA_STAT_DONE    (1u << 1)
#define DMA_STAT_ERROR   (1u << 2)

/* DCCM start address used as DMA destination (VeeR EL2 default) */
#define DCCM_BASE 0xF0040000u

/* -------------------------------------------------------------------------
 * Watchdog Timer registers
 * ------------------------------------------------------------------------- */
#define WDT_LOAD (*(volatile uint32_t *)(WDT_BASE + 0x04))
#define WDT_CTRL (*(volatile uint32_t *)(WDT_BASE + 0x08))
#define WDT_PING (*(volatile uint32_t *)(WDT_BASE + 0x0C))
#define WDT_IM   (*(volatile uint32_t *)(WDT_BASE + 0x10))
#define WDT_RIS  (*(volatile uint32_t *)(WDT_BASE + 0x14))
#define WDT_MIS  (*(volatile uint32_t *)(WDT_BASE + 0x18))
#define WDT_IC   (*(volatile uint32_t *)(WDT_BASE + 0x1C))

#define WDT_CTRL_EN        (1u << 0)
#define WDT_CTRL_AUTOKICK  (1u << 1)
#define WDT_CTRL_NMI_EN    (1u << 2)
#define WDT_CTRL_RESET_EN  (1u << 3)

/* -------------------------------------------------------------------------
 * GPIO registers
 * ------------------------------------------------------------------------- */
#define GPIO_EN_REG   (*(volatile uint32_t *)(GPIO_BASE + 0x080))
#define GPIO_IN_REG   (*(volatile uint32_t *)(GPIO_BASE + 0x100))
#define GPIO_OUT_REG  (*(volatile uint32_t *)(GPIO_BASE + 0x180))
#define GPIO_RISE_EN  (*(volatile uint32_t *)(GPIO_BASE + 0x380))
#define GPIO_INT_STAT (*(volatile uint32_t *)(GPIO_BASE + 0x580))

/* -------------------------------------------------------------------------
 * Test result "tohost" register — TB monitors this address.
 * Write 0x1 = PASS, 0xDEAD = FAIL (any individual step).
 * Final 0x900D = all tests passed.
 * ------------------------------------------------------------------------- */
#define TOHOST (*(volatile uint32_t *)0xF0000000u)

/* -------------------------------------------------------------------------
 * NIST FIPS-197 Appendix B test vector
 * Key    : 2b7e1516 28aed2a6 abf71588 09cf4f3c
 * Plain  : 3243f6a8 885a308d 3131982a e0370734
 * Cipher : 3925841d 02dc09fb dc118597 196a0b32
 * ------------------------------------------------------------------------- */
#define AES_KEY_W0  0x2b7e1516u
#define AES_KEY_W1  0x28aed2a6u
#define AES_KEY_W2  0xabf71588u
#define AES_KEY_W3  0x09cf4f3cu

#define AES_PT_W0   0x3243f6a8u
#define AES_PT_W1   0x885a308du
#define AES_PT_W2   0x3131982au
#define AES_PT_W3   0xe0370734u

#define AES_CT_W0   0x3925841du
#define AES_CT_W1   0x02dc09fbu
#define AES_CT_W2   0xdc118597u
#define AES_CT_W3   0x196a0b32u

/* -------------------------------------------------------------------------
 * Simple spin-delay (calibrated for 100 MHz / VeeR timing)
 * ------------------------------------------------------------------------- */
static inline void delay(uint32_t cycles)
{
    volatile uint32_t i;
    for (i = 0; i < cycles; i++)
        __asm__ volatile ("nop");
}

/* -------------------------------------------------------------------------
 * Fail trap — write tohost and spin so the TB watchdog catches it
 * ------------------------------------------------------------------------- */
static void fail_trap(uint32_t step)
{
    TOHOST = 0xDEAD0000u | (step & 0xFFFFu);
    while (1) { __asm__ volatile ("nop"); }
}

/* =========================================================================
 * TEST FUNCTIONS
 * ========================================================================= */

/* --- TC01/TC02: Post-reset (nothing to actively write — TB checks outputs) */

/* --- TC03-TC06: UART ---------------------------------------------------- */
static void test_uart(void)
{
    uint32_t lsr;

    /* LCR: 8N1 */
    UART_LCR  = 0x03u;
    if (UART_LCR != 0x03u) fail_trap(3);

    /* Baud divisor */
    UART_BAUD = SIM_BAUD_DIV;

    /* IER: RX data available interrupt enable */
    UART_IER  = 0x01u;
    if (UART_IER != 0x01u) fail_trap(3);

    /* TC04: Poll THRE then write 'K' to TX */
    do { lsr = UART_LSR; } while (!(lsr & LSR_THRE));
    UART_THR = 0x4Bu;   /* 'K' */

    /* TC05/TC06: Wait for TX to drain */
    do { lsr = UART_LSR; } while (!(lsr & LSR_TEMT));

    /*
     * TC06: RX loopback — in the BFM-driven TB the uart_inject_byte task
     * drives the serial line externally; firmware just polls LSR and reads RBR.
     * When running with real firmware, the loopback is provided by the TB.
     */
    do { lsr = UART_LSR; } while (!(lsr & LSR_DATA_RDY));
    {
        uint32_t rx = UART_RBR & 0xFFu;
        /* Expected: 0xA5 injected by TB uart_inject_byte task */
        if (rx != 0xA5u) fail_trap(6);
    }

    TOHOST = 0x0006u;   /* TC06 passed */
}

/* --- TC07-TC09: System Timer -------------------------------------------- */
static void test_timer(void)
{
    uint32_t t0, t1;

    /* prescaler=9 (bits[19:8]), step=1 (bits[7:0]) → tick every 10 clocks */
    TIMER_CFG0   = 0x00000901u;
    /* Max compare initially */
    TIMER_CMP_LO = 0xFFFFFFFFu;
    TIMER_CMP_HI = 0xFFFFFFFFu;
    /* Enable */
    TIMER_CTRL   = 0x1u;

    /* TC08: counter must advance */
    t0 = TIMER_VAL_LO;
    delay(50u);
    t1 = TIMER_VAL_LO;
    if (t1 <= t0) fail_trap(8);

    /* TC09: set compare just above current count and wait for IRQ status */
    t0 = TIMER_VAL_LO;
    TIMER_CMP_LO = t0 + 100u;
    TIMER_CMP_HI = 0x0u;
    TIMER_INTR_EN = 0x1u;
    {
        uint32_t tmo = 0u;
        while (!(TIMER_INTR_ST & 0x1u)) {
            if (++tmo > 100000u) fail_trap(9);
        }
    }
    TIMER_INTR_ST = 0x1u;  /* W1C */

    TOHOST = 0x0009u;   /* TC09 passed */
}

/* --- TC10-TC13: AES Engine ---------------------------------------------- */
static void test_aes(void)
{
    /* TC10: Key + plaintext load */
    AES_KEY0   = AES_KEY_W0;
    AES_KEY1   = AES_KEY_W1;
    AES_KEY2   = AES_KEY_W2;
    AES_KEY3   = AES_KEY_W3;
    AES_TXTIN0 = AES_PT_W0;
    AES_TXTIN1 = AES_PT_W1;
    AES_TXTIN2 = AES_PT_W2;
    AES_TXTIN3 = AES_PT_W3;

    /* TC11: START */
    AES_CTRL_REG = 0x01u;

    /* TC12: Wait for COMPLETE status */
    {
        uint32_t tmo = 0u;
        while (AES_STATUS != AES_STATUS_COMPLETE) {
            if (++tmo > 100000u) fail_trap(12);
        }
    }

    /* TC13: Ciphertext read-back */
    if (AES_TXTOUT0 != AES_CT_W0) fail_trap(13);
    if (AES_TXTOUT1 != AES_CT_W1) fail_trap(13);
    if (AES_TXTOUT2 != AES_CT_W2) fail_trap(13);
    if (AES_TXTOUT3 != AES_CT_W3) fail_trap(13);

    TOHOST = 0x0013u;   /* TC13 passed */
}

/* --- TC14-TC16: DMA Controller ----------------------------------------- */
static void test_dma(void)
{
    /* TC14: CSR read — just verify OKAY response (no bus error) */
    volatile uint32_t ctrl_rd = DMA_CTRL_REG;
    volatile uint32_t stat_rd = DMA_STAT_REG;
    (void)ctrl_rd; (void)stat_rd;

    /* TC15: Descriptor setup — DMA from UART base → DCCM */
    DMA_DESC0_SRC = UART_BASE;
    DMA_DESC0_DST = DCCM_BASE;
    DMA_CTRL_REG  = DMA_CTRL_START | DMA_CTRL_IRQ_EN;

    /* TC16: Poll for done */
    {
        uint32_t tmo = 0u;
        while (!(DMA_STAT_REG & DMA_STAT_DONE)) {
            if (DMA_STAT_REG & DMA_STAT_ERROR) fail_trap(16);
            if (++tmo > 200000u) fail_trap(16);
        }
    }

    TOHOST = 0x0016u;   /* TC16 passed */
}

/* --- TC17-TC21: Watchdog Timer ----------------------------------------- */
static void test_wdt(void)
{
    /* TC17: LOAD + CTRL enable (generous window so it does NOT fire yet) */
    WDT_LOAD = 0x00100000u;     /* ~1M cycles */
    WDT_IM   = 0x01u;           /* unmask IRQ */
    WDT_CTRL = WDT_CTRL_EN | WDT_CTRL_AUTOKICK;

    /* TC18: SW ping — write any value to PING register */
    delay(20u);
    WDT_PING = 0xABCDEF01u;
    delay(5u);
    /* IRQ should NOT have fired */
    if (WDT_MIS & 0x1u) fail_trap(18);

    /*
     * TC19: AES auto-kick — fire another AES encrypt;
     * the aes_done_pulse_o is wired to WDT kick input inside the DUT.
     * After AES completes, the WDT counter should have reloaded.
     */
    AES_TXTIN0 = AES_PT_W0; AES_TXTIN1 = AES_PT_W1;
    AES_TXTIN2 = AES_PT_W2; AES_TXTIN3 = AES_PT_W3;
    AES_CTRL_REG = 0x01u;
    {
        uint32_t tmo = 0u;
        while (AES_STATUS != AES_STATUS_COMPLETE) {
            if (++tmo > 100000u) fail_trap(19);
        }
    }
    /* WDT should still be running, not timed out */
    if (WDT_MIS & 0x1u) fail_trap(19);

    /* TC20: Shorten window so IRQ fires, then W1C clear */
    WDT_CTRL = WDT_CTRL_EN;                 /* disable auto-kick */
    WDT_LOAD = 0x10u;                       /* 16-cycle timeout */
    WDT_CTRL = WDT_CTRL_EN;
    {
        uint32_t tmo = 0u;
        while (!(WDT_RIS & 0x1u)) {
            if (++tmo > 200000u) fail_trap(20);
        }
    }
    WDT_IC = 0xFFFFFFFFu;   /* W1C */
    delay(3u);
    if (WDT_RIS & 0x1u) fail_trap(20);

    /*
     * TC21: NMI + hard reset escalation.
     * Enable NMI_EN and RESET_EN with tiny window.
     * Once wdt_reset_o fires the TB will observe it;
     * firmware will be in spin here (reset kills it externally).
     */
    WDT_CTRL = WDT_CTRL_EN | WDT_CTRL_NMI_EN | WDT_CTRL_RESET_EN;
    WDT_LOAD = 0x08u;
    /* Wait for WDT to escalate — TB watches wdt_nmi_o / wdt_reset_o */
    {
        uint32_t tmo = 0u;
        while (!(WDT_RIS & 0x1u)) {
            if (++tmo > 200000u) fail_trap(21);
        }
    }
    /* Disable to stop continuous assertion */
    WDT_CTRL = 0x00u;
    WDT_IC   = 0xFFFFFFFFu;

    TOHOST = 0x0021u;   /* TC17–TC21 passed */
}

/* --- TC22-TC25: GPIO --------------------------------------------------- */
static void test_gpio(void)
{
    /* TC22: Output enable + write */
    GPIO_EN_REG  = 0x000000FFu;    /* lower 8 bits output */
    GPIO_OUT_REG = 0xA5u;

    /* TC23: gpio_out_o verified by TB (firmware cannot self-check its own output
     * pins in a purely internal sense, but we can read back the OUT register) */
    delay(3u);
    /* (TB monitors gpio_out_o == 0xA5 externally) */

    /*
     * TC24: gpio_in_i is driven externally by TB to 0x5A5A_A5A5.
     * Read GPIO_IN_REG to exercise the read path.
     */
    {
        volatile uint32_t in_val = GPIO_IN_REG;
        /* TB drives the physical pin; we can only verify read doesn't hang */
        (void)in_val;
    }

    /* TC25: Enable rising-edge interrupt on bit 0.
     * TB drives a 0→1 transition on gpio_in_i[0] afterwards. */
    GPIO_RISE_EN = 0x00000001u;

    {
        uint32_t tmo = 0u;
        /* Wait for interrupt status to set (TB drives the edge externally) */
        while (!(GPIO_INT_STAT & 0x1u)) {
            if (++tmo > 200000u) fail_trap(25);
        }
    }
    GPIO_INT_STAT = 0xFFFFFFFFu;   /* W1C */

    TOHOST = 0x0025u;   /* TC22–TC25 passed */
}

/* --- TC26: Full autonomous pipeline ------------------------------------- */
static void test_pipeline(void)
{
    /* Re-configure WDT with generous window */
    WDT_CTRL = 0x00u;
    WDT_LOAD = 0x00100000u;
    WDT_CTRL = WDT_CTRL_EN | WDT_CTRL_AUTOKICK;

    /* Inject AES to represent the DMA→AES→WDT kick pipeline */
    AES_TXTIN0 = AES_PT_W0; AES_TXTIN1 = AES_PT_W1;
    AES_TXTIN2 = AES_PT_W2; AES_TXTIN3 = AES_PT_W3;
    AES_CTRL_REG = 0x01u;
    {
        uint32_t tmo = 0u;
        while (AES_STATUS != AES_STATUS_COMPLETE) {
            if (++tmo > 100000u) fail_trap(26);
        }
    }
    /* WDT must not have reset */
    if (WDT_RIS & 0x1u) fail_trap(26);
    /* Disable WDT */
    WDT_CTRL = 0x00u;

    TOHOST = 0x0026u;
}

/* =========================================================================
 * main — orchestrates all tests, writes 0x900D on full pass
 * ========================================================================= */
int main(void)
{
    test_uart();
    test_timer();
    test_aes();
    test_dma();
    test_wdt();
    test_gpio();
    test_pipeline();

    /* All tests passed */
    TOHOST = 0x900Du;

    /* Halt — infinite NOP loop */
    while (1) { __asm__ volatile ("nop"); }
    return 0;
}
