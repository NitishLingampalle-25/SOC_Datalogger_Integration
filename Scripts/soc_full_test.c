/* soc_full_test.c - firmware for veer2_dma_aes_wdt_uart_gpio_timer
 * Build: make   (see Makefile)  ->  soc_full_test.hex (byte-wide verilog hex)
 * Result reporting: upper 16 bits of GPIO_OUT ("tohost")
 *     0x0006 UART ok  0x0009 timer ok  0x0013 AES ok  0x0016 DMA ok (-DTEST_DMA)
 *     0x0021 WDT ok   0x0025 GPIO ok   0x0026 pipeline ok
 *     0x900D ALL PASSED        0xDEADnnnn  FAILED at step nnnn (whole word)
 */
#include <stdint.h>
#define R32(a) (*(volatile uint32_t *)(a))

#define UART_BASE   0x40000000u
#define TIMER_BASE  0x40001000u
#define AES_BASE    0x40002000u
#define DMA_BASE    0x40003000u
#define WDT_BASE    0x40004000u
#define GPIO_BASE   0x40005000u

#define UART_THR   R32(UART_BASE + 0x00)
#define UART_RBR   R32(UART_BASE + 0x00)
#define UART_IER   R32(UART_BASE + 0x04)
#define UART_BAUD  R32(UART_BASE + 0x08)
#define UART_LCR   R32(UART_BASE + 0x0C)
#define UART_LSR   R32(UART_BASE + 0x14)
#define LSR_DATA_RDY (1u << 0)
#define LSR_THRE     (1u << 5)
#define LSR_TEMT     (1u << 6)
#define SIM_BAUD_DIV 10u

#define TIMER_CTRL    R32(TIMER_BASE + 0x000)
#define TIMER_INTR_EN R32(TIMER_BASE + 0x100)
#define TIMER_INTR_ST R32(TIMER_BASE + 0x104)
#define TIMER_CFG0    R32(TIMER_BASE + 0x10C)
#define TIMER_VAL_LO  R32(TIMER_BASE + 0x110)
#define TIMER_CMP_LO  R32(TIMER_BASE + 0x118)
#define TIMER_CMP_HI  R32(TIMER_BASE + 0x11C)

/* AES register map — matches aes_veer_adapter.v
 *   0x00: AES_CTRL_STAT  [0]=START [1]=KEY_LD [2]=MODE [3]=IRQ_EN [8]=done_latched [16]=IDLE [17]=BUSY
 *   0x04: AES_KEY_W0  [127:96]
 *   0x08: AES_KEY_W1  [95:64]
 *   0x0C: AES_KEY_W2  [63:32]
 *   0x10: AES_KEY_W3  [31:0]
 *   0x14: AES_TXTIN_W0 [127:96]
 *   0x18: AES_TXTIN_W1 [95:64]
 *   0x1C: AES_TXTIN_W2 [63:32]
 *   0x20: AES_TXTIN_W3 [31:0]
 *   0x24: AES_TXTOUT_W0 [127:96]
 *   0x28: AES_TXTOUT_W1 [95:64]
 *   0x2C: AES_TXTOUT_W2 [63:32]
 *   0x30: AES_TXTOUT_W3 [31:0]
 */
#define AES_CTRL_REG R32(AES_BASE + 0x00)
#define AES_KEY0     R32(AES_BASE + 0x04)
#define AES_KEY1     R32(AES_BASE + 0x08)
#define AES_KEY2     R32(AES_BASE + 0x0C)
#define AES_KEY3     R32(AES_BASE + 0x10)
#define AES_TXTIN0   R32(AES_BASE + 0x14)
#define AES_TXTIN1   R32(AES_BASE + 0x18)
#define AES_TXTIN2   R32(AES_BASE + 0x1C)
#define AES_TXTIN3   R32(AES_BASE + 0x20)
#define AES_TXTOUT0  R32(AES_BASE + 0x24)
#define AES_TXTOUT1  R32(AES_BASE + 0x28)
#define AES_TXTOUT2  R32(AES_BASE + 0x2C)
#define AES_TXTOUT3  R32(AES_BASE + 0x30)
/* done_latched = bit 8 of CTRL_STAT register (0x00) */
#define AES_STATUS_COMPLETE (1u << 8)

#define DMA_CTRL_REG  R32(DMA_BASE + 0x00)
#define DMA_STAT_REG  R32(DMA_BASE + 0x08)
#define DMA_DESC0_SRC R32(DMA_BASE + 0x20)
#define DMA_DESC0_DST R32(DMA_BASE + 0x30)
#define DMA_CTRL_START  (1u << 0)
#define DMA_CTRL_IRQ_EN (1u << 1)
#define DMA_STAT_DONE   (1u << 1)
#define DMA_STAT_ERROR  (1u << 2)
#define DCCM_BASE 0x10000000u          /* relocated DCCM */

