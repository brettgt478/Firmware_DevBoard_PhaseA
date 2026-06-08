/*
 * ad9176_init.c -- AD9176 bring-up sequence on the Phase B fabric SPI
 * transport. Register values follow AD9176 datasheet Table 50 with the
 * Phase A ad9176_init.c ordering preserved verbatim where applicable.
 */

#define _POSIX_C_SOURCE 200809L

#include "ad9176_init.h"
#include "dac_subsys_regs.h"

#include <stdio.h>
#include <time.h>

static void msleep(unsigned ms)
{
    struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

int ad9176_reset(const ad9176_ctx_t *ctx)
{
    int rc;
    rc = ad9176_reg_write(ctx, AD9176_REG_SOFT_RESET, 0x81);
    if (rc != AD9176_OK) {
        return rc;
    }
    msleep(2);
    rc = ad9176_reg_write(ctx, AD9176_REG_SOFT_RESET, 0x00);
    if (rc != AD9176_OK) {
        return rc;
    }
    msleep(2);

    /* Enable 4-wire SPI before the first register READ (ISSUE-023). The
     * AD9176 powers up in 3-wire SDIO mode, but the fabric SPI master is a
     * separate-MISO (4-wire) controller, so reads return garbage until SDO
     * is activated. Reg 0x000 = SPI_INTFCONFA, ADI mirrored convention:
     * bit3 SDOACTIVE + bit4 SDOACTIVE(mirror) -> 0x18 (same mirrored scheme
     * as the 0x81 soft-reset above). Writes work in 3-wire too, so this is
     * safe to issue here. */
    rc = ad9176_reg_write(ctx, AD9176_REG_SPI_INTFCONFA, 0x18);
    if (rc != AD9176_OK) {
        return rc;
    }
    msleep(1);
    return AD9176_OK;
}

int ad9176_verify_id(const ad9176_ctx_t *ctx)
{
    uint8_t chip_type = 0, lo = 0, hi = 0;
    int rc;

    rc = ad9176_reg_read(ctx, AD9176_REG_CHIPTYPE, &chip_type);
    if (rc != AD9176_OK) return rc;
    rc = ad9176_reg_read(ctx, AD9176_REG_PRODIDL, &lo);
    if (rc != AD9176_OK) return rc;
    rc = ad9176_reg_read(ctx, AD9176_REG_PRODIDH, &hi);
    if (rc != AD9176_OK) return rc;

    uint16_t prod_id = ((uint16_t)hi << 8) | lo;
    printf("AD9176 chip_type=0x%02X prod_id=0x%04X\n", chip_type, prod_id);

    if (chip_type != 0x04 || prod_id != 0x9176) {
        return AD9176_ERR_ID;
    }
    return AD9176_OK;
}

int ad9176_configure_pll_interp(const ad9176_ctx_t *ctx)
{
    int rc;
    /* DAC PLL enable (Phase A used 0x01; AD9176 mode-4 datapath needs
     * the PLL up before any JESD lane brings up). PLL settle ~5 ms. */
    rc = ad9176_reg_write(ctx, AD9176_REG_DACPLL_CTRL, 0x01);
    if (rc != AD9176_OK) return rc;
    msleep(5);

    uint8_t pll_status = 0;
    rc = ad9176_reg_read(ctx, AD9176_REG_DACPLL_STATUS, &pll_status);
    if (rc != AD9176_OK) return rc;
    printf("AD9176 DAC PLL status=0x%02X\n", pll_status);

    /* 4x main interpolation (Phase B JESD mode 4, NP=16, 4x interp
     * = 2.5 GSPS DAC rate from 625 MSPS per-converter JESD rate). */
    rc = ad9176_reg_write(ctx, AD9176_REG_INTERP_CTRL, 0x04);
    return rc;
}

int ad9176_configure_jesd_params(const ad9176_ctx_t *ctx)
{
    int rc;
    /* Mode 4 per CLAUDE.md Stage 5 plan: L=4, K=32, M=4, NP=16, F=2,
     * S=1, HD=1, SCR=1. AD9176 stores value = parameter - 1 for L/K/M. */
    rc = ad9176_reg_write(ctx, AD9176_REG_JESD_L_CTRL, 0x03);   /* L=4 */
    if (rc != AD9176_OK) return rc;
    rc = ad9176_reg_write(ctx, AD9176_REG_JESD_K_CTRL, 0x1F);   /* K=32 */
    if (rc != AD9176_OK) return rc;
    rc = ad9176_reg_write(ctx, AD9176_REG_JESD_M_CTRL, 0x03);   /* M=4 */
    if (rc != AD9176_OK) return rc;
    /* HD=1 (b7), SCR=1 (b5), S-1=0 (b4:0) */
    rc = ad9176_reg_write(ctx, AD9176_REG_JESD_MISC_CTRL, 0xA0);
    return rc;
}

int ad9176_enable_link(const ad9176_ctx_t *ctx)
{
    return ad9176_reg_write(ctx, AD9176_REG_LINK_CTRL0, 0x01);
}

int dac_subsys_release_sync(const ad9176_ctx_t *ctx)
{
    /* REG_JESD_SYNC_CTRL bit 0 is NOT a "start" bit -- it is the sync-mode
     * select in reg_bank.vhd (0 = per-DAC: group 0 = links 0+1; 1 = all-four:
     * one group needs links 0..3). The JesdSyncController FSM auto-starts from
     * reset, so no write is required to "release". On this single-AD9176 board
     * links 2/3 are tied low, so we MUST stay in per-DAC mode (0): writing 1
     * would demand links 2/3 and the active group could never sync (ISSUE-021).
     * Note: the FPGA does not drive SYNC_N -- the AD9176 drives SYNC_N into the
     * GTS IP -- so this write does not touch SYNC_N at all. Writing 0 explicitly
     * documents the intended mode (also the reset default). */
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_JESD_SYNC_CTRL, 0x00000000);
    return AD9176_OK;
}

