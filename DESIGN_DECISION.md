# DESIGN_DECISION.md — Agilex 5 Custom Firmware: Decisions, Replication & Boot-Issue Lessons

> **Two purposes.** (1) Record the key decisions on our implementation path and how
> to **replicate** it on the `DK-A5E065BB32AES1` kit. (2) Serve as a **transfer
> document** so the lessons — especially the boot-chain and version-coherence
> findings — can be merged into a *different* Agilex 5 / SoC-FPGA project that is
> having boot issues. Sections 3 and 5 are written for that second audience.

See `CLAUDE.md` (design reference) and `PLAN.md` (roadmap) for the full detail.

---

## 1. Context Snapshot (the system we built against)

| Attribute | Value | Source of truth |
|---|---|---|
| Dev kit | Agilex 5 E-Series 065B Premium + OOBE/HPS daughtercard | user |
| FPGA device | `A5ED065BB32AE4S`, family "Agilex 5" | `baseline_a55.qsf:33-34` |
| Quartus | Prime Pro **26.1** (`D:\altera_pro\26.1`) | install / `README.md` |
| GHRD | `D:\a5ed065b-premium-devkit-oobe\baseline-a55`, project `top`, revision `baseline_a55` | source tree |
| Config mode | **HPS-First** | GHRD `README.md` |
| Boot media | SD card (`SSBL_BOOT_SOURCE = mmc0`) | `kas.yml` |
| Starting state | Working SD card that boots Yocto on baseline firmware | user |

---

## 2. Key Design Decisions (decision log)

Each entry: **Decision · Why · Alternatives · Trade-off · Transfer note** (what it
teaches another project).

### D1 — Base on the official GSRD/GHRD, not a from-scratch design
- **Why:** the GHRD already boots Yocto on this exact kit; HPS pin-mux, EMIF, and
  the entire bootloader handoff are known-good. Building HPS bring-up from scratch
  is the single largest source of SoC boot failures.
- **Alternatives:** new Quartus project + blank Platform Designer HPS.
- **Trade-off:** less ground-up understanding; constrained to the GHRD's structure.
- **Transfer note:** *If the other project boots-fails, first ask whether its HPS
  config diverged from a known-good GHRD of the same release.*

### D2 — Constrain the change to FPGA fabric only (do not touch the HPS)
- **Why:** any HPS pin-mux / clock / PLL / EMIF / peripheral change regenerates the
  **bootloader handoff**, which would invalidate the prebuilt SPL/U-Boot and force
  a bootloader (and likely Yocto) rebuild. Keeping HPS untouched means the handoff
  is byte-stable and the entire boot chain is reused.
- **Alternatives:** add the register via an HPS GPIO or a new HPS-side peripheral.
- **Trade-off:** the demo register must live behind an existing HPS↔FPGA bridge.
- **Transfer note (the big one):** **handoff ↔ SPL ↔ periphery RBF must all come
  from the same Quartus/GHRD revision.** This is the #1 cause of "custom .sof won't
  boot" — see §3 and §5.

### D3 — Regenerate only `ghrd.core.rbf`; never touch `ghrd.hps.rbf`
- **Why:** the FPGA image splits into **periphery** (`ghrd.hps.rbf`, HPS/IO/EMIF,
  handoff-tied) and **core/fabric** (`ghrd.core.rbf`, user logic). Our loopback is
  pure fabric → only the core RBF changes. `quartus_pfg … -o hps_core_only=ON`
  emits exactly the fabric portion, independent of the HPS/`_hps_debug` content.
- **Alternatives:** regenerate the full combined image (would re-touch periphery).
- **Trade-off:** none meaningful for our scope.
- **Transfer note:** *Treat periphery RBF and core RBF as separately versioned
  artifacts. A core-only change is safe to redeploy; a periphery change is a
  boot-chain change.*

### D4 — Deploy via `kernel.itb` repack (primary); `fpga load` / DT overlay (alts)
- **Why:** the Yocto image sets `FPGA_ENABLE_CORE_PGM = 1`, so the core RBF is
  **embedded in `kernel.itb`** and **`bootm` programs it during boot**. Embedding
  *our* RBF makes it load identically to the baseline, with zero boot-sequence
  changes — most robust and repeatable.
- **Alternatives:** (a) U-Boot `fpga load` of a standalone `core.rbf`; (b) Linux
  device-tree overlay at runtime.
- **Trade-off:** repack needs a one-time `mkimage` step in WSL. The alternatives
  avoid repack but risk being **overwritten** by `bootm`'s embedded RBF
  (ordering-dependent), so they require disabling `FPGA_ENABLE_CORE_PGM` or running
  strictly after boot (overlay).
