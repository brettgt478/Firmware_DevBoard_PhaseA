-- =============================================================================
-- Testbench:   RegBank_tb
-- Description: Self-checking testbench for RegBank (dac_controller_0 variant).
--              10-bit Avalon-MM address space, no SPI registers.
--              Tests: scratchpad R/W, CSR output ports, status readback,
--              invalid-address decode, reset defaults, PIO stub, adjacent
--              register corruption, JESD error-clear pulse.
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- Updated:     2026-04-07  Adapted for DacControllerPkg: 10-bit addresses,
--                          SPI tests removed, PIO stub test added.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity RegBank_tb is
end entity RegBank_tb;

architecture sim of RegBank_tb is

  constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Avalon-MM signals (10-bit address)
  signal avmm_address     : std_logic_vector(C_AVMM_ADDR_WIDTH - 1 downto 0)
    := (others => '0');
  signal avmm_read        : std_logic := '0';
  signal avmm_write       : std_logic := '0';
  signal avmm_writedata   : std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0)
    := (others => '0');
  signal avmm_readdata    : std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
  signal avmm_waitrequest : std_logic;

  -- CSR interfaces
  signal sine_csr_o        : t_sine_csr;
  signal jesd_sync_csr_o   : t_jesd_sync_csr;
  signal jesd_sync_stat_i  : t_jesd_sync_status := (
    txlink_ready       => "1010",
    group_synced       => "01",
    lmfc_aligned       => '1',
    sync_err           => "0011",
    src_switch_pending => '1',
    src_active         => '0'
  );
  signal jesd_sync_err_clr : std_logic_vector(3 downto 0);

  -- PIO stub
  signal pio_ctrl_reg  : std_logic_vector(31 downto 0);
  signal pio_stat_in   : std_logic_vector(31 downto 0) := x"BABE1234";

  signal error_count : integer := 0;

  -- =========================================================================
  -- Helper procedures (Avalon-MM, zero-wait-state slave)
  -- =========================================================================
  procedure avmm_wr(
    signal clk_s   : in    std_logic;
    signal addr_s  : out   std_logic_vector(C_AVMM_ADDR_WIDTH - 1 downto 0);
    signal write_s : out   std_logic;
    signal wdata_s : out   std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
    constant a     : in    unsigned(C_AVMM_ADDR_WIDTH - 1 downto 0);
    constant d     : in    std_logic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk_s);
    addr_s  <= std_logic_vector(a);
    wdata_s <= d;
    write_s <= '1';
    wait until rising_edge(clk_s);
    write_s <= '0';
  end procedure;

  procedure avmm_rd(
    signal clk_s   : in    std_logic;
    signal addr_s  : out   std_logic_vector(C_AVMM_ADDR_WIDTH - 1 downto 0);
    signal read_s  : out   std_logic;
    signal rdata_s : in    std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
    constant a     : in    unsigned(C_AVMM_ADDR_WIDTH - 1 downto 0);
    variable d     : out   std_logic_vector(31 downto 0)
  ) is
  begin
    wait until rising_edge(clk_s);
    addr_s <= std_logic_vector(a);
    read_s <= '1';
    wait until rising_edge(clk_s);
    d      := rdata_s;
    read_s <= '0';
  end procedure;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- DUT
  u_dut : entity work.RegBank
    port map (
      clk               => clk,
      rst               => rst,
      avmm_address      => avmm_address,
      avmm_read         => avmm_read,
      avmm_write        => avmm_write,
      avmm_writedata    => avmm_writedata,
      avmm_readdata     => avmm_readdata,
      avmm_waitrequest  => avmm_waitrequest,
      sine_csr          => sine_csr_o,
      jesd_sync_csr     => jesd_sync_csr_o,
      jesd_sync_status  => jesd_sync_stat_i,
      jesd_sync_err_clr => jesd_sync_err_clr,
      pio_ctrl_reg      => pio_ctrl_reg,
      pio_stat_in       => pio_stat_in
    );

  -- =========================================================================
  -- Stimulus
  -- =========================================================================
  p_stim : process
    variable rd_val : std_logic_vector(31 downto 0);
  begin
    -- -----------------------------------------------------------------------
    -- Power-on reset
    -- -----------------------------------------------------------------------
    rst <= '1';
    wait for CLK_PERIOD * 5;
    rst <= '0';
    wait until rising_edge(clk);

    -- =======================================================================
    -- TB-REG-001: Scratchpad write / read
    -- =======================================================================
    report "TB-REG-001: Scratchpad write/read";

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH0, x"DEADBEEF");
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH1, x"CAFEBABE");
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH2, x"12345678");
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH3, x"A5A5A5A5");

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH0, rd_val);
    assert rd_val = x"DEADBEEF"
      report "TB-REG-001 FAIL: SCRATCH0 got " & to_hstring(unsigned(rd_val))
      severity error;
    if rd_val /= x"DEADBEEF" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH1, rd_val);
    assert rd_val = x"CAFEBABE"
      report "TB-REG-001 FAIL: SCRATCH1" severity error;
    if rd_val /= x"CAFEBABE" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH2, rd_val);
    assert rd_val = x"12345678"
      report "TB-REG-001 FAIL: SCRATCH2" severity error;
    if rd_val /= x"12345678" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH3, rd_val);
    assert rd_val = x"A5A5A5A5"
      report "TB-REG-001 FAIL: SCRATCH3" severity error;
    if rd_val /= x"A5A5A5A5" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-REG-002: CSR write -> output port verification
    -- =======================================================================
    report "TB-REG-002: CSR write to output ports";

    -- Sine frequency words
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_FREQ_CH1_I, x"051EB851");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.freq_m0) = x"051EB851"
      report "TB-REG-002 FAIL: freq_m0" severity error;
    if std_logic_vector(sine_csr_o.freq_m0) /= x"051EB851" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_FREQ_CH1_Q, x"0A3D70A3");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.freq_m1) = x"0A3D70A3"
      report "TB-REG-002 FAIL: freq_m1" severity error;
    if std_logic_vector(sine_csr_o.freq_m1) /= x"0A3D70A3" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_FREQ_CH2_I, x"147AE147");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.freq_m2) = x"147AE147"
      report "TB-REG-002 FAIL: freq_m2" severity error;
    if std_logic_vector(sine_csr_o.freq_m2) /= x"147AE147" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_FREQ_CH2_Q, x"1EB851EB");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.freq_m3) = x"1EB851EB"
      report "TB-REG-002 FAIL: freq_m3" severity error;
    if std_logic_vector(sine_csr_o.freq_m3) /= x"1EB851EB" then
      error_count <= error_count + 1;
    end if;

    -- Sine enable and conv_enable
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_CTRL, x"0000001F");
    wait until rising_edge(clk);
    assert sine_csr_o.enable = '1'
      report "TB-REG-002 FAIL: sine enable" severity error;
    if sine_csr_o.enable /= '1' then error_count <= error_count + 1; end if;
    assert sine_csr_o.conv_enable = "1111"
      report "TB-REG-002 FAIL: conv_enable" severity error;
    if sine_csr_o.conv_enable /= "1111" then
      error_count <= error_count + 1;
    end if;

    -- Phase offsets
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_PHASE_M0, x"40000000");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.phase_ofs_m0) = x"40000000"
      report "TB-REG-002 FAIL: phase_ofs_m0" severity error;
    if std_logic_vector(sine_csr_o.phase_ofs_m0) /= x"40000000" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_PHASE_M1, x"80000000");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.phase_ofs_m1) = x"80000000"
      report "TB-REG-002 FAIL: phase_ofs_m1" severity error;
    if std_logic_vector(sine_csr_o.phase_ofs_m1) /= x"80000000" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_PHASE_M2, x"C0000000");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.phase_ofs_m2) = x"C0000000"
      report "TB-REG-002 FAIL: phase_ofs_m2" severity error;
    if std_logic_vector(sine_csr_o.phase_ofs_m2) /= x"C0000000" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_PHASE_M3, x"00100000");
    wait until rising_edge(clk);
    assert std_logic_vector(sine_csr_o.phase_ofs_m3) = x"00100000"
      report "TB-REG-002 FAIL: phase_ofs_m3" severity error;
    if std_logic_vector(sine_csr_o.phase_ofs_m3) /= x"00100000" then
      error_count <= error_count + 1;
    end if;

    -- Amplitudes
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_AMP_M0, x"00003FFF");
    wait until rising_edge(clk);
    assert sine_csr_o.amplitude_m0 = x"3FFF"
      report "TB-REG-002 FAIL: amplitude_m0" severity error;
    if sine_csr_o.amplitude_m0 /= x"3FFF" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_AMP_M1, x"00001FFF");
    wait until rising_edge(clk);
    assert sine_csr_o.amplitude_m1 = x"1FFF"
      report "TB-REG-002 FAIL: amplitude_m1" severity error;
    if sine_csr_o.amplitude_m1 /= x"1FFF" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_AMP_M2, x"00000FFF");
    wait until rising_edge(clk);
    assert sine_csr_o.amplitude_m2 = x"0FFF"
      report "TB-REG-002 FAIL: amplitude_m2" severity error;
    if sine_csr_o.amplitude_m2 /= x"0FFF" then
      error_count <= error_count + 1;
    end if;

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_AMP_M3, x"000007FF");
    wait until rising_edge(clk);
    assert sine_csr_o.amplitude_m3 = x"07FF"
      report "TB-REG-002 FAIL: amplitude_m3" severity error;
    if sine_csr_o.amplitude_m3 /= x"07FF" then
      error_count <= error_count + 1;
    end if;

    -- JESD sync mode
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_JESD_SYNC_CTRL, x"00000001");
    wait until rising_edge(clk);
    assert jesd_sync_csr_o.sync_mode = '1'
      report "TB-REG-002 FAIL: sync_mode" severity error;
    if jesd_sync_csr_o.sync_mode /= '1' then
      error_count <= error_count + 1;
    end if;

    -- JESD source select
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_JESD_TX_SRC_SEL, x"00000001");
    wait until rising_edge(clk);
    assert jesd_sync_csr_o.src_sel = '1'
      report "TB-REG-002 FAIL: src_sel" severity error;
    if jesd_sync_csr_o.src_sel /= '1' then
      error_count <= error_count + 1;
    end if;

    -- =======================================================================
    -- TB-REG-003: JESD sync error clear pulse (W1C)
    -- =======================================================================
    report "TB-REG-003: JESD sync error clear pulse";

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_JESD_SYNC_ERR, x"00000005");
    wait until rising_edge(clk);
    assert jesd_sync_err_clr = "0101"
      report "TB-REG-003 FAIL: err_clr not 0101" severity error;
    if jesd_sync_err_clr /= "0101" then error_count <= error_count + 1; end if;

    wait until rising_edge(clk);
    assert jesd_sync_err_clr = "0000"
      report "TB-REG-003 FAIL: err_clr not cleared after 1 cycle" severity error;
    if jesd_sync_err_clr /= "0000" then error_count <= error_count + 1; end if;

    -- Verify stays low on unrelated write
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH0, x"FFFFFFFF");
    wait until rising_edge(clk);
    assert jesd_sync_err_clr = "0000"
      report "TB-REG-003 FAIL: err_clr asserted on unrelated write" severity error;
    if jesd_sync_err_clr /= "0000" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-REG-004: Status register readback
    -- =======================================================================
    report "TB-REG-004: Status register readback";

    -- JESD sync status
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_JESD_SYNC_STATUS, rd_val);
    assert rd_val(3 downto 0) = "1010"
      report "TB-REG-004 FAIL: txlink_ready" severity error;
    if rd_val(3 downto 0) /= "1010" then error_count <= error_count + 1; end if;
    assert rd_val(5 downto 4) = "01"
      report "TB-REG-004 FAIL: group_synced" severity error;
    if rd_val(5 downto 4) /= "01" then error_count <= error_count + 1; end if;
    assert rd_val(6) = '1'
      report "TB-REG-004 FAIL: lmfc_aligned" severity error;
    if rd_val(6) /= '1' then error_count <= error_count + 1; end if;

    -- JESD sync error
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_JESD_SYNC_ERR, rd_val);
    assert rd_val(3 downto 0) = "0011"
      report "TB-REG-004 FAIL: sync_err" severity error;
    if rd_val(3 downto 0) /= "0011" then error_count <= error_count + 1; end if;

    -- JESD TX src status
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_JESD_TX_SRC_STAT, rd_val);
    assert rd_val(0) = '1'
      report "TB-REG-004 FAIL: src_switch_pending" severity error;
    if rd_val(0) /= '1' then error_count <= error_count + 1; end if;
    assert rd_val(1) = '0'
      report "TB-REG-004 FAIL: src_active" severity error;
    if rd_val(1) /= '0' then error_count <= error_count + 1; end if;

    -- PIO status readback (pio_stat_in = 0xBABE1234)
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_PIO_STATUS, rd_val);
    assert rd_val = x"BABE1234"
      report "TB-REG-004 FAIL: pio_status got " &
        to_hstring(unsigned(rd_val)) & " expected BABE1234" severity error;
    if rd_val /= x"BABE1234" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-REG-005: PIO control stub write / readback
    -- =======================================================================
    report "TB-REG-005: PIO control stub";

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_PIO_CTRL, x"AABBCCDD");
    wait until rising_edge(clk);
    assert pio_ctrl_reg = x"AABBCCDD"
      report "TB-REG-005 FAIL: pio_ctrl_reg output" severity error;
    if pio_ctrl_reg /= x"AABBCCDD" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_PIO_CTRL, rd_val);
    assert rd_val = x"AABBCCDD"
      report "TB-REG-005 FAIL: pio_ctrl readback" severity error;
    if rd_val /= x"AABBCCDD" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-REG-006: Invalid address returns zero (no SPI window in this variant)
    -- =======================================================================
    report "TB-REG-006: Invalid address returns zero";

    -- Gap between scratchpad and JESD
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      to_unsigned(16#010#, C_AVMM_ADDR_WIDTH), rd_val);
    assert rd_val = x"00000000"
      report "TB-REG-006 FAIL: 0x010 not zero" severity error;
    if rd_val /= x"00000000" then error_count <= error_count + 1; end if;

    -- Gap between JESD and sine blocks
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      to_unsigned(16#03C#, C_AVMM_ADDR_WIDTH), rd_val);
    assert rd_val = x"00000000"
      report "TB-REG-006 FAIL: 0x03C not zero" severity error;
    if rd_val /= x"00000000" then error_count <= error_count + 1; end if;

    -- Gap above PIO block
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      to_unsigned(16#090#, C_AVMM_ADDR_WIDTH), rd_val);
    assert rd_val = x"00000000"
      report "TB-REG-006 FAIL: 0x090 not zero" severity error;
    if rd_val /= x"00000000" then error_count <= error_count + 1; end if;

    -- Top of 10-bit space
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      to_unsigned(16#3FC#, C_AVMM_ADDR_WIDTH), rd_val);
    assert rd_val = x"00000000"
      report "TB-REG-006 FAIL: 0x3FC not zero" severity error;
    if rd_val /= x"00000000" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-REG-007: Reset defaults
    -- =======================================================================
    report "TB-REG-007: Reset defaults";

    rst <= '1';
    wait for CLK_PERIOD * 3;
    rst <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Scratchpad cleared
    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH0, rd_val);
    assert rd_val = x"00000000"
      report "TB-REG-007 FAIL: scratch0 not zero after reset" severity error;
    if rd_val /= x"00000000" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH1, rd_val);
    assert rd_val = x"00000000"
      report "TB-REG-007 FAIL: scratch1 not zero after reset" severity error;
    if rd_val /= x"00000000" then error_count <= error_count + 1; end if;

    -- Sine CSR defaults
    assert sine_csr_o.enable = '0'
      report "TB-REG-007 FAIL: sine enable not 0" severity error;
    if sine_csr_o.enable /= '0' then error_count <= error_count + 1; end if;

    assert sine_csr_o.conv_enable = "0000"
      report "TB-REG-007 FAIL: conv_enable not 0" severity error;
    if sine_csr_o.conv_enable /= "0000" then
      error_count <= error_count + 1;
    end if;

    assert sine_csr_o.freq_m0 = x"00000000"
      report "TB-REG-007 FAIL: freq_m0 not 0" severity error;
    if sine_csr_o.freq_m0 /= x"00000000" then
      error_count <= error_count + 1;
    end if;

    assert sine_csr_o.amplitude_m0 = x"7FFF"
      report "TB-REG-007 FAIL: amplitude_m0 default" severity error;
    if sine_csr_o.amplitude_m0 /= x"7FFF" then
      error_count <= error_count + 1;
    end if;

    assert sine_csr_o.amplitude_m1 = x"7FFF"
      report "TB-REG-007 FAIL: amplitude_m1 default" severity error;
    if sine_csr_o.amplitude_m1 /= x"7FFF" then
      error_count <= error_count + 1;
    end if;

    assert sine_csr_o.amplitude_m2 = x"7FFF"
      report "TB-REG-007 FAIL: amplitude_m2 default" severity error;
    if sine_csr_o.amplitude_m2 /= x"7FFF" then
      error_count <= error_count + 1;
    end if;

    assert sine_csr_o.amplitude_m3 = x"7FFF"
      report "TB-REG-007 FAIL: amplitude_m3 default" severity error;
    if sine_csr_o.amplitude_m3 /= x"7FFF" then
      error_count <= error_count + 1;
    end if;

    -- JESD CSR defaults
    assert jesd_sync_csr_o.sync_mode = '0'
      report "TB-REG-007 FAIL: sync_mode not 0" severity error;
    if jesd_sync_csr_o.sync_mode /= '0' then
      error_count <= error_count + 1;
    end if;

    assert jesd_sync_csr_o.src_sel = '0'
      report "TB-REG-007 FAIL: src_sel not 0" severity error;
    if jesd_sync_csr_o.src_sel /= '0' then
      error_count <= error_count + 1;
    end if;

    -- PIO ctrl cleared
    assert pio_ctrl_reg = x"00000000"
      report "TB-REG-007 FAIL: pio_ctrl not 0 after reset" severity error;
    if pio_ctrl_reg /= x"00000000" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-REG-008: Adjacent register corruption check
    -- =======================================================================
    report "TB-REG-008: Adjacent register corruption";

    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH0, x"11111111");
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH1, x"22222222");
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH2, x"33333333");
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH3, x"44444444");

    -- Overwrite only SCRATCH1
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SCRATCH1, x"EEEEEEEE");

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH0, rd_val);
    assert rd_val = x"11111111"
      report "TB-REG-008 FAIL: scratch0 corrupted" severity error;
    if rd_val /= x"11111111" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH1, rd_val);
    assert rd_val = x"EEEEEEEE"
      report "TB-REG-008 FAIL: scratch1 not updated" severity error;
    if rd_val /= x"EEEEEEEE" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH2, rd_val);
    assert rd_val = x"33333333"
      report "TB-REG-008 FAIL: scratch2 corrupted" severity error;
    if rd_val /= x"33333333" then error_count <= error_count + 1; end if;

    avmm_rd(clk, avmm_address, avmm_read, avmm_readdata,
      C_REG_SCRATCH3, rd_val);
    assert rd_val = x"44444444"
      report "TB-REG-008 FAIL: scratch3 corrupted" severity error;
    if rd_val /= x"44444444" then error_count <= error_count + 1; end if;

    -- Cross-block: write AMP_M3, then PIO_CTRL; verify amp_m3 not corrupted
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_SINE_AMP_M3, x"0000ABCD");
    avmm_wr(clk, avmm_address, avmm_write, avmm_writedata,
      C_REG_PIO_CTRL, x"000000FF");
    wait until rising_edge(clk);
    assert sine_csr_o.amplitude_m3 = x"ABCD"
      report "TB-REG-008 FAIL: amp_m3 corrupted by PIO write" severity error;
    if sine_csr_o.amplitude_m3 /= x"ABCD" then
      error_count <= error_count + 1;
    end if;

    -- =======================================================================
    -- Summary
    -- =======================================================================
    wait for CLK_PERIOD * 5;
    if error_count = 0 then
      report "SIMULATION PASSED" severity error;
    else
      report "SIMULATION FAILED: " & integer'image(error_count) & " errors"
        severity failure;
    end if;
    std.env.stop;
  end process p_stim;

end architecture sim;
