# CLAUDE.md — dac_controller_0 FPGA Project Guidelines

## 1. System Overview

This repository contains the VHDL-2008 firmware for the **dac_controller_0 IP core for the AD9176-FMC-EBZ development board** synthesized with **Intel Quartus** for an **Agilex 5 E-Series FPGA using GTS Transceiver Architecture** (`A5ED052AB32AI2E`).

### Hardware System

The Agilex 5 FPGA (which includes both FPGA fabric and an embedded ARM hard processor system) is the central hub connecting to an AD9176-FMC-EBZ for digital to analog conversion.

**Embedded ARM HPS** — The ARM core inside the Agilex 5 communicates with the FPGA fabric through an AXI4 bus (`lwhpm2fpga`) exported by the `dac_controller_0` Platform Designer component. This is the software control path for all register configuration.

**One Analog Devices AD9176-FMC-EBZ development board** — Connects to the FPGA through two interfaces. The high-speed data path uses JESD204B (two links, one per DAC core); this connects our firmware to an Intel JESD204B GTS IP block that implements the JESD204B protocol. The AD9176 is configured via a SPI bus driven directly from HPS software (see `src/hps/ad9176_fmc_ebz.c`); the FPGA fabric does not implement a SPI master.

### dac_controller_0 Capabilities

**Capability 1 — AD9176 DAC Interface.** Stream IQ sample data to the AD9176 via JESD204B in **mode 4** across two links (Link 0 = DAC core A, Link 1 = DAC core B). Includes a firmware-implemented sine wave generator (NCO) that produces IQ samples, enabling end-to-end verification of DAC output without an external data source. AD9176 register configuration is handled by HPS software over SPI, not FPGA fabric logic.

---

## 2. Architecture

### External Interfaces

| Component        | Firmware Interface Name        | Protocol / Bus       | IP Block Boundary                        |
| ---------------- | ------------------------------ | -------------------- | ---------------------------------------- |
| ARM HPS          | `lwhpm2fpga`                   | AXI4                 | direct — lwhpm2fpga bridge from HPS      |
| AD9176 DAC       | JESD204B Link 0 (`jesd_gts_ss_TX_outtel_jesd_TX_*`)  | JESD204B (mode 4) | Intel JESD204B GTS IP, DAC core A |
| AD9176 DAC       | JESD204B Link 1 (`jesd_gts_ss_TX_outtel_jesd_TX_p1_*`) | JESD204B (mode 4) | Intel JESD204B GTS IP, DAC core B |
| AD9176 DAC       | SPI (HPS software)             | SPI                  | HPS GPIO/SPI peripheral — not FPGA fabric |

### RTL Modules

| Module                 | Purpose                                          | Capability |
| ---------------------- | ------------------------------------------------ | ---------- |
| `axi_to_avmm`          | AXI4 to Avalon-MM bridge (lwhpm2fpga)            | 1          |
| `reg_bank`             | Avalon-MM slave register interface (10-bit, 1 KB)| 1          |
| `sine_wave_gen`        | internal NCO IQ test generator                   | 1          |
| `jesd_tx_manager`      | JESD transport layer (2 instances, links 0 and 1)| 1          |
| `jesd_sync_controller` | two-link deterministic LMFC alignment            | 1          |
| `data_src_mux`         | NCO / FIFO sample source multiplexer             | 1          |
| `dc_fifo`              | parameterized dual-clock async FIFO (CDC)        | 1          |

### Clock Domains

| Clock                    | Typical Frequency | Source                                        |
| ------------------------ | ----------------- | --------------------------------------------- |
| `clock_sink_clk`         | 100–200 MHz       | HPS lwhpm2fpga bridge (AXI control plane)     |
| `jesd204_tx_link_clk_clk`| ~250 MHz          | Intel JESD204B GTS IP link layer clock        |

> **Internal alias:** `dac_controller_0` aliases `jesd204_tx_link_clk_clk` to the internal signal `txlink_clk`. Use `txlink_clk` in sub-module documentation; use the full port name only at the top-level entity boundary.

---

## 3. Coding Standards

### Language

All RTL: **VHDL-2008** using `ieee.std_logic_1164` and `ieee.numeric_std`.

**Forbidden:** `std_logic_arith`, `std_logic_unsigned`, `std_logic_signed`.

### Naming

| Element           | Convention             | Example                    |
| ----------------- | ---------------------- | -------------------------- |
| Signals           | `snake_case`           | `data_valid`, `write_en`   |
| Entities          | `CamelCase`            | `JesdTxManager`, `DcFifo`  |
| Constants         | `SCREAMING_SNAKE_CASE` | `FIFO_DEPTH`               |
| Generics          | `G_SCREAMING_SNAKE`    | `G_DATA_WIDTH`             |
| Active-low        | `_n` suffix            | `rst_n`, `cs_n`            |
| Clocks            | `clk_<domain>`         | `clk_sys`, `clk_jesd`      |
| Resets            | `rst` or `rst_n`       |                            |
| AXI-Stream ports  | `m_axis_*` / `s_axis_*`| `m_axis_tdata`             |
| Avalon-MM ports   | `avmm_*`               | `avmm_address`             |

