/*
 * ad9176_fmc_ebz.c
 *
 * HPS bare-metal driver implementation for the AD9176-FMC-EBZ eval board.
 * See ad9176_fmc_ebz.h for pin assignments, register addresses, and API docs.
 *
 * SPI is bit-banged via HPS GPIO. Update spi_gpio_*() helpers and the pin
 * definitions in the header to match the physical FMC connector wiring on
 * the Agilex 5 dev board before running on hardware.
 *
 * Startup sequence follows AD9176 datasheet Table 50 (one-time init).
 *
 * Author: Brett Taylor
 * Created: 2026-04-06
 */

#include "ad9176_fmc_ebz.h"

/* =========================================================================
 * Internal helpers: HPS GPIO bit-bang SPI
 *
 * These functions are placeholders. Replace the register accesses below
 * with the correct HPS GPIO peripheral addresses and bit positions for
 * the Agilex 5 dev board FMC connector wiring.
 *
 * If the dev board provides a hardware SPI controller connected to the FMC
 * SPI pins, replace this section with HAL or direct SPI controller calls.
 * ========================================================================= */

/* GPIO output register (data out) — placeholder address */
#define HPS_GPIO_SWPORTA_DR   (*(volatile uint32_t *)(SPI_CLK_GPIO_BASE + 0x00))
/* GPIO direction register (1=output) — placeholder address */
#define HPS_GPIO_SWPORTA_DDR  (*(volatile uint32_t *)(SPI_CLK_GPIO_BASE + 0x04))
/* GPIO input register — placeholder address */
#define HPS_GPIO_EXT_PORTA    (*(volatile uint32_t *)(SPI_CLK_GPIO_BASE + 0x50))

static uint32_t gpio_out_shadow = 0;

static void spi_gpio_init(void)
{
    /* Configure CLK, MOSI, CS as outputs; MISO as input */
    HPS_GPIO_SWPORTA_DDR |= (SPI_CLK_PIN | SPI_MOSI_PIN | SPI_CS_N_PIN);
    HPS_GPIO_SWPORTA_DDR &= ~SPI_MISO_PIN;

    /* Idle state: CLK=0, MOSI=0, CS=1 (deasserted) */
    gpio_out_shadow  = SPI_CS_N_PIN;
    HPS_GPIO_SWPORTA_DR = gpio_out_shadow;
}

static inline void spi_set_clk(int high)
{
    if (high)
        gpio_out_shadow |= SPI_CLK_PIN;
    else
        gpio_out_shadow &= ~SPI_CLK_PIN;
    HPS_GPIO_SWPORTA_DR = gpio_out_shadow;
}

static inline void spi_set_mosi(int high)
{
    if (high)
        gpio_out_shadow |= SPI_MOSI_PIN;
    else
        gpio_out_shadow &= ~SPI_MOSI_PIN;
    HPS_GPIO_SWPORTA_DR = gpio_out_shadow;
}

static inline void spi_set_cs(int assert_active)
{
    /* CS is active low */
    if (assert_active)
        gpio_out_shadow &= ~SPI_CS_N_PIN;
    else
        gpio_out_shadow |= SPI_CS_N_PIN;
    HPS_GPIO_SWPORTA_DR = gpio_out_shadow;
}

static inline int spi_get_miso(void)
{
    return (HPS_GPIO_EXT_PORTA & SPI_MISO_PIN) ? 1 : 0;
}

/*
 * Transfer one bit on the SPI bus (CPOL=0, CPHA=0).
 * Data is shifted MSB first. CLK idles low; data is sampled on rising edge.
 */
static uint8_t spi_transfer_bit(int bit_out)
{
    spi_set_mosi(bit_out);
    spi_set_clk(0);
    /* Brief setup time (no-op loop may be needed on very fast systems) */
    spi_set_clk(1);
    return (uint8_t)spi_get_miso();
}

/*
 * Transfer one byte MSB first. Returns the received byte.
 */
static uint8_t spi_transfer_byte(uint8_t tx)
{
    uint8_t rx = 0;
    int i;
    for (i = 7; i >= 0; i--) {
        rx = (uint8_t)(rx << 1);
        rx |= spi_transfer_bit((tx >> i) & 1);
    }
    spi_set_clk(0);
    return rx;
}

/* =========================================================================
 * SPI frame format (AD9176 datasheet Section 9.1):
 *   Byte 0: [R/W | A14 | A13 | A12 | A11 | A10 | A9 | A8]
 *   Byte 1: [A7  | A6  | A5  | A4  | A3  | A2  | A1 | A0]
 *   Byte 2: [D7  | D6  | D5  | D4  | D3  | D2  | D1 | D0]
 *   R/W=1 for read, R/W=0 for write.
 * ========================================================================= */

