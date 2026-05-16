/* ==========================================================================
 * iq_router Register Definitions
 * Matches IqRouterPkg.vhd register map
 * Author: Brett Taylor
 * Created: 2026-03-15
 * ========================================================================== */

#ifndef IQ_ROUTER_REGS_H
#define IQ_ROUTER_REGS_H

#include <stdint.h>

/* Base address on lwhps2fpga bridge */
#define IQ_ROUTER_BASE          0x04400000UL

/* Global CSR — Scratchpad */
#define REG_SCRATCH0            0x0000
#define REG_SCRATCH1            0x0004
#define REG_SCRATCH2            0x0008
#define REG_SCRATCH3            0x000C

/* JESD TX CSR */
#define REG_JESD_SYNC_CTRL     0x0320
#define REG_JESD_SYNC_STATUS   0x0324
#define REG_JESD_SYNC_ERR      0x0328
#define REG_JESD_TX_SRC_SEL    0x0330
#define REG_JESD_TX_SRC_STATUS 0x0334

/* Sine Wave Gen CSR */
#define REG_SINE_CTRL          0x0400
#define REG_SINE_FREQ_CH1_I    0x0410
#define REG_SINE_FREQ_CH1_Q    0x0414
#define REG_SINE_FREQ_CH2_I    0x0418
#define REG_SINE_FREQ_CH2_Q    0x041C
#define REG_SINE_PHASE_M0      0x0420
#define REG_SINE_PHASE_M1      0x0424
#define REG_SINE_PHASE_M2      0x0428
#define REG_SINE_PHASE_M3      0x042C
#define REG_SINE_AMP_M0        0x0430
#define REG_SINE_AMP_M1        0x0434
#define REG_SINE_AMP_M2        0x0438
#define REG_SINE_AMP_M3        0x043C

/* SPI Control CSR */
#define REG_SPI_CTRL           0x0500
#define REG_SPI_STATUS         0x0504
#define REG_SPI_CLK_DIV        0x0508
#define REG_SPI_CS_MAP         0x050C
#define REG_SPI_DIRECT_TX      0x0510
#define REG_SPI_DIRECT_RX      0x0514

/* SPI Mapped Window */
#define SPI_MAP_BASE           0x2000
#define SPI_MAP_END            0x3FFF

/* JESD_SYNC_STATUS bit fields */
#define SYNC_STATUS_TXLINK_READY_MASK  0x0F
#define SYNC_STATUS_GROUP_SYNCED_SHIFT 4
#define SYNC_STATUS_GROUP_SYNCED_MASK  0x30
#define SYNC_STATUS_LMFC_ALIGNED_BIT   6

/* SINE_CTRL bit fields */
#define SINE_CTRL_ENABLE_BIT           0
#define SINE_CTRL_CONV_ENABLE_SHIFT    1
#define SINE_CTRL_CONV_ENABLE_MASK     0x1E

/* SPI_CTRL bit fields */
#define SPI_CTRL_ADDR_MAP_EN_BIT       0
#define SPI_CTRL_CS_SELECT_SHIFT       2
#define SPI_CTRL_CS_SELECT_MASK        0x0C

/* SPI_STATUS bit fields */
#define SPI_STATUS_BUSY_BIT            0

/* ========================================================================
 * Register access helpers (bare-metal, memory-mapped)
 * ======================================================================== */

static volatile uint32_t *iq_router_base = NULL;

static inline void iq_reg_write(uint32_t offset, uint32_t value)
{
    iq_router_base[offset / 4] = value;
}

static inline uint32_t iq_reg_read(uint32_t offset)
{
    return iq_router_base[offset / 4];
}

/* SPI mapped window: write byte to AD9176 register */
static inline void iq_spi_map_write(uint16_t spi_addr, uint8_t data)
{
    iq_reg_write(SPI_MAP_BASE + (spi_addr & 0x1FFF), (uint32_t)data);
}

/* SPI mapped window: read byte from AD9176 register */
static inline uint8_t iq_spi_map_read(uint16_t spi_addr)
{
    return (uint8_t)(iq_reg_read(SPI_MAP_BASE + (spi_addr & 0x1FFF)) & 0xFF);
}

#endif /* IQ_ROUTER_REGS_H */
