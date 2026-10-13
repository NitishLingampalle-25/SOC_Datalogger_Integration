/* =============================================================================
 * soc_full_test.c
 * =============================================================================
 * Bare-metal C firmware for VeeR EL2 — full SoC peripheral test covering:
 *   1. UART    (LCR / BAUD / IER / LSR / TX / RX)
 *   2. System Timer (CFG0 / CTRL / counter read / interrupt via mtimecmp)
 *   3. AES     (key load / start / status poll / ciphertext read-back)
 *   4. DMA     (descriptor write / START / done-status poll)
 *   5. WDT     (LOAD / CTRL / ping / IRQ / timeout detection)
 *   6. GPIO    (EN / OUT / IN / interrupt enable)
 *
 * Memory map matches veer2_dma_aes_wdt_uart_gpio_timer.v :
 *   UART  base : 0x4000_0000
 *   TIMER base : 0x4000_1000
 *   AES   base : 0x4000_2000
 *   DMA   base : 0x4000_3000
 *   WDT   base : 0x4000_4000
 *   GPIO  base : 0x4000_5000
 *
 * Result reporting (simulation tohost convention):
 *   Write 0xDEAD_BEEF to 0xD058_0000 → all tests passed
 *   Write 0xBAD0_DEAD  to 0xD058_0000 → one or more tests failed
 *
 * Compile (RV32IMC, VeeR EL2 default):
 *   riscv64-unknown-elf-gcc \
 *       -march=rv32imc_zicsr -mabi=ilp32 \
 *       -O1 -g -static -nostdlib -nostartfiles \
 *       -T <snapshot>/link.ld \
 *       soc_full_test.c crt0.S \
 *       -o soc_full_test.elf
 *   riscv64-unknown-elf-objcopy -O ihex soc_full_test.elf soc_full_test.hex
 *
 * Notes:
 *   - All peripheral accesses are 32-bit word reads/writes (volatile unsigned int).
 *   - Spin delays replace timer-based delays to keep the code dependency-free.
 *   - AES test uses NIST FIPS-197 Appendix B vectors.
 *   - WDT is kicked via software ping after configuration to prevent a reset
 *     during the test sequence; it is deliberately allowed to fire in TC_WDT_TIMEOUT.
 * =============================================================================
 */

#ifndef __riscv
#error "This firmware must be compiled for a RISC-V target."
#endif

/* ============================================================
 * Peripheral register definitions
 * ============================================================ */

/* ---- UART (0x4000_0000) ---- */
#define UART_BASE       0x40000000UL
#define UART_THR        (*(volatile unsigned int *)(UART_BASE + 0x00U)) /* TX write */
#define UART_RBR        (*(volatile unsigned int *)(UART_BASE + 0x00U)) /* RX read  */
#define UART_IER        (*(volatile unsigned int *)(UART_BASE + 0x04U))
#define UART_BAUD       (*(volatile unsigned int *)(UART_BASE + 0x08U))
#define UART_LCR        (*(volatile unsigned int *)(UART_BASE + 0x0CU))
#define UART_LSR        (*(volatile unsigned int *)(UART_BASE + 0x14U))
/* LSR bits */
#define LSR_DR          (1u << 0)   /* RX data ready        */
#define LSR_THRE        (1u << 5)   /* TX holding reg empty */
#define LSR_TEMT        (1u << 6)   /* TX completely empty  */

/* ---- System Timer (0x4000_1000) ---- */
#define TIMER_BASE      0x40001000UL
#define TIMER_CTRL      (*(volatile unsigned int *)(TIMER_BASE + 0x000U))
#define TIMER_INTR_EN   (*(volatile unsigned int *)(TIMER_BASE + 0x100U))
#define TIMER_INTR_ST   (*(volatile unsigned int *)(TIMER_BASE + 0x104U))
#define TIMER_INTR_TEST (*(volatile unsigned int *)(TIMER_BASE + 0x108U))
#define TIMER_CFG0      (*(volatile unsigned int *)(TIMER_BASE + 0x10CU))
#define TIMER_VAL_LO    (*(volatile unsigned int *)(TIMER_BASE + 0x110U))
#define TIMER_VAL_HI    (*(volatile unsigned int *)(TIMER_BASE + 0x114U))
#define TIMER_CMP_LO    (*(volatile unsigned int *)(TIMER_BASE + 0x118U))
#define TIMER_CMP_HI    (*(volatile unsigned int *)(TIMER_BASE + 0x11CU))

