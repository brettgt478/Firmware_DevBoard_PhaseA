# JESD204B Bring-up Sequence (AD9176 + Phase B dac_subsys)

End-to-end bring-up reference for the AD9176-FMC-EBZ on the Phase B
`agilex5_devkit` firmware. Pairs with
[doc/integration.md Procedure 5.A](integration.md#procedure-5a--jesd-link-bring-up--first-sine-wave-on-ad9176-rf-out)
(System Console over JTAG) and
[Procedure 7.A](integration.md#procedure-7a----linux-user-space-bring-up-of-ad9176-via-ad9176-config)
(Linux user-space). The sequence below is the abstract spec; the two
procedures are the executable transports.

> **Authoritative software entry-points:** the C-side implementation is
> [software/ad9176_config/ad9176_init.c](../software/ad9176_config/ad9176_init.c).
> If the doc and the code disagree, the code is the source of truth --
> file an update.

---

## 1. Pre-conditions (must be true before bring-up starts)

| Pre-condition | How to check |
|---------------|--------------|
| FMC VADJ programmed to 1.2 V (CLAUDE.md s6 #3) | Multimeter on the dev kit VADJ jumper bank; MAX10 PGOOD LED solid |
| AD9176-FMC-EBZ seated, HMC7044 PLLed to internal reference | Scope on AD9176 J5 (TRIG) for the device clock; HMC7044 LOCK LED |
| Bitstream programmed via `quartus_pgm` (`.sof` or `_time_limited.sof`) | Quartus `Programmer` -- success message; FPGA CONF_DONE asserted |
| `fmc_handshake.fmc_ready` asserted | `devmem 0x02001120` returns `0x21` (bits 0 + 5) -- or peek 0x02001120 from user-space |
| HPS booted, LWS2F window mapped | `ad9176-config status` exits 0 |

If `fmc_ready` is `0`, **stop**. The JESD GTS reset is held asserted by
the gate in [agilex5_devkit.sv line 239-240](../projects/agilex5_devkit/agilex5_devkit.sv);
no further step will succeed.

---

## 2. AD9176 SPI register sequence

Numbered against the AD9176 datasheet Rev. C Table 50 ordering. All
addresses 16-bit; the Phase B fabric SPI master uses 24-bit framing
(`[23] R/W | [22:16] reserved | [15:0] addr` for header, then 8 data
bits in the same 24-bit shift -- see
[ad9176_fmc_ebz.c](../software/ad9176_config/ad9176_fmc_ebz.c)
`spi_write24`/`spi_read24`).

### Step 1 -- Soft reset and ID verify

| # | Reg | Addr | Value | Notes |
|---|-----|------|-------|-------|
| 1.1 | `AD9176_REG_SOFT_RESET` | `0x000` | `0x81` | Self-clearing soft reset (Phase A uses this same value). Wait >= 2 ms. |
| 1.2 | `AD9176_REG_SOFT_RESET` | `0x000` | `0x00` | Clear the reset latch. Wait >= 2 ms. |
| 1.3 | `AD9176_REG_CHIPTYPE` | `0x003` | _read_ | Expect `0x04`. |
| 1.4 | `AD9176_REG_PRODIDL` | `0x004` | _read_ | Expect `0x76`. |
| 1.5 | `AD9176_REG_PRODIDH` | `0x005` | _read_ | Expect `0x91`. Combined product ID = `0x9176`. |

If the ID doesn't match: SPI is not reaching the AD9176 -- check
`fmc_spi_en` PIO and `fmc_pe_ctrl` (Procedure 4.B).

### Step 2 -- DAC PLL + interpolation

| # | Reg | Addr | Value | Notes |
|---|-----|------|-------|-------|
| 2.1 | `AD9176_REG_DACPLL_CTRL` | `0x095` | `0x01` | DAC PLL enable. Wait >= 5 ms for settle. |
| 2.2 | `AD9176_REG_DACPLL_STATUS` | `0x096` | _read_ | Expect bit 0 = `1` (LOCK). |
| 2.3 | `AD9176_REG_INTERP_CTRL` | `0x198` | `0x04` | 4x main interpolation: 625 MSPS per-converter JESD rate -> 2.5 GSPS DAC rate. |

### Step 3 -- JESD link parameters (mode 4)

AD9176 stores L/K/M as `value = parameter - 1`.

| # | Reg | Addr | Value | Meaning |
|---|-----|------|-------|---------|
| 3.1 | `AD9176_REG_JESD_L_CTRL` | `0x450` | `0x03` | L = 4 lanes per link |
| 3.2 | `AD9176_REG_JESD_K_CTRL` | `0x451` | `0x1F` | K = 32 frames per multiframe |
| 3.3 | `AD9176_REG_JESD_M_CTRL` | `0x452` | `0x03` | M = 4 converters per link |
| 3.4 | `AD9176_REG_JESD_MISC_CTRL` | `0x453` | `0xA0` | HD=1 (bit 7), SCR=1 (bit 5), S-1=0 (bits 4:0) |
| 3.5 | _(other JESD regs)_ | various | per Phase A `reference/ad9176_init.c` | Cross-bar / lane-map regs -- preserve verbatim from the Phase A initial sequence |

> The fact that the AD9176 stores `L-1` etc. is the source of the most
> common bring-up mistake. Mode-4 _physical_ value is L=4, but the
> register holds `0x03`. Phase A's original sequence got this right;
> the Phase B C code preserves it.

### Step 4 -- Link enable

| # | Reg | Addr | Value | Notes |
|---|-----|------|-------|-------|
| 4.1 | `AD9176_REG_LINK_CTRL0` | `0x300` | `0x01` | Enable the JESD link state machine on the AD9176 side. |

The AD9176 is now listening for FPGA-side lane data + ILAS.

---

## 3. FPGA-side sequence (in parallel after Step 4)

The JESD GTS IP starts trying to bring up its TX lanes as soon as its
reset deasserts (`jesd_reset_n_gated`). Because the gate includes
`fmc_ready`, the PMA will already be running by the time
`ad9176-config bringup` reaches this step; the AD9176 just wasn't
ready to receive yet.

### Step 5 -- Release sync

Write `1` to `REG_JESD_SYNC_CTRL` (LWS2F offset `0x0200_0020`):

```c
ad9176_csr_write(ctx, DAC_CTRL_OFFSET + REG_JESD_SYNC_CTRL, 0x00000001);
```

This sets the `start` bit of Phase A's `JesdSyncController` state
machine. The controller:

- Waits for both `u_jesd_link*.tx_link_ready` to assert.
- Waits for `u_dac_controller_0.LinkClkLocked` (set by the
  DcFifo when its read pointer has been stable for N cycles).
- Once both gates pass, deasserts the toggle synchronizer that drives
  the `sync_n` output (Phase A's classic LMFC-aligned release).

### Step 6 -- Poll sync status

Read `REG_JESD_SYNC_STATUS` (LWS2F offset `0x0200_0024`) until:

| Field | Mask | Expected |
|-------|------|----------|
| `txlink_ready` | `0x0F` | `0xF` (all 4 lanes per link ready on both links -> 0xF combined per
[ad9176_init.c line 116](../software/ad9176_config/ad9176_init.c#L116)) |
| `group_synced` | `0x300` | `0x3` (both link groups synced) |
| `lmfc_aligned` | `0x400` | `1` |

`ad9176_init.c::dac_subsys_wait_link_lock` polls at 1 ms cadence with a
5000 ms timeout.

If the timeout fires, capture the GTS link CSR snapshot via
`ad9176-config peek 0x2000 .. 0x2FFC` (link 0) and `0x3000 .. 0x3FFC`
(link 1) and file in [potential_issues.md](potential_issues.md).
Common causes:

- **All-zeros GTS CSR**: the GTS Reset Sequencer is missing
  (ISSUE-019). PLL_LOCKED never asserts.
- **PLL_LOCKED set, LANE_READY clear**: lane mapping mismatch. Check
  AD9176 cross-bar registers vs. the GTS IP `lane_map`.
- **PLL_LOCKED + LANE_READY set, FRAME_READY clear**: ILAS mismatch.
  Re-check mode-4 register values (Step 3 above) against the GTS IP
  parameters.
- **All set on FPGA side, AD9176 still asserts sync_n**: SUBCLASSV
  strap mismatch. Drop the FPGA to subclass-0 via the GTS IP runtime
  CSR (`SUBCLASSV = 0`) and retry.

### Step 7 -- Configure NCO source (FPGA SineWaveGen)

Phase A's `SineWaveGen` is the test source for Stage 5/7 bring-up.
Frequency word = `freq_hz x 2^32 / fs_hz`.

| # | LWS2F offset | Value | Notes |
|---|--------------|-------|-------|
| 7.1 | `0x0200_0048` (`REG_SINE_FREQ_CH1_I`) | freq word | Channel 1 I |
| 7.2 | `0x0200_004C` (`REG_SINE_FREQ_CH1_Q`) | freq word | Channel 1 Q |
| 7.3 | `0x0200_0050` (`REG_SINE_FREQ_CH2_I`) | freq word | Channel 2 I |
| 7.4 | `0x0200_0054` (`REG_SINE_FREQ_CH2_Q`) | freq word | Channel 2 Q |
| 7.5 | `0x0200_0060..006C` (phase regs) | I = `0x00000000`, Q = `0x40000000` | +90 deg via top-bit offset |
| 7.6 | `0x0200_0070..007C` (amp regs) | `0x00007FFF` per converter | Near full scale |
| 7.7 | `0x0200_0040` (`REG_SINE_CTRL`) | `0x0000001F` | Enable mask: bits 4:1 per-converter, bit 0 global |
| 7.8 | `0x0200_0080` (`REG_JESD_TX_SRC_SEL`) | `0x00000000` | Select NCO as transport source |

### Step 8 -- AD9176 TX enable

Assert both `TXEN[1:0]` via the PIO at `0x0200_1100`:

```c
ad9176_set_tx_en(ctx, 0x3);   /* both inputs hot */
```

The AD9176 main DAC starts emitting on RF outputs J1..J4.

---

## 4. Verification at each step

| Step | Software gate (sim or HPS) | Hardware gate |
|------|---------------------------|---------------|
| 1 | `chip_type == 0x04 && prod_id == 0x9176` | --- |
| 2.1 | `DACPLL_STATUS & 0x01 == 0x01` (LOCK) | --- |
| 3 | _none_ -- register writes only | --- |
| 5..6 | `JESD_SYNC_STATUS` reads `txlink=0xF grp=0x3 lmfc=1` | Scope on FMC `LA01/LA02` -- `sync_n` rises from 0 to 1 (handshake done) |
| 7 | `peek 0x0200_0040` returns `0x1F` | --- |
| 8 | `peek 0x0200_1100` returns `0x3` | Scope on AD9176 J1: sine at the configured frequency |

Stage 8b's `dac_subsys_tb.sv` exercises Steps 5, 7, 8 over the LWH2F
AXI BFM (no real JESD link layer); a regression there indicates a
fabric-side break, not a JESD or AD9176 break.

---

## 5. Subclass-0 fallback

Subclass-1 deterministic latency requires the AD9176-FMC-EBZ
SYSREF/GBTCLK0 phasing to meet source-sync timing at the FPGA
balls. The kit strap default is subclass-1 capable; **if** during
bring-up the LMFC alignment is unstable (Step 6 `lmfc_aligned`
oscillates), drop to subclass-0:

- AD9176 side: write subclass-0 to `AD9176_REG_JESD_MISC_CTRL` bit
  pattern per datasheet Table 75.
- FPGA side: write `SUBCLASSV = 0` to the GTS IP CSR (offset is GTS
  IP-version-dependent -- consult the JESD204B IP CSR map under
  `D:/altera_pro/26.1/ip/altera/jesd204b_gts/`).

Subclass-0 doesn't need SYSREF; the determinism guarantee is dropped
but link sync still works. For the dev-board signal-generation use
case, subclass-0 is acceptable.

---

## 6. Cross-references

- [architecture.md](architecture.md) -- system overview, clock domains, address map
- [integration.md Procedure 5.A](integration.md) -- JTAG/System Console transport
- [integration.md Procedure 7.A](integration.md) -- Linux user-space transport
- [software/ad9176_config/ad9176_init.c](../software/ad9176_config/ad9176_init.c) -- C source of truth
- [software/ad9176_config/dac_subsys_regs.h](../software/ad9176_config/dac_subsys_regs.h) -- LWS2F register map
- [potential_issues.md ISSUE-019](potential_issues.md) -- GTS Reset Sequencer gap (likely Step 5 blocker)