int dac_subsys_wait_link_lock(const ad9176_ctx_t *ctx, unsigned timeout_ms)
{
    for (unsigned ms = 0; ms < timeout_ms; ++ms) {
        uint32_t s = ad9176_csr_read(ctx, DAC_CTRL_OFFSET + REG_JESD_SYNC_STATUS);
        uint8_t txrdy = (uint8_t)(s & SYNC_STATUS_TXLINK_READY_MASK);
        uint8_t grp   = (uint8_t)((s & SYNC_STATUS_GROUP_SYNCED_MASK) >>
                                  SYNC_STATUS_GROUP_SYNCED_SHIFT);
        uint8_t lmfc  = (uint8_t)((s >> SYNC_STATUS_LMFC_ALIGNED_BIT) & 1u);
        /* ISSUE-009: the single-AD9176-FMC-EBZ target populates only links
         * 0-1 (sync group 0); links 2-3 are tied low. So gate on the ACTIVE
         * links (0-1 => 0x3) and active group (group 0 => bit 0) only; do not
         * require lmfc_aligned (needs BOTH groups RUNNING -> always 0 here).
         *
         * ISSUE-020: this FPGA status only proves the dac_controller_0
         * TRANSPORT released data (its frame_ready feedback came from the
         * jesd_stub, not the GTS IP). It does NOT prove the AD9176 achieved
         * code-group sync. We read the AD9176's own LINK_STATUS (0x301) below
         * and print it so the bring-up engineer can confirm the physical link
         * on hardware (Procedure 5.A). Once the GTS link-status conduit is
         * wired back to the controller (ISSUE-020 permanent fix), this gate
         * becomes a true link-up indication. */
        if ((txrdy & 0x03u) == 0x03u && (grp & 0x01u)) {
            uint8_t ad_ls = 0;
            (void)ad9176_reg_read(ctx, AD9176_REG_LINK_STATUS, &ad_ls);
            printf("JESD transport released (status=0x%08X txrdy=0x%X grp=0x%X "
                   "lmfc=%u); AD9176 LINK_STATUS(0x301)=0x%02X -- confirm "
                   "code-group sync on hardware (ISSUE-020)\n",
                   s, (unsigned int)txrdy, (unsigned int)grp,
                   (unsigned int)lmfc, (unsigned int)ad_ls);
            return AD9176_OK;
        }
        msleep(1);
    }
    uint32_t s = ad9176_csr_read(ctx, DAC_CTRL_OFFSET + REG_JESD_SYNC_STATUS);
    uint8_t ad_ls = 0;
    (void)ad9176_reg_read(ctx, AD9176_REG_LINK_STATUS, &ad_ls);
    fprintf(stderr, "JESD link-lock timeout (status=0x%08X, "
            "AD9176 LINK_STATUS=0x%02X)\n", s, (unsigned int)ad_ls);
    return AD9176_ERR_NOT_READY;
}