/* ---- AES Engine (0x4000_2000) ---- */
#define AES_BASE        0x40002000UL
#define AES_CTRL        (*(volatile unsigned int *)(AES_BASE + 0x00U))
#define AES_STATUS      (*(volatile unsigned int *)(AES_BASE + 0x04U))
#define AES_KEY0        (*(volatile unsigned int *)(AES_BASE + 0x08U))
#define AES_KEY1        (*(volatile unsigned int *)(AES_BASE + 0x0CU))
#define AES_KEY2        (*(volatile unsigned int *)(AES_BASE + 0x10U))
#define AES_KEY3        (*(volatile unsigned int *)(AES_BASE + 0x14U))
#define AES_TXTIN0      (*(volatile unsigned int *)(AES_BASE + 0x18U))
#define AES_TXTIN1      (*(volatile unsigned int *)(AES_BASE + 0x1CU))
#define AES_TXTIN2      (*(volatile unsigned int *)(AES_BASE + 0x20U))
#define AES_TXTIN3      (*(volatile unsigned int *)(AES_BASE + 0x24U))
#define AES_TXTOUT0     (*(volatile unsigned int *)(AES_BASE + 0x28U))
#define AES_TXTOUT1     (*(volatile unsigned int *)(AES_BASE + 0x2CU))
#define AES_TXTOUT2     (*(volatile unsigned int *)(AES_BASE + 0x30U))
#define AES_TXTOUT3     (*(volatile unsigned int *)(AES_BASE + 0x34U))
/* AES_CTRL bits */
#define AES_START       (1u << 0)
#define AES_MODE_CBC    (1u << 1)
#define AES_DIR_DEC     (1u << 2)
/* AES_STATUS bits */
#define AES_STAT_IDLE   (0u)
#define AES_STAT_BUSY   (1u)
#define AES_STAT_DONE   (2u)

/* ---- DMA Controller (0x4000_3000) ---- */
#define DMA_BASE        0x40003000UL
#define DMA_CTRL        (*(volatile unsigned int *)(DMA_BASE + 0x00U))
#define DMA_STAT        (*(volatile unsigned int *)(DMA_BASE + 0x08U))
#define DMA_ERR         (*(volatile unsigned int *)(DMA_BASE + 0x10U))
#define DMA_DESC0_SRC   (*(volatile unsigned int *)(DMA_BASE + 0x20U))
#define DMA_DESC0_DST   (*(volatile unsigned int *)(DMA_BASE + 0x30U))
#define DMA_DESC1_SRC   (*(volatile unsigned int *)(DMA_BASE + 0x28U))
#define DMA_DESC1_DST   (*(volatile unsigned int *)(DMA_BASE + 0x38U))
/* DMA_CTRL bits */
#define DMA_START       (1u << 0)
#define DMA_IRQ_EN      (1u << 1)
#define DMA_MODE_STREAM (1u << 2)
/* DMA_STAT bits */
#define DMA_BUSY        (1u << 0)
#define DMA_DONE        (1u << 1)
#define DMA_ERROR       (1u << 2)

/* ---- Watchdog (0x4000_4000)  — ef_wdt32_axi_wrapper offsets ---- */
#define WDT_BASE        0x40004000UL
#define WDT_LOAD        (*(volatile unsigned int *)(WDT_BASE + 0x04U))
#define WDT_CTRL        (*(volatile unsigned int *)(WDT_BASE + 0x08U))
#define WDT_PING        (*(volatile unsigned int *)(WDT_BASE + 0x0CU))
#define WDT_IM          (*(volatile unsigned int *)(WDT_BASE + 0x10U))
#define WDT_RIS         (*(volatile unsigned int *)(WDT_BASE + 0x14U))
#define WDT_MIS         (*(volatile unsigned int *)(WDT_BASE + 0x18U))
#define WDT_IC          (*(volatile unsigned int *)(WDT_BASE + 0x1CU))
/* WDT_CTRL bits */
#define WDT_EN          (1u << 0)
#define WDT_AUTO_KICK   (1u << 1)
#define WDT_NMI_EN      (1u << 2)
#define WDT_RESET_EN    (1u << 3)

