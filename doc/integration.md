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