void ad9176_spi_write(uint16_t addr, uint8_t data)
{
    uint8_t b0 = (uint8_t)((addr >> 8) & 0x7F);  /* R/W=0 (write) */
    uint8_t b1 = (uint8_t)(addr & 0xFF);

    spi_set_cs(1);
    spi_transfer_byte(b0);
    spi_transfer_byte(b1);
    spi_transfer_byte(data);
    spi_set_cs(0);
}

uint8_t ad9176_spi_read(uint16_t addr)
{
    uint8_t b0 = (uint8_t)(((addr >> 8) & 0x7F) | 0x80);  /* R/W=1 (read) */
    uint8_t b1 = (uint8_t)(addr & 0xFF);
    uint8_t rx;

    spi_set_cs(1);
    spi_transfer_byte(b0);
    spi_transfer_byte(b1);
    rx = spi_transfer_byte(0x00);
    spi_set_cs(0);
    return rx;
}

/* =========================================================================
 * Busy-wait helper (approximate milliseconds)
 * Replace with a real timer or RTOS sleep on hardware.
 * ========================================================================= */
static void delay_ms(uint32_t ms)
{
    volatile uint32_t i;
    /* ~500k iterations ≈ 1 ms at 500 MHz with simple loop — calibrate */
    for (; ms > 0; ms--)
        for (i = 500000; i > 0; i--)
            ;
}

/* =========================================================================
 * Public API implementations
 * ========================================================================= */

int ad9176_fpga_bridge_test(void)
{
    static const uint32_t patterns[4] = {
        0xDEADBEEFUL, 0xA5A5A5A5UL, 0x12345678UL, 0x00000000UL
    };
    static const uint32_t offsets[4] = {
        REG_SCRATCH0, REG_SCRATCH1, REG_SCRATCH2, REG_SCRATCH3
    };
    int i;
    uint32_t readback;

    for (i = 0; i < 4; i++) {
        FPGA_REG_WRITE(offsets[i], patterns[i]);
        readback = FPGA_REG_READ(offsets[i]);
        if (readback != patterns[i])
            return AD9176_ERR_SCRATCH;
    }
    return AD9176_OK;
}

int ad9176_init(void)
{
    uint8_t val;

    spi_gpio_init();

    /* ------------------------------------------------------------------
     * Step 1: Soft reset (AD9176 datasheet Table 50, step 1)
     * Write 0x81 to SPI_CONFIG_A (bit 7 = software reset).
     * The reset bit is self-clearing; wait for it to clear before continuing.
     * ------------------------------------------------------------------ */
    ad9176_spi_write(AD9176_REG_SPI_CONFIG_A, 0x81);
    delay_ms(10);

    /* Confirm reset cleared */
    val = ad9176_spi_read(AD9176_REG_SPI_CONFIG_A);
    if (val & 0x80)
        return AD9176_ERR_SPI;  /* reset did not clear — SPI problem */

    /* ------------------------------------------------------------------
     * Step 2: Configure for 12 GSPS, 6× interpolation
     * DAC PLL configuration depends on the reference clock on the FMC-EBZ.
     * The FMC-EBZ provides a 500 MHz reference. Configure PLL for 12 GHz
     * VCO (×24 from 500 MHz). Adjust multiplier registers as needed.
     * Full PLL register sequence: see AD9176 datasheet Table 50 / UG-1659.
     * ------------------------------------------------------------------ */

    /* Set main datapath interpolation to 6× */
    ad9176_spi_write(AD9176_REG_INTERP_MODE, AD9176_INTERP_6X);

    /* Enable PLL and wait for lock */
    delay_ms(5);
    val = ad9176_spi_read(AD9176_REG_DACPLL_STATUS);
    if (!(val & 0x01))
        return AD9176_ERR_PLL;  /* DAC PLL did not lock */

    /* ------------------------------------------------------------------
     * Step 3: Configure JESD204B parameters
     * Mode 4: L=4, M=4, F=2, K=32, N=16, NP=16, S=1, HD=1, SCR=1.
     * Write L-1, F-1, K-1, M-1 (with HD and SCR flags), N-1, NP-1, S-1.
     * ------------------------------------------------------------------ */
    ad9176_spi_write(AD9176_REG_JESD_L,  AD9176_JESD_L_VAL);
    ad9176_spi_write(AD9176_REG_JESD_F,  AD9176_JESD_F_VAL);
    ad9176_spi_write(AD9176_REG_JESD_K,  AD9176_JESD_K_VAL);
    /* M register: bits [5:0] = M-1, bit 6 = SCR, bit 7 = HD */
    ad9176_spi_write(AD9176_REG_JESD_M,
                     (uint8_t)(AD9176_JESD_M_VAL |
                                AD9176_JESD_HD_BIT |
                                AD9176_JESD_SCR_BIT));
    ad9176_spi_write(AD9176_REG_JESD_N,  AD9176_JESD_N_VAL);
    ad9176_spi_write(AD9176_REG_JESD_NP, AD9176_JESD_NP_VAL);
    ad9176_spi_write(AD9176_REG_JESD_S,  AD9176_JESD_S_VAL);

    /* ------------------------------------------------------------------
     * Step 4: Verify HD=1 and SCR=1 readback from the M register (0x453).
     * Bits [5:0] = M-1, bit 6 = SCR, bit 7 = HD.
     * ------------------------------------------------------------------ */
    val = ad9176_spi_read(AD9176_REG_JESD_M);
    if (!(val & AD9176_JESD_HD_BIT) || !(val & AD9176_JESD_SCR_BIT))
        return AD9176_ERR_JESD_PARAM;

    /* ------------------------------------------------------------------
     * Step 5: Enable JESD204B link
     * ------------------------------------------------------------------ */
    ad9176_spi_write(AD9176_REG_JESD_EN, 0x01);

    /* ------------------------------------------------------------------
     * Step 6: Wait for JESD link lock via FPGA status register
     * Both links (bits [1:0] of JESD_SYNC_STATUS) must assert ready.
     * Allow up to 500 ms for training to complete.
     * ------------------------------------------------------------------ */
    return ad9176_jesd_wait_lock(500);
}