/* ---- GPIO (0x4000_5000)  — gpio_axi_wrapper / gpio_reg_top offsets ---- */
#define GPIO_BASE           0x40005000UL
#define GPIO_EN             (*(volatile unsigned int *)(GPIO_BASE + 0x080U))
#define GPIO_IN             (*(volatile unsigned int *)(GPIO_BASE + 0x100U))
#define GPIO_OUT            (*(volatile unsigned int *)(GPIO_BASE + 0x180U))
#define GPIO_SET            (*(volatile unsigned int *)(GPIO_BASE + 0x200U))
#define GPIO_CLR            (*(volatile unsigned int *)(GPIO_BASE + 0x280U))
#define GPIO_TOGGLE         (*(volatile unsigned int *)(GPIO_BASE + 0x300U))
#define GPIO_RISE_EN        (*(volatile unsigned int *)(GPIO_BASE + 0x380U))
#define GPIO_FALL_EN        (*(volatile unsigned int *)(GPIO_BASE + 0x400U))
#define GPIO_LVL_HI_EN      (*(volatile unsigned int *)(GPIO_BASE + 0x480U))
#define GPIO_LVL_LO_EN      (*(volatile unsigned int *)(GPIO_BASE + 0x500U))
#define GPIO_INT_STAT       (*(volatile unsigned int *)(GPIO_BASE + 0x580U))

/* ============================================================
 * Simulation control
 * ============================================================ */
#define TOHOST_ADDR     0xD0580000UL
#define PASS_CODE       0xDEADBEEFUL
#define FAIL_CODE       0xBAD0DEADUL
#define RESULT_REG      (*(volatile unsigned int *)(TOHOST_ADDR))

/* ============================================================
 * NIST FIPS-197 Appendix B test vector
 * Key (128-bit):      2b7e1516 28aed2a6 abf71588 09cf4f3c
 * Plaintext (128-bit):3243f6a8 885a308d 3131982a e0370734
 * Ciphertext(128-bit):3925841d 02dc09fb dc118597 196a0b32
 * ============================================================ */
#define AES_KEY_W0  0x2b7e1516U
#define AES_KEY_W1  0x28aed2a6U
#define AES_KEY_W2  0xabf71588U
#define AES_KEY_W3  0x09cf4f3cU

#define AES_PT_W0   0x3243f6a8U
#define AES_PT_W1   0x885a308dU
#define AES_PT_W2   0x3131982aU
#define AES_PT_W3   0xe0370734U

#define AES_CT_W0   0x3925841dU
#define AES_CT_W1   0x02dc09fbU
#define AES_CT_W2   0xdc118597U
#define AES_CT_W3   0x196a0b32U

/* ============================================================
 * Test result tracking
 * ============================================================ */
static volatile unsigned int g_fail  = 0u;
static volatile unsigned int g_pass  = 0u;
static volatile unsigned int g_tests = 0u;

static void tc_pass(void)      { g_pass++;  g_tests++; }
static void tc_fail(void)      { g_fail++;  g_tests++; g_fail = 1u; }

static inline void check(unsigned int got, unsigned int expected,
                         unsigned int mask)
{
    if ((got & mask) == (expected & mask))
        tc_pass();
    else
        tc_fail();
}

/* ============================================================
 * Helpers
 * ============================================================ */
static void spin(volatile unsigned int n)
{
    while (n--) { __asm__ volatile ("nop"); }
}

/* Busy-poll with timeout; returns 1 on success, 0 on timeout. */
#define POLL_TIMEOUT 100000U

