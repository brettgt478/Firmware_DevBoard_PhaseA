# CLAUDE.md — Phase B Dev-Board Firmware Project Guidelines

## 1. System Overview

This repository builds the deployable FPGA firmware for the **DK-A5E065BB32AES1 Agilex 5 E-Series 065B Premium Development Kit** (HPS Enablement Daughtercard, Opsero OP073 M.2 M-key Stack FMC mezzanine) driving a single **Analog Devices AD9176-FMC-EBZ** DAC over **JESD204B mode 4**, two links, eight lanes.

Phase B = baseline Altera GSRD + the Phase A `dac_controller_0` IP + JESD204B GTS Subsystem + a fabric SPI master for AD9176 register access + an `ad9176-config` Linux user-space tool. The HPS runs Yocto Linux. The Phase A IP is unchanged at the source level; it is wrapped as a Platform Designer component and instantiated inside a new `dac_subsys.qsys`.

- **Device:** A5ED065BB32AE6SR0 (Agilex 5 E-Series 065B, ES silicon)
- **Toolchain:** Quartus Prime Pro 26.1, Questa Pro 26.1, Yocto (meta-custom layer)
- **HDL:** VHDL-2008 for all custom RTL. Baseline GHRD SystemVerilog is preserved as-is.

---

## 2. Architecture

### Top-level entity

`agilex5_devkit` in [projects/agilex5_devkit/agilex5_devkit.sv](projects/agilex5_devkit/agilex5_devkit.sv). Renamed from the baseline `baseline_a55`; extended with FMC ports.

### Subsystem hierarchy

```
agilex5_devkit (top)
└── baseline_top.qsys
    ├── u_shell_subsys      — system PLL, clocks_and_resets, USB3.1 PHY
    ├── u_hps_subsys        — Agilex HPS (A76 + A55), HPS EMIF DDR
    ├── u_fabric_subsys     — NiosV debug, on-chip RAM, LED/SW/BTN PIO,
    │                          H2F + LWS2F bridges, F2SDRAM adapter,
    │                          ACE5-lite coherency translator
    ├── u_niosv_subsys      — JTAG-to-Avalon master (extended to reach dac_subsys)
    └── u_dac_subsys        ← NEW
        ├── u_dac_controller_0    — Phase A IP (NCO, JESD transport, sync, FIFO, regs)
        ├── u_jesd204b_gts_ss     — Intel JESD204B GTS Subsystem, mode 4, 2 links × 4 lanes (Stage 6)
        ├── u_jesd_stub           — Phase B synthesis-only terminator (Stages 3-5; deleted in Stage 6)
        ├── u_spi_master          — Avalon-MM SPI Master to AD9176 (2 CS, 25 MHz, 24-bit)
        ├── u_tx_en_pio           — 2-bit output PIO → FMC_TXEN_0/1
        ├── u_pe_ctrl_pio         — 1-bit output PIO → FMC_PE_CTRL
        ├── u_spi_en_pio          — 1-bit output PIO → FMC_SPI_EN (Stage 4)
        ├── u_pg_c2m_pio          — 1-bit output PIO (dangling externally — MAX10 owns FMC PG_C2M; HPS-readable diagnostic)
        └── u_dac_status_pio      — 32-bit input PIO ← FMC PRSNT_N + JESD status (Stage 6)
```

### Clock domains

| Clock | Frequency | Source |
|-------|-----------|--------|
| `pll_refclk_100` | 100 MHz | dev-kit oscillator (PIN_BK109) |
| `system_clock` | 100 MHz | shell `u_sys_pll` → fabric main clock |
| `clock_sink_clk` (= `system_clock`) | 100 MHz | drives `dac_controller_0` control plane + Avalon-MM CSRs |
| `jesd204_tx_link_clk_clk` | ~250 MHz | from JESD204B GTS Subsystem link layer |
| `fmc_gbtclk0` | AD9176 device clock | FMC `GBTCLK0_M2C` (D4/D5) — GTS PLL reference |
| `fmc_sysref` | low rate, divides DEV_CLK | FMC `LA00_CC` (G6/G7), captured to `jesd204_tx_link_clk` |

### Address map (LWS2F window, HPS view)