#define WDT_LOAD R32(WDT_BASE + 0x04)
#define WDT_CTRL R32(WDT_BASE + 0x08)
#define WDT_PING R32(WDT_BASE + 0x0C)
#define WDT_IM   R32(WDT_BASE + 0x10)
#define WDT_RIS  R32(WDT_BASE + 0x14)
#define WDT_MIS  R32(WDT_BASE + 0x18)
#define WDT_IC   R32(WDT_BASE + 0x1C)
#define WDT_CTRL_EN       (1u << 0)
#define WDT_CTRL_AUTOKICK (1u << 1)
#define WDT_CTRL_NMI_EN   (1u << 2)
#define WDT_CTRL_RESET_EN (1u << 3)

#define GPIO_EN_REG   R32(GPIO_BASE + 0x080)
#define GPIO_IN_REG   R32(GPIO_BASE + 0x100)
#define GPIO_OUT_REG  R32(GPIO_BASE + 0x180)
#define GPIO_RISE_EN  R32(GPIO_BASE + 0x380)
#define GPIO_INT_STAT R32(GPIO_BASE + 0x580)

/* FIPS-197 Appendix B  (note PT word2 = 313198a2; 3131982a was a typo) */
#define AES_KEY_W0 0x2b7e1516u
#define AES_KEY_W1 0x28aed2a6u
#define AES_KEY_W2 0xabf71588u
#define AES_KEY_W3 0x09cf4f3cu
#define AES_PT_W0  0x3243f6a8u
#define AES_PT_W1  0x885a308du
#define AES_PT_W2  0x313198a2u
#define AES_PT_W3  0xe0370734u
#define AES_CT_W0  0x3925841du
#define AES_CT_W1  0x02dc09fbu
#define AES_CT_W2  0xdc118597u
#define AES_CT_W3  0x196a0b32u

/* tohost = GPIO_OUT[31:16].  The testbench watches gpio_out_o. */
static inline void tohost(uint32_t code)
{
    GPIO_EN_REG  |= 0xFFFF0000u;
    GPIO_OUT_REG  = (GPIO_OUT_REG & 0x0000FFFFu) | (code << 16);
}
static void fail_trap(uint32_t step)
{
    GPIO_EN_REG  = 0xFFFFFFFFu;
    GPIO_OUT_REG = 0xDEAD0000u | (step & 0xFFFFu);
    for (;;) __asm__ volatile ("nop");
}
static inline void delay(uint32_t n)
{ volatile uint32_t i; for (i = 0; i < n; i++) __asm__ volatile ("nop"); }

static void aes_encrypt_once(uint32_t step)
{
    AES_TXTIN0 = AES_PT_W0; AES_TXTIN1 = AES_PT_W1;
    AES_TXTIN2 = AES_PT_W2; AES_TXTIN3 = AES_PT_W3;
    AES_CTRL_REG = 0x01u;
    for (uint32_t t = 0; !(AES_CTRL_REG & AES_STATUS_COMPLETE); )
        if (++t > 100000u) fail_trap(step);
}

static void test_uart(void)
{
    uint32_t lsr;
    UART_LCR = 0x03u;  if (UART_LCR != 0x03u) fail_trap(3);
    UART_BAUD = SIM_BAUD_DIV;
    UART_IER = 0x01u;  if (UART_IER != 0x01u) fail_trap(3);
    do { lsr = UART_LSR; } while (!(lsr & LSR_THRE));
    UART_THR = 0x4Bu;                                   /* 'K' - TB sees this, then injects 0xA5 */
    do { lsr = UART_LSR; } while (!(lsr & LSR_TEMT));
    for (uint32_t t = 0; !(UART_LSR & LSR_DATA_RDY); )  /* wait for TB-injected byte */
        if (++t > 200000u) fail_trap(6);
    if ((UART_RBR & 0xFFu) != 0xA5u) fail_trap(6);
    tohost(0x0006u);
}

static void test_timer(void)
{
    uint32_t t0, t1;
    TIMER_CFG0 = 0x00000901u;
    TIMER_CMP_LO = 0xFFFFFFFFu; TIMER_CMP_HI = 0xFFFFFFFFu;
    TIMER_CTRL = 0x1u;
    t0 = TIMER_VAL_LO; delay(50u); t1 = TIMER_VAL_LO;
    if (t1 <= t0) fail_trap(8);
    t0 = TIMER_VAL_LO;
    TIMER_CMP_LO = t0 + 100u; TIMER_CMP_HI = 0u;
    TIMER_INTR_EN = 0x1u;
    for (uint32_t t = 0; !(TIMER_INTR_ST & 0x1u); )
        if (++t > 100000u) fail_trap(9);
    TIMER_INTR_ST = 0x1u;
    tohost(0x0009u);
}