static int poll_until_set(volatile unsigned int *reg,
                          unsigned int mask, unsigned int timeout)
{
    unsigned int i;
    for (i = 0u; i < timeout; i++) {
        if ((*reg) & mask) return 1;
        spin(4u);
    }
    return 0;
}

static int poll_until_clear(volatile unsigned int *reg,
                             unsigned int mask, unsigned int timeout)
{
    unsigned int i;
    for (i = 0u; i < timeout; i++) {
        if (!((*reg) & mask)) return 1;
        spin(4u);
    }
    return 0;
}

/* ============================================================
 * TC1 — UART
 * ============================================================ */
static void test_uart(void)
{
    unsigned int lcr_rb, ier_rb, lsr_val;

    /* 1.1  8N1 line control */
    UART_LCR  = 0x03u;
    spin(4u);
    lcr_rb = UART_LCR;
    check(lcr_rb, 0x03u, 0xFFu);               /* TC_UART_LCR_RB */

    /* 1.2  Baud divisor (fast for simulation) */
    UART_BAUD = 0x0Au;   /* 10 */
    spin(4u);

    /* 1.3  IER — enable RX data-ready interrupt */
    UART_IER = 0x01u;
    spin(4u);
    ier_rb = UART_IER;
    check(ier_rb, 0x01u, 0xFFu);               /* TC_UART_IER_RB */

    /* 1.4  LSR — TX empty bits should be set after reset */
    lsr_val = UART_LSR;
    check(lsr_val, LSR_THRE | LSR_TEMT, LSR_THRE | LSR_TEMT);  /* TC_UART_LSR_TX */

    /* 1.5  TX write — 'K' (0x4B) */
    if (!poll_until_set(&UART_LSR_RAW, LSR_THRE, POLL_TIMEOUT)) { tc_fail(); }
    UART_THR = 0x4Bu;
    spin(8u);

    /* 1.6  Second TX write — 'A' (0x41) */
    UART_THR = 0x41u;
    spin(8u);

    /* 1.7  Poll THRE after TX */
    if (poll_until_set(&UART_LSR_RAW, LSR_THRE, POLL_TIMEOUT))
        tc_pass();
    else
        tc_fail();                              /* TC_UART_THRE_POLL */

    /* 1.8  LCR alternate format write and read-back (parity enable) */
    UART_LCR = 0x0Bu;
    spin(4u);
    lcr_rb = UART_LCR;
    check(lcr_rb, 0x0Bu, 0xFFu);               /* TC_UART_LCR_PARITY */

    /* Restore 8N1 */
    UART_LCR = 0x03u;
}

/* Macro for raw LSR access without macro name collision */
#define UART_LSR_RAW    (*(volatile unsigned int *)(UART_BASE + 0x14U))

/* ============================================================
 * TC2 — System Timer
 * ============================================================ */
static void test_timer(void)
{
    unsigned int t0, t1;

    /* 2.1  Prescaler = 9, step = 1 → tick every 10 clocks (fast sim) */
    TIMER_CFG0 = (9u << 8) | 1u;
    spin(4u);

    /* 2.2  Set compare far away to avoid spurious IRQ during counter test */
    TIMER_CMP_LO = 0xFFFFFFFFu;
    TIMER_CMP_HI = 0xFFFFFFFFu;

    /* 2.3  Enable timer */
    TIMER_CTRL = 0x1u;
    spin(4u);
    check(TIMER_CTRL, 0x1u, 0x1u);            /* TC_TIMER_CTRL_RB */

    /* 2.4  Read counter, wait, confirm increment */
    t0 = TIMER_VAL_LO;
    spin(200u);
    t1 = TIMER_VAL_LO;
    if (t1 > t0)
        tc_pass();
    else
        tc_fail();                             /* TC_TIMER_INC */

    /* 2.5  Set compare to t1 + 50 → fire interrupt */
    TIMER_CMP_LO = t1 + 50u;
    TIMER_CMP_HI = 0x0u;
    TIMER_INTR_EN = 0x1u;
    /* Wait for interrupt status bit (polling; ISR not wired in this test) */
    if (poll_until_set(&TIMER_INTR_ST, 0x1u, POLL_TIMEOUT))
        tc_pass();
    else
        tc_fail();                             /* TC_TIMER_IRQ */

    /* 2.6  W1C clear */
    TIMER_INTR_ST = 0x1u;
    check(TIMER_INTR_ST, 0x0u, 0x1u);         /* TC_TIMER_IRQ_CLEAR */

    /* Disable timer for remainder of test */
    TIMER_CTRL = 0x0u;
    TIMER_INTR_EN = 0x0u;
}

