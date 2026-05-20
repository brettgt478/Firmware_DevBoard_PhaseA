/*
 * ad9176_fmc_ebz.c -- HPS user-space transport for AD9176-FMC-EBZ.
 * See ad9176_fmc_ebz.h for the contract.
 */

#define _POSIX_C_SOURCE 200809L

#include "ad9176_fmc_ebz.h"
#include "dac_subsys_regs.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

struct ad9176_ctx {
    int            mem_fd;
    volatile uint8_t *win;        /* mmap base */
    size_t         win_span;
};

/* Spin until the SPI master reports TMT (transfer complete). 10 ms ceiling
 * is generous -- at 25 MHz SCK a 24-bit frame takes ~1 us. */
static int spi_wait_tmt(const ad9176_ctx_t *ctx)
{
    for (unsigned i = 0; i < 10000; ++i) {
        uint32_t s = ad9176_csr_read(ctx, SPI_MASTER_OFFSET + SPI_REG_STATUS);
        if (s & SPI_STATUS_TMT) {
            return AD9176_OK;
        }
        struct timespec ts = { 0, 1000 };   /* 1 us */
        nanosleep(&ts, NULL);
    }
    return AD9176_ERR_SPI_TIMEOUT;
}

static int spi_wait_trdy(const ad9176_ctx_t *ctx)
{
    for (unsigned i = 0; i < 10000; ++i) {
        uint32_t s = ad9176_csr_read(ctx, SPI_MASTER_OFFSET + SPI_REG_STATUS);
        if (s & SPI_STATUS_TRDY) {
            return AD9176_OK;
        }
        struct timespec ts = { 0, 1000 };
        nanosleep(&ts, NULL);
    }
    return AD9176_ERR_SPI_TIMEOUT;
}

/* One full-duplex 24-bit transaction. Returns the RX word on success or
 * 0xFFFFFFFF + sets errno on timeout. */
static int spi_xfer24(const ad9176_ctx_t *ctx, uint32_t tx24, uint32_t *rx24_out)
{
    /* Clear any sticky error bits from a prior transaction. */
    ad9176_csr_write(ctx, SPI_MASTER_OFFSET + SPI_REG_STATUS, 0);

    /* CS0 = AD9176. The Altera master holds CS low for the dataWidth-bit
     * frame; no need for SSO unless we want to chain frames. */
    ad9176_csr_write(ctx, SPI_MASTER_OFFSET + SPI_REG_SLAVESEL, SPI_SLAVESEL_AD9176);

    if (spi_wait_trdy(ctx) != AD9176_OK) {
        return AD9176_ERR_SPI_TIMEOUT;
    }
    ad9176_csr_write(ctx, SPI_MASTER_OFFSET + SPI_REG_TXDATA, tx24 & 0x00FFFFFFu);

    if (spi_wait_tmt(ctx) != AD9176_OK) {
        return AD9176_ERR_SPI_TIMEOUT;
    }

    /* rxdata is captured during the same shift; read once. */
    if (rx24_out) {
        *rx24_out = ad9176_csr_read(ctx, SPI_MASTER_OFFSET + SPI_REG_RXDATA) & 0x00FFFFFFu;
    } else {
        (void)ad9176_csr_read(ctx, SPI_MASTER_OFFSET + SPI_REG_RXDATA);
    }
    return AD9176_OK;
}

ad9176_ctx_t *ad9176_open(void)
{
    ad9176_ctx_t *ctx = calloc(1, sizeof(*ctx));
    if (!ctx) {
        return NULL;
    }

    ctx->mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (ctx->mem_fd < 0) {
        free(ctx);
        return NULL;
    }

    ctx->win_span = DAC_SUBSYS_SPAN;
    void *p = mmap(NULL, ctx->win_span, PROT_READ | PROT_WRITE,
                   MAP_SHARED, ctx->mem_fd, (off_t)DAC_SUBSYS_BASE);
    if (p == MAP_FAILED) {
        int saved = errno;
        close(ctx->mem_fd);
        free(ctx);
        errno = saved;
        return NULL;
    }
    ctx->win = (volatile uint8_t *)p;
    return ctx;
}

void ad9176_close(ad9176_ctx_t *ctx)
{
    if (!ctx) {
        return;
    }
    if (ctx->win) {
        munmap((void *)ctx->win, ctx->win_span);
    }
    if (ctx->mem_fd >= 0) {
        close(ctx->mem_fd);
    }
    free(ctx);
}

uint32_t ad9176_csr_read(const ad9176_ctx_t *ctx, uint32_t byte_offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(ctx->win + byte_offset);
    return *p;
}

void ad9176_csr_write(const ad9176_ctx_t *ctx, uint32_t byte_offset, uint32_t value)
{
    volatile uint32_t *p = (volatile uint32_t *)(ctx->win + byte_offset);
    *p = value;
}

int ad9176_reg_write(const ad9176_ctx_t *ctx, uint16_t reg_addr, uint8_t value)
{
    /* R/W=0, A14..A0, D7..D0. AD9176 ignores A15. */
    uint32_t tx = ((uint32_t)(reg_addr & 0x7FFFu) << 8) | (uint32_t)value;
    return spi_xfer24(ctx, tx, NULL);
}

int ad9176_reg_read(const ad9176_ctx_t *ctx, uint16_t reg_addr, uint8_t *value)
{
    uint32_t tx = (1u << 23) | ((uint32_t)(reg_addr & 0x7FFFu) << 8);
    uint32_t rx = 0;
    int rc = spi_xfer24(ctx, tx, &rx);
    if (rc != AD9176_OK) {
        return rc;
    }
    if (value) {
        *value = (uint8_t)(rx & 0xFFu);
    }
    return AD9176_OK;
}

int ad9176_wait_fmc_ready(const ad9176_ctx_t *ctx, unsigned timeout_us)
{
    unsigned waited = 0;
    while (waited < timeout_us) {
        uint32_t st = ad9176_csr_read(ctx, DAC_STATUS_PIO_OFFSET);
        if (st & (1u << DAC_STATUS_FMC_READY_BIT)) {
            return AD9176_OK;
        }
        struct timespec ts = { 0, 100 * 1000 };   /* 100 us */
        nanosleep(&ts, NULL);
        waited += 100;
    }
    return AD9176_ERR_NOT_READY;
}

void ad9176_set_spi_en(const ad9176_ctx_t *ctx, int on)
{
    ad9176_csr_write(ctx, SPI_EN_PIO_OFFSET, on ? 1u : 0u);
}

void ad9176_set_pe_ctrl(const ad9176_ctx_t *ctx, int on)
{
    ad9176_csr_write(ctx, PE_CTRL_PIO_OFFSET, on ? 1u : 0u);
}

void ad9176_set_tx_en(const ad9176_ctx_t *ctx, unsigned mask_2bit)
{
    ad9176_csr_write(ctx, TX_EN_PIO_OFFSET, mask_2bit & 0x3u);
}
