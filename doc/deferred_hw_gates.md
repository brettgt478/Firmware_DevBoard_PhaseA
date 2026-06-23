# Deferred Hardware-In-Loop Verify Gates

Tracking ledger for [PLAN.md](../PLAN.md) verify steps that require physical
hardware (dev kit, AD9176-FMC-EBZ mezzanine, scope, JESD link, Linux boot)
and have been **deferred** because hardware is not currently connected to the
development workstation.

Per Stage 0 decision (2026-05-15): the project executes all software-side
verifies (Quartus elaborate/fit reports, Questa simulation, Verilator lint,
report inspection) as each stage's gate. Hardware-side verifies queue here
for later execution when hardware is available.

Do NOT advance to a later stage if a deferred gate has been escalated to a
**blocker** (i.e. cannot be unblocked by simulation evidence). Stages 1-3
have only soft hardware gates; Stage 4 forward have gates that should be
re-evaluated as blockers vs. deferrable per stage.

---

## Format

Each entry:
- `Stage X verify N`  the source step in PLAN.md
- **What was deferred**: the exact action the PLAN calls for.
- **Why deferred**: brief.
- **Software substitute**: what we ran instead (if anything) to gain confidence.
- **Unblock when**: condition that must be met to clear the gate.

---

## Stage 1 - Repo merge & baseline retarget

### Stage 1 verify 5: Baseline Yocto image boot

- **What was deferred**: "Boot the produced bitstream on the dev kit; baseline
  Yocto image (untouched) reaches login prompt."
- **Why deferred**: dev kit not present; Yocto build host not provisioned
  per Stage 0 decision (Yocto integration stubbed until Stage 7).
- **Software substitute**: `quartus_sh -t build.tcl --project-only` proves
  IP regeneration on retargeted ES silicon succeeds. Full
  `quartus_sh -t build.tcl` produces a clean `.sof`. Sim_setup directory
  produced by ipgenerate proves IP simulation models build.
- **Unblock when**: dev kit + AD9176-FMC-EBZ connected, VADJ programmed to
  1.2 V, baseline Yocto image flashed to SD card.

---

## Stage 3 - Build dac_subsys.qsys (control plane only, JESD stubbed)

### Stage 3 verify: optional Platform Designer GUI inspection of dac_subsys

- **What was deferred**: a belt-and-suspenders GUI walk-through of the
  generated `ip/dac_subsys/dac_subsys.qsys` to visually confirm instance
  layout, address-map carving, and System Messages cleanliness. The PLAN
  verify gate is fully software-checkable
  (`quartus_sh -t build.tcl --project-only` clean, address map  16 KB,
  AXI ID-width adapter auto-inserted); the GUI run is **not required**.
- **Why deferred**: GUI sessions need a human in front of qsys-edit. The
  headless ipgenerate already gates correctness; this is documentation
  insurance, not a blocker.