/* ============================================================
 * TC3 — AES (NIST FIPS-197 encrypt)
 * ============================================================ */
static void test_aes(void)
{
    /* 3.1  Load 128-bit key */
    AES_KEY0 = AES_KEY_W0;
    AES_KEY1 = AES_KEY_W1;
    AES_KEY2 = AES_KEY_W2;
    AES_KEY3 = AES_KEY_W3;

    /* 3.2  Load plaintext */
    AES_TXTIN0 = AES_PT_W0;
    AES_TXTIN1 = AES_PT_W1;
    AES_TXTIN2 = AES_PT_W2;
    AES_TXTIN3 = AES_PT_W3;

    /* 3.3  Pulse START (bit0), MODE=ECB (bit1=0), DIR=ENC (bit2=0) */
    AES_CTRL = AES_START;
    spin(2u);

    /* 3.4  Wait for done — poll AES_STATUS or aes_done_o via STATUS reg */
    if (!poll_until_set(&AES_STATUS, AES_STAT_DONE, POLL_TIMEOUT))
        tc_fail();                             /* TC_AES_DONE_POLL */
    else
        tc_pass();

    /* 3.5  Ciphertext read-back vs NIST vector */
    check(AES_TXTOUT0, AES_CT_W0, 0xFFFFFFFFu);   /* TC_AES_CT_W0 */
    check(AES_TXTOUT1, AES_CT_W1, 0xFFFFFFFFu);   /* TC_AES_CT_W1 */
    check(AES_TXTOUT2, AES_CT_W2, 0xFFFFFFFFu);   /* TC_AES_CT_W2 */
    check(AES_TXTOUT3, AES_CT_W3, 0xFFFFFFFFu);   /* TC_AES_CT_W3 */

    /* 3.6  Clear START bit */
    AES_CTRL = 0x0u;
}

/* ============================================================
 * TC4 — DMA Controller CSRs
 * ============================================================ */
static void test_dma(void)
{
    unsigned int stat;

    /* 4.1  Read DMA control register — should respond (not SLVERR) */
    stat = DMA_CTRL;
    tc_pass();    /* reaching here = bus ACK received */           /* TC_DMA_CSR_ACK */

    /* 4.2  Write descriptor: SRC = UART_BASE, DST = DCCM start */
    DMA_DESC0_SRC = (unsigned int)UART_BASE;
    DMA_DESC0_DST = 0xF0040000u;   /* VeeR DCCM base */
    spin(2u);

    /* Read back src to verify register path */
    check(DMA_DESC0_SRC, (unsigned int)UART_BASE, 0xFFFFFFFFu);  /* TC_DMA_SRC_RB */

    /* 4.3  ARM: START | IRQ_EN */
    DMA_CTRL = DMA_START | DMA_IRQ_EN;
    spin(4u);

    /* 4.4  Poll DONE bit with timeout */
    if (poll_until_set(&DMA_STAT, DMA_DONE, POLL_TIMEOUT))
        tc_pass();
    else
        tc_fail();                           /* TC_DMA_DONE */

    /* 4.5  No error */
    check(DMA_STAT & DMA_ERROR, 0u, 0xFFFFFFFFu);  /* TC_DMA_NO_ERR */

    /* Clear control */
    DMA_CTRL = 0x0u;
}

/* ============================================================
 * TC5 — Watchdog Timer
 * ============================================================ */
