# PLAN.md — Phase B Implementation Plan

Comprehensive stage-by-stage plan for building the deployable firmware on the DK-A5E065BB32AES1 Agilex 5 dev kit driving an AD9176-FMC-EBZ over JESD204B mode 4. Treat this as the engineering script of record; the per-stage *verify* gates are the contract between stages.

For the rationale and high-level architecture see [CLAUDE.md](CLAUDE.md). Phase A's design description (preserved verbatim) is at [doc/phase_a_design_description.md](doc/phase_a_design_description.md).

---

## Context

We have a working Phase A IP — `dac_controller_0` — that already streams two JESD204B mode-4 links of sine-wave IQ into the AD9176, validated at the block level. It exists as VHDL-2008 RTL only ([D:\Firmware_PhaseA\src\](D:\Firmware_PhaseA\src), 10 modules, 8 testbenches) with **no Quartus project, no Platform Designer system, no pin assignments, and no build scripts**. It targets device `A5ED052AB32AI2E`; our dev kit is `A5ED065BB32AE6SR0`.

Phase B wraps that IP into a complete dev-board project that boots Yocto Linux, configures the AD9176 over fabric SPI, brings up JESD links, and emits the Phase A sine wave on the AD9176 RF outputs. The structural backbone is Altera's GSRD baseline-a55 reference at [D:\agilex5e-ed-gsrd-main\a5ed065b-premium-devkit-debug2\baseline-a55\](D:\agilex5e-ed-gsrd-main\a5ed065b-premium-devkit-debug2\baseline-a55).

### Decisions taken (do not relitigate)