int dac_subsys_set_nco_tone(const ad9176_ctx_t *ctx,
                            uint32_t freq_hz,
                            uint32_t f_sample_hz)
{
    /* freq_word = freq_hz * 2^32 / f_sample_hz. Uses 64-bit math to keep
     * precision across the full freq range. */
    uint64_t fw64 = ((uint64_t)freq_hz << 32) / (uint64_t)f_sample_hz;
    uint32_t fw   = (uint32_t)fw64;

    printf("SineWaveGen: f=%u Hz fs=%u Hz freq_word=0x%08X\n",
           freq_hz, f_sample_hz, fw);

    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_FREQ_CH1_I, fw);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_FREQ_CH1_Q, fw);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_FREQ_CH2_I, fw);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_FREQ_CH2_Q, fw);

    /* Q channels: +90 deg via top-bit phase offset (1/4 of 2^32). */
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_PHASE_M0, 0x00000000);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_PHASE_M1, 0x40000000);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_PHASE_M2, 0x00000000);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_PHASE_M3, 0x40000000);

    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_AMP_M0, 0x00007FFF);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_AMP_M1, 0x00007FFF);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_AMP_M2, 0x00007FFF);
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_AMP_M3, 0x00007FFF);

    /* Enable: global + all 4 converters (bits 4:1 = conv enable mask,
     * bit 0 = global enable). */
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_SINE_CTRL, 0x0000001F);
    /* Select NCO (FPGA SineWaveGen) as JESD TX source. */
    ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_JESD_TX_SRC_SEL, 0x00000000);
    return AD9176_OK;
}

int ad9176_bringup_full(const ad9176_ctx_t *ctx,
                        uint32_t tone_hz,
                        uint32_t f_sample_hz)
{
    int rc;

    printf("== AD9176 / dac_subsys Stage 7 bring-up ==\n");

    rc = ad9176_wait_fmc_ready(ctx, 1000 * 1000);   /* 1 s */
    if (rc != AD9176_OK) {
        fprintf(stderr, "fmc_ready never asserted (check FMC seating, VADJ=1.2V)\n");
        return rc;
    }
    printf("fmc_ready asserted\n");

    ad9176_set_spi_en(ctx, 1);
    ad9176_set_pe_ctrl(ctx, 1);

    rc = ad9176_reset(ctx);
    if (rc != AD9176_OK) { fprintf(stderr, "ad9176_reset failed (%d)\n", rc); return rc; }

    rc = ad9176_verify_id(ctx);
    if (rc != AD9176_OK) { fprintf(stderr, "ad9176_verify_id failed (%d)\n", rc); return rc; }

    rc = ad9176_configure_pll_interp(ctx);
    if (rc != AD9176_OK) { fprintf(stderr, "ad9176_configure_pll_interp failed (%d)\n", rc); return rc; }

    rc = ad9176_configure_jesd_params(ctx);
    if (rc != AD9176_OK) { fprintf(stderr, "ad9176_configure_jesd_params failed (%d)\n", rc); return rc; }

    rc = ad9176_enable_link(ctx);
    if (rc != AD9176_OK) { fprintf(stderr, "ad9176_enable_link failed (%d)\n", rc); return rc; }

    rc = dac_subsys_release_sync(ctx);
    if (rc != AD9176_OK) return rc;

    rc = dac_subsys_wait_link_lock(ctx, 5000);
    if (rc != AD9176_OK) return rc;

    rc = dac_subsys_set_nco_tone(ctx, tone_hz, f_sample_hz);
    if (rc != AD9176_OK) return rc;

    /* Enable both AD9176 inputs (TX_EN0/1). */
    ad9176_set_tx_en(ctx, 0x3);

    printf("== Bring-up complete; scope on AD9176 RF outputs ==\n");
    return AD9176_OK;
}