- **Transfer note:** *Know whether your boot flow auto-programs the fabric from
  `kernel.itb`. If two things program the FPGA, the last one wins — silent cause of
  "my bitstream isn't there."*

### D5 — Loopback on the LWS2F bridge, accessed by `devmem` (no driver)
- **Why:** the Lightweight HPS-to-FPGA (LWS2F, base `0x2000_0000`) is the standard
  place for FPGA control/status registers and already hosts the GHRD sysid/PIOs, so
  a new slave inherits bridge enablement. `devmem` needs no kernel driver →
  fastest unambiguous proof of HPS↔FPGA connectivity.
- **Register map:** `+0x0 SCRATCH` (R/W, reads back last write) · `+0x4 ID` (RO
  magic `0x10C0_0BAC`). SCRATCH proves the round trip; ID proves the bus actually
  reached our logic (not a floating read).
- **Alternatives:** UIO driver, custom char driver, HPS GPIO.
- **Transfer note:** *A fixed magic-ID register is a cheap, decisive "is the fabric
  alive and addressable?" probe — useful when debugging any HPS↔FPGA bring-up.*

### D6 — Build natively on Windows via `quartus_*` (bypass the GHRD Makefile)
- **Why:** the GHRD Makefile uses bash/`flock`/`zip`/`chmod` and does not run on
  native Windows; the underlying `quartus_ipgenerate` / `quartus_sh --flow compile`
  / `quartus_pfg` commands do. A PowerShell wrapper reproduces the essential chain.
- **Transfer note:** *The Makefile is orchestration, not magic — the real build is
  a handful of `quartus_*` calls you can run anywhere Quartus is installed.*

### D7 — Keep Linux work to a single `mkimage` step in WSL2
- **Why:** honors "don't rebuild Yocto." The only Linux-only tool we need is
  `u-boot-tools` (`mkimage`/`dumpimage`) for the `kernel.itb` repack.
- **Transfer note:** *Repacking a FIT image ≠ rebuilding Yocto. You can swap kernel/
  dtb/RBF inside `kernel.itb` without the BSP.*

### D8 — Pin every layer to the 26.1 GSRD release
- **Why:** the SD card, bootloader, kernel, and our `.sof` must share one release so
  the handoff/periphery/U-Boot/kernel ABI all agree. See the matrix in §4.2.
- **Transfer note:** *Version drift across Quartus, GSRD layers, U-Boot, ATF, and
  kernel is the most common boot-failure root cause — pin and verify it first.*

---

## 3. The Boot Chain — and where it breaks (for the other project)

HPS-First boot, stage by stage. For a boot-issue investigation, walk this top-down
and identify the **last stage that produced UART output**.

| # | Stage | Configured by / file | Typical failure symptom | Most common root cause |
|---|---|---|---|---|
| 1 | SDM loads HPS **periphery** | `ghrd.hps.rbf` (from `.sof`, handoff) | board dead, no UART, no heartbeat LED | periphery RBF / device mismatch; corrupt SDM image |
| 2 | **U-Boot SPL (FSBL)** + DDR cal | `u-boot-spl-dtb.hex` (built **from the handoff**) | hangs before any U-Boot banner; "DDR cal fail" | **handoff ≠ the `.sof` the SPL was built from** (D2); wrong EMIF settings |
| 3 | **ATF / bl31** | `bl31.bin` (ATF `v2.14.0`) | reset loop after SPL | ATF/U-Boot version mismatch |
| 4 | **U-Boot proper** | `u-boot.itb` (`v2026.01`), env, `boot.scr.uimg` | U-Boot prompt but no kernel load | wrong boot source / missing `kernel.itb`; bad env |
| 5 | `bootm` loads **kernel.itb** (+ programs core RBF) | `kernel.itb` (Image+DTB+`core.rbf`), `FPGA_ENABLE_CORE_PGM=1` | kernel panic, no console, or fabric not present | DTB ↔ kernel mismatch; RBF program failure |
| 6 | **Linux** mounts rootfs | ext4 rootfs (Yocto `scarthgap`) | kernel up but no login / rootfs not found | wrong root= / partition; rootfs ABI vs kernel |

**Golden diagnostic rule:** *The first three stages depend on the **handoff**, which
is generated by the Quartus project that produced the `.sof`. If you pair a custom
`.sof` with a prebuilt bootloader and it dies before the U-Boot banner, suspect a
handoff/version mismatch before anything else.*

---

## 4. Replication Package

### 4.1 Source files that matter (and what each controls)

GHRD root: `D:\a5ed065b-premium-devkit-oobe\baseline-a55`

