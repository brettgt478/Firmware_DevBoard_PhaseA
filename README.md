# Phase B Dev-Board Firmware  agilex5_devkit

Deployable firmware for the **DK-A5E065BB32AES1** Agilex 5 E-Series 065B
Premium Development Kit driving an **AD9176-FMC-EBZ** DAC mezzanine over
JESD204B mode 4 (2 links, 8 lanes).

For architecture, build commands, IO map, and project rules see
[CLAUDE.md](CLAUDE.md). For the stage-by-stage implementation script see
[PLAN.md](PLAN.md). Open issues are tracked in
[doc/potential_issues.md](doc/potential_issues.md); hardware-bound verify
gates that are deferred until the dev kit is connected are in
[doc/deferred_hw_gates.md](doc/deferred_hw_gates.md).

---

## Quick start

### Prerequisites

| Tool                | Version | Notes                                  |
| ------------------- | ------- | -------------------------------------- |
| Quartus Prime Pro   | 26.1    | Set `LM_LICENSE_FILE` to Altera license |
| Questa Pro          | 26.1    | Set `MGLS_LICENSE_FILE`                 |
| Verilator           | recent  | Lint only                              |
| Python              | 3.11.5  | GSRD Makefile dependency               |

This repo assumes the toolchain lives at `D:/altera_pro/26.1/` on Windows.
Other layouts work; adjust `PATH` accordingly.

### Build the bitstream

```bash
cd projects/agilex5_devkit

# IP generation + project setup only (fast, ~5 min on first run)
quartus_sh -t build.tcl --project-only

# Full compile flow (ipgen + syn + fit + sta + asm; ~30-60 min)
quartus_sh -t build.tcl
```

The bitstream lands at
`projects/agilex5_devkit/output_files/agilex5_devkit.sof`.

### Run Phase A block testbenches

```bash
export REPO_ROOT="$(pwd)"
vsim -c -do "do tb/run_block_tbs.tcl; quit -f"
```

Pass criterion: 8/8 testbenches report `SIMULATION PASSED`.

### Repo layout

See [CLAUDE.md §4](CLAUDE.md#4-repository-layout). High level:

```
ip/dac_controller_0/      - Phase A IP (VHDL-2008, 10 modules)
ip/dac_subsys/            - Phase B DAC subsystem qsys (Stage 3 onward)
projects/agilex5_devkit/  - Quartus project root (build entry point)
tb/                       - Phase A block testbenches + Stage 1 regression
software/ad9176_config/   - Linux user-space configuration tool (Stage 7)
doc/                      - Architecture, JESD bring-up, issue logs
```

---

## Project status

| Stage | Goal                                  | Status  |
| ----- | ------------------------------------- | ------- |
| 1     | Repo merge & baseline retarget        | **Complete** |
| 2     | Wrap Phase A as Platform Designer IP  | **Complete** |
| 3-7   | dac_subsys, FMC SPI, JESD GTS, Linux  | Pending |
| 8     | System simulation                     | Pending |
| 9     | Hygiene & doc finalization            | Pending |

Stage 1 closed with one deviation from the upstream baseline: the HPS EMIF
was retargeted from DDR4-3200 @ 1066.667 MHz (production silicon) to
DDR4-1600 @ 800 MHz (ES SR0 silicon). See
[doc/potential_issues.md ISSUE-011](doc/potential_issues.md).