static void test_aes(void)
{
    AES_KEY0 = AES_KEY_W0; AES_KEY1 = AES_KEY_W1;
    AES_KEY2 = AES_KEY_W2; AES_KEY3 = AES_KEY_W3;
    aes_encrypt_once(12);
    if (AES_TXTOUT0 != AES_CT_W0) fail_trap(13);
    if (AES_TXTOUT1 != AES_CT_W1) fail_trap(13);
    if (AES_TXTOUT2 != AES_CT_W2) fail_trap(13);
    if (AES_TXTOUT3 != AES_CT_W3) fail_trap(13);
    tohost(0x0013u);
}

#ifdef TEST_DMA   /* OFF by default: DMA -> core-local DCCM is not reachable via the 2x6 interconnect */
static void test_dma(void)
{
    (void)DMA_CTRL_REG; (void)DMA_STAT_REG;
    DMA_DESC0_SRC = UART_BASE;
    DMA_DESC0_DST = DCCM_BASE;
    DMA_CTRL_REG  = DMA_CTRL_START | DMA_CTRL_IRQ_EN;
    for (uint32_t t = 0; !(DMA_STAT_REG & DMA_STAT_DONE); ) {
        if (DMA_STAT_REG & DMA_STAT_ERROR) fail_trap(16);
        if (++t > 200000u) fail_trap(16);
    }
    tohost(0x0016u);
}
#endif

static void test_wdt(void)
{
    WDT_LOAD = 0x00100000u; WDT_IM = 0x01u;
    WDT_CTRL = WDT_CTRL_EN | WDT_CTRL_AUTOKICK;
    delay(20u); WDT_PING = 0xABCDEF01u; delay(5u);
    if (WDT_MIS & 0x1u) fail_trap(18);
    aes_encrypt_once(19);                         /* AES done pulse auto-kicks WDT */
    if (WDT_MIS & 0x1u) fail_trap(19);
    WDT_CTRL = WDT_CTRL_EN;                       /* auto-kick off */
    WDT_LOAD = 0x10u;
    WDT_CTRL = WDT_CTRL_EN;
    for (uint32_t t = 0; !(WDT_RIS & 0x1u); )
        if (++t > 200000u) fail_trap(20);
    WDT_IC = 0xFFFFFFFFu; delay(3u);
    if (WDT_RIS & 0x1u) fail_trap(20);
#ifdef TEST_WDT_ESCALATION  /* needs an NMI handler at nmi_vec; covered by BFM TC21 otherwise */
    WDT_CTRL = WDT_CTRL_EN | WDT_CTRL_NMI_EN | WDT_CTRL_RESET_EN;
    WDT_LOAD = 0x08u;
    for (uint32_t t = 0; !(WDT_RIS & 0x1u); )
        if (++t > 200000u) fail_trap(21);
#endif
    WDT_CTRL = 0x00u; WDT_IC = 0xFFFFFFFFu;
    tohost(0x0021u);
}

static void test_gpio(void)
{
    GPIO_EN_REG  = 0x000000FFu;
    GPIO_OUT_REG = 0xA5u;                         /* TB waits for this, then drives gpio_in_i[0] 0->1 */
    delay(3u);
    (void)GPIO_IN_REG;
    GPIO_RISE_EN = 0x00000001u;
    for (uint32_t t = 0; !(GPIO_INT_STAT & 0x1u); )
        if (++t > 400000u) fail_trap(25);
    GPIO_INT_STAT = 0xFFFFFFFFu;
    tohost(0x0025u);
}

static void test_pipeline(void)
{
    WDT_CTRL = 0x00u; WDT_LOAD = 0x00100000u;
    WDT_CTRL = WDT_CTRL_EN | WDT_CTRL_AUTOKICK;
    aes_encrypt_once(26);
    if (WDT_RIS & 0x1u) fail_trap(26);
    WDT_CTRL = 0x00u;
    tohost(0x0026u);
}

int main(void)
{
    GPIO_EN_REG = 0xFFFF0000u;  GPIO_OUT_REG = 0u;
    test_uart();
    test_timer();
    test_aes();
#ifdef TEST_DMA
    test_dma();
#endif
    test_wdt();
    test_gpio();
    test_pipeline();
    tohost(0x900Du);
    for (;;) __asm__ volatile ("nop");
}
