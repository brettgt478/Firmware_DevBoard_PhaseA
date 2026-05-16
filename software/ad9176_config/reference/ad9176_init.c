/* ==========================================================================
 * AD9176 Initialization Driver
 *
 * Bare-metal HPS driver for configuring AD9176 DACs via iq_router SPI bridge
 * and enabling NCO test tone output.
 *
 * Author: Brett Taylor
 * Created: 2026-03-15
 * ========================================================================== */

#include "ad9176_init.h"
#include "iq_router_regs.h"
#include <stdio.h>

/* =====================================================================
 * AD9176 Register Addresses (from AD9176 datasheet)
 * ===================================================================== */
#define AD9176_REG_SPI_INTFCONFA    0x000  /* SPI config */
#define AD9176_REG_CHIPTYPE         0x003  /* Chip type (should be 0x04) */
#define AD9176_REG_PRODIDL          0x004  /* Product ID low */
#define AD9176_REG_PRODIDH          0x005  /* Product ID high */
#define AD9176_REG_CHIPGRADE        0x006  /* Chip grade */

/* JESD204B parameter registers */
#define AD9176_REG_JESD_L_CTRL     0x450  /* L (lanes) */
#define AD9176_REG_JESD_K_CTRL     0x451  /* K (frames per multiframe) */
#define AD9176_REG_JESD_M_CTRL     0x452  /* M (converters) */
#define AD9176_REG_JESD_MISC_CTRL  0x453  /* HD[7], SCR[5], S-1[4:0] */
#define AD9176_REG_JESD_BANK_SEL   0x454  /* Bank select for link params */

/* DAC PLL and interpolation */
#define AD9176_REG_DACPLL_CTRL     0x095
#define AD9176_REG_DACPLL_STATUS   0x096
#define AD9176_REG_INTERP_CTRL     0x198  /* Main datapath interpolation */

/* JESD204B link control */
#define AD9176_REG_LINK_CTRL0      0x300
#define AD9176_REG_LINK_STATUS     0x301

/* Soft reset */
#define AD9176_REG_SOFT_RESET      0x000

/* =====================================================================
 * Internal helpers
 * ===================================================================== */

static void spi_wait_idle(void)
{
    while (iq_reg_read(REG_SPI_STATUS) & (1 << SPI_STATUS_BUSY_BIT))
        ;
}

static void spi_select_cs(uint8_t cs)
{
    uint32_t ctrl = iq_reg_read(REG_SPI_CTRL);
    ctrl &= ~SPI_CTRL_CS_SELECT_MASK;
    ctrl |= ((uint32_t)cs << SPI_CTRL_CS_SELECT_SHIFT) &
             SPI_CTRL_CS_SELECT_MASK;
    iq_reg_write(REG_SPI_CTRL, ctrl);
    iq_reg_write(REG_SPI_CS_MAP, (uint32_t)cs);
}

/* Simple busy-wait delay (bare-metal, no OS timer) */
static void delay_us(uint32_t us)
{
    /* Approximate: ARM at ~1 GHz, ~5 cycles per loop iteration */
    volatile uint32_t count = us * 200;
    while (count--)
        ;
}

/* =====================================================================
 * Public API
 * ===================================================================== */

int ad9176_init_regs(void *base_vaddr)
{
    iq_router_base = (volatile uint32_t *)base_vaddr;
    return AD9176_OK;
}

int ad9176_test_bridge(void)
{
    const uint32_t test_patterns[] = {
        0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xA5A5A5A5
    };
    const uint32_t offsets[] = {
        REG_SCRATCH0, REG_SCRATCH1, REG_SCRATCH2, REG_SCRATCH3
    };

    /* Write patterns */
    for (int i = 0; i < 4; i++) {
        iq_reg_write(offsets[i], test_patterns[i]);
    }

    /* Read back and verify */
    for (int i = 0; i < 4; i++) {
        uint32_t readback = iq_reg_read(offsets[i]);
        if (readback != test_patterns[i]) {
            printf("ERROR: Bridge test failed at offset 0x%04X: "
                   "wrote 0x%08X, read 0x%08X\n",
                   offsets[i], test_patterns[i], readback);
            return AD9176_ERR_BRIDGE;
        }
    }

    printf("Bridge connectivity test PASSED\n");
    return AD9176_OK;
}

int ad9176_configure_spi(uint8_t clk_divider)
{
    /* Set clock divider */
    iq_reg_write(REG_SPI_CLK_DIV, (uint32_t)clk_divider);

    /* Enable address-mapped mode */
    uint32_t ctrl = iq_reg_read(REG_SPI_CTRL);
    ctrl |= (1 << SPI_CTRL_ADDR_MAP_EN_BIT);
    iq_reg_write(REG_SPI_CTRL, ctrl);

    return AD9176_OK;
}