| # | Decision |
|---|----------|
| D1 | AD9176 SPI is driven by a fabric Avalon SPI Master IP on LWS2F. HPS bit-bang is scrapped. |
| D2 | HPS software is Linux user-space under the GSRD Yocto build (`ad9176-config` mmap's `/dev/mem`). |
| D3 | Phase A is merged into Phase B at [D:\Firmware_DevBoard_PhaseA\](D:\Firmware_DevBoard_PhaseA). Live work happens here; [D:\Firmware_PhaseA\](D:\Firmware_PhaseA) is the archival snapshot. |
| D4 | One AD9176 only — Links 0/1 wired, 8 FMC TX lanes. Links 2/3 RTL stays unbonded. |

---

## Stage 1 — Repo merge & baseline retarget

**Goal.** Establish the merged repo and prove the unmodified GHRD baseline still builds and boots on our ES silicon. This is the floor we add features onto.

### Files created or modified

| Action | Path |
|--------|------|
| create dir tree | per [CLAUDE.md §4](CLAUDE.md) layout |
| copy | `D:\agilex5e-ed-gsrd-main\a5ed065b-premium-devkit-debug2\baseline-a55\*` → [projects/agilex5_devkit/](projects/agilex5_devkit/) |
| rename | `baseline_a55.qpf` → `agilex5_devkit.qpf` |
| rename | `baseline_a55.qsf` → `agilex5_devkit.qsf` |
| rename | `baseline_a55.sv` → `agilex5_devkit.sv` |
| rename | `baseline_a55.sdc` → `agilex5_devkit.sdc` |
| edit qsf | line 34: `DEVICE A5ED065BB32AE4S` → `DEVICE A5ED065BB32AE6SR0` |
| edit qsf | `TOP_LEVEL_ENTITY baseline_a55` → `TOP_LEVEL_ENTITY agilex5_devkit` |
| edit qsf | append `IP_SEARCH_PATHS ../../ip/*/**/*` for vendored IP |
| edit Makefile | `PROJECT_NAME := baseline_a55` → `agilex5_devkit` and reference targets |
| vendor RTL | [D:\Firmware_PhaseA\src\\*.vhd](D:\Firmware_PhaseA\src) → [ip/dac_controller_0/src/](ip/dac_controller_0/src/) |
| vendor TBs | [D:\Firmware_PhaseA\tb\\*.vhd](D:\Firmware_PhaseA\tb) → [tb/](tb/) |
| vendor docs | [D:\Firmware_PhaseA\doc\\*](D:\Firmware_PhaseA\doc) → [doc/](doc/) (preserve as `phase_a_*`) |
| create | [projects/agilex5_devkit/build.tcl](projects/agilex5_devkit/build.tcl) (entry script) |

### `build.tcl` contract

```tcl
# build.tcl — entry point for Phase B Quartus build
# Cleans previous outputs, then invokes IP gen + full compile (or --project-only).

set project_only 0
foreach arg $::argv {
  if {$arg eq "--project-only"} { set project_only 1 }
}

# Hard clean — prevent stale artifact builds
foreach d {output_files db incremental_db qdb ip/dac_subsys ip/dac_controller_0/dac_controller_0} {
  if {[file exists $d]} { file delete -force $d }
}

# Regenerate qsys + IP
exec quartus_ipgenerate --generate_project_ip_files agilex5_devkit.qpf

if {$project_only} { exit 0 }

# Full compile flow
exec quartus_sh --flow compile agilex5_devkit.qpf
```

### Commands

```bash
cd projects/agilex5_devkit
quartus_sh -t build.tcl --project-only        # IP/qsys regen only
quartus_sh -t build.tcl                       # full flow
```

### Verification

- `output_files/agilex5_devkit.sof` exists.
- `output_files/agilex5_devkit.fit.summary` shows the design fit without timing violations.
- All ES-silicon warnings are reviewed and benign (record in [doc/potential_issues.md](doc/potential_issues.md) if any).
- Phase A block testbenches run end-to-end via Questa from [tb/](tb/) with `SIMULATION PASSED`.
- Boot the produced bitstream on the dev kit; baseline Yocto image (untouched) reaches login prompt.

### Rollback

If retargeting to `A5ED065BB32AE6SR0` produces unrecoverable IP regeneration errors, revert the device line to `A5ED065BB32AE4S` and treat the ES-silicon-vs-production discrepancy as a separate blocker logged in `potential_issues.md`.

### Stage 1 risks

- ES-silicon-only DRC errors in `hps_subsys` or `emif_io96b_hps` IP regen → expect at most warnings; if errors, escalate before proceeding.

### Stage 1 status (2026-05-15)

**Complete.** Software-side verify gates passed: `quartus_sh -t build.tcl --project-only` clean (0 errors, 146 warnings — all ES-silicon stepping-mismatch related, all benign); Phase A block testbenches 8/8 `SIMULATION PASSED` via Questa (see [tb/run_block_tbs.tcl](tb/run_block_tbs.tcl)). Baseline Yocto boot deferred per [doc/deferred_hw_gates.md](doc/deferred_hw_gates.md).

**Deviation:** the predicted Stage 1 risk fired — the 065B baseline EMIF was configured for DDR4-3200 @ 1066.667 MHz, which exceeds the ES SR0 silicon cap of 800 MHz. Resolved by swapping in the ES-variant `emif_io96b_hps.ip` (DDR4-1600 @ 800 MHz) and stripping the DBI plumbing it doesn't export (`mem_0_dbi_n` removed from `hps_subsys.qsys`, `baseline_top.qsys`, `agilex5_devkit.sv`, and 5 pin assignments in the qsf). Documented as [ISSUE-011](doc/potential_issues.md). Also normalized `IP_SEARCH_PATHS` to `**/*` glob style to satisfy the ES IP's stricter path validation.

---

## Stage 2 — Wrap Phase A as a Platform Designer IP component

**Goal.** Make `dac_controller_0` instantiable from Platform Designer; no Qsys edits yet.

### Files created or modified

| Action | Path |
|--------|------|
| create | [ip/dac_controller_0/dac_controller_0_hw.tcl](ip/dac_controller_0/dac_controller_0_hw.tcl) |
| reuse  | [ip/dac_controller_0/src/dac_controller_0.vhd](ip/dac_controller_0/src/dac_controller_0.vhd) and 9 siblings |

### `dac_controller_0_hw.tcl` interface declarations

Declare the following interfaces, with port mappings verified against [ip/dac_controller_0/src/dac_controller_0.vhd:43-162](ip/dac_controller_0/src/dac_controller_0.vhd):

| Interface group | Type | Notes |
|-----------------|------|-------|
| `lwhpm2fpga` | AXI4 slave | 4-bit ID, 10-bit addr, 32-bit data; associated clock `clock_sink`, reset `reset_sink` |
| `clock_sink` | clock sink | drives AXI + reg_bank |
| `jesd_tx_link_clk` | clock sink | drives JESD framers |
| `reset_sink` | reset sink | active-high synchronous |
| `jesd_link0_data` | AVST source | 128-bit data, ready+valid, no channels; associated clock `jesd_tx_link_clk` |
| `jesd_link1_data` | AVST source | 128-bit data, ready+valid; associated clock `jesd_tx_link_clk` |
| `jesd_link0_status` | conduit | `somf[3:0]` in, `frame_error` out, `frame_ready` in |
| `jesd_link1_status` | conduit | `frame_error` out, `frame_ready` in |
| `jesd_reset_seq` | conduit | `in_of_reset` in, `rst_n` out, `rst_ack_n` in |
| `jesd_refclk_ctrl` | conduit | `txphy_clk[3:0]` in, `rs_priority[3:0]` out, `refclk_fail_status[7:0]` in, `refclk_on_ack` in, `refclk_on[9:0]` out, `core_pll_locked` in |
| `jesd_csr_readback` | conduit | HD, CS, L, K, N, NP, S, CF, F, M, DLB_DATA, DLB_KCHAR, TESTMODE, TESTPATTERN_A..D (all in) |
| `pio_control` | conduit | 32-bit in (stubbed) |
| `pio_status` | conduit | 32-bit out (stubbed) |
| `tx_enbl` | conduit | 1-bit in (stubbed) |

Use Intel's `_hw.tcl` boilerplate; declare the file set with `add_fileset_file dac_controller_0.vhd VHDL PATH src/dac_controller_0.vhd TOP_LEVEL_FILE` and add each of the 9 supporting VHDL files.

### Commands

```bash
cd projects/agilex5_devkit
quartus_sh -t build.tcl --project-only
# Open Platform Designer GUI to visually confirm the new IP, OR
qsys-script --quartus-project=agilex5_devkit.qpf --cmd=\
  "load_component_descriptor ../../ip/dac_controller_0/dac_controller_0_hw.tcl"
```

### Verification

- `quartus_ipgenerate` completes without errors.
- Platform Designer renders the new component with interface groups colored; no parameter validation warnings.
- Phase A block testbenches still pass — vendoring didn't break VHDL paths.

### Rollback

Delete `ip/dac_controller_0/dac_controller_0_hw.tcl`; the component disappears from the catalog. RTL itself is unchanged from Phase A and need not be reverted.

### Stage 2 risks

- AXI4 slave with 4-bit ID may need an `axi_id_width_adapter` insertion at the next stage. Qsys handles this automatically; verify in Stage 3 generate logs.

### Stage 2 status (2026-05-15)

**Complete.** [ip/dac_controller_0/dac_controller_0_hw.tcl](ip/dac_controller_0/dac_controller_0_hw.tcl) created with 14 interface groups (clock_sink, jesd_tx_link_clk, reset_sink, lwhpm2fpga (AXI4 slave, 4-bit ID, 10-bit address, 32-bit data), jesd_link0_data + jesd_link1_data (Avalon-ST sources, 128-bit), jesd_link0_status + jesd_link1_status (conduits), jesd_reset_seq, jesd_refclk_ctrl, jesd_csr_readback, pio_control, pio_status, tx_enbl) and the `G_LUT_DEPTH` generic exposed as an HDL parameter. Verified by `quartus_sh -t build.tcl --project-only` (0 errors, 146 warnings — identical to Stage 1 baseline, no new component-load warnings); Phase A block testbenches still 8/8 SIMULATION PASSED. Used `package require -exact qsys 14.0` per Intel convention.

---

## Stage 3 — Build `dac_subsys.qsys` (control plane only, JESD stubbed)

**Goal.** End-to-end CSR path: Linux `devmem` writes reach `dac_controller_0` registers. JESD/FMC stays out of the loop.

### Files created or modified

| Action | Path |
|--------|------|
| create | [ip/dac_subsys/dac_subsys.qsys](ip/dac_subsys/dac_subsys.qsys) |

### Qsys component inventory

| Instance | IP | Notes |
|----------|----|-------|
| `u_dac_controller_0` | `dac_controller_0` | from Stage 2 |
| `u_spi_master` | `altera_avalon_spi` (Avalon-MM SPI Master) | 2 CS, mode 0, 25 MHz tx rate, 24-bit transfers |
| `u_tx_en_pio` | `altera_avalon_pio` | 2-bit output |
| `u_pe_ctrl_pio` | `altera_avalon_pio` | 1-bit output |
| `u_dac_status_pio` | `altera_avalon_pio` | 32-bit input, with edge-capture for transient bits |
| `u_clk_bridge_axi` | `altera_clock_bridge` | exports `clock_sink_clk` from outside the subsystem |
| `u_clk_bridge_jesd` | `altera_clock_bridge` | exports `jesd_tx_link_clk` from outside |
| `u_rst_bridge_axi` | `altera_reset_bridge` | HPS reset → AXI domain |
| `u_rst_bridge_jesd` | `altera_reset_bridge` | system reset → JESD domain |

### Address map inside `dac_subsys`

| Offset | Slave | Span |
|--------|-------|------|
| 0x0000 | `u_dac_controller_0.lwhpm2fpga` | 1 KB |
| 0x1000 | `u_spi_master.s1` | 64 B |
| 0x1100 | `u_tx_en_pio.s1` | 16 B |
| 0x1110 | `u_pe_ctrl_pio.s1` | 16 B |
| 0x1120 | `u_dac_status_pio.s1` | 16 B |
| 0x2000 | (reserved for JESD GTS Subsystem in Stage 6) | 8 KB |

Aggregate everything onto a single Avalon-MM slave exported as `axi_csr`. (We use AXI4-Lite as the external face if the LWH2F master is wider; otherwise expose AXI4 directly.) Carve the LWS2F window allocation at the Stage 4 step in `baseline_top.qsys`.

### JESD stub

The two AVST source pairs and JESD conduits from `u_dac_controller_0` are connected to **synthesis-only AVST sinks and dummy zero/floating drivers inside the subsystem** so `dac_subsys.qsys` builds standalone. Tag these with a comment block `-- JESD STUB - REMOVE IN STAGE 6 --` to make replacement trivial.

### Commands

```bash
cd projects/agilex5_devkit
quartus_sh -t build.tcl --project-only
```

### Verification

- Qsys generation reports zero errors.
- `output_files/agilex5_devkit.ipgen.rpt` shows the new `u_dac_subsys` component with the address map carving above and total span ≤ 16 KB.
- Verify the AXI4 ID width adapter (if any) is inserted with `set_property automatic` — no manual fixups required.

### Rollback

Delete `ip/dac_subsys/`. `agilex5_devkit.qsf` does not yet reference it.

### Stage 3 risks

- LWH2F master ID width unknown until Qsys reports it; if Qsys cannot adapt automatically, insert an explicit `axi_id_width_adapter` between LWH2F and `u_dac_subsys.axi_csr`.
- SPI master IP requires an external SCK frequency — generate from the 100 MHz `clock_sink_clk` via the IP's internal divider, not from a new PLL.

---

## Stage 4 — Wire `dac_subsys` into `baseline_top.qsys`; FMC SPI pin-out

**Goal.** First hardware-runnable build with FMC SPI pins active. Verify AD9176 SPI silicon-ID readback over the scope.

### Files modified

| Action | Path |
|--------|------|
| edit | [projects/agilex5_devkit/baseline_top.qsys](projects/agilex5_devkit/baseline_top.qsys) — add `u_dac_subsys` |
| edit | [projects/agilex5_devkit/niosv_subsys.qsys](projects/agilex5_devkit/niosv_subsys.qsys) — extend `jtag_master` address span to reach `dac_subsys.axi_csr` |
| edit | [projects/agilex5_devkit/agilex5_devkit.sv](projects/agilex5_devkit/agilex5_devkit.sv) — add FMC SPI + control ports + housekeeping |
| edit | [projects/agilex5_devkit/agilex5_devkit.qsf](projects/agilex5_devkit/agilex5_devkit.qsf) — add FMC pin locations + IO standards + IP file for dac_subsys |
| add  | `set_global_assignment -name QSYS_FILE ../../ip/dac_subsys/dac_subsys.qsys` |

### `baseline_top.qsys` wiring

```
u_fabric_subsys.lwhps2fpga_bridge.m0      → u_dac_subsys.axi_csr     @ offset 0x0200_0000 (16 KB)
u_niosv_subsys.jtag_avalon_master         → u_dac_subsys.axi_csr     (multi-master arbitration auto)
u_shell_subsys.system_clock_out           → u_dac_subsys.clock_sink_clk
u_shell_subsys.system_reset_out           → u_dac_subsys.reset_sink_reset
```

JESD-side clock/reset will land in Stage 6.

### Top-level port additions in `agilex5_devkit.sv`

```systemverilog
// FMC SPI bus (HSIO 3B, 1.2-V LVCMOS)
output logic fmc_spi_sck,
output logic fmc_spi_mosi,
input  logic fmc_spi_miso,
output logic fmc_spi_cs1_n,
output logic fmc_spi_cs2_n,
output logic fmc_spi_en,

// FMC control GPIOs (HSIO 3B, 1.2-V LVCMOS)
output logic [1:0] fmc_txen,
output logic fmc_pe_ctrl,

// FMC housekeeping (3.3-V LVCMOS)
input  logic fmc_prsnt_n,
input  logic fmc_pg_m2c,
output logic fmc_pg_c2m,
input  logic [1:0] fmc_ga,
```

Wire to `u_dac_subsys` conduits exported through `baseline_top.qsys`. `fmc_pg_c2m` drives a tied-high register controlled by HPS through the PIO once FPGA fabric is up.

### `agilex5_devkit.qsf` pin assignments (Stage 4 additions)

```tcl
# FMC SPI bus — HSIO 3B (1.2-V LVCMOS)
set_location_assignment PIN_G9  -to fmc_spi_sck
set_location_assignment PIN_G10 -to fmc_spi_mosi
set_location_assignment PIN_H10 -to fmc_spi_miso
set_location_assignment PIN_H11 -to fmc_spi_cs1_n
set_location_assignment PIN_D11 -to fmc_spi_cs2_n
set_location_assignment PIN_D12 -to fmc_spi_en
set_instance_assignment -name IO_STANDARD "1.2-V LVCMOS" -to fmc_spi_sck
# (repeat IO_STANDARD for the other 5 SPI pins)

# FMC control GPIOs — HSIO 3B (1.2-V LVCMOS)
set_location_assignment PIN_C10 -to fmc_txen[0]
set_location_assignment PIN_C11 -to fmc_txen[1]
set_location_assignment PIN_H13 -to fmc_pe_ctrl
set_instance_assignment -name IO_STANDARD "1.2-V LVCMOS" -to fmc_txen[0]
set_instance_assignment -name IO_STANDARD "1.2-V LVCMOS" -to fmc_txen[1]
set_instance_assignment -name IO_STANDARD "1.2-V LVCMOS" -to fmc_pe_ctrl

# FMC housekeeping — 3.3-V LVCMOS
set_location_assignment PIN_H2  -to fmc_prsnt_n
set_location_assignment PIN_F1  -to fmc_pg_m2c
set_location_assignment PIN_D1  -to fmc_pg_c2m
set_location_assignment PIN_D35 -to fmc_ga[1]
set_location_assignment PIN_C34 -to fmc_ga[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to fmc_prsnt_n
# (repeat for the other housekeeping signals)
```

### Pre-build hardware check

**FMC VADJ MUST be programmed to 1.2 V on the dev kit before applying the bitstream.** Use the kit's `vadj` utility (or jumper, per dev-kit user guide §4) and verify with a multimeter at the FMC pin or VADJ test point. Driving 1.2-V LVCMOS into an unset (often 2.5 V default) FMC carrier will damage HSIO 3B.

### Commands

```bash
cd projects/agilex5_devkit
quartus_sh -t build.tcl
# Program:
quartus_pgm -m JTAG -c 1 -o "p;output_files/agilex5_devkit.sof"
```

### Verification

- Quartus fit passes; no unbonded-pin warnings.
- Load `.sof`; boot Yocto Linux.
- From Linux shell: `devmem 0x02000000` returns `dac_controller_0.ID` register (Phase A reg_bank ID, see [ip/dac_controller_0/src/reg_bank.vhd](ip/dac_controller_0/src/reg_bank.vhd)).
- `devmem 0x02001000` writes drive `u_spi_master` CSR; a scope on `fmc_spi_sck` (G9) shows the 25 MHz clock; on `fmc_spi_mosi` shows the data pattern.
- AD9176 silicon ID read sequence: write `0x80_00_00` to SPI master, read back; expected silicon ID per AD9176 datasheet.

### Rollback

Comment out the `set_global_assignment -name QSYS_FILE ../../ip/dac_subsys/dac_subsys.qsys` line; the build reverts to bare baseline.

### Stage 4 risks

- LA pin location typos cause permanent FMC damage — **double-check every pin against [Agilex_FMC_Pinout.txt](Agilex_FMC_Pinout.txt) and [AD9176_Dev_Pinout.txt](AD9176_Dev_Pinout.txt) before applying VADJ**.
- HSIO 3B drive strength default may be too high for 1.2-V LVCMOS — limit to 8 mA in qsf.

---

## Stage 5 — Add GTS reference clock + FMC differential ports (no JESD IP yet)

**Goal.** Fitter accepts GBTCLK0 as a transceiver reference clock; all JESD-related diff pairs are placed; SDC declares clock and timing relationships.

### Files modified

| Action | Path |
|--------|------|
| edit | [projects/agilex5_devkit/agilex5_devkit.sv](projects/agilex5_devkit/agilex5_devkit.sv) — add GBTCLK, SYSREF, SYNC, SERDIN ports (stub-driven for now) |
| edit | [projects/agilex5_devkit/agilex5_devkit.qsf](projects/agilex5_devkit/agilex5_devkit.qsf) — add GBTCLK + LVDS + SERDIN pin assignments |
| create | [projects/agilex5_devkit/sdc/fmc_io.sdc](projects/agilex5_devkit/sdc/fmc_io.sdc) |
| edit | [projects/agilex5_devkit/agilex5_devkit.qsf](projects/agilex5_devkit/agilex5_devkit.qsf) — `set_global_assignment -name SDC_FILE sdc/fmc_io.sdc` |

### Top-level port additions

```systemverilog
// JESD GTS reference clock — UX 4B GBTCLK0 (transceiver bank)
input  logic fmc_gbtclk0_p,
input  logic fmc_gbtclk0_n,

// JESD SYSREF — HSIO 3B LA00_CC (LVDS, 1.2 V)
input  logic fmc_sysref_p,
input  logic fmc_sysref_n,

// JESD SYNC (FPGA → DAC) — HSIO 3B LA01/LA02
output logic fmc_sync0_p,
output logic fmc_sync0_n,
output logic fmc_sync1_p,
output logic fmc_sync1_n,

// JESD serial TX lanes (FPGA TX0..7 → AD9176 SERDIN7..0 with scrambled order)
output logic [7:0] fmc_serdin_tx_p,
output logic [7:0] fmc_serdin_tx_n,
```

### Pin assignments

| Port | Pin | IO standard | Bank |
|------|-----|-------------|------|
| `fmc_gbtclk0_p/n` | D4 / D5 | LVDS / transceiver refclk | UX 4B |
| `fmc_sysref_p/n` | G6 / G7 (LA00_CC) | LVDS 1.2-V | HSIO 3B |
| `fmc_sync0_p/n` | D8 / D9 (LA01_CC) | LVDS 1.2-V | HSIO 3B |
| `fmc_sync1_p/n` | H7 / H8 (LA02) | LVDS 1.2-V | HSIO 3B |
| `fmc_serdin_tx_p[0]/n[0]` | C2 / C3 (FMC_TX0) | high-speed differential | UX 4B |
| `fmc_serdin_tx_p[1]/n[1]` | A22 / A23 (FMC_TX1) | high-speed differential | UX 4B |
| `fmc_serdin_tx_p[2]/n[2]` | A26 / A27 (FMC_TX2) | high-speed differential | UX 4B |
| `fmc_serdin_tx_p[3]/n[3]` | A30 / A31 (FMC_TX3) | high-speed differential | UX 4B |
| `fmc_serdin_tx_p[4]/n[4]` | A34 / A35 (FMC_TX4) | high-speed differential | UX 4C |
| `fmc_serdin_tx_p[5]/n[5]` | A38 / A39 (FMC_TX5) | high-speed differential | UX 4C |
| `fmc_serdin_tx_p[6]/n[6]` | B36 / B37 (FMC_TX6) | high-speed differential | UX 4C |
| `fmc_serdin_tx_p[7]/n[7]` | B32 / B33 (FMC_TX7) | high-speed differential | UX 4C |

Note: HSST transceiver lanes do not take an `IO_STANDARD` assignment — the GTS Subsystem IP determines termination and signaling. Just `set_location_assignment` is required.

### `sdc/fmc_io.sdc` contents

```tcl
# AD9176 device-clock reference back to FPGA via FMC GBTCLK0.
# Frequency confirmed against AD9176-FMC-EBZ default clocking (TBD per Stage 6
# JESD IP parameters; placeholder = 250 MHz refclk for mode-4 at 12.5 Gbps).
create_clock -name fmc_gbtclk0 -period 4.000 [get_ports fmc_gbtclk0_p]

# SYSREF is captured into JESD link domain; declare asynchronous to fabric clk.
set_clock_groups -asynchronous -group [get_clocks fmc_gbtclk0]

# SYNC_N outputs are quasi-static; false-path them.
set_false_path -from * -to [get_ports fmc_sync0_p]
set_false_path -from * -to [get_ports fmc_sync1_p]
```

### Verification

- `quartus_sta` reports `fmc_gbtclk0` recognized as a transceiver reference clock at the expected rate.
- Fitter places all 8 SERDIN lanes in UX 4B and UX 4C transceiver banks.
- `flow.rpt` clean; no unbonded-pin warnings.
- Timing margin ≥ 0.5 ns on fabric clocks (JESD link clock not yet present).

### Stage 5 risks

- **GBTCLK0 (UX 4B) sourcing transceiver lanes in UX 4C** — Agilex 5 GTS may or may not support cross-tile refclk routing. If unsupported, the FMC also provides `GBTCLK1_M2C` (B20/B21, UX 4C); add a second refclk port and configure the JESD IP with two refclks (one per tile).
- LA00_CC at 1.2-V LVDS — Agilex 5 HSIO 3B supports LVDS at 1.2 V but confirm via the Agilex 5 IO Standards table.

---

## Stage 6 — Add JESD204B GTS Subsystem IP and integrate

**Goal.** Fully wired RTL system that can light up JESD links once hardware is configured.

### Files created or modified

| Action | Path |
|--------|------|
| create | `ip/dac_subsys/jesd204b_gts_ss.ip` (Intel JESD204B GTS Subsystem instance) |
| edit | [ip/dac_subsys/dac_subsys.qsys](ip/dac_subsys/dac_subsys.qsys) — replace JESD stubs with `u_jesd204b_gts_ss` |
| create | [projects/agilex5_devkit/src/sysref_capture.vhd](projects/agilex5_devkit/src/sysref_capture.vhd) |
| create | [projects/agilex5_devkit/src/fmc_handshake.sv](projects/agilex5_devkit/src/fmc_handshake.sv) |
| create | [projects/agilex5_devkit/sdc/jesd_cdc.sdc](projects/agilex5_devkit/sdc/jesd_cdc.sdc) |
| edit | [projects/agilex5_devkit/agilex5_devkit.qsf](projects/agilex5_devkit/agilex5_devkit.qsf) — add VHDL/SV source files + SDC |

### JESD GTS Subsystem parameters

| Parameter | Value | Source |
|-----------|-------|--------|
| Subclass | 1 (default), 0 fallback | per [doc/jesd_bringup_sequence.md](doc/jesd_bringup_sequence.md) |
| M (converters/link) | 4 | Phase A `DacControllerPkg` |
| L (lanes/link) | 4 | Phase A `DacControllerPkg` |
| F (octets/frame) | 2 | Phase A `DacControllerPkg` |
| S (samples/converter/frame) | 1 | Phase A `DacControllerPkg` |
| N (resolution) | 16 | Phase A `DacControllerPkg` |
| NP (word size) | 16 | Phase A `DacControllerPkg` |
| K (frames/multiframe) | 32 | Phase A `DacControllerPkg` |
| HD (high density) | 1 | Phase A `DacControllerPkg` |
| SCR (scrambling) | 1 | per [D:\Firmware_PhaseA\src\hps\ad9176_fmc_ebz.h](D:\Firmware_PhaseA\src\hps\ad9176_fmc_ebz.h) line 159 |
| Links | 2 | one per AD9176 DAC core |
| Lanes per link | 4 | |
| Reference clock | `fmc_gbtclk0` | AD9176 device clock |
| Logical→physical lane map | per table below | confirms AD9176 ↔ FPGA TX mapping |

### Logical→physical lane mapping

The AD9176 SERDIN pins land on FMC TX pins in a scrambled order. Configure the GTS Subsystem `Logical → Physical Lane Map` so logical lanes 0..7 match SERDIN0..7:

| Logical lane | AD9176 input | FMC pin | FPGA port |
|--------------|--------------|---------|-----------|
| Link 0 lane 0 | SERDIN0 | A38/A39 (FMC_TX5) | `fmc_serdin_tx[5]` |
| Link 0 lane 1 | SERDIN1 | B36/B37 (FMC_TX6) | `fmc_serdin_tx[6]` |
| Link 0 lane 2 | SERDIN2 | A34/A35 (FMC_TX4) | `fmc_serdin_tx[4]` |
| Link 0 lane 3 | SERDIN3 | B32/B33 (FMC_TX7) | `fmc_serdin_tx[7]` |
| Link 1 lane 0 | SERDIN4 | A30/A31 (FMC_TX3) | `fmc_serdin_tx[3]` |
| Link 1 lane 1 | SERDIN5 | A26/A27 (FMC_TX2) | `fmc_serdin_tx[2]` |
| Link 1 lane 2 | SERDIN6 | A22/A23 (FMC_TX1) | `fmc_serdin_tx[1]` |
| Link 1 lane 3 | SERDIN7 | C2/C3 (FMC_TX0) | `fmc_serdin_tx[0]` |

**Confirm this mapping against the AD9176-FMC-EBZ board schematic before locking it in.** Mis-mapping does not damage hardware but the JESD link will fail to align.

### `sysref_capture.vhd`

```vhdl
entity SysrefCapture is
  port (
    sysref_in_p : in  std_logic;      -- LVDS_RX from FMC LA00_CC
    sysref_in_n : in  std_logic;
    link_clk    : in  std_logic;      -- jesd_tx_link_clk
    rst_n       : in  std_logic;
    sysref_out  : out std_logic       -- single-bit, captured to link_clk domain
  );
end entity;
```

Use an Agilex LVDS_RX primitive on the diff pair, then a 2-stage synchronizer to `link_clk`. Subclass-1 deterministic capture relies on the AD9176 board's source-synchronous SYSREF↔GBTCLK0 phasing.

### `fmc_handshake.sv`

```systemverilog
module fmc_handshake (
  input  logic clk,
  input  logic rst,
  input  logic fmc_prsnt_n,
  input  logic fmc_pg_m2c,
  output logic fmc_ready
);
  // 2-stage synchronizers + AND gate. Holds fmc_ready low until both
  // presence-detect and power-good are stable for >= 32 clock cycles.
endmodule
```

The output `fmc_ready` gates the JESD GTS reset deassertion inside `dac_subsys`.

### `sdc/jesd_cdc.sdc`

```tcl
# False-paths between AXI control clock and JESD link clock for all
# CDC structures Phase A documents (2-stage synchronizers + DcFifo).
set_clock_groups -asynchronous \
  -group [get_clocks {*clock_sink_clk*}] \
  -group [get_clocks {*jesd204_tx_link_clk*}]

# JESD GTS Subsystem internal CDC paths per Intel's user guide
# (the GTS IP emits these automatically into ip/dac_subsys/jesd204b_gts_ss/synthesis/*.sdc,
#  this file documents project-scope additions only).
```

### Commands

```bash
cd projects/agilex5_devkit
quartus_sh -t build.tcl
```

### Verification

- Full Quartus build clean.
- Open System Console; using NiosV JTAG-to-Avalon master, read the JESD GTS Subsystem CSRs at `0x02002000`. PLL_LOCKED, LANE_READY, and FRAME_READY all assert after the AD9176 is configured (Stage 7 task).
- Without booting Linux, drive the SPI master from System Console scripts to bring up the AD9176, then verify JESD link state — this is the unit test for Stage 6 before Stage 7's full Linux flow.

### Stage 6 risks

- **ES-silicon stepping support**: Quartus 26.1 may emit `IP_NOT_PRODUCTION_READY` warnings for the JESD204B GTS IP on `SR0` silicon. Capture in [doc/potential_issues.md](doc/potential_issues.md) and proceed; the IP is expected to function on ES.
- **Subclass-1 strap**: confirm the AD9176-FMC-EBZ has the SYSREF source-sync strap configured for subclass-1. If subclass-1 doesn't lock, drop to subclass-0 (release SYSREF gating) and accept non-deterministic latency.
- **Mode-4 wizard params vs Phase A CSR exports**: the GTS IP may bake M/L/F/K/etc. as compile-time parameters rather than runtime CSRs. Phase A's `csr_*_export` ports become decorative read-backs in that case. Document in `potential_issues.md`.

---

## Stage 7 — `ad9176-config` user-space tool & full bring-up

**Goal.** Linux user-space program drives full AD9176 + JESD bring-up. Scope shows sine wave on the AD9176 RF output.

### Files created or modified

| Action | Path |
|--------|------|
| create | [software/ad9176_config/ad9176_config.c](software/ad9176_config/ad9176_config.c) — main |
| create | [software/ad9176_config/ad9176_fmc_ebz.c](software/ad9176_config/ad9176_fmc_ebz.c) / `.h` — SPI transport over LWS2F |
| create | [software/ad9176_config/ad9176_init.c](software/ad9176_config/ad9176_init.c) / `.h` — register sequence (lifted from Phase A) |
| create | [software/ad9176_config/iq_router_regs.h](software/ad9176_config/iq_router_regs.h) — audited against `reg_bank.vhd` |
| create | [software/ad9176_config/Makefile](software/ad9176_config/Makefile) |
| create | `software/yocto_linux/meta-custom/recipes-apps/ad9176-config/ad9176-config_0.1.bb` |
| edit | device tree under [software/yocto_linux/meta-custom/](software/yocto_linux/meta-custom/) — add nodes for `dac_subsys` peripherals (sopc2dts will mostly do this) |

### `ad9176_config` bring-up sequence

```c
// 1. mmap LWS2F window (0x02000000, 16 KB) via /dev/mem
// 2. Wait for fmc_ready bit in dac_status_pio
// 3. Assert SYNC (drive sync_n low via dac_status_pio output, or via JESD GTS CSR)
// 4. Drive fmc_spi_en high, fmc_pe_ctrl per AD9176 reset sequence
// 5. SPI: AD9176 soft-reset, configure clock chain, configure JESD link params
//    (sequence lifted from D:\Firmware_PhaseA\src\hps\ad9176_init.c — transport
//     replaced with fabric SPI master register writes)
// 6. Configure AD9176 datapath (mode 4, interpolation, NCO bypass)
// 7. Release JESD GTS reset (write to JESD CSR at 0x02002000)
// 8. Negate SYNC; wait for LINK_READY bit (poll dac_status_pio)
// 9. Configure Phase A NCO via dac_controller_0 reg_bank:
//    - freq word per converter (m0..m3)
//    - amplitude
//    - conv_enable
//    - sine src_sel (0 = NCO)
//    - sine enable
// 10. Report: AD9176 silicon ID, JESD status, NCO frequency, status PIO snapshot
```

### Audit `iq_router_regs.h` against `reg_bank.vhd`

Walk every define in `iq_router_regs.h` and confirm the matching offset exists in [ip/dac_controller_0/src/reg_bank.vhd](ip/dac_controller_0/src/reg_bank.vhd) decode. Update or remove stale defines. Capture results in [doc/potential_issues.md](doc/potential_issues.md) as ISSUE-007 if any drift is found.

### Yocto recipe

```bitbake
# ad9176-config_0.1.bb
SUMMARY = "Linux user-space configuration tool for AD9176-FMC-EBZ"
LICENSE = "MIT"
SRC_URI = "file://ad9176_config.c file://ad9176_fmc_ebz.c file://ad9176_init.c file://Makefile"
do_install() { install -d ${D}${bindir}; install -m 0755 ad9176-config ${D}${bindir}; }
```

### Commands

```bash
# Build Yocto image with new tool (from yocto_linux dir)
bitbake core-image-minimal-dev
# Flash SD card per baseline GSRD instructions
# Boot, log in:
ad9176-config
```

### Verification

- AD9176 reports silicon ID `0x9176` (or per AD9176 datasheet errata).
- JESD links 0 and 1 both report `link_ready=1` in `dac_status_pio`.
- Scope on AD9176 RF outputs (J1..J4 per AD9176-FMC-EBZ) shows a clean sine wave at the configured NCO frequency.
- `ad9176-config --freq 1000000` retunes the NCO; output frequency follows.
- All 4 converters (M0..M3 on link 0, M0..M3 on link 1) produce IQ pairs.

### Stage 7 risks

- **Device tree mismatch**: if `/dev/mem` mmap address doesn't decode to LWS2F, falls back to manual `mmap()` of the physical address. Document workaround.
- **Race between FPGA configuration and Linux mmap**: the `.sof` is loaded as `core.rbf` during U-Boot; ensure FPGA is configured before kernel boots so that LWS2F is alive.
- **AD9176 register sequence ordering**: Phase A's [ad9176_init.c](D:\Firmware_PhaseA\src\hps\ad9176_init.c) follows AD9176 datasheet Table 50 — preserve order exactly; some writes have required delays.

---

## Stage 8 — System simulation

**Goal.** Regression-grade simulation that exercises the integrated system. Each new RTL change runs `vsim -c -do "do run_sim.tcl; quit -f"` and gets a pass/fail in under 10 minutes.

### Files created or modified

| Action | Path |
|--------|------|
| create | [projects/agilex5_devkit/sim/dac_subsys_tb.sv](projects/agilex5_devkit/sim/dac_subsys_tb.sv) — system testbench |
| create | [projects/agilex5_devkit/sim/run_sim.tcl](projects/agilex5_devkit/sim/run_sim.tcl) — entry script |
| create | [projects/agilex5_devkit/sim/jesd_gts_bfm/](projects/agilex5_devkit/sim/jesd_gts_bfm/) — Intel JESD GTS BFM in TX mode |

### `dac_subsys_tb.sv` outline

```systemverilog
module dac_subsys_tb;
  // Instantiate dac_subsys with the JESD GTS BFM substituting for the real GTS IP.
  // Drive AXI control plane via an AXI4 BFM.
  // Sink JESD AVST link data into a mode-4 decoder.
  // Compare decoded samples against a golden SineWaveGen reference.
  // Assert link bring-up sequence (SYNC handshake, frame alignment).
endmodule
```

### `run_sim.tcl`

```tcl
# Clean
file delete -force work
vlib work

# Compile Phase A package + RTL
vcom -2008 ../../ip/dac_controller_0/src/dac_controller_pkg.vhd
foreach f [glob ../../ip/dac_controller_0/src/*.vhd] {
  if {[file tail $f] ne "dac_controller_pkg.vhd"} { vcom -2008 $f }
}

# Compile project SV
vlog -sv ../src/clocks_and_resets.sv ../src/debounce.sv ../src/fmc_handshake.sv

# Compile testbench
vlog -sv sim/dac_subsys_tb.sv

# Compile all block testbenches
foreach tb [glob ../../tb/*_tb.vhd] { vcom -2008 $tb }

# Run system test
vsim -c -voptargs="+acc" work.dac_subsys_tb \
  -do "set NumericStdNoWarnings 1; run -all; quit -f"

# Run block tests
foreach tb {sine_wave_gen_tb jesd_tx_manager_tb jesd_sync_controller_tb \
            dc_fifo_tb data_src_mux_tb reg_bank_tb axi_lite_to_avmm_tb \
            dac_controller_tb} {
  vsim -c -voptargs="+acc" work.$tb \
    -do "set NumericStdNoWarnings 1; run -all; quit -f"
}
```

### Verification

- All `SIMULATION PASSED` reports.
- Zero `severity error` (other than intentional end-of-test reports per Phase A's Questa FSE convention) and zero `severity failure`.
- Total runtime ≤ 10 minutes on the dev workstation.

### Stage 8 risks

- Intel JESD GTS BFM may not ship with Quartus 26.1 GTS Subsystem IP — fallback is to write a minimal AVST consumer that frame-decodes mode-4 from the 128-bit lane bus and compares samples.

---

## Stage 9 — Hygiene & doc finalization

**Goal.** Project ready for handoff. Builds reproducibly, docs are complete, no half-finished work.

### Tasks

- `flow.rpt`: confirm < 80% ALM/M20K/DSP utilization; WNS ≥ 0.5 ns; no critical warnings.
- `verilator --lint-only` on all SV files.
- `quartus_sh --flow=elaborate` clean.
- [doc/architecture.md](doc/architecture.md) finalized with block diagram + dataflow + clocking + reset domains.
- [doc/jesd_bringup_sequence.md](doc/jesd_bringup_sequence.md) finalized with exact SPI register sequence and Linux user-space flow.
- [doc/fmc_pinout_crossref.md](doc/fmc_pinout_crossref.md) generated from the two pinout txt files.
- [doc/potential_issues.md](doc/potential_issues.md) updated with any Phase B issues discovered.
- README.md with quick-start: `git clone`, `quartus_sh -t build.tcl`, `make`, `flash SD`, `boot`, `ad9176-config`.
- Decision log appended to PLAN.md Appendix E.

### Verification

- Reproducible build: from a fresh checkout, run `quartus_sh -t build.tcl`; bitstream signature is stable across re-runs.
- All docs cross-link correctly (markdown links resolve).

---

## Appendix A — FMC ↔ AD9176 ↔ FPGA pin cross-reference

Derived from [Agilex_FMC_Pinout.txt](Agilex_FMC_Pinout.txt) and [AD9176_Dev_Pinout.txt](AD9176_Dev_Pinout.txt).

### Transceiver lanes (FPGA TX → AD9176 SERDIN)

| AD9176 input | FMC pin | FPGA port | FPGA bank | Pin (P/N) |
|--------------|---------|-----------|-----------|-----------|
| SERDIN0 | A38/A39 (FMC_TX5) | `fmc_serdin_tx[5]` | UX 4C | A38 / A39 |
| SERDIN1 | B36/B37 (FMC_TX6) | `fmc_serdin_tx[6]` | UX 4C | B36 / B37 |
| SERDIN2 | A34/A35 (FMC_TX4) | `fmc_serdin_tx[4]` | UX 4C | A34 / A35 |
| SERDIN3 | B32/B33 (FMC_TX7) | `fmc_serdin_tx[7]` | UX 4C | B32 / B33 |
| SERDIN4 | A30/A31 (FMC_TX3) | `fmc_serdin_tx[3]` | UX 4B | A30 / A31 |
| SERDIN5 | A26/A27 (FMC_TX2) | `fmc_serdin_tx[2]` | UX 4B | A26 / A27 |
| SERDIN6 | A22/A23 (FMC_TX1) | `fmc_serdin_tx[1]` | UX 4B | A22 / A23 |
| SERDIN7 | C2/C3 (FMC_TX0) | `fmc_serdin_tx[0]` | UX 4B | C2 / C3 |

### Clocks (AD9176 → FPGA)

| Signal | FMC pin | FPGA port | FPGA bank |
|--------|---------|-----------|-----------|
| BR40 (AD9176 device clock) | D4/D5 (GBTCLK0_M2C) | `fmc_gbtclk0_p/n` | UX 4B |
| SYSREF2 | G6/G7 (LA00_CC) | `fmc_sysref_p/n` | HSIO 3B |

### Control + SYNC (FPGA → AD9176, except MISO)

| Signal | FMC pin | FPGA port | FPGA bank |
|--------|---------|-----------|-----------|
| SYNC0 | D8/D9 (LA01_CC) | `fmc_sync0_p/n` | HSIO 3B |
| SYNC1 | H7/H8 (LA02) | `fmc_sync1_p/n` | HSIO 3B |
| SPI_SCK | G9 (LA03_P) | `fmc_spi_sck` | HSIO 3B |
| SPI_MOSI | G10 (LA03_N) | `fmc_spi_mosi` | HSIO 3B |
| SPI_MISO | H10 (LA04_P) | `fmc_spi_miso` | HSIO 3B |
| SPI_CS1 | H11 (LA04_N) | `fmc_spi_cs1_n` | HSIO 3B |
| SPI_CS2 | D11 (LA05_P) | `fmc_spi_cs2_n` | HSIO 3B |
| SPI_EN | D12 (LA05_N) | `fmc_spi_en` | HSIO 3B |
| TXEN_0 | C10 (LA06_P) | `fmc_txen[0]` | HSIO 3B |
| TXEN_1 | C11 (LA06_N) | `fmc_txen[1]` | HSIO 3B |
| PE_CTRL | H13 (LA07_P) | `fmc_pe_ctrl` | HSIO 3B |

### FMC housekeeping (3.3-V LVCMOS)

| Signal | FMC pin | FPGA port | Direction |
|--------|---------|-----------|-----------|
| GA0 | C34 | `fmc_ga[0]` | in |
| GA1 | D35 | `fmc_ga[1]` | in |
| PG_C2M | D1 | `fmc_pg_c2m` | out |
| PG_M2C | F1 | `fmc_pg_m2c` | in |
| PRSNT_M2C_L | H2 | `fmc_prsnt_n` | in |

---

## Appendix B — Address map (HPS view)

| Span | Base | Size | Contents |
|------|------|------|----------|
| LWS2F window | `0x0200_0000` | 16 MB | per GSRD baseline |
| └ `dac_subsys.axi_csr` | `0x0200_0000` | 16 KB | |
| └└ `u_dac_controller_0.lwhpm2fpga` | `0x0200_0000` | 1 KB | Phase A reg_bank |
| └└ `u_spi_master.s1` | `0x0200_1000` | 64 B | Avalon SPI Master CSR |
| └└ `u_tx_en_pio.s1` | `0x0200_1100` | 16 B | TXEN[1:0] |
| └└ `u_pe_ctrl_pio.s1` | `0x0200_1110` | 16 B | PE_CTRL |
| └└ `u_dac_status_pio.s1` | `0x0200_1120` | 16 B | PRSNT, PG, link-ready, framer status |
| └└ `u_jesd204b_gts_ss.csr` | `0x0200_2000` | 8 KB | JESD204B GTS Subsystem |

The remaining 16 KB → 16 MB of LWS2F window is reserved for future expansion or unused.

The NiosV JTAG-to-Avalon master targets the same `dac_subsys.axi_csr` slave for System Console debug; address arbitration is automatic via Qsys multi-master support.

---

## Appendix C — JESD204B mode-4 parameter table

| Parameter | Value | Defined in |
|-----------|-------|-----------|
| Mode | 4 | AD9176 datasheet |
| M (converters/link) | 4 | [ip/dac_controller_0/src/dac_controller_pkg.vhd](ip/dac_controller_0/src/dac_controller_pkg.vhd) |
| L (lanes/link) | 4 | same |
| F (octets/frame) | 2 | same |
| S (samples/converter/frame) | 1 | same |
| N (resolution) | 16 | same |
| NP (word size) | 16 | same |
| K (frames/multiframe) | 32 | same |
| HD (high density) | 1 | same |
| CS (control bits) | 0 | same |
| CF (control words/frame) | 0 | same |
| SCR (scrambling) | 1 | [D:\Firmware_PhaseA\src\hps\ad9176_fmc_ebz.h](D:\Firmware_PhaseA\src\hps\ad9176_fmc_ebz.h):159 |
| Number of links | 2 | (one per AD9176 DAC core; links 2/3 unbonded) |
| Total lanes | 8 | |
| Subclass | 1 (with subclass-0 fallback) | per AD9176-FMC-EBZ board strap |
| Link clock | ~250 MHz | from JESD GTS IP link layer |
| Device clock | 500 MSPS (implied) | from AD9176 board via FMC GBTCLK0 |

LMFC period = K × F / (L × 4 / M) = 32 × 2 / (4 × 4 / 4) = 16 link clocks.

---

## Appendix D — JESD bring-up sequence (high level)

For the precise AD9176 register sequence, see [doc/jesd_bringup_sequence.md](doc/jesd_bringup_sequence.md). Outline:

1. **Hardware presence gate**: `fmc_handshake` confirms `~prsnt_n & pg_m2c` is stable.
2. **JESD GTS held in reset**, SYNC0/SYNC1 asserted (low).
3. **AD9176 soft-reset over SPI**, silicon ID read-back.
4. **AD9176 clock & PLL configuration**: enable on-board clock chain, configure DEV_CLK PLL, enable JESD interface.
5. **AD9176 JESD link parameters**: mode 4, scrambling on, lane mapping written to AD9176 cross-bar registers.
6. **AD9176 DAC datapath**: interpolation factors, NCO bypass (since FPGA provides IQ samples).
7. **AD9176 enable TX path**, drive TXEN_0/1 high.
8. **JESD GTS reset deassert** via reg_bank CSR write — Phase A's `dac_controller_0` drives `jesd204_tx_rst_n` low.
9. **Wait for JESD GTS PLL_LOCKED** (poll JESD CSR).
10. **Negate SYNC0/SYNC1**, wait for AD9176 to detect ILAS sequence.
11. **Poll `frame_ready` per link** until both deassert their `sync_n` outputs (handshake complete).
12. **Phase A `dac_controller_0` `RegBank` writes**: NCO frequency, amplitude, conv_enable, source select, enable.
13. **DAC output appears on AD9176 RF outputs**.

A failure at any step latches in `dac_status_pio` and is readable from user-space.

---

## Appendix E — Decision Log

| # | Decision | Made when | Rationale |
|---|----------|-----------|-----------|
| D1 | Fabric Avalon SPI Master IP on LWS2F (not HPS GPIO bit-bang) | Phase B kickoff | HPS pins cannot reach FMC; bit-bang via PIO is slow and ugly |
| D2 | Linux user-space (Yocto) tool, not bare-metal A55 | Phase B kickoff | Aligns with baseline GHRD shipping model; faster development cycle |
| D3 | Phase A merged into Phase B repo at [D:\Firmware_DevBoard_PhaseA\](D:\Firmware_DevBoard_PhaseA) | Phase B kickoff | Single repo of record; Phase A archive retained at [D:\Firmware_PhaseA\](D:\Firmware_PhaseA) |
| D4 | One AD9176 only, 8 lanes, links 0/1 wired | Phase B kickoff | Matches the actual hardware; defer dual-DAC to future Phase C |
| D5 | Quartus 26.1 Pro + Questa Pro 26.1 (not Phase A's 25.1std) | Stage 1 | Match baseline GHRD toolchain; Phase A was 25.1std for Questa FSE |
| D6 | Subclass-1 default with subclass-0 fallback | Stage 6 | Deterministic latency preferred when AD9176 board supports it |

Add new decisions here as the project progresses.

---

## Open issues

Tracked in [doc/potential_issues.md](doc/potential_issues.md). Stage owners append new issues as they discover them; don't silently close issues, mark resolution + commit hash.

**End of PLAN.md**
