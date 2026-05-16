/*
 * ad9176_fmc_ebz.h
 *
 * HPS bare-metal driver for the AD9176-FMC-EBZ evaluation board.
 * Targets: Agilex 5 dev board, single AD9176 (dual DAC core, 2 JESD links).
 *
 * SPI access: bit-banged through the Agilex HPS GPIO or the dedicated HPS
 * SPI peripheral, NOT through FPGA fabric registers. All AD9176 register
 * accesses use 24-bit SPI frames: [R/W | A14..A0 | D7..D0].
 *
 * FPGA register access: memory-mapped through the lwhpm2fpga AXI bridge.
 * Base address must match the Platform Designer assignment for dac_controller_0.
 * Update DAC_CTRL_BASE if your PD project maps it differently.
 *
 * Author: Brett Taylor
 * Created: 2026-04-06
 */

#ifndef AD9176_FMC_EBZ_H
#define AD9176_FMC_EBZ_H

#include <stdint.h>

/* =========================================================================
 * FPGA register base address on lwhpm2fpga bridge
 * Update to match the Platform Designer memory map for dac_controller_0.
 * ========================================================================= */
#define DAC_CTRL_BASE  0xFF200000UL   /* placeholder — confirm in PD project */

/* =========================================================================
 * FPGA register offsets (byte-addressed, 10-bit space)
 * Must match dac_controller_pkg.vhd register map.
 * ========================================================================= */

/* Scratchpad (bridge connectivity test) */
#define REG_SCRATCH0          0x000
#define REG_SCRATCH1          0x004
#define REG_SCRATCH2          0x008
#define REG_SCRATCH3          0x00C

/* JESD TX CSR */
#define REG_JESD_SYNC_CTRL    0x020
#define REG_JESD_SYNC_STATUS  0x024
#define REG_JESD_SYNC_ERR     0x028
#define REG_JESD_TX_SRC_SEL   0x030
#define REG_JESD_TX_SRC_STAT  0x034

/* JESD_SYNC_STATUS bit definitions */
#define JESD_STATUS_TXLINK_READY_MASK   0x0FU        /* bits [3:0]: per-link JESD IP lock */
#define JESD_STATUS_GROUP_SYNCED_MASK   0x30U        /* bits [5:4]: both sync groups */
#define JESD_STATUS_GROUP0_SYNCED       (1U << 4)    /* bit 4: group 0 (links 0+1) in RUNNING */
#define JESD_STATUS_GROUP1_SYNCED       (1U << 5)    /* bit 5: group 1 (links 2+3) in RUNNING */
/* NOTE: LMFC_ALIGNED requires both groups in RUNNING state. In the current
 * 2-active-link configuration (links 2 and 3 unconnected), group 1 never
 * reaches RUNNING, so this bit is always 0. Use GROUP0_SYNCED instead. */
#define JESD_STATUS_LMFC_ALIGNED        (1U << 6)

/* JESD_SYNC_CTRL bit definitions */
#define JESD_CTRL_SYNC_MODE_ALL_FOUR    (1U << 0) /* 0=per-DAC 2-link groups, 1=all-four links */

/* JESD_SYNC_ERR bit definitions (write-1-to-clear, bits [3:0]) */
#define JESD_SYNC_ERR_LINK0             (1U << 0)
#define JESD_SYNC_ERR_LINK1             (1U << 1)
#define JESD_SYNC_ERR_LINK2             (1U << 2)
#define JESD_SYNC_ERR_LINK3             (1U << 3)
#define JESD_SYNC_ERR_ALL_MASK          0x0FU

/* REG_JESD_TX_SRC_SEL bit definitions */
#define JESD_SRC_SEL_NCO                0x00U        /* bit [0] = 0: NCO (default) */
#define JESD_SRC_SEL_FIFO               (1U << 0)    /* bit [0] = 1: FIFO input */

/* REG_JESD_TX_SRC_STAT bit definitions (read-only) */
#define JESD_SRC_STAT_SWITCH_PENDING    (1U << 0)    /* source switch in progress */
#define JESD_SRC_STAT_ACTIVE            (1U << 1)    /* 0=NCO active, 1=FIFO active */