int ad9176_init_dac(uint8_t cs)
{
    int rc;

    printf("Initializing AD9176 on CS%d...\n", cs);
    spi_select_cs(cs);

    /* Step 1: Soft reset */
    iq_spi_map_write(AD9176_REG_SOFT_RESET, 0x81);
    delay_us(1000);  /* Wait for reset */
    iq_spi_map_write(AD9176_REG_SOFT_RESET, 0x00);
    delay_us(1000);

    /* Step 2: Verify chip ID */
    uint8_t prod_id_l = iq_spi_map_read(AD9176_REG_PRODIDL);
    uint8_t prod_id_h = iq_spi_map_read(AD9176_REG_PRODIDH);
    uint16_t prod_id = ((uint16_t)prod_id_h << 8) | prod_id_l;
    printf("  Product ID: 0x%04X\n", prod_id);

    /* AD9176 product ID = 0x9176 (expected) */
    if (prod_id != 0x9176) {
        printf("  WARNING: Unexpected product ID (expected 0x9176)\n");
    }

    /* Step 3: Configure DAC PLL for 12 GSPS */
    iq_spi_map_write(AD9176_REG_DACPLL_CTRL, 0x01);  /* Enable PLL */
    delay_us(5000);  /* Wait for PLL lock */

    uint8_t pll_status = iq_spi_map_read(AD9176_REG_DACPLL_STATUS);
    printf("  DAC PLL status: 0x%02X\n", pll_status);

    /* Step 4: Set 6x main interpolation */
    iq_spi_map_write(AD9176_REG_INTERP_CTRL, 0x05);  /* 6x interp */

    /* Step 5: Configure JESD204B parameters */
    iq_spi_map_write(AD9176_REG_JESD_L_CTRL, 0x03);  /* L=4 (value=L-1) */
    iq_spi_map_write(AD9176_REG_JESD_K_CTRL, 0x1F);  /* K=32 (value=K-1) */
    iq_spi_map_write(AD9176_REG_JESD_M_CTRL, 0x03);  /* M=4 (value=M-1) */
    /* HD=1 (bit 7), SCR=1 (bit 5), S-1=0 (bits 4:0) */
    iq_spi_map_write(AD9176_REG_JESD_MISC_CTRL, 0xA0);

    /* Step 6: Verify JESD parameters */
    rc = ad9176_verify_jesd_params(cs);
    if (rc != AD9176_OK)
        return rc;

    /* Step 7: Enable JESD204B link */
    iq_spi_map_write(AD9176_REG_LINK_CTRL0, 0x01);

    printf("  AD9176 CS%d initialization complete\n", cs);
    return AD9176_OK;
}

int ad9176_verify_jesd_params(uint8_t cs)
{
    spi_select_cs(cs);

    uint8_t misc = iq_spi_map_read(AD9176_REG_JESD_MISC_CTRL);
    uint8_t hd  = (misc >> 7) & 0x01;
    uint8_t scr = (misc >> 5) & 0x01;

    printf("  JESD params: HD=%d, SCR=%d (reg 0x453 = 0x%02X)\n",
           hd, scr, misc);

    if (hd != 1) {
        printf("  ERROR: HD != 1\n");
        return AD9176_ERR_JESD_PARAM;
    }
    if (scr != 1) {
        printf("  ERROR: SCR != 1\n");
        return AD9176_ERR_JESD_PARAM;
    }

    uint8_t l_val = iq_spi_map_read(AD9176_REG_JESD_L_CTRL);
    uint8_t k_val = iq_spi_map_read(AD9176_REG_JESD_K_CTRL);
    uint8_t m_val = iq_spi_map_read(AD9176_REG_JESD_M_CTRL);

    printf("  JESD: L=%d, K=%d, M=%d\n", l_val + 1, k_val + 1, m_val + 1);

    if ((l_val + 1) != 4 || (k_val + 1) != 32 || (m_val + 1) != 4) {
        printf("  ERROR: JESD parameter mismatch\n");
        return AD9176_ERR_JESD_PARAM;
    }

    printf("  JESD parameter verification PASSED\n");
    return AD9176_OK;
}

