# Phase B Dev-Board Firmware -- `agilex5_devkit`

Deployable firmware for the **DK-A5E065BB32AES1** Agilex 5 E-Series 065B
Premium Development Kit driving an **AD9176-FMC-EBZ** DAC mezzanine over
JESD204B mode 4 (2 links, 8 lanes, 12.5 Gbps).

For project rules and the critical-constraints checklist see
[CLAUDE.md](CLAUDE.md). For the stage-by-stage implementation script see
[PLAN.md](PLAN.md). For the bring-up procedures that need hardware see
[doc/integration.md](doc/integration.md).

---

## Quick start

### Prerequisites

| Tool                | Version | Notes                                       |
| ------------------- | ------- | ------------------------------------------- |
| Quartus Prime Pro   | 26.1    | Set `LM_LICENSE_FILE` to the Altera license |
| Questa Pro          | 26.1    | Or the Questa Altera Starter FPGA Edition bundled with Quartus 26.1 (covers Stage 8a + 8b regressions) |
| Yocto build host    | matches upstream GSRD | Off-tree; only needed for Stage 7 user-space tool deploy |

This repo assumes the toolchain lives at `D:/altera_pro/26.1/` on
Windows. Adjust `PATH` for other layouts.

### Build the bitstream

```bash
cd projects/agilex5_devkit

# IP generation + project setup only (fast, ~5 min on first run)
quartus_sh -t build.tcl --project-only

# Full compile flow (ipgen + syn + fit + sta + asm; ~30-60 min)
quartus_sh -t build.tcl
```

The bitstream lands at
`projects/agilex5_devkit/output_files/agilex5_devkit.sof` (or
`_time_limited.sof` if the JESD204B GTS IP is in OpenCore Plus
evaluation mode -- see
[doc/potential_issues.md ISSUE-016](doc/potential_issues.md)).

> **This `.sof` is NOT bootable on its own.** It contains the FPGA fabric
> and HPS handoff but **no bootloader (FSBL / U-Boot SPL)**. This is an
> HPS-first kit, so a bare `.sof` configures the fabric but the HPS will not
> boot Linux. To build a bootable QSPI image (bitstream + FSBL merged via
> `quartus_pfg -o hps_path=…`) and program it, follow
> [doc/integration.md → Deployable boot image](doc/integration.md#deployable-boot-image--integrating-the-bootloader-read-first-if-linux-wont-boot).

### Run the regression suites

```bash
# Phase A block testbenches (Stage 8a regression, ~5 min)
export REPO_ROOT="$(pwd)"
vsim -c -do "do tb/run_block_tbs.tcl; quit -f"

# dac_subsys integration TB (Stage 8b regression, ~2 h)
cd projects/agilex5_devkit/sim
vsim -c -do "do run_dac_subsys_tb.do; quit -f"
```

Pass criterion (8a): 8/8 testbenches report `SIMULATION PASSED`.
Pass criterion (8b): 6/6 sub-tests in `dac_subsys_tb` report PASS.

### Build the user-space tool

```bash
cd software/ad9176_config
make CROSS=aarch64-buildroot-linux-gnu-      # cross-compile for Yocto target
# or, on the dev-kit itself after boot:
make
```

Produces `ad9176-config`. Run on the dev-kit (root by default on the
baseline GSRD Yocto image):

```bash
ad9176-config status               # quick gate: fmc_ready + presence
ad9176-config bringup --freq 10000000 --fs 625000000
ad9176-config tone --freq 5000000  # re-tune live, no link bring-down
```

See [doc/jesd_bringup_sequence.md](doc/jesd_bringup_sequence.md) for the
underlying AD9176 SPI sequence and JESD link bring-up flow.

### Repo layout

See [CLAUDE.md s4](CLAUDE.md#4-repository-layout). High level:

```
ip/dac_controller_0/      Phase A IP (VHDL-2008, 10 modules)
ip/dac_subsys/            Phase B DAC subsystem (Stage 3 onward)
projects/agilex5_devkit/  Quartus project root (build entry point)
tb/                       Phase A block testbenches + Stage 1 regression
software/ad9176_config/   Linux user-space configuration tool (Stage 7)
software/yocto_linux/     Yocto meta-custom layer scaffold (Stage 7)
doc/                      Architecture, JESD bring-up, FMC pinout, issues
```

---

## Documentation index

| Doc | Purpose |
|-----|---------|
| [CLAUDE.md](CLAUDE.md) | Project rules, architecture summary, critical constraints, coding standards |
| [PLAN.md](PLAN.md) | Stage-by-stage implementation script with verify gates |
| [doc/architecture.md](doc/architecture.md) | Subsystem hierarchy, clock domains, address map, dataflow |
| [doc/jesd_bringup_sequence.md](doc/jesd_bringup_sequence.md) | AD9176 SPI register sequence + JESD link bring-up |
| [doc/fmc_pinout_crossref.md](doc/fmc_pinout_crossref.md) | FMC <-> AD9176 <-> FPGA pin map (authoritative) |
| [doc/integration.md](doc/integration.md) | Hardware-deferred procedures (Procedures 1.A through 8.C) |
| [doc/deferred_hw_gates.md](doc/deferred_hw_gates.md) | Ledger of PLAN verify gates skipped pending hardware |
| [doc/potential_issues.md](doc/potential_issues.md) | Open + closed issues (19 tracked) |
| [doc/phase_a_design_description.md](doc/phase_a_design_description.md) | Inherited Phase A CLAUDE.md + design notes |

---

## Project status

| Stage | Goal                                              | Status   |
| ----- | ------------------------------------------------- | -------- |
| 1     | Repo merge + baseline retarget                    | Complete |
| 2     | Wrap Phase A `dac_controller_0` as Platform Designer IP | Complete |
| 3     | `dac_subsys.qsys` (control plane only, JESD stubbed) | Complete |
| 4     | Wire dac_subsys into baseline_top + FMC SPI pinout | Complete |
| 5     | JESD204B GTS Subsystem + FMC differential ports (merged with original Stage 6) | Complete |
| 7     | `ad9176-config` user-space tool + Yocto recipe    | Complete |
| 8a    | Phase A block testbench regression on Phase B workstation | Complete |
| 8b    | dac_subsys integration TB (CSR-plane)             | Complete |
| 8c    | JESD link-layer BFM golden-sample compare         | Deferred (covered by hardware bring-up) |
| 9     | Hygiene + doc finalization                        | Complete |

### Deferred to hardware-in-loop

- **Procedure 5.A** -- JESD link bring-up + first sine on AD9176 RF
  (likely blocked by [ISSUE-019](doc/potential_issues.md): missing GTS
  Reset Sequencer IP -- fix scoped, ~1-stage of work)
- **Procedure 7.A** -- end-to-end Linux user-space bring-up
- **ISSUE-016** -- OpenCore Plus license server fix for full
  deployable `.sof`

See [doc/deferred_hw_gates.md](doc/deferred_hw_gates.md) for the full
ledger.

### Stage 1 baseline deviation

The HPS EMIF was retargeted from DDR4-3200 @ 1066.667 MHz (production
silicon) to DDR4-1600 @ 800 MHz (ES SR0 silicon cap;
[doc/potential_issues.md ISSUE-011](doc/potential_issues.md)). Five DBI
pin assignments (`B119`, `AC90`, `V87`, `H87`, `B97`) are intentionally
unbonded because the ES EMIF IP variant does not export `mem_dbi_n`.
