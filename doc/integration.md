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

## Stage 1 — Repo merge & baseline retarget

PLAN reference: [PLAN.md Stage 1](../PLAN.md#stage-1--repo-merge--baseline-retarget)

### What got deferred

Per Stage 1 verify gate, only **one** hardware test is queued:

> Boot the produced bitstream on the dev kit; baseline Yocto image
> (untouched) reaches login prompt.

(See [deferred_hw_gates.md → Stage 1 verify 5](deferred_hw_gates.md#stage-1-verify-5-baseline-yocto-image-boot).)

A second issue lurks that is NOT in the PLAN's gate list but **must** be
checked the first time the kit is powered on with this firmware: the
EMIF retarget from DDR4-3200 (production) to DDR4-1600 @ 800 MHz (ES SR0)
documented as [ISSUE-011](potential_issues.md#issue-011-es-silicon-hps-emif-retargeted-to-ddr4-1600--800-mhz-dbi-removed).

### Procedure 1.A — Bitstream boot smoke test

**Goal:** confirm the retargeted `.sof` configures the FPGA, the HPS comes
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
   If the build fails on `MEM_OPERATING_FREQ_MHZ`, **stop** —
   [ISSUE-011](potential_issues.md#issue-011-es-silicon-hps-emif-retargeted-to-ddr4-1600--800-mhz-dbi-removed)
   was reverted somewhere.
3. Power on the kit. With JTAG attached, program over JTAG:
   ```bash
   quartus_pgm -m JTAG -c 1 -o "p;output_files/agilex5_devkit.sof"
   ```
4. Open the UART console. Within ~5 seconds expect U-Boot text. If U-Boot
   never appears: HPS EMIF init failed → see Procedure 1.B.
5. **Pass criterion:**
   - Heartbeat LED (top user LED) blinks at ~2 Hz
   - U-Boot prints `## SoC: Altera Agilex 5 Platform` (or similar)
   - UART eventually reaches `Yocto ... login:` prompt
   - No `EMIF calibration FAILED` lines in the boot log

### Procedure 1.B — EMIF DDR4-1600 calibration check

**Goal:** confirm the ES-silicon-stepping EMIF retarget calibrated cleanly
at 800 MHz. If Procedure 1.A's UART prints `EMIF cal FAILED` or
hangs before U-Boot, run this.

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

### Procedure 1.C — Confirm removed DBI pins are inert

**Goal:** the 5 pins formerly assigned to `mem_0_dbi_n[0..4]` (PIN_B119,
AC90, V87, H87, B97) should be floating (high-Z) after the retarget. If
they have residual drive, they could glitch adjacent DDR4 signals.

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

**Goal:** confirm DDR4-1600 @ 800 MHz is stable over a sustained workload
(the production-stepping firmware would have run at DDR4-3200).

**Steps:**

1. Boot Linux on the kit.
2. Run a stress test:
   ```bash
   apt install memtester      # or build from source
   memtester 1024M 5          # 5 passes over 1 GiB
   ```
3. **Pass criterion:** zero errors across 5 passes. Total runtime should
   be ~25 min at 800 MHz; at 1066.667 MHz it would be ~19 min.

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