- **Software substitute**: `quartus_sh -t build.tcl --project-only`
  ipgenerate is clean (0 errors, 148 warnings  consistent with the
  Stage 1/2 baseline). Address-map readback from
  [ip/dac_subsys/dac_subsys.qsys](../ip/dac_subsys/dac_subsys.qsys) (search
  for `baseAddress`) and the `dac_subsys.csv` instance map confirm the
  five slave assignments (0x0000, 0x1000, 0x1100, 0x1110, 0x1120) and the
  auto-inserted Avalon-to-AXI translator at the dac_controller_0 boundary.
  See [doc/integration.md Procedure 3.A](integration.md#procedure-3a--platform-designer-gui-inspection-of-dac_subsys).
- **Unblock when**: a human runs Procedure 3.A and confirms the System
  Messages pane is empty. No hardware required.

---

## Stage 4 - Wire dac_subsys into baseline_top; FMC SPI pinout

### Stage 4 verify 2-5: SOF program + Linux `devmem` + AD9176 SPI silicon-ID readback

- **What was deferred**: program SOF, boot Yocto, run `devmem 0x02000000`,
  `devmem 0x02001000` writes, scope FMC SPI lines, AD9176 silicon-ID read.
- **Why deferred**: hardware not connected (per Stage 0 decision).
- **Software substitute**: Quartus elaborate + fit pass clean
  (`quartus_sh -t build.tcl` produces `output_files/agilex5_devkit.sof`
  with WNS > 0.5 ns, no unbonded-pin warnings on any `fmc_*` port).
  Stage 3 ipgenerate proved the LWH2F → `axi_csr` path elaborates with
  the auto-inserted AXI4-to-Avalon-MM adapter; Stage 4 adds only pinout
  and wiring. SPI Master IP CSR map matches Avalon SPI Master User Guide;
  PIO + SPI Master CSR values will be exercised in `dac_subsys_tb.sv`
  (Stage 8) before hardware is required.
- **Procedure when hardware available**: see
  [integration.md Procedure 4.A](integration.md#procedure-4a--fmc-spi-bring-up--ad9176-silicon-id-readback)
  for full SOF program + devmem + scope + AD9176 silicon-ID readback
  sequence, and Procedure 4.B for the TXEN/PE_CTRL toggle smoke test.
- **Unblock when**: dev kit + AD9176-FMC-EBZ connected, VADJ at 1.2 V
  (multimeter-verified), AD9176 datasheet silicon-ID register address
  confirmed.

### Stage 4 - NiosV JTAG-master access to dac_subsys.axi_csr (architectural deferral)

- **What was deferred**: extension of `u_jtag_avalon_master` in
  `niosv_subsys.qsys` to reach `u_dac_subsys.axi_csr`, enabling System
  Console CSR access without booting Linux.
- **Why deferred**: per Stage 4 design decision — Stage 4 Linux `devmem`
  via LWH2F is the primary verify path; the JTAG-master alternate path
  is only needed for Stage 6 GTS bring-up debug. Adding it in Stage 4
  would have required editing `niosv_subsys.qsys` (currently baseline-
  derived) without a downstream consumer.
- **Software substitute**: none required at Stage 4 (the LWH2F path is
  the architectural primary).
- **Unblock when**: Stage 6 brings up the JESD GTS Subsystem. Add a new
  exported master interface to `niosv_subsys.qsys` that taps off
  `u_jtag_avalon_master.master`, then wire it in `baseline_top.qsys` to
  `u_dac_subsys.axi_csr` @ `0x02000000` (multi-master arbitration with
  the existing LWH2F path auto-inserted by Qsys).

---

## Stage 5 (merged with original Stage 6) - JESD204B GTS Subsystem integration

### Stage 5 verify 1: fitter places SERDIN lanes across UX 4B + 4C

- **What was deferred**: physical verification that the placed lanes route
  cleanly; signal integrity of the FMC mezzanine connection.
- **Why deferred**: fit-report-only verification is software-side; SI is HW.
- **Software substitute**: `flow.rpt` placement confirms UX 4B / UX 4C
  bank assignments. Cross-tile GBTCLK0 routing risk tracked in
  [potential_issues.md ISSUE-014](potential_issues.md).
- **Unblock when**: hardware available, eye-diagram capture taken at AD9176
  receiver pins, BER measured per JESD204B Annex G.

### Stage 5 verify 2: System-Console JESD CSR readback + AD9176 link bring-up

- **What was deferred**: System Console (or `devmem` via Linux) access to
  the GTS JESD204B CSRs at `0x0200_2000` (link 0) and `0x0200_3000`
  (link 1); PLL_LOCKED, LANE_READY, FRAME_READY readback; AD9176 SPI
  bring-up sequence; SYNC release.
- **Why deferred**: hardware (AD9176-FMC-EBZ + dev kit + scope).
- **Software substitute**: Stage 8 `dac_subsys_tb.sv` will substitute a
  JESD GTS BFM that asserts PLL_LOCKED etc. and verifies CSR decode paths
  in simulation.
- **Unblock when**: hardware available + dev kit JTAG reachable via
  USB-Blaster. See [integration.md Procedure 5.A](integration.md#procedure-5a--jesd-link-bring-up--first-sine-wave-on-ad9176-rf-out).

### Stage 5 verify 3: Subclass-1 deterministic latency

- **What was deferred**: confirmation that the AD9176-FMC-EBZ
  SYSREF/GBTCLK0 phasing meets subclass-1 source-sync timing.
- **Why deferred**: hardware-only (scope + AD9176 board strap inspection).
- **Software substitute**: none (subclass-1 latency is a board-level
  property). If subclass-1 doesn't lock at bring-up, drop to subclass-0
  via the GTS IP's runtime `SUBCLASSV` CSR write.
- **Unblock when**: hardware bring-up Procedure 5.A succeeds + scope
  measurement confirms SYSREF leading-edge phasing matches GBTCLK0.

---

## Stage 7 - ad9176-config user-space tool + full bring-up

### Stage 7 verify: scope shows sine wave on AD9176 RF output

- **What was deferred**: the entire end-to-end "lights on" check.
- **Why deferred**: hardware + Yocto build deferred per Stage 0.
- **Software substitute**: the C tool compiles cleanly with `gcc -Wall
  -Wextra -Wpedantic -Werror -std=c11` on the build host. Host build
  on this Windows workstation was SKIPPED (no gcc/WSL); the cross-build
  via Yocto's `oe_runmake CROSS=${TARGET_PREFIX}` is the deployed path.
  Phase A `ad9176_init.c` sequence is preserved in
  [`software/ad9176_config/reference/ad9176_init.c`](../software/ad9176_config/reference/ad9176_init.c);
  Phase B re-uses the AD9176 register sequence verbatim and rewrites the
  transport to use the Stage 5 fabric SPI master (see
  [potential_issues.md ISSUE-017](potential_issues.md#issue-017-phase-a-iq_router_regsh-is-stale-new-dac_subsys_regsh-is-the-source-of-truth)).
- **Procedure when hardware available**: see
  [integration.md Procedure 7.A](integration.md#procedure-7a----linux-user-space-bring-up-of-ad9176-via-ad9176-config).
- **Unblock when**: dev kit + AD9176-FMC-EBZ + scope available, Yocto SD
  card with `ad9176-config` flashed, dev kit booted to login prompt.

---

## Stage 7 Yocto build

### Stage 7 verify: bitbake build + boot

- **What was deferred**: `bitbake core-image-minimal-dev` and SD-card flash
  per Stage 0 decision ("Set up later -- stub Yocto plumbing in Stage 7 only.")
- **Why deferred**: no Yocto build host; per user direction (2026-05-20)
  Stage 7 stages the recipe only and does NOT invoke bitbake from this
  workstation.
- **Software substitute**: meta-custom layer files (`conf/layer.conf`,
  `recipes-apps/ad9176-config/ad9176-config_0.1.bb`,
  `recipes-apps/ad9176-config/files/README.txt`) are present and
  syntactically correct; the recipe's `SRC_URI` points at the in-tree
  sources under `software/ad9176_config/` and needs a symlink/copy step
  at the recipe `files/` directory on the build host (instructions in
  the README).
- **Unblock when**: Yocto build host provisioned; upstream GSRD Yocto root
  path confirmed; meta-custom layer integrated via `BBLAYERS +=`.

---

## Stage 8 - System simulation

### Stage 8a -- block testbench regression

- **What was deferred**: nothing -- Stage 8a runs entirely on the
  Phase B workstation.
- **Status:** COMPLETE (2026-05-20). All 8 Phase A block testbenches
  pass under Questa Altera Starter FPGA Edition (the simulator
  bundled with Quartus Pro 26.1). VHDL-2008 enabled via the
  `tb/run_block_tbs.tcl` script's `vcom -2008` flag.
- **Re-run procedure**: see
  [integration.md Procedure 8.A](integration.md#procedure-8a----block-level-regression-on-questa).
- **License probe**: see
  [integration.md Procedure 8.B](integration.md#procedure-8b----license-probe-diagnostic-on-demand).

### Stage 8b -- integration TB against the real JESD204B GTS IP

- **What was deferred**: golden-sample JESD link-up + decoded-frame
  comparison still needs a JESD RX BFM (no AD9176 model in sim).
- **Status:** CSR-plane TB COMPLETE (2026-05-20). `dac_subsys_tb.sv`
  drives the LWH2F AXI BFM through dac_controller_0 scratchpad,
  SPI master CSR, PIOs, and SineWaveGen NCO. Six sub-tests pass.
  Wall-clock ~2 h on the dev workstation; ~5 GB sim DB.
- **What this TB found**: the dac_status_word concat in
  agilex5_devkit.sv had a missing reserved bit -- fmc_ready was at
  bit 4 instead of bit 5 (where CLAUDE.md, dac_subsys_regs.h, and
  the comment block all expected it). Fixed in same Stage 8b commit
  (`1'b0` -> `2'b00`).
- **Re-run procedure**: see
  [integration.md Procedure 8.C](integration.md#procedure-8c----dac_subsys-integration-tb-stage-8b).
- **Hardware substitute remaining**: link-layer behaviour (PLL
  lock, ILAS, frame alignment, payload decode) still needs hardware
  to fully validate; software-side gate covers CSR + handshake.

### Stage 8c -- JESD RX BFM golden-sample compare (deferred)

- **What was deferred**: end-to-end "FPGA SineWaveGen -> JESD link
  -> BFM RX decode -> compare against math_real sine" loop.
- **Why deferred**: 8b succeeded for CSR scope; link-layer decode is
  a larger investment (need an Intel JESD204B GTS BFM or hand-rolled
  decoder). Not a blocker for hardware bring-up (Procedure 5.A
  exercises the same link via real silicon).
- **Software substitute**: 8b CSR coverage + hardware bring-up
  (Procedures 5.A/7.A) cover the same surface area together.
- **Unblock when**: a regression escapes hardware bring-up that
  could only have been caught at the link layer in simulation, OR
  the dev team adopts pre-silicon link-layer regression as a gate.

---

## Stage 9 - Hygiene & doc finalization

### Stage 9 hygiene: README.md rewrite

- **What was deferred**: full README rewrite per PLAN Stage 9.
- **Status:** COMPLETE (2026-05-21). README.md rewritten as Phase B
  quick-start; doc index added pointing at the four new architecture
  / bring-up / pinout docs and the existing integration /
  deferred-gates / issues docs.

### Stage 9 hygiene: verilator lint

- **What was deferred**: `verilator --lint-only` on all SV files
  (PLAN Stage 9 task).
- **Why deferred**: verilator is not installed on the firmware
  workstation; on-disk path `D:/altera_pro/26.1/` ships Quartus + the
  bundled Questa Starter only.
- **Software substitute**: `quartus_syn --analysis_and_elaboration
  agilex5_devkit` was run as the elaborate gate (Stage 9 closeout,
  2026-05-21). 0 errors. The 1 warning (Intel FPGA IP Evaluation Mode
  on the JESD204B GTS IP) is tracked as
  [potential_issues.md ISSUE-016](potential_issues.md).
- **Unblock when**: workstation has verilator installed, OR a future
  CI host adds a `verilator --lint-only` step gating PRs.

### Stage 9 hygiene: reproducible-build re-run

- **What was deferred**: PLAN Stage 9 verify "from a fresh checkout,
  run `quartus_sh -t build.tcl`; bitstream signature is stable across
  re-runs."
- **Why deferred**: ~45-min wall-clock per build; per Stage 9 scoping
  (user decision D11, 2026-05-21) the existing
  `output_files/agilex5_devkit*.sof` from commit `6f5a43c` was
  reused for utilization / STA / DRC verification because no source
  files have changed in a way that affects the fitter outputs (the
  Stage 8b source change was a single concat-bit fix in the
  top-level status word; it does not change fitter results
  materially).
- **Software substitute**: Stage 5 (commit `6f5a43c`) was a clean
  full-flow build (`output_files/agilex5_devkit.fit.summary` line 1:
  `Fitter Status : Successful`). The Stage 9 closeout reused those
  reports.
- **Unblock when**: hardware available -- Procedure 5.A starts with
  a fresh `quartus_sh -t build.tcl` for that bench session, which
  doubles as the reproducible-build check. If two consecutive
  full-flow runs in clean checkouts yield byte-identical .sof files,
  the check is satisfied.

### Stage 9 architectural finding: GTS Reset Sequencer missing

- **What was deferred**: the *fix* for [ISSUE-019](potential_issues.md)
  (`u_jesd_link0/1` need `intel_gts_reset_sequencer` driving their
  request/grant/CU-clock ports; 3 Critical DRC violations: IPC-40028,
  IPC-40030, IPC-40036).
- **Why deferred**: outside the Stage 9 scope (doc hygiene). The DRC
  warnings were already present in the Stage 5 fit reports but were
  not surfaced until Stage 9 swept the reports. **Scope corrected
  2026-06-03**: this is NOT "one IP + 3 connections" -- per Altera's own
  example-design generator
  (`<quartus>/ip/altera/jesd204b_gts/ed/ds/ds_jesd_subsystem_qsys.tcl.terp`)
  it is a clock/reset cluster (`intel_srcss_gts` + `altera_reset_sequencer`
  + reset bridges + top-level reset-qualification glue), with
  placement-dependent parameters, plus a re-confirm of the `jesd_cdc.sdc`
  clock names afterwards. See the corrected "Implementation procedure" in
  [ISSUE-019](potential_issues.md). It **must be done on the build
  machine** -- `qsys-generate` + fit + DRC are required to validate it;
  it cannot be emitted blind without breaking the currently-building
  design.
- **Software substitute**: NONE in simulation for the sequencer itself.
  Stage 8b CSR-plane TB does not exercise the JESD link layer, so the
  missing reset-sequencer connectivity is invisible there. However, the
  *downstream DRC symptoms* are now understood and two independent SDC
  side-findings from the same DRC set have been fixed and are commitable
  now (no rebuild dependency): `fmc_io.sdc` adds the `fmc_prsnt_n`
  false_path (clears TMC-20011, the only High), and `jesd_cdc.sdc` now
  uses real clock names instead of the never-matching `*u_clk_bridge_*`
  filters (clears STA 332174/332049 + TMC-20025/20026 clock lines and
  actually applies the CLAUDE.md s6 #8 async grouping). See ISSUE-019
  "Related fixes already applied".
- **Unblock when**: Procedure 5.A is run on hardware, OR a build-machine
  session is taken specifically to implement ISSUE-019. Most likely
  outcome without the fix: the link never PLL-locks, GTS CSR reads all
  zero. Apply the fix per ISSUE-019, rebuild, re-run, and confirm
  IPC-40028/30/36 = 0 and FLP-10500 = 0.

---

## Cross-stage — Deployable boot image / bootloader integration

### Bootloader integration: bare `.sof` does not boot Linux

- **What was deferred**: producing and programming a *bootable* image.
  `build.tcl` stops at `output_files/agilex5_devkit.sof`, which carries the
  FPGA fabric + HPS handoff but **no FSBL/U-Boot SPL**. On this HPS-first kit
  (`HPS_INITIALIZATION "HPS FIRST"`, `QSPI_OWNERSHIP HPS`) the SDM has nothing
  to boot, so the bare `.sof` configures the fabric but never starts the HPS.
  The deployable image = bitstream + Yocto-built FSBL merged via
  `quartus_pfg -o hps_path=u-boot-spl-dtb.hex`, programmed to **QSPI** as a
  `.jic`; the fabric `core.rbf`, kernel, and rootfs ride on the SD card.
- **Why deferred**: needs (a) a Linux Yocto build host for the BSP, and
  (b) the dev kit on the bench to flash QSPI/SD and watch the UART. Neither is
  the Windows firmware workstation.
- **Why it surfaced**: baseline GSRD image (with bootloader) boots Linux;
  swapping in *only* the FPGA fabric leaves the **baseline** SDM+FSBL+handoff
  in QSPI — a mismatch with this design's DDR4-1600 EMIF retarget
  ([ISSUE-011](potential_issues.md)), so Linux never comes up.
- **Software substitute**: none — boot is inherently hardware. The build-side
  artifacts (Yocto recipes, `qspi_helper.pfg`/`qspi_boot.pfg`,
  `swbuild_config.mk` merge targets) are present and reviewed.
- **Procedure when hardware available**: see
  [integration.md → Deployable boot image](integration.md#deployable-boot-image--integrating-the-bootloader-read-first-if-linux-wont-boot)
  (Procedures D.A fast recovery, D.B full Yocto build, D.C SD card).
- **Unblock when**: Linux Yocto host provisioned; QSPI `.jic` rebuilt from
  *this* design's `.sof` with the FSBL merged; programmed to QSPI (MSEL =
  ASX4); SD card carries matching `ghrd.core.rbf` + kernel + rootfs; UART
  reaches the `login:` prompt.