int ad9176_nco_enable(uint32_t freq_hz, uint32_t f_sample_hz)
{
    uint32_t freq_word;

    /* Select NCO as sample source before writing config */
    FPGA_REG_WRITE(REG_JESD_TX_SRC_SEL, JESD_SRC_SEL_NCO);

    /* Disable NCO before writing config (quasi-static CDC constraint) */
    FPGA_REG_WRITE(REG_SINE_CTRL, 0x00);

    /* Compute and write frequency word — same tone on all four converters */
    freq_word = AD9176_NCO_FREQ_WORD(freq_hz, f_sample_hz);

    FPGA_REG_WRITE(REG_SINE_FREQ_CH1_I, freq_word);
    FPGA_REG_WRITE(REG_SINE_FREQ_CH1_Q, freq_word);
    FPGA_REG_WRITE(REG_SINE_FREQ_CH2_I, freq_word);
    FPGA_REG_WRITE(REG_SINE_FREQ_CH2_Q, freq_word);

    /* Zero phase offsets */
    FPGA_REG_WRITE(REG_SINE_PHASE_M0, 0x00);
    FPGA_REG_WRITE(REG_SINE_PHASE_M1, 0x00);
    FPGA_REG_WRITE(REG_SINE_PHASE_M2, 0x00);
    FPGA_REG_WRITE(REG_SINE_PHASE_M3, 0x00);

    /* Full-scale amplitude (0x7FFF = default from reg_bank reset) */
    FPGA_REG_WRITE(REG_SINE_AMP_M0, 0x00007FFF);
    FPGA_REG_WRITE(REG_SINE_AMP_M1, 0x00007FFF);
    FPGA_REG_WRITE(REG_SINE_AMP_M2, 0x00007FFF);
    FPGA_REG_WRITE(REG_SINE_AMP_M3, 0x00007FFF);

    /* Enable all converters, then assert global enable */
    FPGA_REG_WRITE(REG_SINE_CTRL, SINE_CTRL_ALL_CONV_EN | SINE_CTRL_ENABLE);

    return AD9176_OK;
}

void ad9176_nco_disable(void)
{
    /* Clear enable bit; leave config registers intact */
    FPGA_REG_WRITE(REG_SINE_CTRL,
                   FPGA_REG_READ(REG_SINE_CTRL) & ~SINE_CTRL_ENABLE);
}

int ad9176_jesd_wait_lock(uint32_t timeout_ms)
{
    uint32_t status;
    uint32_t elapsed = 0;
    /* Require: txlink_ready[1:0] (JESD IP locked) and group_synced[0]
     * (JesdSyncController LMFC-aligned and releasing data on links 0+1). */
    const uint32_t lock_mask = 0x03U | JESD_STATUS_GROUP0_SYNCED;

    while (elapsed < timeout_ms) {
        status = FPGA_REG_READ(REG_JESD_SYNC_STATUS);
        if ((status & lock_mask) == lock_mask)
            return AD9176_OK;
        delay_ms(1);
        elapsed++;
    }
    return AD9176_ERR_LINK;
}