| Span | Base (HPS) | Size | Contents |
|------|-----------|------|----------|
| `dac_subsys.axi_csr` | `0x0200_0000` | 16 KB | Below sub-allocations |
| └ `u_dac_controller_0` | `0x0200_0000` | 1 KB | Phase A `reg_bank` (NCO + JESD sync CSRs) |
| └ `u_spi_master` | `0x0200_1000` | 64 B | Avalon-MM SPI Master CSR |
| └ `u_tx_en_pio` | `0x0200_1100` | 16 B | TXEN_0/1 |
| └ `u_pe_ctrl_pio` | `0x0200_1110` | 16 B | PE_CTRL |
| └ `u_dac_status_pio` | `0x0200_1120` | 16 B | PRSNT_N (bit 0), PG_C2M loopback (bit 2), JESD status (bits 31:5 Stage 6) |
| └ `u_spi_en_pio` | `0x0200_1130` | 16 B | FMC SPI level-shifter enable (Stage 4) |
| └ `u_pg_c2m_pio` | `0x0200_1140` | 16 B | PG_C2M PIO (dangling — see [doc/potential_issues.md ISSUE-012](doc/potential_issues.md)) |
| └ `u_jesd204b_gts_ss` | `0x0200_2000` | 8 KB | JESD GTS Subsystem CSR (Stage 6) |

The NiosV JTAG-to-Avalon master path to `axi_csr` is deferred to Stage 6 alongside GTS bring-up — Stage 4's `devmem` over LWH2F is the primary CSR access path.

### External interfaces

FPGA package pins are recovered from the user-annotated [AD9176_Dev_Pinout.txt](AD9176_Dev_Pinout.txt) rightmost column. The "Pin Number" column in [Agilex_FMC_Pinout.txt](Agilex_FMC_Pinout.txt) is the VITA 57.1 **FMC-connector** grid coordinate, NOT the FPGA BGA package pin — do not use it for `set_location_assignment`. Stage 4 discovered this the hard way (see [doc/potential_issues.md ISSUE-012/013](doc/potential_issues.md)).

| Signal group | FMC connector | FPGA pin | FPGA bank | IO standard |
|--------------|---------------|----------|-----------|-------------|
| `fmc_serdin_tx[7:0]_p/n` | FMC_TX0..TX7 | AU/AR/AN/AL/BE/BC/BA/AW + 7/10 | UX 4B / 4C | HSST (Stage 5) |
| `fmc_gbtclk0_p/n` | D4/D5 (BR40) | AP16/AP21 | UX 4B | LVPECL (Stage 5) |
| `fmc_sysref_p/n` | G6/G7 (LA00_CC) | A45/B42 | HSIO 3B | LVDS, 1.2 V (Stage 5) |
| `fmc_sync0_p/n` | D8/D9 (LA01_CC) | B45/A48 | HSIO 3B | LVDS, 1.2 V (Stage 5) |
| `fmc_sync1_p/n` | H7/H8 (LA02) | B51/A51 | HSIO 3B | LVDS, 1.2 V (Stage 5) |
| `fmc_spi_sck` | G9 (LA03_P) | **A54** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_spi_mosi` | G10 (LA03_N) | **B54** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_spi_miso` | H10 (LA04_P) | **A63** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_spi_cs1_n` | H11 (LA04_N) | **B60** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_spi_cs2_n` | D11 (LA05_P) | **B56** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_spi_en` | D12 (LA05_N) | **A60** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_txen[0]` | C10 (LA06_P) | **M58** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_txen[1]` | C11 (LA06_N) | **K58** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_pe_ctrl` | H13 (LA07_P) | **F47** | HSIO 3B | 1.2-V (Stage 4 ✓) |
| `fmc_prsnt_n` | H2 (PRSNT_M2C_L) | **K8** | 3.3-V housekeeping | 3.3-V LVCMOS (Stage 4 ✓) |

Agilex 5 IO standard at 1.2 V is `"1.2-V"` (no `LVCMOS` suffix — implicit at this voltage); at 3.3 V it is `"3.3-V LVCMOS"`.

**Owned by the on-board MAX10 board-mgmt FPGA, NOT routed to the main Agilex** (see [doc/potential_issues.md ISSUE-012](doc/potential_issues.md)):