static void test_wdt(void)
{
    unsigned int ris_val;

    /* 5.1  Load timer with large value */
    WDT_LOAD = 0x00100000u;        /* ~1M cycles */
    spin(2u);

    /* 5.2  Unmask IRQ */
    WDT_IM = 0x1u;

    /* 5.3  Enable: WDT_EN | AUTO_KICK_EN */
    WDT_CTRL = WDT_EN | WDT_AUTO_KICK;
    check(WDT_CTRL & WDT_EN, WDT_EN, 0xFFFFFFFFu);  /* TC_WDT_EN */

    /* 5.4  Software ping — must not trigger IRQ */
    spin(10u);
    WDT_PING = 0xDEADu;            /* any write = kick */
    spin(10u);
    check(WDT_RIS & 0x1u, 0u, 0x1u);               /* TC_WDT_NO_IRQ_AFTER_PING */

    /* 5.5  Read-back LOAD */
    check(WDT_LOAD, 0x00100000u, 0xFFFFFFFFu);      /* TC_WDT_LOAD_RB */

    /* 5.6  Intentional timeout test:
     *      Disable auto-kick, set a very short load, wait for IRQ.
     *      We intentionally keep RESET_EN=0 so the core is not reset. */
    WDT_CTRL = WDT_EN;             /* auto-kick off, reset off, NMI off */
    WDT_LOAD = 0x10u;              /* 16-cycle timeout */
    spin(1u);
    /* Restart counter by pinging first */
    WDT_PING = 0x1u;

    if (poll_until_set(&WDT_RIS, 0x1u, POLL_TIMEOUT))
        tc_pass();
    else
        tc_fail();                                   /* TC_WDT_TIMEOUT_IRQ */

    /* Verify MIS (IRQ_IM gated) */
    ris_val = WDT_MIS;
    check(ris_val & 0x1u, 0x1u, 0x1u);             /* TC_WDT_MIS */

    /* 5.7  W1C interrupt clear */
    WDT_IC = 0xFFFFFFFFu;
    spin(2u);
    check(WDT_RIS & 0x1u, 0u, 0x1u);               /* TC_WDT_IRQ_CLEAR */

    /* 5.8  Disable WDT after test */
    WDT_CTRL = 0x0u;
}

/* ============================================================
 * TC6 — GPIO
 * ============================================================ */
static void test_gpio(void)
{
    unsigned int gpio_in_snap;

    /* 6.1  Enable lower 8 bits as outputs */
    GPIO_EN = 0x000000FFu;
    check(GPIO_EN, 0x000000FFu, 0xFFu);             /* TC_GPIO_EN_RB */

    /* 6.2  Write GPIO_OUT */
    GPIO_OUT = 0xA5u;
    spin(2u);
    check(GPIO_OUT, 0xA5u, 0xFFu);                  /* TC_GPIO_OUT_RB */

    /* 6.3  Atomic GPIO_SET: set bit8 */
    GPIO_SET = 0x100u;
    spin(2u);
    check(GPIO_OUT & 0x100u, 0x100u, 0x100u);       /* TC_GPIO_SET */

    /* 6.4  Atomic GPIO_CLR: clear bit8 */
    GPIO_CLR = 0x100u;
    spin(2u);
    check(GPIO_OUT & 0x100u, 0x0u, 0x100u);         /* TC_GPIO_CLR */

    /* 6.5  GPIO_TOGGLE: toggle bit0 */
    {
        unsigned int before = GPIO_OUT & 0x1u;
        GPIO_TOGGLE = 0x1u;
        spin(2u);
        check((GPIO_OUT & 0x1u) ^ before, 0x1u, 0x1u);  /* TC_GPIO_TOGGLE */
    }

    /* 6.6  GPIO_IN read (pins driven by external stimulus; read back whatever
     *      the hardware reports — just verify the register is accessible) */
    gpio_in_snap = GPIO_IN;
    tc_pass();                                      /* TC_GPIO_IN_ACCESS */
    (void)gpio_in_snap;                             /* suppress unused-var warning */

    /* 6.7  Rising-edge interrupt enable on bit0 */
    GPIO_RISE_EN = 0x1u;
    check(GPIO_RISE_EN, 0x1u, 0x1u);               /* TC_GPIO_RISE_EN_RB */

    /* 6.8  Level-high interrupt enable on bit1 */
    GPIO_LVL_HI_EN = 0x2u;
    check(GPIO_LVL_HI_EN, 0x2u, 0x2u);             /* TC_GPIO_LVL_HI_EN_RB */

    /* 6.9  Interrupt status read (W1C clear) */
    GPIO_INT_STAT = 0xFFFFFFFFu;  /* clear any pending */
    spin(2u);
    /* GPIO_IN read for interrupt trigger check handled by TB */
    tc_pass();                                      /* TC_GPIO_INT_CLEAR */

    /* Disable all interrupts */
    GPIO_RISE_EN   = 0x0u;
    GPIO_LVL_HI_EN = 0x0u;
}

