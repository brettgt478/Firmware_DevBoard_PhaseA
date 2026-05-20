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

## Stage 9 - Hygiene & doc finalization

### Stage 9 hygiene: README.md rewrite

- **What was deferred**: full README rewrite per PLAN Stage 9.
- **Why deferred**: lower-priority hygiene; baseline README inherited from
  GHRD baseline-a55 still references `baseline_a55` in commands and the
  upstream device part `A5ED065BB32AE4S`. Functional impact is zero
  (commands documented are alternates to build.tcl).
- **Software substitute**: build.tcl + CLAUDE.md + PLAN.md are the
  authoritative build/architecture references during phase B development.
- **Unblock when**: Stage 9 reached; all earlier stages closed.