> **Exception:** The top-level entity `dac_controller_0` uses `snake_case` intentionally to match the Platform Designer component name. All sub-modules use `CamelCase`.

### File Organization

One entity per file. Filename is the entity name in `snake_case` with `.vhd` extension:
`JesdTxManager` → `jesd_tx_manager.vhd`, testbench → `jesd_tx_manager_tb.vhd`.

Project-wide shared types, constants, and interface record types go in `dac_controller_pkg.vhd`.
Module-local types belong in the entity's own declarative region.

### Package Record Types

Complex interfaces are encapsulated as VHDL record types in `dac_controller_pkg.vhd` to reduce port map verbosity and improve type safety. The following records are defined:

**Sample bus:**
- `t_sample_bus` — 8 samples per clock (4 converters × 2 samples: `m0_s0` through `m3_s1`)
- `t_sample_array` — unconstrained array of `signed(C_SAMPLE_BITS-1 downto 0)`

**JESD204B lane data:**
- `t_lane_data` — 4 lanes × 32 bits (`lane0`–`lane3`) per streaming source

**JESD sync CSR:**
- `t_jesd_sync_csr` — `sync_mode` (0 = per-DAC 2-link group, 1 = all-four) and `src_sel` (0 = NCO, 1 = FIFO)
- `t_jesd_sync_status` — `txlink_ready[3:0]`, `group_synced[1:0]`, `lmfc_aligned`, `sync_err[3:0]`, `src_switch_pending`, `src_active`

**Sine wave gen CSR:**
- `t_sine_csr` — `enable`, `conv_enable[3:0]`, per-converter frequency, phase offset, and amplitude fields

### Formatting

- 2-space indentation, <100 characters per line.
- One port per line. Generics declared before ports.
- Port ordering: `clk`, `rst`, inputs, outputs.
- Use **direct entity instantiation** (not component declarations):

```vhdl
u_fifo : entity work.DcFifo
  generic map (
    G_DATA_WIDTH => 128,
    G_DEPTH      => 512
  )
  port map (
    wr_clk   => clock_sink_clk,
    rd_clk   => txlink_clk,
    wr_data  => fifo_wr_data,
    rd_data  => fifo_rd_data
  );
```

### Comments
- Use comments to describe the purpose of entities and packages.
- Use comments to describe any major design decisions.

---

## 4. RTL Design Rules

### General

- No unintended latches. No undriven signals.
- Explicit bit widths on all assignments and type conversions.
- Arithmetic uses `signed` / `unsigned`. Use `std_logic_vector` only for raw bus data.
- **Records** are encouraged for grouping related signals (JESD lane bundles, CSR buses). Define record types in `dac_controller_pkg.vhd`.

### Synchronous Reset (default pattern)

All registers must be reset to known states using synchronous reset:

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      count <= (others => '0');
    else
      count <= count + 1;
    end if;
  end if;
end process;
```

### Reset Synchronization Across Clock Domains

The HPS reset (`reset_sink_reset`) is active-high and originates in the `clock_sink_clk` domain. Before use as a synchronous reset in the `txlink_clk` domain, it must be synchronized with a 2-stage synchronizer:

```vhdl
-- Standard pattern: synchronize reset_sink_reset into txlink_clk domain
signal txlink_rst_meta : std_logic := '1';
signal txlink_rst      : std_logic := '1';

process(txlink_clk)
begin
  if rising_edge(txlink_clk) then
    txlink_rst_meta <= reset_sink_reset;
    txlink_rst      <= txlink_rst_meta;
  end if;
end process;
-- Use txlink_rst as the synchronous reset for all txlink_clk domain logic.
```

> **Rule:** Never use `reset_sink_reset` directly in `txlink_clk` domain logic. The `DcFifo` module accepts synchronous active-high resets on each port; the caller is responsible for passing the domain-correct reset.

### Clock Domain Crossings

All cross-domain transfers **must** use CDC-safe structures.

**Single-bit signals** → 2-stage synchronizer:

```vhdl
process(clk_dst)
begin
  if rising_edge(clk_dst) then
    sync_meta <= async_in;
    sync_out  <= sync_meta;
  end if;
end process;
```

**Single-bit pulses** → toggle synchronizer (used for error-clear feedback between `clock_sink_clk` and `txlink_clk`):

```vhdl
-- Source domain: toggle on each pulse
process(clk_src)
begin
  if rising_edge(clk_src) then
    if rst_src = '1' then
      toggle_src <= '0';
    elsif pulse_in = '1' then
      toggle_src <= not toggle_src;
    end if;
  end if;
end process;

-- Destination domain: detect toggle edge → pulse
process(clk_dst)
begin
  if rising_edge(clk_dst) then
    toggle_meta <= toggle_src;
    toggle_sync <= toggle_meta;
    toggle_prev <= toggle_sync;
  end if;