| Signal | FMC connector | Notes |
|--------|---------------|-------|
| `PG_M2C` | F1 | MAX10 handles the FMC power-good handshake autonomously |
| `PG_C2M` | D1 | dac_subsys keeps an internal `u_pg_c2m_pio` for HPS diagnostic readback; output dangles inside baseline_top |
| `GA[1:0]` | C34, D35 | Board pull-ups only; never routed |

The `doc/fmc_pinout_crossref.md` referenced in earlier drafts of this file is not yet written; until it is, use [AD9176_Dev_Pinout.txt](AD9176_Dev_Pinout.txt) as the authoritative source. For HPS IO48 pin locations, see the upstream-GHRD reference in §3.

---

## 3. Toolchain & Build

| Tool | Version | Notes |
|------|---------|-------|
| Quartus Prime Pro | 26.1 | License via `SALT_LICENSE_SERVER` |
| Questa Pro | 26.1 | Same license server |
| Verilator | any recent | lint only |
| Python | 3.11.5 | invoked by GSRD Makefile |
| Yocto | matches baseline GHRD | builds via `software/yocto_linux/` recipes |

### Upstream GHRD reference (off-tree)

The upstream Altera GHRD lives at `D:/agilex5e-ed-gsrd-main/` (outside the
Phase B repo). Useful when the Phase B repo is missing a baseline-derived
artifact — Stage 1 retargeting silently dropped some, e.g. the 48 HPS IO48
pin locations recovered in Stage 4 (see [doc/potential_issues.md ISSUE-013](doc/potential_issues.md)).
Search order for missing pin assignments / qsys parameters:

1. `D:/agilex5e-ed-gsrd-main/a5ed065es-premium-devkit-debug2/legacy-baseline/legacy_baseline.qsf`
   — most complete for HPS IO48 peripheral pin LOCATIONS.
2. `D:/agilex5e-ed-gsrd-main/a5ed065es-premium-devkit-oobe/baseline-a55/baseline_a55.qsf`
   — Phase B Stage 0 baseline source; has IO_STANDARD / pull-up / drive
   strength but no `set_location_assignment` for HPS pins.
3. `D:/agilex5e-ed-gsrd-main/a5ed065b-premium-devkit-emmc/baseline-a55/baseline_a55.qsf`
   — production-silicon (non-ES) variant; last-resort cross-check.

### Build commands

```bash
# Full bitstream — runs qsys-generate, IP gen, synth, fit, asm
cd projects/agilex5_devkit
quartus_sh -t build.tcl

# Project & IP only (no synth/fit) — fast iteration
quartus_sh -t build.tcl --project-only

# Simulation
cd projects/agilex5_devkit/sim
vsim -c -do "do run_sim.tcl; quit -f"

# Lint
quartus_sh --flow=elaborate
verilator --lint-only -Iprojects/agilex5_devkit/src projects/agilex5_devkit/agilex5_devkit.sv

# Convert SOF to core.rbf for Linux config
make agilex5_devkit-install-core-rbf
```

Every build TCL script must clean its previous outputs (`output_files/`, `db/`, `incremental_db/`, `qdb/`, `ip/` generated dirs) before starting. **Never accumulate stale builds.**

---

## 4. Repository Layout

```
CLAUDE.md                        — this file
PLAN.md                          — comprehensive implementation plan
README.md                        — quick-start
AD9176_Dev_Pinout.txt            — reference data
Agilex_FMC_Pinout.txt            — reference data
doc/                             — architecture, JESD bring-up, pin cross-refs, issues
ip/
  dac_controller_0/
    dac_controller_0_hw.tcl      — Platform Designer descriptor
    src/                         — 10 VHDL files (Phase A)
  dac_subsys/
    dac_subsys.qsys              — DAC + JESD GTS + SPI + PIOs
projects/
  agilex5_devkit/                — Quartus project (root build entry)
    agilex5_devkit.qpf/qsf/sdc
    agilex5_devkit.sv            — top entity (renamed/extended baseline_a55)
    baseline_top.qsys            — adds u_dac_subsys
    fabric_subsys.qsys           — baseline, unchanged
    hps_subsys.qsys              — baseline, unchanged
    shell_subsys.qsys            — baseline, unchanged
    niosv_subsys.qsys            — JTAG master extended to dac_subsys
    build.tcl                    — entry point
    src/                         — clocks_and_resets.sv, debounce.sv,
                                   fmc_handshake.sv, sysref_capture.vhd
    sdc/                         — fmc_io.sdc, jesd_cdc.sdc
    sim/                         — run_sim.tcl, dac_subsys_tb.sv
tb/                              — block-level VHDL testbenches from Phase A
software/
  ad9176_config/                 — Linux user-space tool
  yocto_linux/                   — extended baseline Yocto build
```

