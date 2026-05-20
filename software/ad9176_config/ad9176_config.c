/*
 * ad9176-config -- Linux user-space tool for the Phase B Agilex 5 / AD9176
 * stack. Runs on the on-board HPS (or any system with /dev/mem reaching
 * the LWS2F window).
 *
 * Commands:
 *   ad9176-config status
 *       Read the dac_status PIO + JESD sync status; print summary.
 *   ad9176-config bringup [--freq HZ] [--fs HZ]
 *       Full Stage 7 sequence: fmc_ready -> SPI EN -> AD9176 init ->
 *       JESD link release -> sine tone.
 *   ad9176-config tone --freq HZ [--fs HZ]
 *       Re-tune the FPGA SineWaveGen (no AD9176 reset).
 *   ad9176-config peek OFFSET
 *   ad9176-config poke OFFSET VALUE
 *       Raw 32-bit CSR access into the 16 KB dac_subsys window.
 *
 * Defaults: --fs=625000000 (per-converter sample rate at JESD mode 4,
 * 12.5 Gbps lane rate, M=4 / L=4 / NP=16); --freq=10000000 (10 MHz tone).
 */

#define _POSIX_C_SOURCE 200809L

#include "ad9176_fmc_ebz.h"
#include "ad9176_init.h"
#include "dac_subsys_regs.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_FS_HZ    625000000u
#define DEFAULT_TONE_HZ   10000000u

static void usage(FILE *out)
{
    fprintf(out,
        "usage: ad9176-config <command> [options]\n"
        "  status\n"
        "  bringup [--freq HZ] [--fs HZ]\n"
        "  tone --freq HZ [--fs HZ]\n"
        "  peek <byte-offset-hex>\n"
        "  poke <byte-offset-hex> <value-hex>\n"
        "defaults: --fs=%u, --freq=%u\n",
        DEFAULT_FS_HZ, DEFAULT_TONE_HZ);
}

static int cmd_status(ad9176_ctx_t *ctx)
{
    uint32_t pio    = ad9176_csr_read(ctx, DAC_STATUS_PIO_OFFSET);
    uint32_t sync_s = ad9176_csr_read(ctx, DAC_CTRL_OFFSET + REG_JESD_SYNC_STATUS);
    uint32_t sync_e = ad9176_csr_read(ctx, DAC_CTRL_OFFSET + REG_JESD_SYNC_ERR);
    uint32_t sine_c = ad9176_csr_read(ctx, DAC_CTRL_OFFSET + REG_SINE_CTRL);

    printf("dac_status_pio   = 0x%08X  prsnt_n=%u pg_c2m_lb=%u fmc_ready=%u\n",
           pio,
           (pio >> DAC_STATUS_PRSNT_N_BIT) & 1u,
           (pio >> DAC_STATUS_PG_C2M_LOOPBACK_BIT) & 1u,
           (pio >> DAC_STATUS_FMC_READY_BIT) & 1u);
    printf("jesd_sync_status = 0x%08X  txlink=0x%X grp=0x%X lmfc=%u\n",
           sync_s,
           sync_s & SYNC_STATUS_TXLINK_READY_MASK,
           (sync_s & SYNC_STATUS_GROUP_SYNCED_MASK) >> SYNC_STATUS_GROUP_SYNCED_SHIFT,
           (sync_s >> SYNC_STATUS_LMFC_ALIGNED_BIT) & 1u);
    printf("jesd_sync_err    = 0x%08X\n", sync_e);
    printf("sine_ctrl        = 0x%08X  enable=%u conv_en=0x%X\n",
           sine_c,
           sine_c & 1u,
           (sine_c & SINE_CTRL_CONV_ENABLE_MASK) >> SINE_CTRL_CONV_ENABLE_SHIFT);
    return 0;
}

static int parse_u32(const char *s, uint32_t *out)
{
    char *end = NULL;
    unsigned long v = strtoul(s, &end, 0);
    if (!end || *end != '\0') {
        return -1;
    }
    *out = (uint32_t)v;
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        usage(stderr);
        return 1;
    }
    const char *cmd = argv[1];

    if (strcmp(cmd, "-h") == 0 || strcmp(cmd, "--help") == 0) {
        usage(stdout);
        return 0;
    }

    ad9176_ctx_t *ctx = ad9176_open();
    if (!ctx) {
        fprintf(stderr, "ad9176_open: %s\n", strerror(errno));
        fprintf(stderr, "  (need root or CAP_SYS_RAWIO; check /dev/mem)\n");
        return 1;
    }

    int rc = 0;

    if (strcmp(cmd, "status") == 0) {
        rc = cmd_status(ctx);
    } else if (strcmp(cmd, "bringup") == 0) {
        uint32_t fs   = DEFAULT_FS_HZ;
        uint32_t tone = DEFAULT_TONE_HZ;
        for (int i = 2; i + 1 < argc; i += 2) {
            if (strcmp(argv[i], "--freq") == 0) {
                if (parse_u32(argv[i + 1], &tone) != 0) { usage(stderr); rc = 1; goto done; }
            } else if (strcmp(argv[i], "--fs") == 0) {
                if (parse_u32(argv[i + 1], &fs) != 0) { usage(stderr); rc = 1; goto done; }
            } else {
                usage(stderr); rc = 1; goto done;
            }
        }
        rc = ad9176_bringup_full(ctx, tone, fs);
    } else if (strcmp(cmd, "tone") == 0) {
        uint32_t fs   = DEFAULT_FS_HZ;
        uint32_t tone = DEFAULT_TONE_HZ;
        for (int i = 2; i + 1 < argc; i += 2) {
            if (strcmp(argv[i], "--freq") == 0) {
                if (parse_u32(argv[i + 1], &tone) != 0) { usage(stderr); rc = 1; goto done; }
            } else if (strcmp(argv[i], "--fs") == 0) {
                if (parse_u32(argv[i + 1], &fs) != 0) { usage(stderr); rc = 1; goto done; }
            } else {
                usage(stderr); rc = 1; goto done;
            }
        }
        rc = dac_subsys_set_nco_tone(ctx, tone, fs);
    } else if (strcmp(cmd, "peek") == 0 && argc == 3) {
        uint32_t off;
        if (parse_u32(argv[2], &off) != 0 || off >= DAC_SUBSYS_SPAN) {
            usage(stderr); rc = 1;
        } else {
            printf("0x%08X: 0x%08X\n", off, ad9176_csr_read(ctx, off));
        }
    } else if (strcmp(cmd, "poke") == 0 && argc == 4) {
        uint32_t off, val;
        if (parse_u32(argv[2], &off) != 0 || off >= DAC_SUBSYS_SPAN ||
            parse_u32(argv[3], &val) != 0) {
            usage(stderr); rc = 1;
        } else {
            ad9176_csr_write(ctx, off, val);
            printf("0x%08X <- 0x%08X\n", off, val);
        }
    } else {
        usage(stderr);
        rc = 1;
    }

done:
    ad9176_close(ctx);
    return rc;
}