| File / dir | Controls | Edit for our path? |
|---|---|---|
| `top.qpf` | Quartus project | no |
| `project_config.mk` | project name `top`, revision `baseline_a55` | no |
| `baseline_a55.qsf` | **device `A5ED065BB32AE4S`**, pins, HPS assignments, IP search path | no (HPS) |
| `baseline_a55.sv` | top RTL (incl. heartbeat LED on MSB of `led`) | only if wiring new top ports |
| `baseline_a55.sdc`, `jtag.sdc` | timing constraints | no |
| `baseline_top.qsys` | top Platform Designer system | no |
| `hps_subsys.qsys` | **HPS configuration — DO NOT EDIT** (handoff) | **NEVER** |
| `fabric_subsys.qsys` | fabric: NiosV, OCRAM, sysid, PIOs on **LWS2F** | **YES — add loopback here** |
| `shell_subsys.qsys`, `niosv_subsys.qsys` | shell / JTAG-master debug subsystems | no |
| `custom_ip/*_hw.tcl` | custom IP components (search path in `ip_include.tcl`) | **YES — add `loopback_csr_hw.tcl`** |
| `ip_include.tcl` | `IP_SEARCH_PATHS = custom_ip/**/*` | no |
| `qsys_update.tcl` | IP-upgrade/footprint reload helper | no |
| `swbuild_config.mk` | RBF + Yocto/SD targets, `RBF_NAME=ghrd`, `hps_core_only` | reference only |
| `software/hps_debug/` | `hps_wipe.ihex` for `_hps_debug.sof` | no |
| `software/yocto_linux/` | **Yocto/kas build** (`kas.yml`, `kas/`, `meta-custom/`, `build.sh`) | reference only (avoid rebuild) |

