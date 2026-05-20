/*
 * ad9176_fmc_ebz.h -- HPS user-space transport for AD9176-FMC-EBZ.
 *
 * Reaches the FPGA fabric via /dev/mem mmap on the lwhps2fpga window
 * (DAC_SUBSYS_BASE in dac_subsys_regs.h). AD9176 SPI writes/reads land on
 * the Avalon-MM SPI Master at SPI_MASTER_OFFSET; CS0 is the AD9176, CS1
 * spare.
 *
 * SPI frame format (24 bits, transmitted MSB-first as one txdata write):
 *   [23]    R/W   (1=read, 0=write)
 *   [22:8]  15-bit register address
 *   [7:0]   8-bit data (write) or don't-care (read)
 *
 * The Altera Avalon-MM SPI Master shifts dataWidth bits per txdata write,
 * full-duplex, returning the received word in rxdata.
 *
 * CLAUDE.md SS6 #9: AD9176 SPI is driven from fabric; HPS pins do NOT
 * reach the FMC. This transport is the only supported path.
 */

#ifndef AD9176_FMC_EBZ_H
#define AD9176_FMC_EBZ_H

#include <stdint.h>

/* Return codes */
#define AD9176_OK              0
#define AD9176_ERR_OPEN_MEM   -1
#define AD9176_ERR_MMAP       -2
#define AD9176_ERR_SPI_TIMEOUT -3
#define AD9176_ERR_NOT_READY  -4   /* fmc_ready bit clear */
#define AD9176_ERR_ID         -5   /* CHIPTYPE / PRODID mismatch */

/* Opaque handle. Created by ad9176_open(), released by ad9176_close(). */
typedef struct ad9176_ctx ad9176_ctx_t;

/* Open /dev/mem and map the dac_subsys window. Returns NULL on failure
 * (errno set). */
ad9176_ctx_t *ad9176_open(void);
void          ad9176_close(ad9176_ctx_t *ctx);

/* Raw dac_subsys CSR access (32-bit, byte offset within the 16 KB window). */
uint32_t ad9176_csr_read (const ad9176_ctx_t *ctx, uint32_t byte_offset);
void     ad9176_csr_write(const ad9176_ctx_t *ctx, uint32_t byte_offset, uint32_t value);

/* AD9176 SPI register access (15-bit addr, 8-bit data).
 * Returns AD9176_OK on success, AD9176_ERR_SPI_TIMEOUT on master hang. */
int ad9176_reg_write(const ad9176_ctx_t *ctx, uint16_t reg_addr, uint8_t  value);
int ad9176_reg_read (const ad9176_ctx_t *ctx, uint16_t reg_addr, uint8_t *value);

/* Convenience wrappers for the Stage 5 FMC PIO gates. */
int  ad9176_wait_fmc_ready(const ad9176_ctx_t *ctx, unsigned timeout_us);
void ad9176_set_spi_en   (const ad9176_ctx_t *ctx, int on);
void ad9176_set_pe_ctrl  (const ad9176_ctx_t *ctx, int on);
void ad9176_set_tx_en    (const ad9176_ctx_t *ctx, unsigned mask_2bit);

#endif /* AD9176_FMC_EBZ_H */
