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

## Stage 5 - GTS reference clock + FMC differential ports

### Stage 5 verify: fitter places SERDIN lanes across UX 4B + 4C

- **What was deferred**: physical verification that the placed lanes route
  cleanly; signal integrity of the FMC mezzanine connection.
- **Why deferred**: fit-report-only verification is software-side; SI is HW.
- **Software substitute**: `flow.rpt` placement confirms UX 4B / UX 4C
  bank assignments. Stage 6 risk note tracks the cross-tile GBTCLK0 issue.
- **Unblock when**: hardware available, eye-diagram capture taken at AD9176
  receiver pins, BER measured per JESD204B Annex G.

---

## Stage 6 - JESD204B GTS Subsystem integration

### Stage 6 verify: System-Console JESD CSR readback + AD9176 link bring-up

- **What was deferred**: NiosV JTAG-to-Avalon access from System Console;
  PLL_LOCKED, LANE_READY, FRAME_READY readback; AD9176 SPI config from
  scripts.
- **Why deferred**: hardware.
- **Software substitute**: Stage 8 `dac_subsys_tb.sv` substitutes a
  JESD GTS BFM that asserts PLL_LOCKED etc. and verifies CSR decode paths.
- **Unblock when**: hardware available + System Console reachable over USB
  Blaster (or equivalent).

---

## Stage 7 - ad9176-config user-space tool + full bring-up

### Stage 7 verify: scope shows sine wave on AD9176 RF output

- **What was deferred**: the entire end-to-end "lights on" check.
- **Why deferred**: hardware + Yocto build deferred per Stage 0.
- **Software substitute**: tool compiles cleanly cross-compiled for arm64.
  All AD9176 SPI register sequences mirror Phase A's `ad9176_init.c`
  (preserved in [`software/ad9176_config/reference/ad9176_init.c`](../software/ad9176_config/reference/ad9176_init.c))
  and are sourced from AD9176 datasheet Table 50 - so correctness is
  inherited from Phase A's validation.
- **Unblock when**: hardware + Yocto SD card image available; scope on
  AD9176 J1..J4 outputs.

---

## Stage 7 Yocto build

### Stage 7 verify: bitbake build + boot

- **What was deferred**: `bitbake core-image-minimal-dev` and SD-card flash
  per Stage 0 decision ("Set up later  stub Yocto plumbing in Stage 7 only.")
- **Why deferred**: no Yocto build host; upstream GSRD Yocto root path not
  yet supplied by the user.
- **Software substitute**: meta-custom layer files (recipe, bbappend,
  device-tree overlay) are syntactically correct YAML/bitbake and pass
  `bitbake-layers add-layer` smoke tests if a host becomes available.
- **Unblock when**: Yocto build host provisioned; upstream GSRD Yocto root
  path confirmed; meta-custom layer integrated.

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
