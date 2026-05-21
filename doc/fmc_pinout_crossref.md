# FMC <-> AD9176 <-> FPGA Pin Cross-Reference

Authoritative pin map for the Phase B `agilex5_devkit` firmware. Derived
from two reference files in the repo root:

- [Agilex_FMC_Pinout.txt](../Agilex_FMC_Pinout.txt) -- dev-kit Table 21
  (J34 FMC connector mapping)
- [AD9176_Dev_Pinout.txt](../AD9176_Dev_Pinout.txt) -- AD9176-FMC-EBZ
  user-annotated mapping; **rightmost column is the FPGA BGA package
  pin** for the Phase B targeted device `A5ED065BB32AE6SR0`.

**Gotcha:** the `Agilex_FMC_Pinout.txt` "Pin Number" column is the
VITA 57.1 FMC-connector grid coordinate (`C2`, `D8`, `H2`, etc.), NOT
the FPGA package pin. Do not use it for `set_location_assignment`.
Stage 4 discovered this the hard way (see
[potential_issues.md ISSUE-012/013](potential_issues.md)).

---

## 1. JESD204B serial lanes (FPGA TX -> AD9176 SERDIN)

8 differential pairs, 12.5 Gbps each. Logical-to-physical lane map is
the column to read for software / GTS IP parameter alignment.

| AD9176 SERDIN (logical) | FMC connector (V57.1) | FMC connector name | FPGA package pin (P/N) | FPGA bank | dac_subsys port |
|-------------------------|-----------------------|--------------------|------------------------|-----------|-----------------|
| SERDIN0_P/N | A38 / A39 | FMC_TX5_P/N | BC7 / BC10 | UX 4C | `fmc_serdin_tx[5]_p/n` |
| SERDIN1_P/N | B36 / B37 | FMC_TX6_P/N | BA7 / BA10 | UX 4C | `fmc_serdin_tx[6]_p/n` |
| SERDIN2_P/N | A34 / A35 | FMC_TX4_P/N | BE7 / BE10 | UX 4C | `fmc_serdin_tx[4]_p/n` |
| SERDIN3_P/N | B32 / B33 | FMC_TX7_P/N | AW7 / AW10 | UX 4C | `fmc_serdin_tx[7]_p/n` |
| SERDIN4_P/N | A30 / A31 | FMC_TX3_P/N | AL7 / AL10 | UX 4B | `fmc_serdin_tx[3]_p/n` |
| SERDIN5_P/N | A26 / A27 | FMC_TX2_P/N | AN7 / AN10 | UX 4B | `fmc_serdin_tx[2]_p/n` |
| SERDIN6_P/N | A22 / A23 | FMC_TX1_P/N | AR7 / AR10 | UX 4B | `fmc_serdin_tx[1]_p/n` |
| SERDIN7_P/N | C2  / C3  | FMC_TX0_P/N | AU7 / AU10 | UX 4B | `fmc_serdin_tx[0]_p/n` |

**Tile split:** SERDIN0..3 are on UX 4C; SERDIN4..7 are on UX 4B.
This drives the dual-refclk requirement -- see Section 2.

