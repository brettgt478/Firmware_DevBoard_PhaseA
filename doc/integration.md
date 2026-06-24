# Hardware Integration Test Procedures

Procedures for tests that **cannot be run on the development workstation**
because they require physical hardware (DK-A5E065BB32AES1 Agilex 5 dev kit
+ AD9176-FMC-EBZ mezzanine + scope / Linux console), or that require a
human in front of the Platform Designer GUI.

The companion ledger [deferred_hw_gates.md](deferred_hw_gates.md) tracks
*which* PLAN verify steps are deferred for each stage. This file documents
*how* to run them when hardware becomes available.

**Update rule:** every stage's closeout adds (or updates) a section here
when it introduces new gates that require hardware or GUI verification.
Per [CLAUDE.md §7](../CLAUDE.md#7-verification-entry-points).

---

## Hardware bring-up prerequisites (run once)

Before running ANY stage's hardware procedure, the following must be true:

| Item | Required state | How to verify |
|------|---------------|---------------|
| FMC VADJ | **1.2 V** (NOT the dev-kit 2.5 V default) | Multimeter at VADJ test point, or kit GUI |
| AD9176-FMC-EBZ | Seated in J34 with both screws | Visual |
| AD9176 subclass-1 strap | Set per AD9176-FMC-EBZ user guide | Inspect board |
| USB-Blaster / FTDI cable | Connected to J5 (USB-JTAG) | `jtagconfig` lists the device |
| UART console | 115200 8N1 on /dev/ttyUSB0 (or COMx) | `screen` / `picocom` opens |
| SD card slot | Empty (load over JTAG) or holds Yocto image | per stage |
| Lab power | 12 V brick → J37 barrel jack | LED D2 (PWR_OK) on |

**Driving 1.2-V LVCMOS into a wrongly-set VADJ FMC carrier destroys the
HSIO 3B bank, the FMC mezzanine, and/or the AD9176 board.** This is
[CLAUDE.md §6 Critical Constraint #3](../CLAUDE.md#6-critical-constraints).
Confirm VADJ before any image touches the FMC.

---

## Deployable boot image — integrating the bootloader (READ FIRST if Linux won't boot)

This section explains how to turn the `build.tcl` FPGA bitstream into an
image the board can actually **boot Linux** from, and why the bare `.sof`
cannot. It is a prerequisite for every procedure below that boots Linux or
runs `ad9176-config` (Procedures 1.A, 5.A, 7.A).

> **TL;DR — the current model is fabric-only.** Phase B is now a **fabric-only**
> delta on the production GHRD ([CLAUDE.md §6 #10–#12](../CLAUDE.md#6-critical-constraints)),
> so the HPS bootloader in QSPI is the **stock production image and is left
> untouched**. You deploy by regenerating only `ghrd.core.rbf` and repacking it
> into `kernel.itb` — **[Procedure D.E](#procedure-de--deploy-fabric-only-via-kernelitb-repack-primary)**.
> You do **not** rebuild or reflash the QSPI `.jic`.
>
> The QSPI re-merge flow (Procedures D.A–D.C, which merge a Yocto-built FSBL
> into the bitstream with `quartus_pfg -o hps_path=…`) is now a **fallback** —
> only for first-time QSPI provisioning, or if the HPS is ever deliberately
> changed (which #11 forbids by default). Background on the boot chain and why a
> bare `.sof` can't boot on its own: D.0 below.

### D.0 — Why a bare `.sof` never boots Linux on this kit

This design is **HPS-first** (`HPS_INITIALIZATION "HPS FIRST"`,
`QSPI_OWNERSHIP HPS` in
[agilex5_devkit.qsf](../projects/agilex5_devkit/agilex5_devkit.qsf)). On
Agilex 5 the boot chain is:

```
Power-on
  │
  ▼
SDM (Secure Device Manager) ── boot device = QSPI flash (active-serial x4 / ASX4)
  │   • configures HPS EMIF I/O + HPS pins from the bitstream handoff
  │   • copies the FSBL *code* + the HW *handoff* binary into HPS on-chip RAM
  ▼
FSBL = U-Boot SPL (u-boot-spl-dtb.hex)  ── brings up DDR4, then loads ↓
  ▼
BL31 = Arm Trusted Firmware (bl31.bin)
  ▼
SSBL = U-Boot proper (u-boot.itb)       ── SSBL_BOOT_SOURCE=mmc0 → loads ↓ from SD
  │   • load mmc 0:1 … ghrd.core.rbf ; fpga load 0 …   (configures FPGA fabric)
  │   • bridge enable ; boot kernel
  ▼
Linux (Image / kernel.itb) + rootfs (SD)
```

Two facts make the bare `.sof` a dead end:

1. **The FSBL is *software*, not in the bitstream.** `build.tcl` runs
   `quartus_asm` and stops at `output_files/agilex5_devkit.sof`. That `.sof`
   carries the FPGA fabric **and the HPS hardware handoff**, but it does
   **not** contain the U-Boot SPL. The SPL is built by Yocto and must be
   *merged into* the bitstream with `quartus_pfg -o hps_path=u-boot-spl-dtb.hex`.
   Without that merge the SDM has no FSBL to copy into OCRAM → the HPS never
   executes a boot instruction → no U-Boot banner, no Linux. The FPGA fabric
   still configures, so the heartbeat LED can blink — which is misleading.

2. **The HPS handoff lives in the bitstream — so don't change the HPS.** For
   Agilex 5 the entire HPS handoff (EMIF timing, pin mux, clocks, HPS↔FPGA
   bridge widths) is baked into the configuration bitstream by Quartus —
   there is no separate handoff folder and no `bsp-editor` step. Phase B's
   Stage 1 retarget of the EMIF to DDR4-1600/800 MHz (ES silicon) changed the
   handoff and broke the prebuilt bootloader. **That retarget has been reverted**
   ([ISSUE-011](potential_issues.md)): Phase B is now **fabric-only** on the
   production baseline (device `A5ED065BB32AE4S`, DDR4-3200), so the bitstream's
   HPS handoff is **identical** to the production GHRD the prebuilt bootloader
   expects. The HPS/QSPI image is therefore reused unchanged.

**Why the fabric-only model fixes the symptom:** with the HPS byte-stable, the
SDM+FSBL+handoff in QSPI matches the bitstream, so the prebuilt boot chain runs
exactly as it does for the stock baseline. You change **only** the fabric and
deliver it via `kernel.itb` ([Procedure D.E](#procedure-de--deploy-fabric-only-via-kernelitb-repack-primary)) —
no QSPI reflash, no FSBL re-merge. Fact #1 still applies if you ever provision
QSPI from scratch (the bare `.sof` then needs the FSBL merged — Procedures
D.A–D.C), but that is the exception, not the deploy path.

### D.0.1 — The artifacts and where they live (this kit: QSPI `.jic` + rootfs on SD)

| Artifact | Made by | Carries | Lives on |
|----------|---------|---------|----------|
| `qspi_helper.hps.jic` (+ `.rpd`) | `quartus_pfg` + [qspi_helper.pfg](../projects/agilex5_devkit/software/yocto_linux/scripts/qspi_helper.pfg) | SDM firmware + **this design's bitstream/handoff** + **FSBL** + U-Boot proper | **QSPI flash** |
| `ghrd.core.rbf` | `quartus_pfg … -o hps_core_only=ON` | FPGA **fabric only** (DAC subsys, JESD, FMC) | **SD FAT** — U-Boot `fpga load`s it |
| `Image` / `kernel.itb`, `*.dtb` | Yocto | Linux kernel + device tree | **SD FAT** |
| rootfs (`.wic` / ext4) | Yocto | Root filesystem (+ `ad9176-config`) | **SD ext4** |

In this kit's mode the QSPI image is the **U-Boot-only** `qspi_helper`
variant (SDM + bitstream + FSBL + U-Boot proper). U-Boot then loads the
fabric `ghrd.core.rbf`, the kernel and the rootfs from the SD card. (The
full-QSPI alternative — kernel+rootfs in a QSPI UBI image via
[qspi_boot.pfg](../projects/agilex5_devkit/software/yocto_linux/scripts/qspi_boot.pfg)
— is *not* this kit's configuration and is left to the
`software-yocto_linux_qspi` make target.)

### Procedure D.A — Fast recovery (re-merge FSBL, rebuild QSPI image, reflash)

Use this when Linux stopped booting after a bitstream swap and you already
have a known-good set of Yocto boot binaries (from the baseline build or a
prior run). For Agilex 5 the FSBL / U-Boot are **design-independent** (the
handoff is in the bitstream), so you can **reuse the existing
`u-boot-spl-dtb.hex` and `u-boot.itb`** and only re-merge them with the new
bitstream — no Yocto rebuild required.

**Host:** any machine with Quartus Prime Pro 26.1 (`quartus_pfg`,
`quartus_pgm`) on PATH — **Windows is fine here**, no Yocto needed.

**Inputs (gather into one working directory):**

- `agilex5_devkit.sof` — from `quartus_sh -t build.tcl` (full JESD license →
  a real `.sof`, not `_time_limited.sof`; see [ISSUE-016](potential_issues.md))
- `u-boot-spl-dtb.hex`, `u-boot.itb` — from the Yocto deploy dir
  (`build/tmp/deploy/images/agilex5e/`); reuse the baseline set or build via
  [Procedure D.B](#procedure-db--full-deployable-build-yocto-bsp--image)
- `qspi_helper.pfg`, `uboot_bin.sh` — from
  [software/yocto_linux/scripts/](../projects/agilex5_devkit/software/yocto_linux/scripts/)

**Steps:**

1. Build (or locate) this design's `.sof`, then stage it under the name the
   pfg expects:
   ```bash
   cd projects/agilex5_devkit
   quartus_sh -t build.tcl                 # → output_files/agilex5_devkit.sof
   cp output_files/agilex5_devkit.sof ghrd.sof
   ```
2. Merge the FSBL + U-Boot into a QSPI image built around **this** `.sof`:
   ```bash
   ./uboot_bin.sh                          # u-boot.itb → padded u-boot.bin
   quartus_pfg -c qspi_helper.pfg          # → qspi_helper.hps.jic (+ .rpd, .map)
   ```
   The pfg embeds the FSBL via `hps_path=u-boot-spl-dtb.hex`. Equivalent
   explicit form (no pfg):
   ```bash
   quartus_pfg -c ghrd.sof qspi_helper.jic \
     -o device=MT25QU02G \
     -o flash_loader=A5ED065BB32AE4S \
     -o hps_path=u-boot-spl-dtb.hex \
     -o mode=ASX4 -o hps=1
   ```
   (`flash_loader=A5ED065BB32AE4S` is the production part — it must match the
   qsf `DEVICE`; see the device-ID gotcha in [D.3](#d3--gotchas).)
3. Regenerate the **fabric** RBF for the SD card so it matches the new design:
   ```bash
   quartus_pfg -c output_files/agilex5_devkit.sof ghrd.core.rbf \
     -o hps=ON -o hps_core_only=ON
   ```
4. Program QSPI over JTAG:
   ```bash
   # Set the kit MSEL dipswitch to JTAG mode, power on, then:
   jtagconfig --setparam 1 JtagClock 16M
   quartus_pgm -c 1 -m jtag -o "pvi;qspi_helper.hps.jic"
   ```
5. Copy `ghrd.core.rbf` onto the SD FAT partition (replace the stale one),
   then set MSEL back to **ASX4 (QSPI active-serial)** boot and power-cycle.

**Pass criterion:** UART (115200 8N1 on J6) shows SDM → SPL → ATF → U-Boot
banners, then the kernel boots to `… login:`. After login,
`ad9176-config status` runs (Procedure 7.A).

### Procedure D.B — Full deployable build (Yocto BSP + image)

The canonical, reproducible flow the repo's Makefile drives. Needed when you
have no prebuilt boot binaries, or you changed U-Boot/SPL/ATF/kernel/rootfs.

**Host:** a **Linux** Yocto build host (Ubuntu 22.04+, `/bin/sh` → bash) —
**not** the Windows firmware workstation. Host packages + kas setup are in
[software/yocto_linux/README.md](../projects/agilex5_devkit/software/yocto_linux/README.md).

1. Build the FPGA `.sof` (`quartus_sh -t build.tcl`).
2. Stage the fabric RBF that Yocto folds into `kernel.itb` (the recipe wants
   the name in `kas.yml`'s `FPGA_RBF_FILE`):
   ```bash
   quartus_pfg -c output_files/agilex5_devkit.sof output_files/ghrd.core.rbf \
     -o hps=ON -o hps_core_only=ON
   cp output_files/ghrd.core.rbf \
     software/yocto_linux/meta-custom/recipes-fpga/fpga-bitstream/files/baseline_a55_hps_debug.core.rbf
   ```
3. Build the BSP + image (FSBL/SPL, ATF, U-Boot, kernel, rootfs):
   ```bash
   cd software/yocto_linux && kas build kas.yml
   ```
   Outputs land in `build/tmp/deploy/images/agilex5e/` — including
   `u-boot-spl-dtb.hex`, `u-boot.itb`, `Image`, `kernel.itb`, and the rootfs
   `gsrd-console-image-agilex5e.rootfs.wic`.
4. **Or** let the GHRD Makefile orchestrate build + bootloader merge +
   image postprocess in one shot (this kit's target):
   ```bash
   make software-yocto_linux_sd-install-sw     # (or: make install-sw  for all media)
   ```
   This runs the
   [swbuild_config.mk](../projects/agilex5_devkit/swbuild_config.mk)
   `software-yocto_linux_sd` chain: builds Yocto, then `sd-postprocess` runs
   `uboot_bin.sh`, `quartus_pfg -c qspi_helper.pfg`, and the
   `… -o hps_path=… ghrd.jic` merge — producing `qspi_helper.hps.jic`,
   `ghrd.core.rbf`, `ghrd.hps.rbf`, and `agilex5_devkit_yocto_linux_sd.sof`
   under `install/binaries/software/yocto_linux_sd/`.
5. Program QSPI (Procedure D.A step 4) and prepare the SD card
   ([Procedure D.C](#procedure-dc--prepare--refresh-the-sd-card)).

### Procedure D.C — Prepare / refresh the SD card

The SD card holds the kernel, device tree, the fabric `ghrd.core.rbf`, and
the rootfs. Two options:

- **Whole-disk WIC (clean install):**
  ```bash
  sudo dd if=gsrd-console-image-agilex5e.rootfs.wic of=/dev/sdX bs=1M && sync
  ```
  Overwrites the entire card (FAT boot partition + ext4 rootfs).
- **In-place file copy (incremental):** mount the FAT partition and replace
  only what changed — `ghrd.core.rbf`, `Image`/`kernel.itb`, `*.dtb`,
  `u-boot.scr` — leaving the rootfs untouched. Use this when only the fabric
  changed.

### Procedure D.F — One-time migration to the production part (Phase 1–3)

> Run this **once** to convert the tree from the (reverted) ES retarget to the
> production fabric-only baseline. After it passes, steady-state deploys use
> Procedure D.E. **This is a build-machine procedure (Quartus 26.1):** the HPS
> revert is a coupled IP + qsys + pin change that *must* be validated by a
> Quartus regen — applying it half-way leaves the build broken, so do the whole
> phase and honor the gates. The doc edits are already done; the source/IP edits
> below are the remaining work.
>
> **What's already done in-repo (this change):** all Phase 4 docs;
> `swbuild_config.mk` flash device → `MT25QU02G`. The `qspi_*.pfg` already use
> `flash_loader=A5ED065BB32AE4S`.

**Phase 1 — Restore the production HPS / EMIF (undo [ISSUE-011](potential_issues.md)).**

Source of truth: the on-disk production GHRD
`D:/agilex5e-ed-gsrd-main/a5ed065b-premium-devkit-oobe/baseline-a55/` (verified
present: `hps_subsys.qsys`, `baseline_a55.qsf`, `ip/hps_subsys/emif_io96b_hps.ip`,
`ip/hps_subsys/agilex_hps.ip`).

1. Copy the production HPS + EMIF IP and the HPS subsystem wholesale into the
   repo (overwrites the ES variants):
   ```bash
   GHRD=/d/agilex5e-ed-gsrd-main/a5ed065b-premium-devkit-oobe/baseline-a55
   PRJ=projects/agilex5_devkit
   cp "$GHRD/ip/hps_subsys/emif_io96b_hps.ip" "$PRJ/ip/hps_subsys/"
   cp "$GHRD/ip/hps_subsys/agilex_hps.ip"     "$PRJ/ip/hps_subsys/"
   cp "$GHRD/hps_subsys.qsys"                  "$PRJ/hps_subsys.qsys"
   ```
2. `agilex5_devkit.qsf`: set the device and restore the 5 DBI pins.
   - `set_global_assignment -name DEVICE A5ED065BB32AE6SR0` → `… A5ED065BB32AE4S`.
   - Re-add these 10 lines (verbatim from `$GHRD/baseline_a55.qsf:422-431`),
     in the EMIF section near the other `emif_hps_emif_mem_0_*` assignments:
     ```tcl
     set_location_assignment PIN_B119 -to emif_hps_emif_mem_0_mem_dbi_n[0]
     set_instance_assignment -name IO_STANDARD "1.2-V POD" -to emif_hps_emif_mem_0_mem_dbi_n[0]
     set_location_assignment PIN_AC90 -to emif_hps_emif_mem_0_mem_dbi_n[1]
     set_instance_assignment -name IO_STANDARD "1.2-V POD" -to emif_hps_emif_mem_0_mem_dbi_n[1]
     set_location_assignment PIN_V87 -to emif_hps_emif_mem_0_mem_dbi_n[2]
     set_instance_assignment -name IO_STANDARD "1.2-V POD" -to emif_hps_emif_mem_0_mem_dbi_n[2]
     set_location_assignment PIN_H87 -to emif_hps_emif_mem_0_mem_dbi_n[3]
     set_instance_assignment -name IO_STANDARD "1.2-V POD" -to emif_hps_emif_mem_0_mem_dbi_n[3]
     set_location_assignment PIN_B97 -to emif_hps_emif_mem_0_mem_dbi_n[4]
     set_instance_assignment -name IO_STANDARD "1.2-V POD" -to emif_hps_emif_mem_0_mem_dbi_n[4]
     ```
   - Also delete the ISSUE-011 comment block in the qsf that says these pins are
     "now unbonded". Then grep the qsf and all `ip/**/*.ip` for `AE6SR0` — there
     must be **none** left.
3. `agilex5_devkit.sv`: restore the DBI port + connection ISSUE-011 removed
   (verbatim from `$GHRD/baseline_a55.sv:34` and `:210`):
   - top-level port — add alongside the other `emif_hps_emif_mem_0_*` ports:
     ```systemverilog
     inout  wire [  4:0] emif_hps_emif_mem_0_mem_dbi_n,
     ```
   - `u_baseline_top` instance hookup — add after the
     `.emif_hps_emif_ref_clk_0_clk (…)` line:
     ```systemverilog
     .emif_hps_emif_mem_0_mem_dbi_n        (emif_hps_emif_mem_0_mem_dbi_n),
     ```
4. `baseline_top.upstream.qsys` (the frozen snapshot build.tcl regenerates from):
   re-add the single DBI `<port>` block ISSUE-011 removed, into the
   `interface`/`ports` list of the top module (next to the other
   `emif_hps_emif_mem_0_*` ports). In the `.qsys` the port list is stored
   **HTML-escaped**, exactly as in `$GHRD/baseline_top.qsys:7126-7134`:
   ```xml
                       &lt;port&gt;
                           &lt;name&gt;emif_hps_emif_mem_0_mem_dbi_n&lt;/name&gt;
                           &lt;role&gt;mem_dbi_n&lt;/role&gt;
                           &lt;direction&gt;Bidir&lt;/direction&gt;
                           &lt;width&gt;5&lt;/width&gt;
                           &lt;lowerBound&gt;0&lt;/lowerBound&gt;
                           &lt;vhdlType&gt;STD_LOGIC_VECTOR&lt;/vhdlType&gt;
                           &lt;terminationValue&gt;0&lt;/terminationValue&gt;
                       &lt;/port&gt;
   ```
   (Unescaped, that is a `<port>` with `<name>emif_hps_emif_mem_0_mem_dbi_n</name>`,
   `<role>mem_dbi_n</role>`, `<direction>Bidir</direction>`, `<width>5</width>`.)
   The Phase B fabric patches (`baseline_top_phaseb_patches.tcl`) re-apply on top
   automatically. **Simplest alternative:** since `hps_subsys.qsys` and the top
   are inherited unchanged from the baseline, you may instead re-snapshot
   `baseline_top.upstream.qsys` directly from `$GHRD/baseline_top.qsys` and let
   the patch script reapply the Phase B fabric edits.
5. Regenerate + compile, then **gate on the handoff**:
   ```bash
   cd projects/agilex5_devkit
   quartus_sh -t build.tcl --project-only      # qsys/IP regen must be clean
   quartus_sh -t build.tcl                      # full compile → .sof
   quartus_pfg -c output_files/agilex5_devkit.sof ghrd.hps.rbf \
     -o hps=ON -o hps_path=<prebuilt>/u-boot-spl-dtb.hex
   ```
   **Gate (critical):** the resulting `ghrd.hps.rbf` must match the production
   baseline's HPS image (same EMIF/pin-mux/clock handoff — ideally byte-identical
   bar timestamps). If it differs, an HPS delta remains; find it before going on.
   A clean handoff is what lets the **stock** prebuilt bootloader boot unchanged.

**Phase 2 — Regenerate fabric IP for the production part.**

Changing the device means the JESD204B GTS, `xcvr_refclk`, and transceiver
primitives must be regenerated for `A5ED065BB32AE4S` ([CLAUDE.md §6 #10](../CLAUDE.md#6-critical-constraints)).
`quartus_ipgenerate` (run by `build.tcl`) regenerates from the `.ip`/`.qsys` for
the current device; if any IP reports a device/stepping mismatch, force an
upgrade:
```bash
# from projects/agilex5_devkit (uses the Makefile ip-upgrade target on a build host):
make agilex5_devkit-ip-upgrade        # or: quartus_sh --ip_upgrade agilex5_devkit -revision agilex5_devkit -mode all
quartus_sh -t build.tcl               # rebuild
```
**Gate:** full compile clean; fit WNS ≥ 0.5 ns; ALM/M20K/DSP/GTS within budget;
no wrong-stepping primitive warnings.

**Phase 3 — Deploy fabric-only.** Proceed to
[Procedure D.E](#procedure-de--deploy-fabric-only-via-kernelitb-repack-primary):
emit `ghrd.core.rbf`, repack `kernel.itb`, copy to SD, boot. The QSPI image and
bootloader stay the stock production ones — untouched.

**Rollback:** the ES analysis and the exact removed blocks are in
[ISSUE-011](potential_issues.md); `git checkout` the pre-migration commit to
restore the ES state.

---

### Procedure D.E — Deploy fabric-only via `kernel.itb` repack (PRIMARY)

**Goal:** ship a new FPGA fabric to a board that already boots the stock
production GHRD, without touching the HPS, QSPI, or the bootloader. This is the
default Phase B deploy path (CLAUDE.md §6 #12).

**Preconditions:**

- The board already boots Linux from the **stock production** image (QSPI
  `.jic` + SD). If it does not yet, provision QSPI once via Procedure D.A/D.B.
- Your design is fabric-only (CLAUDE.md §6 #11): HPS untouched, device
  `A5ED065BB32AE4S`, EMIF DDR4-3200. **Verify** the generated `ghrd.hps.rbf` is
  byte-identical to the production baseline's before trusting this path — if it
  differs, you changed the HPS and must fall back to the QSPI flow.

**Host:** Quartus on PATH (Windows OK) for the RBF; a Linux/WSL2 shell with
`u-boot-tools` (`mkimage`/`dumpimage`) for the repack.

**Steps:**

1. Build the bitstream and emit the **core-only** RBF (fabric, no HPS):
   ```bash
   cd projects/agilex5_devkit
   quartus_sh -t build.tcl                                   # → output_files/agilex5_devkit.sof
   quartus_pfg -c output_files/agilex5_devkit.sof output_files/agilex5_devkit.core.rbf \
     -o hps=ON -o hps_core_only=ON
   ```
2. Repack the new core RBF into `kernel.itb` (WSL2 / Linux; no Yocto rebuild):
   ```bash
   cp kernel.itb kernel.itb.bak       # always back up first
   dumpimage -l kernel.itb            # inspect FIT nodes/configs; note the fpga node + Image/dtb
   # extract Image + dtb(s); author kernel.its referencing agilex5_devkit.core.rbf
   mkimage -f kernel.its kernel.itb   # → new kernel.itb embedding the new RBF
   ```
   The Yocto image sets `FPGA_ENABLE_CORE_PGM=1`, so `bootm` programs this
   embedded RBF during boot.
3. Copy the new `kernel.itb` to the SD card **FAT** partition (replace the
   existing one). Leave QSPI and the rootfs untouched.
4. Power-cycle. UART shows the stock boot chain (SDM → SPL → ATF → U-Boot →
   kernel); during `bootm` the fabric is programmed from the embedded RBF.

**Pass criterion:** Linux reaches `login:` exactly as the stock baseline, and
`devmem` reads the DAC subsystem ID register (Procedure 4.A / 7.A), proving the
*new* fabric is live.

**Notes / pitfalls:**

- **Only one thing should program the fabric.** With `FPGA_ENABLE_CORE_PGM=1`
  the `kernel.itb` RBF wins at `bootm`; a separate `fpga load` in the U-Boot env
  or a runtime DT overlay can be silently overwritten ([DESIGN_DECISION.md](../DESIGN_DECISION.md) D4).
  To use a standalone `core.rbf` on the FAT loaded by `fpga load` instead,
  disable `FPGA_ENABLE_CORE_PGM`.
- If the new fabric needs a Linux device-tree change (new bridge node /
  address), update the kernel DTB in the same `kernel.itb` repack.
- The DAC CSR base may move when rebased on the production GHRD's bridge window;
  keep [dac_subsys_regs.h](../software/ad9176_config/dac_subsys_regs.h) and the
  Linux DT offsets in sync ([CLAUDE.md §6 #6](../CLAUDE.md#6-critical-constraints)).

---

### D.2 — When must I rebuild each artifact? (change matrix)

| If you changed… | QSPI `.jic` (HPS) | `core.rbf` in `kernel.itb` | SD kernel/rootfs |
|-----------------|:-----------------:|:--------------------------:|:----------------:|
| FPGA fabric only (DAC subsys, JESD, FMC pins) — the normal case | **no** (byte-stable) | **yes** (Procedure D.E) | no |
| HPS / EMIF / pinmux / bridges — **forbidden by [§6 #11](../CLAUDE.md#6-critical-constraints)** | **yes** + rebuild bootloader | yes | maybe (DT) |
| U-Boot / SPL / ATF | **yes** | no | no |
| Linux kernel / DT / rootfs / `ad9176-config` | no | no (or DT inside the itb) | **yes** |

The whole point of the fabric-only model: a normal change touches **only** the
`core.rbf` embedded in `kernel.itb`. The QSPI `.jic` (HPS + bootloader) is the
stock production image and is reprogrammed **only** for first-time provisioning
or a (discouraged) HPS change.

### D.3 — Gotchas

- **Device-ID consistency
  ([CLAUDE.md §6 #10](../CLAUDE.md#6-critical-constraints)).** Now that Phase B
  targets the production part, **every** device-targeting field must read
  `A5ED065BB32AE4S`: the qsf `DEVICE`, all IP `.ip` device fields, and the
  `flash_loader` in `qspi_helper.pfg` / `qspi_boot.pfg` /
  [swbuild_config.mk](../projects/agilex5_devkit/swbuild_config.mk). The
  checked-in pfgs already use `flash_loader=A5ED065BB32AE4S` — they were *ahead*
  of the qsf, which the Phase 1 migration brings in line by reverting the qsf
  from the ES `A5ED065BB32AE6SR0` back to `A5ED065BB32AE4S`. Mixing the two
  (production loader against an ES bitstream, or vice-versa) produces a
  wrong-stepping SDM/config image that silently fails to boot. Confirm the QSPI
  part against the DK-A5E065BB32AES1 user guide before trusting `MT25QU02G`
  (note `swbuild_config.mk`'s U-Boot-only path passes `device=MT25QU128` — fix
  it to `MT25QU02G` unless your board truly has the smaller part).
- **MSEL.** Programming the `.jic` over JTAG needs the kit in JTAG mode;
  booting needs **ASX4** (active-serial x4 / QSPI). The exact dipswitch
  pattern is specific to the DK-A5E065BB32AES1 — read it off the board's user
  guide; do not copy another kit's pattern.
- **IP license (confirmed full).** `build.tcl` emits a real
  `output_files/agilex5_devkit.sof`, deployable permanently. If a workstation
  ever lacks the JESD204B GTS license it emits `…_time_limited.sof`, which
  still boots but halts the design ~1 h after configuration
  ([ISSUE-016](potential_issues.md)) — never ship it.
- **VADJ first.** Independent of boot, never let an image drive the FMC HSIO
  bank before VADJ = 1.2 V
  ([CLAUDE.md §6 #3](../CLAUDE.md#6-critical-constraints)).

### D.4 — Failure paths

- **No SDM / U-Boot output on UART at all** → FSBL not in the QSPI image.
  Re-check that `quartus_pfg` ran with `hps_path=u-boot-spl-dtb.hex` and that
  you flashed the resulting `.jic`/`.rpd`, **not** the bare `.sof`. Confirm
  MSEL = ASX4.
- **U-Boot SPL starts but `DDR:` / EMIF calibration hangs** → handoff
  mismatch: the bitstream's HPS handoff doesn't match the prebuilt SPL. In the
  fabric-only model this means the HPS was inadvertently changed (e.g. an EMIF
  edit) — confirm `ghrd.hps.rbf` is byte-identical to the production baseline
  and that the device is `A5ED065BB32AE4S` (DDR4-3200), not the reverted ES
  config. See [Procedure 1.B](#procedure-1b--emif-ddr4-3200-calibration-check).
- **U-Boot runs but `fpga load` / `bridge enable` fails, or kernel hangs
  probing the FPGA** → the `core.rbf` on SD does not match the handoff in
  QSPI. Regenerate `core.rbf` from the **same** `.sof` you built the `.jic`
  from.
- **Kernel boots but `ad9176-config` cannot see the DAC CSRs** → not a boot
  problem; see Procedures 4.A / 7.A and the LWS2F base
  ([CLAUDE.md §6 #6](../CLAUDE.md#6-critical-constraints)).

Log captures to [potential_issues.md](potential_issues.md).

---

## Stage 1 — Repo merge & baseline retarget

PLAN reference: [PLAN.md Stage 1](../PLAN.md#stage-1--repo-merge--baseline-retarget)

### What got deferred

Per Stage 1 verify gate, only **one** hardware test is queued:

> Boot the produced bitstream on the dev kit; baseline Yocto image
> (untouched) reaches login prompt.

(See [deferred_hw_gates.md → Stage 1 verify 5](deferred_hw_gates.md#stage-1-verify-5-baseline-yocto-image-boot).)

> **⚠ Reverted:** the Stage 1 ES-silicon EMIF retarget (DDR4-3200 → DDR4-1600 @
> 800 MHz, DBI removed) has been **rolled back** ([ISSUE-011](potential_issues.md)).
> Phase B is now fabric-only on the **production** baseline — device
> `A5ED065BB32AE4S`, stock **DDR4-3200**, DBI bonded. The EMIF is therefore the
> unmodified production config, validated by the baseline boot itself.
> **Procedures 1.B–1.D below are historical** (they checked the reverted ES
> config); retained for the record but no longer the active gate.

### Procedure 1.A — Bitstream boot smoke test

**Goal:** confirm the `.sof` configures the FPGA, the HPS comes
out of reset, and the heartbeat LED blinks.

**Hardware:** dev kit only; AD9176-FMC-EBZ optional (FMC port is unused
in Stage 1 — top-level SV has no FMC ports yet).

**Steps:**

1. Power off the kit; connect USB-Blaster to J5 and UART console
   (115200 8N1) to J6.
2. Build a fresh `.sof`:
   ```bash
   cd projects/agilex5_devkit
   quartus_sh -t build.tcl
   ```
   Expect `output_files/agilex5_devkit.sof` to appear after ~30-60 min.
   If the build fails on `MEM_OPERATING_FREQ_MHZ`, the EMIF IP/part pairing is
   inconsistent — confirm device `A5ED065BB32AE4S` with the production DDR4-3200
   EMIF IP (see [ISSUE-011](potential_issues.md)).
3. Power on the kit. With JTAG attached, program over JTAG:
   ```bash
   quartus_pgm -m JTAG -c 1 -o "p;output_files/agilex5_devkit.sof"
   ```
   > **NOTE — this is a fabric-only smoke test, not a Linux boot test.** On
   > this HPS-first design the bare `.sof` contains **no FSBL/U-Boot SPL**, so
   > programming it over JTAG configures the FPGA fabric but the **HPS will
   > not boot** (no U-Boot, no Linux). That is expected — see
   > [Deployable boot image](#deployable-boot-image--integrating-the-bootloader-read-first-if-linux-wont-boot).
   > To exercise the full boot chain, program the **bootloader-integrated
   > QSPI image** ([Procedure D.A](#procedure-da--fast-recovery-re-merge-fsbl-rebuild-qspi-image-reflash))
   > and boot from QSPI (MSEL = ASX4) instead.
4. Open the UART console. With the **QSPI boot image** programmed (not the
   bare `.sof`), within ~5 seconds expect U-Boot text. If U-Boot never
   appears: confirm the FSBL was merged and QSPI was flashed (see D.4
   Failure paths), then suspect HPS EMIF init → see Procedure 1.B.
5. **Pass criterion** (QSPI boot image in flash, MSEL = ASX4):
   - Heartbeat LED (top user LED) blinks at ~2 Hz
   - U-Boot prints `## SoC: Altera Agilex 5 Platform` (or similar)
   - UART eventually reaches `Yocto ... login:` prompt
   - No `EMIF calibration FAILED` lines in the boot log

### Procedure 1.B — EMIF DDR4-3200 calibration check

> **Historical note:** this procedure originally validated the reverted ES
> DDR4-1600/800 MHz retarget. With the production DDR4-3200 config restored, EMIF
> calibration is the stock-baseline path (already proven by the baseline boot).
> The steps below still apply as a generic EMIF-cal check.

**Goal:** confirm the production-stepping EMIF calibrated cleanly. If
Procedure 1.A's UART prints `EMIF cal FAILED` or hangs before U-Boot, run this.

**Method 1 — System Console (no Linux required):**

1. With the kit powered and `.sof` loaded, launch System Console:
   ```bash
   system-console -cli --project-dir=projects/agilex5_devkit
   ```
2. In System Console:
   ```tcl
   set service_path [lindex [get_service_paths emif_debug] 0]
   set claim [claim_service emif_debug $service_path ""]
   emif_debug::get_cal_status $claim
   ```
   Expect `PASS`.
3. If `FAIL`, capture `emif_debug::get_cal_report $claim` for analysis
   and log into [potential_issues.md](potential_issues.md) under
   ISSUE-011's action items.

**Method 2 — U-Boot dump:**

In U-Boot console:
```
=> printenv ddrcalstatus
=> md.l 0xffd12000 16    # SDM EMIF status registers
```

### Procedure 1.C — Confirm removed DBI pins are inert (OBSOLETE)

> **Obsolete after the ISSUE-011 revert.** DBI is back: `mem_dbi_n` is exported
> by the production EMIF IP and PIN_B119/AC90/V87/H87/B97 are **bonded** again.
> There are no "removed DBI pins" to check. Disregard this procedure unless you
> are intentionally re-doing the (discouraged) ES retarget.

**Goal (historical):** the 5 pins formerly assigned to `mem_0_dbi_n[0..4]`
(PIN_B119, AC90, V87, H87, B97) should be floating (high-Z) after the ES
retarget. If they have residual drive, they could glitch adjacent DDR4 signals.

**Steps:**

1. With the kit running and Linux booted, install a probe-and-check
   harness. Easiest: use the Quartus In-System Sources & Probes (ISSP)
   tool to read the actual pin state.
2. Alternative: scope-probe each of PIN_B119, AC90, V87, H87, B97 at the
   FPGA package directly (not feasible on a BGA without an interposer
   board; skip if interposer not available).
3. **Pass criterion:** all 5 pins are high-Z (no observable drive); DDR4
   read/write benchmarks (`memtester`, `stream`) show no errors.

### Procedure 1.D — DDR4 stress test (deferred to first hardware turn-on)

**Goal:** confirm DDR4-3200 @ 1066.667 MHz (the restored production config) is
stable over a sustained workload.

**Steps:**

1. Boot Linux on the kit.
2. Run a stress test:
   ```bash
   apt install memtester      # or build from source
   memtester 1024M 5          # 5 passes over 1 GiB
   ```
3. **Pass criterion:** zero errors across 5 passes (~19 min at DDR4-3200 /
   1066.667 MHz).

---

## Stage 2 — Wrap `dac_controller_0` as a Platform Designer component

PLAN reference: [PLAN.md Stage 2](../PLAN.md#stage-2--wrap-phase-a-as-a-platform-designer-ip-component)

### What got deferred

Per Stage 2 verify gate, one GUI-side check was deferred:

> Platform Designer renders the new component with interface groups
> colored; no parameter validation warnings.

(This is superseded once Stage 3 instantiates the IP in `dac_subsys.qsys`
and validates it end-to-end. Run anyway as belt-and-suspenders.)

### Procedure 2.A — Platform Designer GUI inspection

**Goal:** the IP catalog scanner finds `dac_controller_0` and renders its
14 interface groups without warnings.

**Hardware:** none. This is a GUI test on the workstation, not deferred
because of hardware — deferred because the headless `qsys-script` flow
does not expose component-mode API consistently (see commit
`0d064b9`'s message).

**Steps:**

1. Open Platform Designer GUI:
   ```bash
   cd projects/agilex5_devkit
   qsys-edit baseline_top.qsys --quartus-project=agilex5_devkit.qpf
   ```
2. In the IP Catalog pane (left side), expand **Project > Phase B DAC**
   (the GROUP property set in `dac_controller_0_hw.tcl`).
3. Double-click `DAC Controller (AD9176-FMC-EBZ, Phase A)`.
   Platform Designer opens a **New IP Variant** dialog asking where to
   save the instance parameterization. The dialog appearing is itself
   positive evidence that the catalog scanner found and parsed the
   component. Enter:
   - **File name**: `dac_smoke_check` (throwaway)
   - **Save in folder**: `scratch/` under the project root  this folder
     is in `.gitignore` so the generated `.ip` won't be committed.
   Click **Create** / **OK**.
4. The IP Parameter Editor opens. Verify:
   - **Parameters tab**: `G_LUT_DEPTH` is editable, default `1024`,
     allowed range `16:65536`.
   - **Signals & Interfaces** tab (Quartus 26.1 Pro; older versions call
     this "Interfaces"): all 14 interfaces present, colour-coded:
     - 2 clock sinks: `clock_sink`, `jesd_tx_link_clk` (green)
     - 1 reset sink: `reset_sink` (brown)
     - 1 AXI4 slave: `lwhpm2fpga` (blue, 4-bit ID, 10-bit addr, 32-bit data)
     - 2 Avalon-ST sources: `jesd_link0_data`, `jesd_link1_data`
       (orange, 128-bit, readyLatency 0)
     - 8 conduits: `jesd_link0_status`, `jesd_link1_status`,
       `jesd_reset_seq`, `jesd_refclk_ctrl`, `jesd_csr_readback`,
       `pio_control`, `pio_status`, `tx_enbl` (grey)
   - **System Messages** pane (bottom): zero red errors.
5. Close the Parameter Editor with **Cancel** (NOT **Finish**  Finish
   would commit the instance into `baseline_top.qsys`, which is not what
   we want at Stage 2).
6. If you accidentally hit Finish: in the baseline_top system view,
   right-click the new `dac_controller_0_0` instance and Remove. Delete
   `scratch/dac_smoke_check.ip` from the filesystem. Save baseline_top.qsys.

**Known-and-resolved warning history.**

The first run of Procedure 2.A (against commit `0d064b9`) surfaced four
warnings in System Messages:

```
Warning: dac_smoke_check.dac_controller_0_0.jesd_link0_data: Interface must have an associated reset
Warning: dac_smoke_check.dac_controller_0_0.jesd_link1_data: Interface must have an associated reset
Warning: dac_smoke_check.dac_controller_0_0.jesd_link0_data: dac_controller_0_0.jesd_link0_data does not have an associated reset
Warning: dac_smoke_check.dac_controller_0_0.jesd_link1_data: dac_controller_0_0.jesd_link1_data does not have an associated reset
```

Plus two follow-on `Export associatedReset of ...` warnings when the
interfaces were exported as conduits in the throwaway system.

Root cause: Quartus 26.1 Pro requires every Avalon-ST source to declare
`associatedReset`. The original `_hw.tcl` left it unset because the
JESD-link AVST sources live in `jesd_tx_link_clk` (~250 MHz) while the
only declared reset interface (`reset_sink`) lives in `clock_sink_clk`
(100 MHz) and Phase A's RTL does not export a separate JESD-domain
reset port.

Resolution: associate both `jesd_link*_data` sources with `reset_sink`.
The actual reset behaviour is gated inside `dac_controller_0` by the
JESD reset sequencer (`jesd_reset_seq` conduit) and the dc_fifo CDC, so
pointing at `reset_sink` satisfies the validator without
misrepresenting the runtime behaviour. Fix applied in commit `2d786e7`.

**If you started Procedure 2.A against pre-`2d786e7` code and saw the
warnings above**, you must refresh the IP catalog before the fix takes
effect:

- In Platform Designer: **File → Refresh System** (or **System → Refresh
  System** depending on Quartus version), then re-instantiate
  `dac_controller_0`.
- If refresh doesn't pick up the change (catalog caches the parsed
  `_hw.tcl` aggressively), close `qsys-edit` and re-open it. The IP
  catalog is re-scanned on launch.
- If you committed an instance into `baseline_top.qsys` before the
  refresh, remove the `dac_controller_0_0` instance and re-add it so it
  picks up the updated interface metadata.

**Pass criterion:** with the fix in place, the System Messages pane is
empty (no red errors, no yellow warnings related to `dac_controller_0`).

**Verified 2026-05-16 (bench, Quartus 26.1 Pro):** all six original
warnings cleared after applying commit `2d786e7` and refreshing the IP
catalog. Procedure 2.A passes.

If new warnings appear that are not the four above, capture screenshot
and log to [potential_issues.md](potential_issues.md) before Stage 3.

### Procedure 2.B — Instantiate into a throwaway system (smoke test)

**Goal:** confirm the IP can actually be wired up before Stage 3 commits
the real `dac_subsys.qsys`.

**Steps:**

1. From Platform Designer, File → New System; name it `dac_smoke_test`.
2. Drag-drop `DAC Controller (AD9176-FMC-EBZ, Phase A)` from the IP
   catalog into the system.
3. Connect:
   - System clock → `clock_sink` and `jesd_tx_link_clk`
   - System reset → `reset_sink`
   - Leave all other interfaces as exported conduits / unconnected
4. Click "Generate HDL" → expect success with no errors.
5. **Pass criterion:** the system generates a Verilog top wrapper; the
   wrapper instantiates `dac_controller_0` with the right port names.
6. Discard `dac_smoke_test.qsys` afterward (Stage 3 builds the real one).

---

## Stage 3 — Build `dac_subsys.qsys` (control plane only, JESD stubbed)

PLAN reference: [PLAN.md Stage 3](../PLAN.md#stage-3--build-dac_subsysqsys-control-plane-only-jesd-stubbed)

### What got deferred

The Stage 3 verify gate is fully workstation-executable
(`quartus_sh -t build.tcl --project-only` clean ipgenerate; address-map
spans verified by reading the generated `.qsys`). No hardware in the
loop. One **optional** GUI sanity check (Procedure 3.A below) is
recorded for belt-and-suspenders coverage; the headless ipgenerate
already gates correctness.

(See [deferred_hw_gates.md → Stage 3 verify](deferred_hw_gates.md#stage-3---build-dac_subsysqsys-control-plane-only-jesd-stubbed).)

### Procedure 3.A — Platform Designer GUI inspection of dac_subsys

**Goal:** visually verify the generated `ip/dac_subsys/dac_subsys.qsys`
matches the architecture in CLAUDE.md / PLAN.md: 11 instances, correct
address-map carving, JESD-side interfaces routed through `u_jesd_stub`,
clean System Messages pane.

**Hardware:** none. Workstation-only GUI inspection.

**Steps:**

1. Open Platform Designer GUI on the standalone subsystem:
   ```bash
   cd projects/agilex5_devkit
   qsys-edit ../../ip/dac_subsys/dac_subsys.qsys \
       --quartus-project=agilex5_devkit.qpf
   ```
   The system loads as `dac_subsys`.
2. **System Contents tab — instance list.** Confirm all eleven instances
   are present, no red error decorations:
   - `u_clk_bridge_axi`, `u_clk_bridge_jesd` (altera_clock_bridge)
   - `u_rst_bridge_axi`, `u_rst_bridge_jesd` (altera_reset_bridge)
   - `u_csr_bridge` (altera_avalon_mm_bridge, 14-bit address, 32-bit data)
   - `u_dac_controller_0` (DAC Controller, Phase A IP, Phase B DAC group)
   - `u_spi_master` (Avalon SPI Master, 2 CS, 25 MHz, 24-bit)
   - `u_tx_en_pio` (PIO, Output, width 2)
   - `u_pe_ctrl_pio` (PIO, Output, width 1)
   - `u_dac_status_pio` (PIO, Input, width 32, edge-capture ANY)
   - `u_jesd_stub` (JESD-side stub  Phase B DAC group)
3. **Address Map tab.** Select master `u_csr_bridge.m0` and confirm the
   five connections:
   | Slave | Base | End |
   |---|---|---|
   | `u_dac_controller_0.lwhpm2fpga` | `0x0000` | `0x03FF` (1 KB) |
   | `u_spi_master.spi_control_port` | `0x1000` | `0x101F` (32 B) |
   | `u_tx_en_pio.s1`                | `0x1100` | `0x111F` (32 B) |
   | `u_pe_ctrl_pio.s1`              | `0x1110` | `0x111F` (32 B  overlap is benign; PIO uses only 24 B) |
   | `u_dac_status_pio.s1`           | `0x1120` | `0x113F` (32 B) |
   The PE_CTRL / TX_EN PIO end addresses appear to overlap because the
   PIO IP rounds slave span up to a power-of-2; only the first 24 bytes
   of each PIO contain CSRs. The 0x10-byte stride in our address map
   places each register block on a 32-bit-clean boundary without
   collision. Stage 6 fills 0x2000-0x3FFF with the JESD GTS Subsystem.
4. **System Messages pane (bottom).** Expect zero red errors. Some
   informational messages about the auto-inserted Avalon-to-AXI4
   translator at the dac_controller_0 boundary are expected and
   benign  Qsys inserts these because `u_csr_bridge.m0` is Avalon-MM
   and `u_dac_controller_0.lwhpm2fpga` is AXI4 (4-bit ID, 10-bit addr).
5. **Connections panel.** Right-click `u_jesd_stub` and confirm its
   10 conduit/AVST connections are all to `u_dac_controller_0` (no
   external exports, no dangling pins). The presence of u_jesd_stub
   wired exhaustively to u_dac_controller_0's JESD-side ports is the
   visual cue that **Stage 6 will replace this stub with the real GTS
   Subsystem**  search the codebase for
   `JESD STUB - REMOVE IN STAGE 6` to find the cleanup hooks.
6. **Exit with File → Close (do NOT click Generate HDL).** The .qsys
   was generated by build.tcl; running Generate from the GUI would
   re-output without going through the qsys-script source-of-truth,
   causing drift.

**Pass criterion:** all eleven instances present and parameterized as
above; address map exactly matches the table; System Messages pane
shows no red errors.

**Failure path:** capture screenshot of the Address Map tab and any
System Messages errors, log to [potential_issues.md](potential_issues.md)
under a new ISSUE-XXX entry. The most likely cause of a drift is
someone hand-editing `dac_subsys.qsys` without updating
`ip/dac_subsys/dac_subsys.tcl`  the build.tcl regen step would then
overwrite the hand-edit on the next run.

---

## Stage 4 — Wire dac_subsys into baseline_top; FMC SPI pin-out

PLAN reference: [PLAN.md Stage 4](../PLAN.md#stage-4--wire-dac_subsys-into-baseline_topqsys-fmc-spi-pin-out)

### What got deferred

The Stage 4 fit and elaborate gates run on the workstation (no hardware
needed for build sign-off). All four end-to-end verify steps require the
dev kit + AD9176-FMC-EBZ:

1. SOF program over JTAG.
2. Yocto boot.
3. `devmem` reads of `dac_controller_0` ID + writes to `u_spi_master`
   CSR at `0x0200_0000` / `0x0200_1000`.
4. Scope on `fmc_spi_sck` (G9) confirming 25 MHz; AD9176 silicon-ID
   readback per AD9176 datasheet.

(See [deferred_hw_gates.md → Stage 4 verify 2-5](deferred_hw_gates.md#stage-4-verify-2-5-sof-program--linux-devmem--ad9176-spi-silicon-id-readback).)

### Procedure 4.A — FMC SPI bring-up + AD9176 silicon-ID readback

**Goal:** prove the LWH2F path reaches `u_dac_subsys.axi_csr` at
`0x0200_0000`, the `u_spi_master` CSR drives the FMC pins through the
1.2-V level-shifter on the AD9176-FMC-EBZ, and the AD9176 responds with
the expected silicon-ID register on CS1.

**Hardware prerequisites** (read [#hardware-bring-up-prerequisites-run-once]
above first):

- Dev kit powered, **VADJ = 1.2 V on the FMC carrier (verified with
  multimeter)** — see [CLAUDE.md §6 #3](../CLAUDE.md#6-critical-constraints).
- AD9176-FMC-EBZ seated in J34, both screws tight, FMC pin H2 (PRSNT_M2C_L)
  pulled low by the mezzanine. PG_M2C / PG_C2M are owned by the on-board
  MAX10 board-mgmt FPGA on this dev kit (see
  [potential_issues.md ISSUE-012](potential_issues.md#issue-012-ad9176-fmc-ebz-board-mgmt-signals-routed-to-max10-not-main-fpga));
  no main-FPGA action required for the power-good handshake.
- USB-Blaster on J5, UART on J6 (115200 8N1), 12 V brick on J37.
- 2-channel scope with probes on FMC pins **G9 (SCK)** and **G10 (MOSI)**.

**Steps:**

1. Confirm VADJ before powering or programming. Loss of 1.2 V here
   risks the FMC bank, AD9176 board, or FPGA bank.
2. Build the bitstream:
   ```bash
   cd projects/agilex5_devkit
   quartus_sh -t build.tcl
   ```
   Expect `output_files/agilex5_devkit.sof`. Inspect
   `output_files/agilex5_devkit.fit.summary`: WNS ≥ 0.5 ns, no unbonded-pin
   warnings on any `fmc_*` port.
3. Program over JTAG:
   ```bash
   quartus_pgm -m JTAG -c 1 -o "p;output_files/agilex5_devkit.sof"
   ```
   Heartbeat LED blinks → FPGA configured. UART reaches Yocto login (per
   Procedure 1.A).
4. Verify `dac_subsys` ID-register readback through LWH2F (does NOT
   touch the FMC yet):
   ```bash
   # On the Yocto target:
   devmem 0x02000000 32        # Phase A reg_bank ID (per ip/dac_controller_0/src/reg_bank.vhd)
   ```
   Expect the Phase A `reg_bank` ID constant. If `0xDEADBEEF` or
   `0xFFFFFFFF` → LWH2F is not reaching the dac_subsys; check the
   `u_shell_subsys.lwhps2fpga → u_dac_subsys.axi_csr` connection in
   `baseline_top.qsys` and the `[base=0x02000000 16 KB]` address-map slot
   visible in `baseline_top/baseline_top.csv` post-ipgen.
5. Enable the FMC SPI level-shifter and assert PG_C2M back to the
   mezzanine:
   ```bash
   devmem 0x02001130 32 1     # spi_en  <- 1   (u_spi_en_pio at 0x1130)
   devmem 0x02001140 32 1     # pg_c2m  <- 1   (u_pg_c2m_pio at 0x1140; output
                              # dangles on this dev kit -- MAX10 owns the pad,
                              # but the loopback bit below still reflects the write)
   ```
   Read back `0x02001120` for the housekeeping/status PIO — expect
   bit 0 = ~PRSNT (1 = AD9176 board present), bit 1 = 0 (PG_M2C is on
   MAX10, not main FPGA -- see ISSUE-012), bit 2 = PG_C2M loopback
   (= 1 if step 5 succeeded), bits 31:3 reserved (Stage 6 fills in
   JESD link/framer status).
6. Issue a single SPI read of the AD9176 silicon-ID register (CS1):
   ```bash
   # altera_avalon_spi CSR layout: 0=RXDATA, 4=TXDATA, 8=STATUS,
   # 0x0C=CONTROL, 0x14=SLAVESEL. 24-bit transfers (1 frame = 24 bits)
   # configured at IP level.
   #
   # AD9176 silicon-ID register address: TBD per AD9176 datasheet
   # (Analog Devices UG-1578, "Chip Type / Product ID"). The 8-bit address
   # combined with a read-bit (MSB=1) is the standard ADI SPI convention.

   devmem 0x02001014 32 1     # SLAVESEL = bit0 (CS1)
   devmem 0x02001004 32 0x800003  # TXDATA = 0x80_0000 OR (silicon_id_addr << 8)
   devmem 0x02001000 32       # RXDATA  - expect AD9176 silicon-ID byte in low 8 bits
   ```
7. Scope confirmation (single capture, ~10 us window after step 6's
   TXDATA write):
   - SCK (G9): 25 MHz clock burst of exactly 24 cycles.
   - MOSI (G10): the silicon-ID read command pattern.
   - CS1 (H11): low for the full burst.
8. **Pass criterion:** RXDATA byte matches the AD9176 datasheet silicon
   ID. SCK measured frequency within ±1% of 25 MHz. CS2 (D11) inactive
   throughout. JESD bring-up itself is **NOT** exercised at Stage 4 — the
   `u_jesd_stub` terminates the link domain, scope on SERDIN[0..7] would
   show nothing.

**Failure path:**

- No SCK on G9 → check `fmc_spi_en` (must be 1) and VADJ (must be 1.2 V).
- SCK present but no MOSI activity → check `dac_spi_MOSI` wiring in
  `agilex5_devkit.sv` (the `.dac_spi_MOSI (fmc_spi_mosi)` mapping).
- All-`0xFF` RXDATA → MISO path issue (cable, level-shifter, AD9176 not
  powered). Probe H10 (MISO) and verify AD9176 VDDx rails.
- Log scope captures and CSR readbacks to
  [potential_issues.md](potential_issues.md) under a new ISSUE-XXX.

### Procedure 4.B — TXEN + PE_CTRL toggle smoke test

**Goal:** confirm the two TXEN PIOs and PE_CTRL PIO physically drive
their FMC pins (no scope-on-AD9176-board required; probe the FMC
break-out points on the AD9176-FMC-EBZ).

**Hardware:** dev kit + AD9176-FMC-EBZ + scope probes on C10/C11/H13.

**Steps:**

1. From Yocto (or System Console without booting Linux — see Stage 6
   when the NiosV JTAG-master path is brought up):
   ```bash
   devmem 0x02001100 32 0x3    # tx_en  <- 11b (assert both TXEN_0 and TXEN_1)
   devmem 0x02001110 32 0x1    # pe_ctrl <- 1
   ```
2. Scope:
   - C10 (TXEN_0): low → high transition.
   - C11 (TXEN_1): low → high transition.
   - H13 (PE_CTRL): low → high transition.
3. De-assert all three:
   ```bash
   devmem 0x02001100 32 0
   devmem 0x02001110 32 0
   ```
   Confirm all three pins return low.

**Pass criterion:** all three pins toggle in lockstep with the CSR
writes, voltage swings 0 V ↔ 1.2 V.

---

## Stage 5 (merged with original Stage 6) — JESD204B GTS Subsystem integration

**PLAN reference:** [PLAN.md Stage 5 (merged)](../PLAN.md#stage-5-merged-with-original-stage-6--jesd204b-gts-subsystem-integration--fmc-differential-ports)

**What got deferred:**

- **Eye diagram + BER on SERDIN lanes** — needs a high-speed scope
  (≥ 25 GHz BW) or BERT instrument. Cross-ref:
  [deferred_hw_gates.md](deferred_hw_gates.md) Stage 5 entry.
- **JESD link bring-up to AD9176** — needs AD9176-FMC-EBZ mounted,
  HMC7044 configured to drive GBTCLK0 + SYSREF, AD9176 SPI bring-up
  sequence executed via System Console or Linux.
- **Subclass-1 deterministic latency confirmation** — needs the
  AD9176-FMC-EBZ source-sync SYSREF/GBTCLK0 strap verified per the
  AD9176 datasheet table referenced in
  [jesd_bringup_sequence.md](jesd_bringup_sequence.md).

### Procedure 5.A — JESD link bring-up + first sine wave on AD9176 RF out

**Goal.** Confirm the merged Stage 5 (merged) bitstream brings up both
JESD204B links to the AD9176, releases SYNC, and produces a clean sine
on at least one AD9176 RF output.

**Hardware required:**

- DK-A5E065BB32AES1 dev kit, USB-Blaster (JTAG), ATX 12 V supply
  (J17), AD9176-FMC-EBZ mezzanine seated in FMC slot, VADJ set to 1.2 V
  (CRITICAL — see [CLAUDE.md §6 #3](../CLAUDE.md#6-critical-constraints))
- HMC7044 configured for GBTCLK0 = 312.5 MHz, SYSREF per AD9176-FMC-EBZ
  default (low-rate, divides DEV_CLK)
- Scope with ≥ 1 GHz BW on AD9176 RF output J1 (or any of J1..J4)
- System Console (Quartus 26.1) over JTAG, OR Linux booted with
  `devmem` reachable

**Steps:**

1. Build + flash `agilex5_devkit.sof` (or
   `agilex5_devkit_time_limited.sof` if the workstation lacks the
   JESD204B IP license -- see
   [potential_issues.md ISSUE-016](potential_issues.md#issue-016-jesd204b-fpga-ip-for-f-tile-is-opencore-plus-on-this-workstation))
   via Quartus Programmer (or boot FPGA via `core.rbf` from the dev kit
   SD card). The time-limited variant halts after ~1 hour and must be
   re-flashed to recover.
2. From System Console, confirm the dac_controller_0 ID register reads
   correctly at LWH2F base `0x0200_0000` (the heartbeat indicates
   fabric is alive; same gate as Stage 4 Procedure 4.A).
3. Confirm `fmc_ready` is asserted by reading the dac_status PIO at
   `0x0200_1120` bit 5. If clear: check FMC seating (prsnt_n on
   `fmc_prsnt_n`) and MAX10 power-good status on the board indicator
   LEDs.
4. Enable the FMC SPI buffer + drive PE_CTRL high (Stage 4
   Procedure 4.B):
   ```bash
   devmem 0x02001130 32 0x1    # spi_en  <- 1 (FMC SPI buffer enable)
   devmem 0x02001110 32 0x1    # pe_ctrl <- 1
   ```
5. Run the AD9176 init sequence from Phase A's
   `D:\Firmware_PhaseA\src\hps\ad9176_init.c` adapted to the SPI master
   CSR at `0x0200_1000`. The bring-up sequence is documented in
   [jesd_bringup_sequence.md](jesd_bringup_sequence.md).
6. Release SYNC: the GTS IPs will sample `fmc_sync0` / `fmc_sync1`
   (AD9176 drives) and start transmitting JESD ILAS once SYNC goes
   high.
7. Poll JESD GTS CSRs at `0x0200_2000` (link 0) and `0x0200_3000`
   (link 1) for link-ready bits. The GTS IP CSR map is in the Intel
   JESD204B GTS IP User Guide (Quartus 26.1 doc set).
8. Scope on AD9176 RF J1: should show the configured NCO sine wave.

**Pass criterion:** both JESD links report link-ready; AD9176 RF
output produces a recognizable sine wave at the configured NCO
frequency (Stage 7 will fully exercise the NCO via the
ad9176-config Linux tool — for Stage 5, even a default NCO tone
suffices).

**Failure path:**

- If `fmc_ready` never asserts: trace `fmc_prsnt_n` on the dev kit
  test point H2 (FMC_PRSNT_M2C_L); ensure FMC card is fully seated.
- If JESD link does not lock: capture the GTS link state machine
  via System Console (CSR readout at link0/link1 base), then file in
  [potential_issues.md](potential_issues.md). Common failure modes:
  HMC7044 not configured (no GBTCLK), VADJ not 1.2 V (HSIO 3B fails
  to drive SYSREF/SYNC), SUBCLASSV strap mismatch (drop to subclass 0
  via the IP's runtime CSR if subclass 1 won't lock).
- If RF output is silent but JESD link is up: the AD9176 datapath
  (interpolators, NCO, output mux) may need explicit register writes;
  see AD9176 datasheet Table 50 (init sequence).

---

## Stage 8 -- System simulation

**PLAN reference:** [PLAN.md Stage 8](../PLAN.md#stage-8--system-simulation)

**Status:** Stage 8a complete (block-level regression runs clean under
Questa Altera Starter FPGA Edition); 8b and 8c pending.

**What got deferred:**

- **Integration TB against the real JESD204B GTS IP** (Stage 8b). Will
  be attempted next; see Procedure 8.B once written.
- **BFM substitution fallback** (Stage 8c). Only invoked if 8b cannot
  drive the GTS IP from a SystemVerilog testbench.
- **Hardware-driven regression** -- block TBs are software-only; the
  end-to-end check stays in Procedure 5.A / 7.A.

### Procedure 8.A -- Block-level regression on Questa

**Goal.** Confirm all 8 Phase A block testbenches compile and pass on
the Phase B workstation. This is the same Stage 1 gate from Phase A,
re-validated for Phase B's toolchain.

**Hardware required:** None. Pure software.

**Steps:**

```sh
# From repo root, with Questa Altera Starter on PATH.
# Quartus Pro 26.1 ships it at:
#   D:/altera_pro/26.1/questa_fse/win64/
# (on Linux: <install>/questa_fse/linux64/)

export PATH=/d/altera_pro/26.1/questa_fse/win64:$PATH
vsim -c -do "do tb/run_block_tbs.tcl; quit -f"
```

**Pass criterion:**
- `run_block_tbs: summary` reports `TBs run: 8 / TBs failed: 0`.
- Last line printed: `Stage 1 block-tb gate: PASS` and exit code 0.

**Failure path:**
- `(vcom-1441) Process(ALL) is not defined for this version of the
  language` -- VHDL-2008 not enabled. Phase A RTL uses `process(all)`.
  Confirm `tb/run_block_tbs.tcl` calls `vcom -2008` (it should --
  this is a regression test for the script itself).
- License errors at `vsim` start: Questa Altera Starter requires a
  Quartus license on the same license server. Confirm
  `SALT_LICENSE_SERVER` is set.
- Specific TB fails: capture the `** Error:` line(s) from the
  transcript and file in [potential_issues.md](potential_issues.md).
  Phase A's TB idiom uses `severity error` for `** Error:
  SIMULATION PASSED` (intentional, for visibility); look at the
  `TBs failed` count in the summary line, not the raw Errors count.

### Procedure 8.B -- License probe (diagnostic, on-demand)

**Goal.** Verify the JESD204B GTS IP simulation models compile under
Questa without an additional license. Useful when the toolchain
version changes or when bringing a new workstation online.

**Hardware required:** None.

**Steps:**

```sh
cd projects/agilex5_devkit/sim
vsim -c -do probe_license.do
```

**Pass criterion:** Final line of transcript reads
`== probe_license.do: PROBE_PASS (all libs + IP compiled) ==`
and exit code 0.

**Failure path:**
- `PROBE_FAIL: com -- ... vcom failed` with `(vcom-1441) Process(ALL)`:
  same as 8.A; -2008 flag missing.
- `PROBE_FAIL` with `License (FlexLM-...)`: the workstation's Altera
  license server does not include the simulation feature; contact
  license admin.

### Procedure 8.C -- dac_subsys integration TB (Stage 8b)

**Goal.** Drive the dac_subsys CSR plane through the HPS LWH2F AXI
BFM against the real baseline_top netlist (real JESD204B GTS IP
instances, no BFM substitution). Confirms the LWH2F -> AXI -> AvMM
-> reg_bank / SPI master / PIO paths are alive in simulation; gates
the address-decode and bit-layout correctness that hardware-side
debugging is otherwise expensive to find.

**Hardware required:** None. Long runtime (~2 hours wall clock on a
typical workstation; ~5 GB sim DB).

**Steps:**

```sh
cd projects/agilex5_devkit/sim
vsim -c -do run_dac_subsys_tb.do
```

**Pass criterion:** Final lines of the transcript include
`dac_subsys_tb summary: errors=0` and `dac_subsys_tb: SIMULATION
PASSED`. All six sub-tests pass:
- T1: fmc_handshake asserts fmc_ready when prsnt_n drops + pg_m2c=1
- T2: scratchpad write/readback survives LWH2F -> AvMM
- T3: SPI master CONTROL/SLAVESEL CSR writes survive
- T4: PIOs (tx_en, pe_ctrl, spi_en) write/read-back at the right
  byte offsets
- T5: SineWaveGen NCO freq + amp CSRs round-trip
- T6: dac_status_pio still reflects fmc_ready (stickiness check)

**Failure path:**
- T1 FAIL `fmc_ready never asserted`: walk the dac_status_word
  concat in [agilex5_devkit.sv:217](../projects/agilex5_devkit/agilex5_devkit.sv#L217).
  The Stage 8b run originally caught a missing reserved bit in this
  concat (`1'b0` -> `2'b00`) that shifted fmc_ready from bit 5 to
  bit 4 vs documentation -- regression-protect that fix.
- T2-T5 FAIL: address decode error in `dac_subsys.qsys`. Re-check
  the `set_connection_parameter_value ... baseAddress` lines in
  [ip/dac_subsys/dac_subsys.tcl](../ip/dac_subsys/dac_subsys.tcl).
- T6 FAIL `fmc_ready dropped`: fmc_handshake spurious resync. Check
  [src/fmc_handshake.sv](../projects/agilex5_devkit/src/fmc_handshake.sv)
  hold-off counter behavior after the initial assert.
- vsim hangs past 3 hrs: the JESD GTS IP simulation may be spinning
  on PLL lock (no RX peer in sim). Add a watchdog in the TB and
  consider Stage 8c (BFM substitution).

---

## Stage 7 -- ad9176-config user-space tool & full Linux-driven bring-up

**PLAN reference:** [PLAN.md Stage 7](../PLAN.md#stage-7--ad9176-config-user-space-tool--full-bring-up)

**What got deferred:**

- **Bench bring-up itself** -- needs the dev kit booted to Linux on the
  Yocto image with `ad9176-config` installed (see Procedure 7.A).
  Cross-ref: [deferred_hw_gates.md](deferred_hw_gates.md) Stage 7 entry.
- **Yocto build** -- the recipe at
  `software/yocto_linux/meta-custom/recipes-apps/ad9176-config/` is
  not invoked from the firmware workstation. Build host steps are in
  the Procedure.
- **Scope verification of the AD9176 RF output** -- needs >=1 GHz BW
  scope on J1..J4; see Procedure 7.A pass criterion.

### Procedure 7.A -- Linux user-space bring-up of AD9176 via ad9176-config

**Goal.** Boot the dev kit into Yocto, run `ad9176-config bringup`, and
confirm the AD9176 emits the configured sine wave on at least one RF
output. This is the deployable-flow analogue of Procedure 5.A (which
uses System Console over JTAG).

**Hardware required:**

- Same as Procedure 5.A (dev kit + AD9176-FMC-EBZ at VADJ=1.2 V + HMC7044
  configured + scope on J1).
- SD card flashed with the Yocto image that includes `ad9176-config`
  (bitbake step below).
- Serial console (J5 micro-USB on the dev kit) or SSH into the booted
  HPS over the Ethernet management port.

**Build host steps (one-time, on a Linux workstation with Yocto set up):**

```sh
cd software/yocto_linux/meta-custom/recipes-apps/ad9176-config/files/
# Symlink or copy the C sources from software/ad9176_config/ per
# files/README.txt.  Then back up to the Yocto build root:
cd ../../../../..
# Append meta-custom to BBLAYERS, then:
bitbake ad9176-config
# Or rebuild the dev-kit image with ad9176-config included:
bitbake core-image-minimal-dev
```

**Steps (on the dev kit, post-boot):**

1. Flash the FPGA: either `quartus_pgm -m jtag -o "p;agilex5_devkit.sof"`
   (or `_time_limited.sof` per
   [potential_issues.md ISSUE-016](potential_issues.md#issue-016-jesd204b-fpga-ip-for-f-tile-is-opencore-plus-on-this-workstation))
   OR boot U-Boot which loads `core.rbf` from the SD card.
2. Log in to Yocto (root by default on the GSRD baseline). Confirm
   `ad9176-config --help` runs.
3. Quick gate before bring-up:
   ```sh
   ad9176-config status
   ```
   Expected: `fmc_ready=1`; `prsnt_n=0`; jesd_sync_status txlink=0x0 /
   grp=0x0 / lmfc=0 (no link yet).
4. Run the full bring-up:
   ```sh
   ad9176-config bringup --freq 10000000 --fs 625000000
   ```
   Expected output:
   - `fmc_ready asserted`
   - `AD9176 chip_type=0x04 prod_id=0x9176`
   - `AD9176 DAC PLL status=0x??` (datasheet bit 0 = LOCK)
   - `JESD sync OK (status=0x???????? txrdy=0x3 grp=0x1 lmfc=0)` (active links 0-1 / group 0 -- ISSUE-009)
   - `SineWaveGen: f=10000000 Hz fs=625000000 Hz freq_word=0x...`
   - `Bring-up complete; scope on AD9176 RF outputs`
5. Scope on AD9176 J1: 10 MHz sine wave at the configured amplitude.
6. Re-tune without re-init:
   ```sh
   ad9176-config tone --freq 5000000
   ```
   Scope should track to 5 MHz with no glitch.

**Pass criterion:**
- `ad9176-config bringup` exits 0 with both AD9176 ID + JESD sync OK.
- Scope shows clean sine at configured `--freq`, amplitude near
  full-scale, no spurs above -40 dBc within +/-10 % of carrier.

**Failure path:**

- `fmc_ready never asserts`: same checklist as Procedure 5.A
  (FMC seating, VADJ=1.2 V, MAX10 PGOOD LED).
- `AD9176 chip_type=0x.. prod_id=0x...` mismatch: SPI not reaching
  the AD9176. Check `fmc_spi_en` PIO (Procedure 4.B), `fmc_pe_ctrl`,
  and scope SCK/MOSI/MISO on the FMC test points.
- `JESD link-lock timeout`: capture the JESD GTS CSR snapshot
  (`ad9176-config peek 0x2000`..`0x2FFC` and same for `0x3000`)
  and file in [potential_issues.md](potential_issues.md). Common
  causes: AD9176 mode register mismatch, HMC7044 mis-configured,
  SUBCLASSV strap mismatch.
- `Bring-up returns 0 but scope is silent`: AD9176 main DAC may be
  in standby; check `ad9176-config peek 0x080` (REG_PIO_CTRL) and
  `peek 0x040` (REG_SINE_CTRL bit 0); poke 0x1 if zero.

---

## Stage 9 -- Hygiene & doc finalization

**PLAN reference:** [PLAN.md Stage 9](../PLAN.md#stage-9--hygiene--doc-finalization)

**Status:** COMPLETE (2026-05-21).

**What got deferred:**

- **`verilator --lint-only` run** -- workstation has no verilator
  install; Quartus elaborate covers the same ground for this
  workstation. See [deferred_hw_gates.md](deferred_hw_gates.md)
  Stage 9 verilator entry.
- **Reproducible-build full re-run** -- per Stage 9 scoping decision
  D11, the existing `output_files/agilex5_devkit*.sof` was reused
  because no source files have changed in a way that affects fitter
  output. See [deferred_hw_gates.md](deferred_hw_gates.md) Stage 9
  reproducible-build entry. The reproducibility check rolls into
  Procedure 5.A's bench-side build.
- **ISSUE-019 fix (GTS Reset Sequencer)** -- a real architectural gap
  surfaced by Stage 9's DRC sweep; the fix is small (one IP + 3
  connections + an address-map entry at `0x0200_4000`) but belongs
  to whatever stage owns the JESD bring-up hardware turn-on. See
  [potential_issues.md ISSUE-019](potential_issues.md).

No new in-procedure hardware steps -- Stage 9 is doc / lint hygiene.
Stage 9 closeout is documentary only; the bench-side validation is
Procedure 5.A.

---

## How to add a new stage's procedures

When closing a stage, append a `## Stage N — <name>` section here that
includes:

1. **PLAN reference** — link to the stage in PLAN.md.
2. **What got deferred** — explicit list of verify steps that needed
   hardware / GUI / external systems, cross-linked to the matching entry
   in [deferred_hw_gates.md](deferred_hw_gates.md).
3. **One subsection per procedure** (`### Procedure N.X — <goal>`):
   - **Goal** — what we're trying to prove.
   - **Hardware** — what's required (or "none, GUI-only").
   - **Steps** — copy-pasteable commands; absolute paths or paths
     relative to the repo root.
   - **Pass criterion** — observable outcome, not subjective judgment.
   - **Failure path** — where to log issues (usually
     potential_issues.md), what to check first.

Procedures should be runnable by someone who knows the toolchain but not
the project. Spell out kit identifiers (J5, J37, etc.) and CLI flags.

---

## Cross-references

- [PLAN.md](../PLAN.md) — stage-by-stage implementation script
- [CLAUDE.md](../CLAUDE.md) — architecture, critical constraints, build rules
- [potential_issues.md](potential_issues.md) — open + closed issues
- [deferred_hw_gates.md](deferred_hw_gates.md) — ledger of skipped gates
- [fmc_pinout_crossref.md](fmc_pinout_crossref.md) — FMC ↔ AD9176 ↔ FPGA pin map