---

## 5. Coding Standards

All custom RTL is **VHDL-2008** following the conventions established in Phase A's CLAUDE.md (preserved verbatim in [doc/phase_a_design_description.md](doc/phase_a_design_description.md)):

- `ieee.std_logic_1164` + `ieee.numeric_std` only — never `std_logic_arith`/`std_logic_unsigned`.
- **Naming:** signals `snake_case`, entities `CamelCase`, constants `SCREAMING_SNAKE_CASE`, generics `G_SCREAMING_SNAKE`, active-low `_n` suffix. Top-level entity `agilex5_devkit` and Platform Designer component `dac_controller_0` retain snake_case for Quartus compatibility.
- **One entity per file**, filename = `snake_case` of entity. Package types in `dac_controller_pkg.vhd`.
- **Direct entity instantiation** (no component declarations).
- **Synchronous active-high reset** as the default register pattern.
- **CDC discipline**: 2-stage synchronizer for single-bit; toggle synchronizer for pulses; `DcFifo` (or req/ack) for multi-bit. Never synchronize a multi-bit bus directly.
- 2-space indentation, < 100 chars/line, one port per line, port order `clk` → `rst` → inputs → outputs.

The baseline GHRD SystemVerilog ([projects/agilex5_devkit/src/clocks_and_resets.sv](projects/agilex5_devkit/src/clocks_and_resets.sv), [projects/agilex5_devkit/src/debounce.sv](projects/agilex5_devkit/src/debounce.sv), and `agilex5_devkit.sv`) remains SystemVerilog. New top-level glue may also be SV when extending the baseline; new self-contained modules should be VHDL-2008.

---

## 6. Critical Constraints

These are sticky — every change must respect them or builds fail or hardware breaks.

1. **`PROMOTE_WARNING_TO_ERROR 12677`** is set in the qsf. Any top-level port without a `set_location_assignment` aborts the fit. Every FMC port added to `agilex5_devkit.sv` must have a matching pin location in the same commit.

2. **`PROMOTE_WARNING_TO_ERROR 332148`** is set. Any timing-failed corner aborts the fit. Target WNS ≥ 0.5 ns; tighten SDC rather than relax this.

3. **FMC VADJ must be set to 1.2 V on the dev kit BEFORE any image drives the FMC HSIO 3B bank.** The HSIO 3B LA bus on this kit is 1.2 V (per [Agilex_FMC_Pinout.txt](Agilex_FMC_Pinout.txt) lines 40–107). Driving HSIO into a wrong-VADJ FMC card risks damaging the FMC mezzanine, the AD9176 board, or the FPGA bank. Confirm before flashing.

4. **JESD bring-up gates on `~fmc_prsnt_n & fmc_pg_m2c`** via [src/fmc_handshake.sv](projects/agilex5_devkit/src/fmc_handshake.sv). The GTS reset is not deasserted until the AD9176 board reports presence and power-good. Do not bypass this gate even for bench debug.

5. **SYSREF is HSIO 3B LVDS captured on `LA00_CC`**, resampled to `jesd204_tx_link_clk` in [src/sysref_capture.vhd](projects/agilex5_devkit/src/sysref_capture.vhd). JESD204B subclass-1 deterministic latency requires SYSREF to be source-synchronous to GBTCLK0 on the AD9176 board — confirm the AD9176-FMC-EBZ subclass-1 strap before relying on it. Default plan is subclass-1; subclass-0 fallback is documented in [doc/jesd_bringup_sequence.md](doc/jesd_bringup_sequence.md).

6. **LWS2F base is `0x0200_0000`**, `dac_subsys.axi_csr` occupies a 16 KB span at that base. All HPS user-space code and System Console scripts use this base. Do not move it without updating [software/ad9176_config/ad9176_fmc_ebz.h](software/ad9176_config/ad9176_fmc_ebz.h) and the device tree.