end process;
pulse_out <= toggle_sync xor toggle_prev;
```

**Multi-bit buses** → dual-clock FIFO (use `DcFifo` wrapper in `dc_fifo.vhd`) or req/ack handshake. Gray-coded pointers for all FIFO-based crossings. **Never** synchronize a multi-bit bus directly.

**CSR readback of cross-domain status** → For status signals in the `txlink_clk` domain read via `clock_sink_clk`, use 2-stage synchronizers. Quasi-static signals (e.g., `txlink_ready`, `group_synced`) are acceptable. Acceptable staleness is ≤4 clock cycles.

### Synthesis Constraints

Design for: WNS ≥ 0.5 ns, <80% utilization on ALMs / M20K / DSP.

All CDC paths must be constrained with `set_false_path` or `set_max_delay`. Gray-code FIFO pointers must be explicitly constrained.

---

## 5. Project Structure

```
/src   RTL source (*.vhd)
/tb    testbenches (*_tb.vhd)
/sim   simulation scripts
/syn   Quartus project files
/doc   architecture docs, interface verification checklists
```

**Never commit** generated files: bitstreams, synthesis reports, waveform dumps, Quartus cache directories.

---

## 6. Verification

Every RTL module must have a **self-checking testbench**.

### Testbench Requirements

- File: `<module>_tb.vhd` in `/tb`.
- Must verify: reset behavior, nominal operation, edge cases, generic/parameter variations.
- Use `assert` statements — waveform-only inspection is insufficient.
- End successful simulations with:

```vhdl
report "SIMULATION PASSED" severity error;
std.env.stop;
```

### Testbench Design Rules (Questa FSE)

Questa FSE (free starter edition) has specific limitations that affect testbench design:

**Report severity:** Only `severity error` and `severity failure` produce visible output in batch mode (`vsim -c`). Both `severity note` and `severity warning` are silently suppressed. Use `severity error` for all informational testbench reports (test banners, results, diagnostics). Use `severity failure` only for the final stop on failure.

**Single driver per signal:** Every process that assigns to a signal creates a permanent VHDL driver. If two processes both assign to the same signal (e.g., a `p_rst` process and a `p_stim` process both driving `rst`), the resolution function produces `'X'` when they disagree — silently breaking the testbench with no error or warning. **Each signal must have exactly one driving process.** If the stimulus process needs to toggle `rst` mid-test, it must also handle the initial reset release.

**Minimize `math_real` function calls:** `ieee.math_real.sin()` takes ~100 ms per call in Questa FSE. This affects both RTL (LUT initialization) and testbenches (gold model references):
- In RTL: evaluate LUT initialization functions once as a `constant`, then replicate to signals via `(others => C_LUT_DATA)`.
- In RTL: use generics for LUT depth so testbenches can use smaller tables (e.g., `G_LUT_DEPTH => 128`) while synthesis uses the full size (e.g., 1024).
- In testbenches: spot-check gold model every Nth sample instead of every sample.

### Testbench Structure

```vhdl
-- Clock generation
constant CLK_PERIOD : time := 10 ns;
signal clk : std_logic := '0';
signal rst : std_logic := '1';

clk <= not clk after CLK_PERIOD / 2;

-- Single stimulus process drives rst, inputs, and checks outputs.
-- Do NOT use a separate reset process (causes multiple-driver issues).
process
begin
  -- Release reset after 5 cycles
  wait for CLK_PERIOD * 5;
  rst <= '0';
  wait until rising_edge(clk);
  -- drive inputs, check outputs with assert
  report "SIMULATION PASSED" severity error;
  std.env.stop;
end process;
```

### Simulation

Primary simulator: **Questa FSE** (Intel Quartus installation)

Path: `D:\altera_standard\25.1std\questa_fse\win64`

License: `D:\altera_standard\25.1std\licenses\LR-295193_License.dat`
Set `SALT_LICENSE_SERVER` before running `vsim`. The free starter edition only allows one concurrent session — do not launch a second `vsim` while one is running.

Always use `-voptargs="+acc"` — without it, the optimizer may strip testbench processes and reports. Always delete the `work` directory before recompiling to avoid stale optimizer cache (`_opt`) loading outdated designs.

```bash
# Set license and PATH
export SALT_LICENSE_SERVER="D:/altera_standard/25.1std/licenses/LR-295193_License.dat"
export PATH="/d/altera_standard/25.1std/questa_fse/win64:$PATH"

# Clean build (always start fresh to avoid stale vopt cache)
rm -rf work && vlib work

# Compile (repeat for each source + testbench file)
vcom -2008 src/dac_controller_pkg.vhd src/<module>.vhd tb/<module>_tb.vhd

# Run simulation in batch mode
vsim -c -voptargs="+acc" -do "set NumericStdNoWarnings 1; run -all; quit -f" work.<Module>_tb
```

### Test IDs

| Test ID Prefix | Module Scope |
|----------------|--------------|
| TB-NCO-*       | `sine_wave_gen` — NCO frequency, phase, amplitude |
| TB-JTXM-*      | `jesd_tx_manager` — sample packing, lane mapping  |
| TB-SYNC-*      | `jesd_sync_controller` — LMFC alignment, group sync |
| TB-MUX-*       | `data_src_mux` — NCO/FIFO source selection        |
| TB-DAC-INT-*   | `dac_controller_0` — top-level integration        |

**End of CLAUDE.md**