int ad9176_enable_nco_tone(uint32_t freq_hz, uint32_t f_sample_hz)
{
    /* freq_word = f_out * 2^32 / f_sample */
    uint64_t freq_word = ((uint64_t)freq_hz << 32) / f_sample_hz;
    uint32_t fw = (uint32_t)freq_word;

    printf("NCO: freq=%u Hz, f_sample=%u Hz, freq_word=0x%08X\n",
           freq_hz, f_sample_hz, fw);

    /* Set frequency words for all channels */
    iq_reg_write(REG_SINE_FREQ_CH1_I, fw);
    iq_reg_write(REG_SINE_FREQ_CH1_Q, fw);
    iq_reg_write(REG_SINE_FREQ_CH2_I, fw);
    iq_reg_write(REG_SINE_FREQ_CH2_Q, fw);

    /* Q channels get 90-degree phase offset */
    iq_reg_write(REG_SINE_PHASE_M0, 0x00000000);
    iq_reg_write(REG_SINE_PHASE_M1, 0x40000000);  /* 90 deg */
    iq_reg_write(REG_SINE_PHASE_M2, 0x00000000);
    iq_reg_write(REG_SINE_PHASE_M3, 0x40000000);  /* 90 deg */

    /* Full-scale amplitude */
    iq_reg_write(REG_SINE_AMP_M0, 0x00007FFF);
    iq_reg_write(REG_SINE_AMP_M1, 0x00007FFF);
    iq_reg_write(REG_SINE_AMP_M2, 0x00007FFF);
    iq_reg_write(REG_SINE_AMP_M3, 0x00007FFF);

    /* Enable: global + all 4 converters */
    iq_reg_write(REG_SINE_CTRL, 0x0000001F);

    /* Select NCO as source (value 0) */
    iq_reg_write(REG_JESD_TX_SRC_SEL, 0x00000000);

    printf("NCO test tone enabled\n");
    return AD9176_OK;
}

int ad9176_wait_link_lock(uint32_t timeout_ms)
{
    uint32_t elapsed = 0;
    const uint32_t poll_interval_us = 1000;  /* 1 ms */

    printf("Waiting for JESD link lock...\n");

    while (elapsed < timeout_ms) {
        uint32_t status = iq_reg_read(REG_JESD_SYNC_STATUS);
        uint8_t txlink_rdy = status & SYNC_STATUS_TXLINK_READY_MASK;
        uint8_t grp_synced = (status & SYNC_STATUS_GROUP_SYNCED_MASK)
                             >> SYNC_STATUS_GROUP_SYNCED_SHIFT;
        uint8_t lmfc_aligned = (status >> SYNC_STATUS_LMFC_ALIGNED_BIT) & 1;

        if (txlink_rdy == 0x0F && grp_synced == 0x03 && lmfc_aligned) {
            printf("  All links locked and synchronized "
                   "(status=0x%08X)\n", status);
            return AD9176_OK;
        }

        delay_us(poll_interval_us);
        elapsed++;
    }

    uint32_t final_status = iq_reg_read(REG_JESD_SYNC_STATUS);
    printf("  ERROR: Link lock timeout (status=0x%08X)\n", final_status);
    return AD9176_ERR_LINK_LOCK;
}

/* =====================================================================
 * Main bring-up sequence
 * ===================================================================== */

#ifndef NO_MAIN
int main(void)
{
    int rc;

    /* TODO: Replace with actual mmap() or bare-metal base address */
    /* For Agilex 5 HPS bare-metal:
     * iq_router_base = (volatile uint32_t *)IQ_ROUTER_BASE; */
    printf("=== iq_router Phase A Bring-Up ===\n");

    /* Step 1: Test bridge connectivity */
    rc = ad9176_test_bridge();
    if (rc != AD9176_OK) return rc;

    /* Step 2: Configure SPI master */
    rc = ad9176_configure_spi(2);  /* divider=2 → 25 MHz SPI clk */
    if (rc != AD9176_OK) return rc;

    /* Step 3: Initialize both AD9176 DACs */
    rc = ad9176_init_dac(AD9176_CS_DAC0);
    if (rc != AD9176_OK) return rc;

    rc = ad9176_init_dac(AD9176_CS_DAC1);
    if (rc != AD9176_OK) return rc;

    /* Step 4: Configure all-four-link sync mode */
    iq_reg_write(REG_JESD_SYNC_CTRL, 0x00000001);

    /* Step 5: Wait for JESD link lock */
    rc = ad9176_wait_link_lock(5000);  /* 5 second timeout */
    if (rc != AD9176_OK) return rc;

    /* Step 6: Enable 10 MHz NCO test tone */
    rc = ad9176_enable_nco_tone(10000000, 500000000);  /* 10 MHz at 500 MSPS */
    if (rc != AD9176_OK) return rc;

    printf("=== Phase A Bring-Up Complete ===\n");
    printf("Verify DAC output on spectrum analyzer.\n");

    return AD9176_OK;
}
#endif
