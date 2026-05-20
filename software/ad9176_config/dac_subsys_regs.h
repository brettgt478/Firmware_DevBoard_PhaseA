/*
 * dac_subsys_regs.h -- HPS-side register map for dac_subsys on Phase B
 *
 * All addresses are HPS-physical, reached through the lwhps2fpga (LWS2F)
 * bridge window. The window base 0x0200_0000 is fixed by CLAUDE.md
 * SS6 #6 -- moving it requires updating this header, the device tree,
 * and any System Console scripts.
 *
 * Phase A's iq_router_regs.h is now stale and lives in
 * software/ad9176_config/reference/ for historical traceability.
 * dac_subsys_regs.h is the source of truth for Phase B user-space
 * code; offsets here MUST match the case statement in
 * ip/dac_controller_0/src/reg_bank.vhd (audit recorded in
 * doc/potential_issues.md ISSUE-007).
 */

#ifndef DAC_SUBSYS_REGS_H
#define DAC_SUBSYS_REGS_H

#include <stdint.h>

/* ---------------------------------------------------------------------
 * LWS2F window
 * --------------------------------------------------------------------- */
#define DAC_SUBSYS_BASE        0x02000000UL
#define DAC_SUBSYS_SPAN        0x00004000UL   /* 16 KB per CLAUDE.md addr map */

/* ---------------------------------------------------------------------
 * dac_controller_0 (Phase A reg_bank) -- 1 KB at 0x0000
 * Offsets cross-checked against ip/dac_controller_0/src/dac_controller_pkg.vhd
 * --------------------------------------------------------------------- */
#define DAC_CTRL_OFFSET                0x00000000UL

#define REG_SCRATCH0                   0x000
#define REG_SCRATCH1                   0x004
#define REG_SCRATCH2                   0x008
#define REG_SCRATCH3                   0x00C

#define REG_JESD_SYNC_CTRL             0x020
#define REG_JESD_SYNC_STATUS           0x024
#define REG_JESD_SYNC_ERR              0x028
#define REG_JESD_TX_SRC_SEL            0x030
#define REG_JESD_TX_SRC_STATUS         0x034

#define REG_SINE_CTRL                  0x040
#define REG_SINE_FREQ_CH1_I            0x050
#define REG_SINE_FREQ_CH1_Q            0x054
#define REG_SINE_FREQ_CH2_I            0x058
#define REG_SINE_FREQ_CH2_Q            0x05C
#define REG_SINE_PHASE_M0              0x060
#define REG_SINE_PHASE_M1              0x064
#define REG_SINE_PHASE_M2              0x068
#define REG_SINE_PHASE_M3              0x06C
#define REG_SINE_AMP_M0                0x070
#define REG_SINE_AMP_M1                0x074
#define REG_SINE_AMP_M2                0x078
#define REG_SINE_AMP_M3                0x07C

#define REG_PIO_CTRL                   0x080
#define REG_PIO_STATUS                 0x084

/* JESD_SYNC_STATUS bit fields */
#define SYNC_STATUS_TXLINK_READY_MASK  0x0F
#define SYNC_STATUS_GROUP_SYNCED_SHIFT 4
#define SYNC_STATUS_GROUP_SYNCED_MASK  0x30
#define SYNC_STATUS_LMFC_ALIGNED_BIT   6

/* SINE_CTRL bit fields */
#define SINE_CTRL_ENABLE_BIT           0
#define SINE_CTRL_CONV_ENABLE_SHIFT    1
#define SINE_CTRL_CONV_ENABLE_MASK     0x1E

/* ---------------------------------------------------------------------
 * u_spi_master -- Altera Avalon-MM SPI Master, 0x1000, 64 B
 * dataWidth=24, 2 CS (CS0=AD9176, CS1=spare), 25 MHz, mode 0 (CPOL=0/CPHA=0),
 * MSB-first.  Register layout per CSV from
 * ip/dac_subsys/ip/dac_subsys/dac_subsys_u_spi_master/dac_subsys_u_spi_master.regmap
 * (word offsets converted to byte offsets here).
 * --------------------------------------------------------------------- */
#define SPI_MASTER_OFFSET              0x00001000UL

#define SPI_REG_RXDATA                 0x00   /* RO  */
#define SPI_REG_TXDATA                 0x04   /* WO  */
#define SPI_REG_STATUS                 0x08   /* R/W (writes clear sticky bits) */
#define SPI_REG_CONTROL                0x0C   /* R/W */
#define SPI_REG_SLAVESEL               0x14   /* R/W (CS bitmask) */
#define SPI_REG_EOP_VALUE              0x18   /* R/W */

/* STATUS bits */
#define SPI_STATUS_ROE                 (1u << 3)   /* receive overrun */
#define SPI_STATUS_TOE                 (1u << 4)   /* transmit overrun */
#define SPI_STATUS_TMT                 (1u << 5)   /* transmit empty (transfer complete) */
#define SPI_STATUS_TRDY                (1u << 6)   /* tx register ready */
#define SPI_STATUS_RRDY                (1u << 7)   /* rx register has data */
#define SPI_STATUS_E                   (1u << 8)   /* OR of TOE/ROE */
#define SPI_STATUS_EOP                 (1u << 9)

/* CONTROL bits */
#define SPI_CONTROL_IROE               (1u << 3)
#define SPI_CONTROL_ITOE               (1u << 4)
#define SPI_CONTROL_ITRDY              (1u << 6)
#define SPI_CONTROL_IRRDY              (1u << 7)
#define SPI_CONTROL_IE                 (1u << 8)
#define SPI_CONTROL_IEOP               (1u << 9)
#define SPI_CONTROL_SSO                (1u << 10)  /* force CS asserted across transfers */

/* CS bitmask values */
#define SPI_SLAVESEL_AD9176            (1u << 0)
#define SPI_SLAVESEL_SPARE             (1u << 1)

/* ---------------------------------------------------------------------
 * PIOs at 0x1100..0x1140 (each 16 B span; first word is the data register)
 * --------------------------------------------------------------------- */
#define TX_EN_PIO_OFFSET               0x00001100UL   /* [1:0] -> fmc_txen[1:0] */
#define PE_CTRL_PIO_OFFSET             0x00001110UL   /* [0]   -> fmc_pe_ctrl   */
#define DAC_STATUS_PIO_OFFSET          0x00001120UL   /* RO inputs (see bits below) */
#define SPI_EN_PIO_OFFSET              0x00001130UL   /* [0]   -> fmc_spi_en    */
#define PG_C2M_PIO_OFFSET              0x00001140UL   /* dangling -- diagnostic */

/* DAC_STATUS_PIO bit assignments (HPS read-only) */
#define DAC_STATUS_PRSNT_N_BIT         0    /* AD9176-FMC-EBZ presence (active low) */
#define DAC_STATUS_PG_C2M_LOOPBACK_BIT 2    /* loopback of PG_C2M PIO (diagnostic) */
#define DAC_STATUS_FMC_READY_BIT       5    /* fmc_handshake.sv: prsnt_n+pg_m2c stable */
/* bits 31:6 reserved for JESD link status (later wiring) */

/* ---------------------------------------------------------------------
 * JESD204B GTS link CSRs -- 4 KB each
 * --------------------------------------------------------------------- */
#define JESD_LINK0_OFFSET              0x00002000UL
#define JESD_LINK1_OFFSET              0x00003000UL

#endif /* DAC_SUBSYS_REGS_H */