7. **HPS warm-reset must not hang the LWH2F slave.** A reset-bridge in `dac_subsys.qsys` resets the AXI slave when the HPS resets so that in-flight bursts complete or terminate cleanly. Do not remove this bridge.

8. **JESD link clock domain is asynchronous to the AXI control clock.** All CSR cross-domain reads use the 2-stage synchronizers and toggle synchronizers documented in Phase A's CDC rules. [sdc/jesd_cdc.sdc](projects/agilex5_devkit/sdc/jesd_cdc.sdc) declares the corresponding false-paths.

9. **AD9176 SPI is driven from fabric**, never from HPS pins. `hps_spim0` is hardwired to IO48 on this kit and cannot reach FMC. Driving SPI any other way breaks the architecture.

10. **Device part is `A5ED065BB32AE6SR0` (ES silicon).** If you regenerate IP from a different part, Qsys will silently produce wrong-stepping primitives. Always confirm the qsf `DEVICE` line and IP `.ip` device fields agree.

11. **HPS EMIF runs DDR4-1600 @ 800 MHz** because ES SR0 silicon caps `MEM_OPERATING_FREQ_MHZ` at 800. `mem_dbi_n` is NOT exported by the ES EMIF IP variant — five pin assignments (PIN_B119, AC90, V87, H87, B97) are intentionally unbonded. Do not bump the EMIF frequency or re-introduce DBI pin assignments without re-evaluating the ES silicon spec. See [doc/potential_issues.md ISSUE-011](doc/potential_issues.md).

---

## 7. Verification Entry-Points

| Scope | Entry-point | Pass criterion |
|-------|-------------|----------------|
| Block-level RTL | [tb/](tb/) VHDL testbenches via Questa | All `SIMULATION PASSED` reports, zero failures |
| System RTL | [projects/agilex5_devkit/sim/dac_subsys_tb.sv](projects/agilex5_devkit/sim/dac_subsys_tb.sv) via `run_sim.tcl` | JESD BFM decodes mode-4 link data matching `SineWaveGen` golden samples |
| Synthesis | `quartus_sh --flow=elaborate` | Zero errors, no critical warnings |
| Fit | `quartus_sh -t build.tcl` | WNS ≥ 0.5 ns, < 80% ALM/M20K/DSP utilization |
| Lint | `verilator --lint-only` | Clean |
| Hardware control plane | System Console via NiosV JTAG master | `dac_controller_0.ID` register reads correctly without booting Linux |
| Hardware end-to-end | `ad9176-config` from Yocto Linux | Scope shows configured sine wave on AD9176 RF output; JESD link-ready bits asserted |

### Stage closeout: update integration.md and deferred_hw_gates.md

**Every stage's closeout MUST update [doc/integration.md](doc/integration.md).** Two cases:

1. **The stage's verify gate includes a step that the workstation cannot execute** — hardware in the loop, scope probing, Linux boot, Platform Designer GUI inspection, external system access. The step is added to `integration.md` as a numbered `### Procedure N.X` with: goal, hardware requirements, copy-pasteable steps, observable pass criterion, failure-path link to `potential_issues.md`. The matching entry in [doc/deferred_hw_gates.md](doc/deferred_hw_gates.md) cross-references the new procedure.

2. **The stage has no deferred gates** — append a one-line `## Stage N — <name>` section stating "No deferred procedures introduced this stage."

This rule keeps `integration.md` the single buildable instruction sheet for whoever ends up in front of the hardware. Don't bury the procedures in commit messages or PLAN.md status notes — those don't survive into the bring-up engineer's workflow.

---

## 8. Open Issues

Tracked in [doc/potential_issues.md](doc/potential_issues.md). Includes Phase A's original issues (ISSUE-001 register read-path timing, ISSUE-004 LMFC release latency, ISSUE-005 link glitch recovery, ISSUE-006 Platform Designer wrapper) plus Phase B additions:

- ES-silicon stepping support in Quartus 26.1 JESD GTS IP — verify benign warnings.
- GBTCLK0 cross-tile transceiver refclk routing if FPGA TX0..7 straddle UX 4B + UX 4C.
- Mode-4 IP parameters as wizard-time vs runtime — Phase A's JESD CSR readback ports may be no-ops.
- `iq_router_regs.h` audit against `reg_bank.vhd` decode.

**End of CLAUDE.md**