/* Sine wave generator CSR */
#define REG_SINE_CTRL         0x040
#define REG_SINE_FREQ_CH1_I   0x050   /* converter 0 (DAC core A, I) */
#define REG_SINE_FREQ_CH1_Q   0x054   /* converter 1 (DAC core A, Q) */
#define REG_SINE_FREQ_CH2_I   0x058   /* converter 2 (DAC core B, I) */
#define REG_SINE_FREQ_CH2_Q   0x05C   /* converter 3 (DAC core B, Q) */
#define REG_SINE_PHASE_M0     0x060
#define REG_SINE_PHASE_M1     0x064
#define REG_SINE_PHASE_M2     0x068
#define REG_SINE_PHASE_M3     0x06C
#define REG_SINE_AMP_M0       0x070
#define REG_SINE_AMP_M1       0x074
#define REG_SINE_AMP_M2       0x078
#define REG_SINE_AMP_M3       0x07C

/* SINE_CTRL bit definitions */
#define SINE_CTRL_ENABLE         (1U << 0)
#define SINE_CTRL_CONV_EN_M0     (1U << 1)
#define SINE_CTRL_CONV_EN_M1     (1U << 2)
#define SINE_CTRL_CONV_EN_M2     (1U << 3)
#define SINE_CTRL_CONV_EN_M3     (1U << 4)
#define SINE_CTRL_ALL_CONV_EN    (0x1EU)   /* bits [4:1] */

/* PIO stubs (deferred) */
#define REG_PIO_CTRL          0x080
#define REG_PIO_STATUS        0x084

/* =========================================================================
 * Software SPI pin assignments
 * Update to match the actual GPIO/SPI peripheral used on the Agilex 5
 * dev board FMC connector. Placeholder numbers shown.
 * ========================================================================= */
#define SPI_CLK_GPIO_BASE    0xFF703000UL  /* HPS GPIO1 base — confirm */
#define SPI_CLK_PIN          (1U << 10)
#define SPI_MOSI_PIN         (1U << 11)
#define SPI_MISO_PIN         (1U << 12)
#define SPI_CS_N_PIN         (1U << 13)

/* AD9176 has one chip-select on the FMC-EBZ (single device) */
#define AD9176_CS_N          SPI_CS_N_PIN

/* =========================================================================
 * AD9176 register address constants (selected subset)
 * Full map: AD9176 datasheet Table 16.
 * ========================================================================= */

/* Device config */
#define AD9176_REG_SPI_CONFIG_A     0x000  /* SPI interface config */
#define AD9176_REG_CHIP_TYPE        0x003  /* read: 0x04 = DAC */
#define AD9176_REG_PROD_ID_MSB      0x004  /* read: 0x92 */
#define AD9176_REG_PROD_ID_LSB      0x005  /* read: 0x00 */
#define AD9176_REG_CHIP_GRADE       0x006

/* DAC PLL / datapath */
#define AD9176_REG_DACPLL_STATUS    0x07D  /* bit0=PLL locked */
#define AD9176_REG_INTERP_MODE      0x200  /* interpolation: bits [2:0] */
#define AD9176_REG_DATAPATH_CFG     0x201

/* JESD204B parameters (as reported by device) */
#define AD9176_REG_JESD_L           0x450  /* L-1 (number of lanes minus 1) */
#define AD9176_REG_JESD_F           0x451  /* F-1 */
#define AD9176_REG_JESD_K           0x452  /* K-1 */
#define AD9176_REG_JESD_M           0x453  /* bits [5:0]=M-1, bit 6=SCR, bit 7=HD */
#define AD9176_REG_JESD_N           0x454  /* N-1 */
#define AD9176_REG_JESD_NP          0x455  /* NP-1 */
#define AD9176_REG_JESD_S           0x456  /* S-1 */

/* JESD enable / link status */
#define AD9176_REG_JESD_EN          0x470  /* bit0: enable JESD link */
#define AD9176_REG_JESD_LINK_STATUS 0x472

/* =========================================================================
 * AD9176 expected JESD parameter values (Mode 4, one link)
 * These are written during init and read back for verification.
 * ========================================================================= */
#define AD9176_JESD_L_VAL    3   /* L-1: 4 lanes */
#define AD9176_JESD_F_VAL    1   /* F-1: 2 octets/frame */
#define AD9176_JESD_K_VAL   31   /* K-1: 32 frames/multiframe */
#define AD9176_JESD_M_VAL    3   /* M-1: 4 converters (bits [5:0]) */
#define AD9176_JESD_N_VAL   15   /* N-1: 16 bits */
#define AD9176_JESD_NP_VAL  15   /* NP-1: 16 bits */
#define AD9176_JESD_S_VAL    0   /* S-1: 1 sample */
#define AD9176_JESD_HD_BIT   (1U << 7)  /* High Density mode */
#define AD9176_JESD_SCR_BIT  (1U << 6)  /* Scrambling enabled */

