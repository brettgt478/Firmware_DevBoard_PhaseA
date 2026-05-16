/* ==========================================================================
 * AD9176 Initialization Driver
 * Author: Brett Taylor
 * Created: 2026-03-15
 * ========================================================================== */

#ifndef AD9176_INIT_H
#define AD9176_INIT_H

#include <stdint.h>

/* AD9176 chip select assignments */
#define AD9176_CS_DAC0  0
#define AD9176_CS_DAC1  1

/* Return codes */
#define AD9176_OK               0
#define AD9176_ERR_BRIDGE      -1
#define AD9176_ERR_SPI         -2
#define AD9176_ERR_JESD_PARAM  -3
#define AD9176_ERR_LINK_LOCK   -4

/* Initialize the iq_router register interface.
 * base_vaddr: virtual address of lwhps2fpga bridge mapping */
int ad9176_init_regs(void *base_vaddr);

/* Verify HPS-to-FPGA bridge connectivity via scratchpad registers */
int ad9176_test_bridge(void);

/* Configure SPI master (clock divider, enable address-mapped mode) */
int ad9176_configure_spi(uint8_t clk_divider);

/* Full AD9176 initialization sequence for one DAC.
 * cs: chip select (0 or 1) */
int ad9176_init_dac(uint8_t cs);

/* Verify JESD204B parameter readback (HD=1, SCR=1, etc.)
 * cs: chip select (0 or 1) */
int ad9176_verify_jesd_params(uint8_t cs);

/* Configure and enable NCO test tone.
 * freq_hz: desired output frequency in Hz
 * f_sample_hz: effective sample rate (2 * link_clk) */
int ad9176_enable_nco_tone(uint32_t freq_hz, uint32_t f_sample_hz);

/* Wait for JESD204B link lock on all links.
 * timeout_ms: maximum wait time */
int ad9176_wait_link_lock(uint32_t timeout_ms);

#endif /* AD9176_INIT_H */