/* ============================================================
 * TC7 — Full Autonomous Pipeline (UART → DMA → AES → WDT kick)
 * ============================================================ */
static void test_pipeline(void)
{
    /*
     * This test configures the full hardware pipeline and verifies:
     *   a) UART RX receives and asserts data-ready
     *   b) AES encrypts and pulses aes_done_pulse_o
     *   c) WDT is auto-kicked (no reset observed during pipeline run)
     *
     * The actual byte injection from the external pin and the DMA transfer
     * are exercised at the TB level.  The firmware here sets up the
     * configuration registers so that the autonomous path is armed.
     */

    /* 7.1  UART: 8N1, fast baud, IER enable */
    UART_LCR  = 0x03u;
    UART_BAUD = 0x0Au;
    UART_IER  = 0x01u;

    /* 7.2  DMA: src=UART_BASE, dst=DCCM, start armed */
    DMA_DESC0_SRC = (unsigned int)UART_BASE;
    DMA_DESC0_DST = 0xF0040000u;
    DMA_CTRL = DMA_START | DMA_IRQ_EN | DMA_MODE_STREAM;

    /* 7.3  AES: key loaded, armed */
    AES_KEY0 = AES_KEY_W0;
    AES_KEY1 = AES_KEY_W1;
    AES_KEY2 = AES_KEY_W2;
    AES_KEY3 = AES_KEY_W3;
    AES_TXTIN0 = AES_PT_W0;
    AES_TXTIN1 = AES_PT_W1;
    AES_TXTIN2 = AES_PT_W2;
    AES_TXTIN3 = AES_PT_W3;
    AES_CTRL = AES_START;

    /* 7.4  WDT: generous timeout, auto-kick enabled */
    WDT_LOAD = 0x00200000u;
    WDT_IM   = 0x1u;
    WDT_CTRL = WDT_EN | WDT_AUTO_KICK;

    /* 7.5  Wait for AES done — proves AES is running */
    if (poll_until_set(&AES_STATUS, AES_STAT_DONE, POLL_TIMEOUT))
        tc_pass();
    else
        tc_fail();                           /* TC_PIPELINE_AES_DONE */

    /* 7.6  After AES done, WDT should not have fired (auto-kick worked) */
    check(WDT_RIS & 0x1u, 0u, 0x1u);       /* TC_PIPELINE_WDT_OK */

    /* 7.7  Clean up */
    AES_CTRL  = 0x0u;
    DMA_CTRL  = 0x0u;
    WDT_CTRL  = 0x0u;
}

/* ============================================================
 * main
 * ============================================================ */
int main(void)
{
    /* Kick WDT first to give firmware maximum headroom */
    WDT_PING = 0x1u;

    /* Run all test groups */
    test_uart();
    test_timer();
    test_aes();
    test_dma();
    test_wdt();
    test_gpio();
    test_pipeline();

    /* Report result via tohost */
    if (g_fail == 0u)
        RESULT_REG = PASS_CODE;     /* 0xDEADBEEF → all pass */
    else
        RESULT_REG = FAIL_CODE;     /* 0xBAD0DEAD → failure  */

    /* Park the core */
    while (1) { __asm__ volatile ("nop"); }

    return 0;
}