Our additions live in `d:\Firmware_DevBoard_Linux\` (`custom_ip/loopback/`,
`quartus/scripts/`, `deploy/`, `patches/`, `docs/`), applied additively onto the GHRD.

### 4.2 Configuration setup — version matrix (PIN THESE)

From `software/yocto_linux/kas.yml`, `kas/bsp.yml`, `kas/machine.yml`:

| Layer | Pin | Notes |
|---|---|---|
| Quartus Prime Pro | **26.1** | `D:\altera_pro\26.1` |
| GSRD meta layer | `meta-altera-fpga` tag **`QPDS26.1_p1_REL_GSRD_PR`** | the release glue |
| Poky / OE | branch **`scarthgap`** | poky, meta-openembedded, meta-clang |
| Linux kernel | `linux-socfpga-lts` **6.18%**, `KBRANCH socfpga-6.18.2-lts`, `LINUX_SRCREV b2496f2fcb06db4d598d0073ad0e9e9be99b9288` | |
| U-Boot | `u-boot-socfpga` **v2026.01%**, `socfpga_v2026.01`, `UBOOT_SRCREV 6e59447316d06b25ca98caaa5c16787f5c74e862` | repo `github.com/altera-fpga/u-boot-socfpga` |
| ATF (TF-A) | **v2.14%**, `socfpga_v2.14.0`, `ATF_SRCREV 4a4b4573e12fabd0a88e95952af49840db6b770d` | repo `github.com/altera-fpga/arm-trusted-firmware` |
| MACHINE | **`agilex5e`** | |
| Linux DTS | `socfpga_agilex5_socdk.dts` (custom `baseline_a55.dts`) | full-featured dev-kit DT |
| U-Boot defconfig / DT | `socfpga_agilex5_defconfig` / `socfpga_agilex5_socdk.dtb` | |
| Boot source | `SSBL_BOOT_SOURCE = mmc0` | SD/MMC |
| FPGA core program | `FPGA_ENABLE_CORE_PGM = 1`, `FPGA_RBF_FILE = baseline_a55_hps_debug.core.rbf` | RBF embedded in `kernel.itb` |

**Deployed boot binaries** (Yocto `deploy/images/agilex5e/`): `u-boot-spl-dtb.hex`,
`u-boot.itb`, `bl31.bin`, `boot.scr.uimg`, `uboot.env`, `Image`,
`socfpga_agilex5_socdk.dtb` / `..._vanilla.dtb`, **`kernel.itb`**, rootfs `.wic`.

### 4.3 Toolchain & host setup
- **Windows:** Quartus 26.1 on PATH (`$env:QUARTUS_ROOTDIR\bin64`).
- **WSL2 Ubuntu (repack only):** `sudo apt-get install -y u-boot-tools`.
- **Serial:** daughtercard UART, **115200 8N1** (PuTTY / Tera Term).

### 4.4 Build & deploy (end to end)
```powershell
# --- Windows: build .sof and core RBF (after adding loopback to fabric_subsys) ---
$env:QUARTUS_ROOTDIR="D:\altera_pro\26.1\quartus"; $env:PATH="$env:QUARTUS_ROOTDIR\bin64;$env:PATH"
cd D:\a5ed065b-premium-devkit-oobe\baseline-a55
quartus_ipgenerate top -c baseline_a55 --synthesis=verilog
quartus_sh --flow compile top -c baseline_a55                          # -> output_files/baseline_a55.sof
quartus_pfg -c output_files/baseline_a55.sof output_files/ghrd.core.rbf -o hps=ON -o hps_core_only=ON
```
```sh
# --- WSL2: repack kernel.itb with the new core RBF (no Yocto) ---
dumpimage -l kernel.itb                      # read FIT node/config layout
#   extract Image + dtb(s); write kernel.its referencing the NEW ghrd.core.rbf
mkimage -f kernel.its kernel.itb             # -> new kernel.itb
#   copy kernel.itb onto SD FAT partition (back up original first)
```

### 4.5 Verification
```sh
# UART console (Linux): prove the HPS↔FPGA path
devmem 0x200100A0 32 0xDEADBEEF   # write SCRATCH  (offset as assigned in Platform Designer)
devmem 0x200100A0                  # -> 0xDEADBEEF
devmem 0x200100A4                  # -> 0x10C00BAC  (ID magic)
# Optional second proof from U-Boot:  mw 0x200100A0 0xDEADBEEF ; md 0x200100A0 1
```

---

## 5. Lessons Learned → Applying to the boot-troubled project

A triage checklist distilled from the above. Run top to bottom.

1. **Establish version coherence first (D8, §4.2).** Confirm Quartus, GSRD meta tag,
   U-Boot, ATF, and kernel are all from one release. Mixed releases are the most
   common boot-failure root cause. Get the failing project's actual pins and diff
   them against a known-good matrix.
2. **Confirm the handoff came from the same `.sof` as the SPL (D2, §3 stage 2).** If
   a custom `.sof` is paired with a prebuilt bootloader and it dies before the
   U-Boot banner, regenerate the SPL/handoff from *that* `.sof` (or rebuild the
   `.sof` from the bootloader's source revision).
3. **Identify the config mode** (HPS-First vs FPGA-First). It changes who brings up
   DDR and when the fabric is programmed.
4. **Check the boot source** matches the media (`SSBL_BOOT_SOURCE`, U-Boot env,
   partition types). Wrong source = U-Boot prompt but no kernel.
5. **Separate periphery vs core RBF (D3).** A core-only change is safe; a periphery
   change is a boot-chain change requiring a matching bootloader.
6. **Know what programs the FPGA, and when (D4).** With `FPGA_ENABLE_CORE_PGM=1` the
   fabric is programmed by `bootm` from `kernel.itb`; a separately loaded bitstream
   can be silently overwritten.
7. **Debug UART-first.** Find the last stage that emitted output (§3 table) and
   attack that stage's inputs. No UART at all → suspect periphery RBF / device /
   power, not Linux.
8. **Use a magic-ID register (D5)** as a fast "is the fabric alive and addressable?"
   probe once you reach a shell or U-Boot.
9. **Don't rebuild what you can reuse (D7).** Repacking `kernel.itb` (kernel/dtb/RBF
   swap) avoids a full Yocto rebuild and removes a large set of variables while
   bisecting a boot problem.

---

## 6. Open / Not-Yet-Verified
- Exact `kernel.itb` FIT node layout (read with `dumpimage -l` during Phase 1).
- Final Platform Designer-assigned loopback offset (target `0x2001_00A0`).
- Quartus 26.1 Agilex 5 license confirmation.
- Kit SKU note: GHRD says `DK-A5E065BB32AEA` / device `…AE4S` vs the user's
  `DK-A5E065BB32AES1`; baseline boots on this GHRD, so `A5ED065BB32AE4S` is treated
  as authoritative — revisit only if compile/boot fails.

## References
- Agilex 5 E-Series Premium GSRD UG: https://altera-fpga.github.io/latest/embedded-designs/agilex-5/e-series/premium/gsrd/ug-gsrd-agx5e-premium/
- GHRD repo: https://github.com/altera-fpga/agilex5e-ed-gsrd
- meta-altera-fpga (Yocto): https://github.com/altera-fpga/meta-altera-fpga (tag `QPDS26.1_p1_REL_GSRD_PR`)
- Agilex 5 HPS TRM (address map / bridges): https://www.intel.com/content/www/us/en/docs/programmable/814346/current
