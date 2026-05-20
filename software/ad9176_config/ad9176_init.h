/*
 * ad9176_init.h -- High-level bring-up sequence for the AD9176-FMC-EBZ.
 *
 * Step ordering follows the AD9176 datasheet (Rev. C) Table 50, adapted
 * for the Phase B fabric SPI transport (see ad9176_fmc_ebz.h) and the
 * Stage 5 dac_subsys signal-source pipeline (FPGA SineWaveGen ->
 * dac_controller_0 -> JESD GTS link -> AD9176 datapath).
 *
 * The AD9176 NCO is bypassed for the Stage 5 / Stage 7 bring-up tone --
 * the test sine is generated in the FPGA SineWaveGen, sent over JESD,
 * and routed straight to the AD9176 main DAC.
 */

#ifndef AD9176_INIT_H
#define AD9176_INIT_H

#include <stdint.h>

#include "ad9176_fmc_ebz.h"

/* AD9176 register addresses, lifted from Phase A's ad9176_init.c.
 * Cross-check against AD9176 datasheet Rev. C Table 75 before edits. */
#define AD9176_REG_SPI_INTFCONFA   0x000
#define AD9176_REG_CHIPTYPE        0x003   /* expect 0x04 */
#define AD9176_REG_PRODIDL         0x004   /* expect 0x76 */
#define AD9176_REG_PRODIDH         0x005   /* expect 0x91 */
#define AD9176_REG_CHIPGRADE       0x006

#define AD9176_REG_DACPLL_CTRL     0x095
#define AD9176_REG_DACPLL_STATUS   0x096
#define AD9176_REG_INTERP_CTRL     0x198

#define AD9176_REG_JESD_L_CTRL     0x450   /* L  (value = L-1)  */
#define AD9176_REG_JESD_K_CTRL     0x451   /* K  (value = K-1)  */
#define AD9176_REG_JESD_M_CTRL     0x452   /* M  (value = M-1)  */
#define AD9176_REG_JESD_MISC_CTRL  0x453   /* HD[7] SCR[5] S-1[4:0] */
#define AD9176_REG_JESD_BANK_SEL   0x454

#define AD9176_REG_LINK_CTRL0      0x300
#define AD9176_REG_LINK_STATUS     0x301

#define AD9176_REG_SOFT_RESET      0x000

/* Bring-up entry points -- each returns AD9176_OK or a negative error. */
int ad9176_reset                 (const ad9176_ctx_t *ctx);
int ad9176_verify_id             (const ad9176_ctx_t *ctx);
int ad9176_configure_pll_interp  (const ad9176_ctx_t *ctx);
int ad9176_configure_jesd_params (const ad9176_ctx_t *ctx);
int ad9176_enable_link           (const ad9176_ctx_t *ctx);

/* FPGA-side helpers (dac_controller_0 SineWaveGen + JESD sync controller). */
int dac_subsys_release_sync   (const ad9176_ctx_t *ctx);
int dac_subsys_wait_link_lock (const ad9176_ctx_t *ctx, unsigned timeout_ms);
int dac_subsys_set_nco_tone   (const ad9176_ctx_t *ctx,
                               uint32_t freq_hz,
                               uint32_t f_sample_hz);

/* Full sequence: mmap -> wait_fmc_ready -> SPI EN + PE_CTRL ->
 * AD9176 reset/init -> JESD link release -> sine tone. */
int ad9176_bringup_full(const ad9176_ctx_t *ctx,
                        uint32_t tone_hz,
                        uint32_t f_sample_hz);

#endif /* AD9176_INIT_H */
