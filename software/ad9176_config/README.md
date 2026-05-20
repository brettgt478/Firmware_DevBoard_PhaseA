# ad9176-config

Linux user-space tool for the Phase B Agilex 5 dev kit + AD9176-FMC-EBZ
stack. Runs on the on-board HPS A55 cluster after Yocto boot.

## Architecture

The tool reaches the FPGA fabric through the **lwhps2fpga (LWS2F)**
bridge window, mmap'd from `/dev/mem` at physical base `0x0200_0000`,
span 16 KB. Inside the window are:

| Offset | Block | Purpose |
|--------|-------|---------|
| `0x0000` | `dac_controller_0` reg_bank | Phase A NCO / JESD sync CSRs |
| `0x1000` | `u_spi_master` | Avalon-MM SPI Master to AD9176 (24-bit, 25 MHz, mode 0) |
| `0x1100..0x1140` | PIOs | TX_EN / PE_CTRL / SPI_EN / DAC status |
| `0x2000` / `0x3000` | JESD link 0 / 1 | Intel JESD204B GTS Subsystem CSRs |

All offsets are captured in [`dac_subsys_regs.h`](dac_subsys_regs.h),
audited against [`reg_bank.vhd`](../../ip/dac_controller_0/src/reg_bank.vhd)
and the generated SPI Master `regmap` file
(see [doc/potential_issues.md ISSUE-007](../../doc/potential_issues.md)).

The AD9176's on-FMC SPI bus is reached **only** through the fabric SPI
master (CLAUDE.md §6 #9 -- HPS SPI peripherals don't reach the FMC
connector on this kit).

## Build

```sh
# Host syntax check (does not deploy)
make

# Cross build for the dev kit HPS (AArch64 Linux)
make CROSS=aarch64-linux-gnu-

# Clean
make clean
```

The host build runs on a Linux workstation as a sanity gate; the
resulting binary will fail at `/dev/mem` open unless executed on the
dev kit. There is no Windows native build path -- on Windows, build via
WSL or the Yocto SDK on a Linux build host.

## Use

```sh
# Read the headline status (FMC ready + JESD sync state)
sudo ad9176-config status

# Full Stage 7 bring-up: wait fmc_ready -> AD9176 init -> JESD link
# -> FPGA SineWaveGen 10 MHz tone
sudo ad9176-config bringup

# Re-tune the FPGA SineWaveGen without re-initialising the AD9176
sudo ad9176-config tone --freq 5000000

# Raw 32-bit CSR access (byte offsets inside the 16 KB window)
sudo ad9176-config peek 0x080            # REG_PIO_CTRL
sudo ad9176-config poke 0x080 0x1        # set bit 0
```

Root is required because `/dev/mem` access is privileged. If you'd
rather drop the root requirement later, the documented next step is a
`spidev` migration -- expose `u_spi_master` as `/dev/spidev0.0` via a
kernel driver and a device-tree binding. That's not in Stage 7 scope.

## Yocto

The recipe at
[`software/yocto_linux/meta-custom/recipes-apps/ad9176-config/ad9176-config_0.1.bb`](../yocto_linux/meta-custom/recipes-apps/ad9176-config/ad9176-config_0.1.bb)
packages the binary into the dev-kit image. The Yocto build itself is
not invoked from this stage; run it on the build host with:

```sh
cd software/yocto_linux
bitbake core-image-minimal-dev
```

## Reference

[`reference/`](reference/) holds the Phase A bare-metal driver
(`ad9176_init.c`, `ad9176_fmc_ebz.h`, `iq_router_regs.h`). The
register-write *sequence* is reused verbatim in the Phase B init
code; the *transport* (memory map, SPI access) is entirely new because
Phase B replaced the merged `iq_router` SPI window with a discrete
Altera Avalon-MM SPI Master.