/* Interpolation: 6× (value 0x06 in INTERP_MODE bits [2:0]) */
#define AD9176_INTERP_6X     0x06

/* =========================================================================
 * NCO frequency word helper
 * freq_word = round(f_out_hz * 2^32 / f_sample_hz)
 * f_sample = 2 * f_link_clk (500 MHz at 250 MHz link clock)
 * Example: 10 MHz tone → 0x051EB852
 * ========================================================================= */
#define AD9176_NCO_FREQ_WORD(f_out_hz, f_sample_hz) \
    ((uint32_t)(((double)(f_out_hz) / (double)(f_sample_hz)) * 4294967296.0))

/* =========================================================================
 * Return codes
 * ========================================================================= */
#define AD9176_OK            0
#define AD9176_ERR_SPI      -1
#define AD9176_ERR_PLL      -2
#define AD9176_ERR_JESD_PARAM -3
#define AD9176_ERR_LINK     -4
#define AD9176_ERR_SCRATCH  -5

/* =========================================================================
 * FPGA register access macros
 * ========================================================================= */
#define FPGA_REG_WRITE(offset, val) \
    (*((volatile uint32_t *)(DAC_CTRL_BASE + (offset))) = (uint32_t)(val))

#define FPGA_REG_READ(offset) \
    (*((volatile uint32_t *)(DAC_CTRL_BASE + (offset))))

/* =========================================================================
 * Public API
 * ========================================================================= */

/*
 * ad9176_fpga_bridge_test
 * Write and read back all four scratchpad registers to verify the
 * lwhpm2fpga AXI bridge is functional before touching the DAC.
 * Returns AD9176_OK on success, AD9176_ERR_SCRATCH on mismatch.
 */
int ad9176_fpga_bridge_test(void);

/*
 * ad9176_spi_write
 * Write one byte to an AD9176 register via software SPI.
 * addr: 15-bit AD9176 register address.
 * data: 8-bit value to write.
 */
void ad9176_spi_write(uint16_t addr, uint8_t data);

/*
 * ad9176_spi_read
 * Read one byte from an AD9176 register via software SPI.
 * addr: 15-bit AD9176 register address.
 * Returns the 8-bit register value.
 */
uint8_t ad9176_spi_read(uint16_t addr);

/*
 * ad9176_init
 * Full AD9176 startup sequence per datasheet Table 50:
 *   1. Soft reset
 *   2. Configure DAC PLL for 12 GSPS (6× interpolation, 2 GHz input)
 *   3. Set JESD204B parameters (M=4, L=4, F=2, K=32, SCR=1, HD=1)
 *   4. Verify HD and SCR readback
 *   5. Enable JESD204B link
 *   6. Wait for link lock (txlink_ready via FPGA status register)
 * Returns AD9176_OK or a negative error code.
 */
int ad9176_init(void);

/*
 * ad9176_nco_enable
 * Configure the FPGA sine wave generator and enable NCO output.
 * freq_hz: desired output frequency in Hz (e.g. 10000000 for 10 MHz).
 * f_sample_hz: DAC sample rate in Hz (e.g. 500000000 for 500 MSPS effective).
 * All four converters are set to the same frequency; phase offsets are zero.
 * Returns AD9176_OK or a negative error code.
 */
int ad9176_nco_enable(uint32_t freq_hz, uint32_t f_sample_hz);

/*
 * ad9176_nco_disable
 * Deassert SINE_CTRL.enable to stop the NCO output.
 */
void ad9176_nco_disable(void);

/*
 * ad9176_jesd_wait_lock
 * Poll FPGA JESD_SYNC_STATUS until both active links (txlink_ready bits [1:0])
 * report JESD IP lock AND group 0 (links 0+1) reports sync controller RUNNING
 * (JESD_STATUS_GROUP0_SYNCED, bit 4), or until timeout_ms elapses.
 * Group 0 sync confirms the JesdSyncController released data flow on an LMFC
 * boundary — txlink_ready alone is insufficient for data transmission.
 * Returns AD9176_OK on full lock, AD9176_ERR_LINK on timeout.
 */
int ad9176_jesd_wait_lock(uint32_t timeout_ms);

#endif /* AD9176_FMC_EBZ_H */