In the top SystemVerilog, `fmc_serdin_tx[3:0]` go to `u_jesd_link0`
and `[7:4]` go to `u_jesd_link1` (see
[agilex5_devkit.sv line 399-402](../projects/agilex5_devkit/agilex5_devkit.sv#L399-L402)).
The logical mapping above (SERDIN0..3 -> link 0, SERDIN4..7 -> link 1)
is what the AD9176 expects; the FPGA pin numbering of
`fmc_serdin_tx[0..7]` is the IP-side ordering, NOT the AD9176-side
ordering. The mapping is swizzled inside the GTS IP `lane_map`
parameter (Stage 5).

---

## 2. Transceiver reference clocks (AD9176 -> FPGA)

Two single-ended refclk pads (each is a differential pair from the
AD9176 board's HMC7044). Both must run at 312.5 MHz; the GTS x40 PMA
PLL produces 12.5 Gbps lane rate.

| Signal | FMC connector (V57.1) | FMC connector name | FPGA package pin (P/N) | FPGA bank | dac_subsys port |
|--------|-----------------------|--------------------|------------------------|-----------|-----------------|
| BR40 (AD9176 device clock, FPGA refclk for link 0) | D4 / D5 | FMC_GBTCLK0_M2C_P/N | AP16 / AP21 | UX 4B | `fmc_gbtclk0_p/n` |
| BR40_EXT (FPGA refclk for link 1, ISSUE-015 fix) | B20 / B21 | FMC_GBTCLK1_M2C_P/N | AV16 / AV21 | UX 4C | `fmc_gbtclk1_p/n` |

Why two? Agilex 5 GTS does not support cross-tile refclk routing
(ISSUE-015). Because the SERDIN lanes straddle UX 4B (link 0) and
UX 4C (link 1), each tile needs its own refclk pad sourced from the
same HMC7044 output channel.

---

## 3. SYSREF (AD9176 -> FPGA, subclass-1 source-sync)

Single LVDS pair on HSIO 3B 1.2-V; sampled to `jesd_link_clk` in
[src/sysref_capture.vhd](../projects/agilex5_devkit/src/sysref_capture.vhd).

| Signal | FMC connector (V57.1) | FMC connector name | FPGA package pin (P/N) | FPGA bank | dac_subsys port |
|--------|-----------------------|--------------------|------------------------|-----------|-----------------|
| SYSREF2_P/N | G6 / G7 | FMC_1V2_LA_P0/N0 (LA00_CC) | A45 / B42 | HSIO 3B | `fmc_sysref` (single-ended, `fmc_sysref_p` is the only pin Quartus needs because LVDS_RX infers the receiver from `IO_STANDARD`) |

IO standard string for the QSF: `"1.2-V TRUE DIFFERENTIAL SIGNALING"`.

---

## 4. SYNC_N + SPI + housekeeping (HSIO 3B 1.2-V)

All on the HSIO 3B bank, IO standard `"1.2 V"` (no LVCMOS suffix --
Agilex 5 implicit at 1.2 V). SYNC_N pairs are LVDS in
[`agilex5_devkit.sv`](../projects/agilex5_devkit/agilex5_devkit.sv);
SPI / TXEN / PE_CTRL are single-ended 1.2 V.

| Signal | Direction | FMC connector (V57.1) | FMC connector name | FPGA package pin | dac_subsys port |
|--------|-----------|-----------------------|--------------------|------------------|-----------------|
| SYNC0_P/N | AD9176 -> FPGA | D8 / D9 | LA01_P_CC / LA01_N_CC | B45 / A48 | `fmc_sync0` (LVDS_RX -- the FPGA samples the AD9176-driven SYNC) |
| SYNC1_P/N | AD9176 -> FPGA | H7 / H8 | LA02_P / LA02_N | B51 / A51 | `fmc_sync1` |
| FMC_SCK | FPGA -> AD9176 | G9 | LA03_P | A54 | `fmc_spi_sck` |
| FMC_MOSI | FPGA -> AD9176 | G10 | LA03_N | B54 | `fmc_spi_mosi` |
| FMC_MISO | AD9176 -> FPGA | H10 | LA04_P | A63 | `fmc_spi_miso` |
| FMC_CS1 | FPGA -> AD9176 | H11 | LA04_N | B60 | `fmc_spi_cs1_n` |
| FMC_CS2 | FPGA -> AD9176 | D11 | LA05_P | B56 | `fmc_spi_cs2_n` |
| FMC_SPI_EN | FPGA -> AD9176 board | D12 | LA05_N | A60 | `fmc_spi_en` (level-shifter enable; gated by HPS PIO) |
| FMC_TXEN_0 | FPGA -> AD9176 | C10 | LA06_P | M58 | `fmc_txen[0]` |
| FMC_TXEN_1 | FPGA -> AD9176 | C11 | LA06_N | K58 | `fmc_txen[1]` |
| FMC_PE_CTRL | FPGA -> AD9176 board | H13 | LA07_P | F47 | `fmc_pe_ctrl` |

The `_CC` suffix on LA01 (SYNC0) and LA00 (SYNC1 is on LA02, not LA02_CC)
identifies the per-bank clock-capable differential pair -- the FPGA can
use it as a clock pin if the SDC declares one. We do for SYNC0 (LVDS
input pair).

---

## 5. 3.3-V housekeeping (FMC connector -> FPGA OR MAX10)

The dev kit splits FMC management between the Agilex and the on-board
**MAX10 board-management FPGA**. Only `PRSNT_M2C_L` reaches the Agilex;
`PG_C2M`, `PG_M2C`, `GA0`, `GA1`, `CLK_DIR`, `SCL`, `SDA`, JTAG TCK/TMS/TDI/TDO,
and `TRST_L` are routed to MAX10. See
[potential_issues.md ISSUE-012](potential_issues.md).

| Signal | Direction | FMC connector (V57.1) | Routed to | FPGA package pin (if applicable) |
|--------|-----------|-----------------------|-----------|---------------------------------|
| PRSNT_M2C_L | AD9176 board -> FPGA | H2 | Agilex | K8 (`fmc_prsnt_n`, 3.3-V LVCMOS) |
| PG_C2M | FPGA -> AD9176 board | D1 | MAX10 (dangling on Agilex; `u_pg_c2m_pio` loops back to status PIO for HPS diagnostic only) | not bonded externally |
| PG_M2C | AD9176 board -> FPGA | F1 | MAX10 (Agilex sees `1'b1` tied in `agilex5_devkit.sv` line 231) | not bonded |
| GA0 | strap | C34 | MAX10 only | not bonded |
| GA1 | strap | D35 | MAX10 only | not bonded |
| CLK_DIR | bidir | B1 | MAX10 only | not bonded |
| FMC_SCL / FMC_SDA | I2C | C30 / C31 | MAX10 only | not bonded |
| FMC_TCK..TRST_L | JTAG chain | D29..D34 | MAX10 only | not bonded |

If a future stage needs MAX10-side data on the Agilex (e.g. read `GA[1:0]`
or drive `PG_C2M` for real), it will route via the existing MAX10-to-Agilex
sideband (a few I2C / serial lines on housekeeping HSIO -- see the kit
schematic). Phase B does not need this.

---

## 6. QSF assignments summary

The pin assignments materialise in
[projects/agilex5_devkit/agilex5_devkit.qsf](../projects/agilex5_devkit/agilex5_devkit.qsf).
Every row in Sections 1-4 of this doc is a
`set_location_assignment` (P pin) + `set_location_assignment` (N pin)
+ `set_instance_assignment -name IO_STANDARD ...` pair.

`PROMOTE_WARNING_TO_ERROR 12677` is set in the QSF, so any top-level
port added in
[agilex5_devkit.sv](../projects/agilex5_devkit/agilex5_devkit.sv) without
a matching pin row in the QSF will abort the fit. Same goes for
`PROMOTE_WARNING_TO_ERROR 332148` (timing). CLAUDE.md s6 #1-#2 covers
both.

---

## 7. Cross-references

- [architecture.md](architecture.md) -- system overview, clock domains
- [CLAUDE.md s2 External Interfaces](../CLAUDE.md) -- pin-table summary
- [PLAN.md Appendix A](../PLAN.md) -- earlier pin table (now superseded by this doc; PLAN appendix kept for historical context)
- [potential_issues.md ISSUE-012](potential_issues.md) -- MAX10 owns FMC management
- [potential_issues.md ISSUE-013](potential_issues.md) -- Stage 1 dropped HPS IO48 pin locations
- [potential_issues.md ISSUE-015](potential_issues.md) -- GBTCLK1 added to fix cross-tile refclk
