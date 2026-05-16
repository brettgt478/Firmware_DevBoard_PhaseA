-- =============================================================================
-- Testbench:   DacController_tb
-- Description: End-to-end integration testbench for dac_controller_0.
--              Covers the full path: AXI4 -> AxiToAvmm -> RegBank ->
--              CDC -> SineWaveGen -> DataSrcMux -> JesdTxManager (x2) ->
--              JesdSyncController gate -> JESD streaming outputs.
--
-- Test cases:
--   TB-DAC-001  Scratchpad write/read via AXI4 (bridge + RegBank round-trip)
--   TB-DAC-002  NCO config -> CDC -> JESD streaming (end-to-end tone)
--   TB-DAC-003  Both JESD link outputs carry identical non-zero data
--   TB-DAC-004  Per-DAC sync: deassert link1 -> both links drop; recover on re-assert
--   TB-DAC-005  Status register readback via CDC -> RegBank -> AXI4
--   TB-DAC-006  JESD reset sequencer: rst_n releases after reset
--   TB-DAC-007  Data changes over time (not stuck / NCO is running)
--   TB-DAC-008  Amplitude register write/readback (all four converters)
--   TB-DAC-009  PIO control write/readback; PIO status pass-through
--   TB-DAC-010  Sync error register readback after link drop; W1C clear
--   TB-DAC-011  Source-status register: src_active=0 (NCO) after NCO enabled
--
-- Author:      Brett Taylor
-- Created:     2026-04-07
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity DacController_tb is
end entity DacController_tb;

architecture sim of DacController_tb is

  constant AXI_CLK_PERIOD  : time := 10 ns;  -- 100 MHz (clock_sink_clk)
  constant JESD_CLK_PERIOD : time := 4 ns;   -- 250 MHz (jesd204_tx_link_clk)
  constant C_TB_LUT_DEPTH  : positive := 64; -- small LUT for fast elaboration

  -- =========================================================================
  -- Clocks and reset
  -- =========================================================================
  signal clk_axi    : std_logic := '0';
  signal clk_jesd   : std_logic := '0';
  signal rst        : std_logic := '1';

  -- =========================================================================
  -- AXI4 bus (10-bit address matching lwhpm2fpga port widths)
  -- =========================================================================
  signal awid    : std_logic_vector(3 downto 0)  := (others => '0');
  signal awaddr  : std_logic_vector(9 downto 0)  := (others => '0');
  signal awlen   : std_logic_vector(7 downto 0)  := x"00";
  signal awsize  : std_logic_vector(2 downto 0)  := "010";
  signal awburst : std_logic_vector(1 downto 0)  := "01";
  signal awlock  : std_logic := '0';
  signal awcache : std_logic_vector(3 downto 0)  := (others => '0');
  signal awprot  : std_logic_vector(2 downto 0)  := (others => '0');
  signal awvalid : std_logic := '0';
  signal awready : std_logic;

  signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb   : std_logic_vector(3 downto 0)  := "1111";
  signal wlast   : std_logic := '1';
  signal wvalid  : std_logic := '0';
  signal wready  : std_logic;

  signal bid     : std_logic_vector(3 downto 0);
  signal bresp   : std_logic_vector(1 downto 0);
  signal bvalid  : std_logic;
  signal bready  : std_logic := '0';

  signal arid    : std_logic_vector(3 downto 0)  := (others => '0');
  signal araddr  : std_logic_vector(9 downto 0)  := (others => '0');
  signal arlen   : std_logic_vector(7 downto 0)  := x"00";
  signal arsize  : std_logic_vector(2 downto 0)  := "010";
  signal arburst : std_logic_vector(1 downto 0)  := "01";
  signal arlock  : std_logic := '0';
  signal arcache : std_logic_vector(3 downto 0)  := (others => '0');
  signal arprot  : std_logic_vector(2 downto 0)  := (others => '0');
  signal arvalid : std_logic := '0';
  signal arready : std_logic;

  signal rid     : std_logic_vector(3 downto 0);
  signal rdata   : std_logic_vector(31 downto 0);
  signal rresp   : std_logic_vector(1 downto 0);
  signal rlast   : std_logic;
  signal rvalid  : std_logic;
  signal rready  : std_logic := '0';

  -- =========================================================================
  -- JESD status inputs (frame_ready used as txlink_ready)
  -- =========================================================================
  signal frame_ready_0 : std_logic := '0';  -- link 0, DAC core A
  signal frame_ready_1 : std_logic := '0';  -- link 1, DAC core B

  -- =========================================================================
  -- JESD streaming outputs
  -- =========================================================================
  signal link0_data  : std_logic_vector(127 downto 0);
  signal link0_valid : std_logic;
  signal link1_data  : std_logic_vector(127 downto 0);
  signal link1_valid : std_logic;

  -- JESD reset monitor
  signal jesd_rst_n : std_logic;

  signal error_count : integer := 0;

  -- =========================================================================
  -- AXI4 BFM write procedure
  -- =========================================================================
  procedure axi4_write(
    constant a       : in  std_logic_vector(9 downto 0);
    constant d       : in  std_logic_vector(31 downto 0);
    signal   aclk    : in  std_logic;
    signal   s_awaddr  : out std_logic_vector(9 downto 0);
    signal   s_awvalid : out std_logic;
    signal   s_awready : in  std_logic;
    signal   s_wdata   : out std_logic_vector(31 downto 0);
    signal   s_wvalid  : out std_logic;
    signal   s_wready  : in  std_logic;
    signal   s_bvalid  : in  std_logic;
    signal   s_bready  : out std_logic
  ) is
  begin
    wait until rising_edge(aclk);
    s_awaddr  <= a;
    s_awvalid <= '1';
    s_wdata   <= d;
    s_wvalid  <= '1';
    loop
      wait until rising_edge(aclk);
      exit when s_awready = '1' and s_wready = '1';
    end loop;
    s_awvalid <= '0';
    s_wvalid  <= '0';
    s_bready  <= '1';
    loop
      wait until rising_edge(aclk);
      exit when s_bvalid = '1';
    end loop;
    s_bready <= '0';
  end procedure;

  -- =========================================================================
  -- AXI4 BFM read procedure
  -- =========================================================================
  procedure axi4_read(
    constant a       : in  std_logic_vector(9 downto 0);
    variable d       : out std_logic_vector(31 downto 0);
    signal   aclk    : in  std_logic;
    signal   s_araddr  : out std_logic_vector(9 downto 0);
    signal   s_arvalid : out std_logic;
    signal   s_arready : in  std_logic;
    signal   s_rdata   : in  std_logic_vector(31 downto 0);
    signal   s_rvalid  : in  std_logic;
    signal   s_rready  : out std_logic
  ) is
  begin
    wait until rising_edge(aclk);
    s_araddr  <= a;
    s_arvalid <= '1';
    loop
      wait until rising_edge(aclk);
      exit when s_arready = '1';
    end loop;
    s_arvalid <= '0';
    s_rready  <= '1';
    loop
      wait until rising_edge(aclk);
      if s_rvalid = '1' then
        d := s_rdata;
        exit;
      end if;
    end loop;
    s_rready <= '0';
  end procedure;

begin

  clk_axi  <= not clk_axi  after AXI_CLK_PERIOD / 2;
  clk_jesd <= not clk_jesd after JESD_CLK_PERIOD / 2;

  -- =========================================================================
  -- DUT
  -- =========================================================================
  u_dut : entity work.dac_controller_0
    generic map (
      G_LUT_DEPTH => C_TB_LUT_DEPTH
    )
    port map (
      -- AXI4
      lwhpm2fpga_awid    => awid,
      lwhpm2fpga_awaddr  => awaddr,
      lwhpm2fpga_awlen   => awlen,
      lwhpm2fpga_awsize  => awsize,
      lwhpm2fpga_awburst => awburst,
      lwhpm2fpga_awlock  => awlock,
      lwhpm2fpga_awcache => awcache,
      lwhpm2fpga_awprot  => awprot,
      lwhpm2fpga_awvalid => awvalid,
      lwhpm2fpga_awready => awready,
      lwhpm2fpga_wdata   => wdata,
      lwhpm2fpga_wstrb   => wstrb,
      lwhpm2fpga_wlast   => wlast,
      lwhpm2fpga_wvalid  => wvalid,
      lwhpm2fpga_wready  => wready,
      lwhpm2fpga_bid     => bid,
      lwhpm2fpga_bresp   => bresp,
      lwhpm2fpga_bvalid  => bvalid,
      lwhpm2fpga_bready  => bready,
      lwhpm2fpga_arid    => arid,
      lwhpm2fpga_araddr  => araddr,
      lwhpm2fpga_arlen   => arlen,
      lwhpm2fpga_arsize  => arsize,
      lwhpm2fpga_arburst => arburst,
      lwhpm2fpga_arlock  => arlock,
      lwhpm2fpga_arcache => arcache,
      lwhpm2fpga_arprot  => arprot,
      lwhpm2fpga_arvalid => arvalid,
      lwhpm2fpga_arready => arready,
      lwhpm2fpga_rid     => rid,
      lwhpm2fpga_rdata   => rdata,
      lwhpm2fpga_rresp   => rresp,
      lwhpm2fpga_rlast   => rlast,
      lwhpm2fpga_rvalid  => rvalid,
      lwhpm2fpga_rready  => rready,
      -- System
      reset_sink_reset   => rst,
      clock_sink_clk     => clk_axi,
      -- JESD link clock
      jesd204_tx_link_clk_clk => clk_jesd,
      -- JESD reset sequencer
      jesd_gts_ss_TX_intel_jesd_TX_jesd204_tx_in_of_reset_export   => '0',
      jesd_gts_ss_tx_outtel_jesd_tx_jesd204_tx_rst_n_reset_n       => jesd_rst_n,
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_rst_ack_n_export    => '1',
      -- GTS PLL / refclk
      jesd_gts_ss_TX_outtel_jesd_TX_txphy_clk_export               => (others => '0'),
      jesd_gts_ss_TX_outst_src_i_src_rs_priority_src_rs_priority   => open,
      jesd_gts_ss_tx_outst_src_o_refclk_fail_status_refclk_fail_status => (others => '0'),
      jesd_gts_ss_tx_outst_src_o_refclk_on_ack_refclk_on_ack       => '0',
      jesd_gts_ss_tx_outst_src_i_refclk_on_refclk_on               => open,
      core_pll_locked_export                                        => '1',
      -- JESD link 0 (DAC core A)
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_data           => link0_data,
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_valid          => link0_valid,
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_ready          => '1',
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_somf_export         => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_error_export  => open,
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_ready_export  => frame_ready_0,
      -- JESD link 1 (DAC core B)
      jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_data          => link1_data,
      jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_valid         => link1_valid,
      jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_ready         => '1',
      jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_error_export => open,
      jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_ready_export => frame_ready_1,
      -- JESD CSR exports (informational, tie off)
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_hd_export       => '1',
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_cs_export       => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_l_export        => std_logic_vector(
        to_unsigned(C_JESD_L - 1, 5)),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_k_export        => std_logic_vector(
        to_unsigned(C_JESD_K - 1, 5)),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_n_export        => std_logic_vector(
        to_unsigned(C_JESD_N - 1, 5)),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_np_export       => std_logic_vector(
        to_unsigned(C_JESD_NP - 1, 5)),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_s_export        => std_logic_vector(
        to_unsigned(C_JESD_S - 1, 5)),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_cf_export       => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_f_export        => std_logic_vector(
        to_unsigned(C_JESD_F - 1, 8)),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_m_export        => std_logic_vector(
        to_unsigned(C_JESD_M - 1, 8)),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_dlb_data_export     => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_dlb_kchar_data_export => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testmode_export         => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_a_export    => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_b_export    => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_c_export    => (others => '0'),
      jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_d_export    => (others => '0'),
      -- PIO stubs
      pio_control_external_connection_export => x"DEADC0DE",
      pio_status_external_connection_export  => open,
      tx_enbl                                => '0'
    );

  -- =========================================================================
  -- Stimulus
  -- =========================================================================
  p_stim : process
    variable rd_val      : std_logic_vector(31 downto 0);
    variable valid_count : integer;
    variable data_snap   : std_logic_vector(127 downto 0);
    variable changed     : boolean;
  begin
    -- -----------------------------------------------------------------------
    -- Power-on reset (hold for 80 clocks, > C_RST_HOLD_CYCLES=64)
    -- -----------------------------------------------------------------------
    rst <= '1';
    wait for AXI_CLK_PERIOD * 80;
    rst <= '0';
    wait for AXI_CLK_PERIOD * 5;

    -- =======================================================================
    -- TB-DAC-001: Scratchpad write/read via AXI4
    -- Verifies: AxiToAvmm bridge + RegBank round-trip, AXI ID echo
    -- =======================================================================
    report "TB-DAC-001: Scratchpad write/read via AXI4";

    awid <= x"3";
    axi4_write(std_logic_vector(C_REG_SCRATCH0), x"DEADBEEF",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    assert bid = x"3"
      report "TB-DAC-001 FAIL: BID echo expected 3 got " & to_hstring(bid)
      severity error;
    if bid /= x"3" then error_count <= error_count + 1; end if;

    arid <= x"5";
    axi4_read(std_logic_vector(C_REG_SCRATCH0), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rid = x"5"
      report "TB-DAC-001 FAIL: RID echo expected 5 got " & to_hstring(rid)
      severity error;
    if rid /= x"5" then error_count <= error_count + 1; end if;
    assert rd_val = x"DEADBEEF"
      report "TB-DAC-001 FAIL: scratch0 got " & to_hstring(rd_val)
      severity error;
    if rd_val /= x"DEADBEEF" then error_count <= error_count + 1; end if;

    axi4_write(std_logic_vector(C_REG_SCRATCH1), x"CAFEBABE",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_read(std_logic_vector(C_REG_SCRATCH1), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"CAFEBABE"
      report "TB-DAC-001 FAIL: scratch1" severity error;
    if rd_val /= x"CAFEBABE" then error_count <= error_count + 1; end if;

    axi4_write(std_logic_vector(C_REG_SCRATCH2), x"12345678",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_read(std_logic_vector(C_REG_SCRATCH2), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"12345678"
      report "TB-DAC-001 FAIL: scratch2" severity error;
    if rd_val /= x"12345678" then error_count <= error_count + 1; end if;

    axi4_write(std_logic_vector(C_REG_SCRATCH3), x"A5A5A5A5",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_read(std_logic_vector(C_REG_SCRATCH3), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"A5A5A5A5"
      report "TB-DAC-001 FAIL: scratch3" severity error;
    if rd_val /= x"A5A5A5A5" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-006: JESD reset sequencer releases rst_n after reset
    -- Reset was held for 80 clocks then released. C_RST_HOLD_CYCLES=64.
    -- TB-DAC-001 may have consumed only ~40 cycles; wait an additional 40
    -- here to guarantee >=64 cycles have elapsed since reset deasserted.
    -- =======================================================================
    report "TB-DAC-006: JESD reset sequencer";
    wait for AXI_CLK_PERIOD * 40;
    assert jesd_rst_n = '1'
      report "TB-DAC-006 FAIL: jesd_rst_n still low after reset released"
      severity error;
    if jesd_rst_n /= '1' then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-002: NCO configure -> CDC -> JESD streaming output
    -- Configure a ~15.6 MHz tone (freq_word = 0x08000000 at 500 MSPS).
    -- Enable NCO. Assert both JESD frame_ready. Verify valid goes high.
    -- =======================================================================
    report "TB-DAC-002: End-to-end NCO to JESD streaming";

    -- Write NCO config while enable=0 (required CDC discipline)
    axi4_write(std_logic_vector(C_REG_SINE_FREQ_CH1_I), x"08000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_FREQ_CH1_Q), x"08000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_FREQ_CH2_I), x"08000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_FREQ_CH2_Q), x"08000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);

    -- Phase offsets: M1 = 90 deg (Q channel), others 0
    axi4_write(std_logic_vector(C_REG_SINE_PHASE_M0), x"00000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_PHASE_M1), x"40000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_PHASE_M2), x"00000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_PHASE_M3), x"40000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);

    -- Sync mode = per-DAC (default: group 0 = links 0+1, group 1 stubbed)
    axi4_write(std_logic_vector(C_REG_JESD_SYNC_CTRL), x"00000000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);

    -- Enable NCO (all 4 converters)
    axi4_write(std_logic_vector(C_REG_SINE_CTRL), x"0000001F",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);

    -- Allow CDC to propagate (2 txlink_clk cycles min, use 20 axi clocks)
    wait for AXI_CLK_PERIOD * 20;

    -- Assert both active JESD link frame_ready signals
    frame_ready_0 <= '1';
    frame_ready_1 <= '1';

    -- Wait for sync controller to align on LMFC boundary + pipeline latency
    wait for JESD_CLK_PERIOD * 200;

    -- Count link0_valid over 1000 JESD clocks
    valid_count := 0;
    for i in 0 to 999 loop
      wait until rising_edge(clk_jesd);
      if link0_valid = '1' then valid_count := valid_count + 1; end if;
    end loop;

    report "TB-DAC-002: link0 valid cycles = " &
      integer'image(valid_count) & "/1000";
    assert valid_count > 900
      report "TB-DAC-002 FAIL: link0 valid only " &
        integer'image(valid_count) & "/1000" severity error;
    if valid_count <= 900 then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-003: Both JESD links output non-zero identical data
    -- =======================================================================
    report "TB-DAC-003: Both JESD links carry valid non-zero data";

    wait until rising_edge(clk_jesd) and link0_valid = '1';

    assert link0_data /= (127 downto 0 => '0')
      report "TB-DAC-003 FAIL: link0 all zeros" severity error;
    if link0_data = (127 downto 0 => '0') then
      error_count <= error_count + 1;
    end if;

    assert link1_valid = '1'
      report "TB-DAC-003 FAIL: link1 not valid" severity error;
    if link1_valid /= '1' then error_count <= error_count + 1; end if;

    assert link1_data /= (127 downto 0 => '0')
      report "TB-DAC-003 FAIL: link1 all zeros" severity error;
    if link1_data = (127 downto 0 => '0') then
      error_count <= error_count + 1;
    end if;

    -- Both links feed the same DataSrcMux output so data must be identical
    assert link0_data = link1_data
      report "TB-DAC-003 FAIL: link0 /= link1 (same MUX output expected)"
      severity error;
    if link0_data /= link1_data then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-007: Data changes over time (NCO is running, not stuck)
    -- =======================================================================
    report "TB-DAC-007: Data changes over time";

    data_snap := link0_data;
    changed   := false;
    for i in 0 to 63 loop
      wait until rising_edge(clk_jesd);
      if link0_valid = '1' and link0_data /= data_snap then
        changed := true;
        exit;
      end if;
    end loop;
    assert changed
      report "TB-DAC-007 FAIL: link0 data stuck for 64 clocks" severity error;
    if not changed then error_count <= error_count + 1; end if;

    -- I/Q offset visible: lane0 (M0, I) differs from lane1 (M1, Q=90 deg)
    -- flatten_lanes: bits[31:0]=lane0=M0, bits[63:32]=lane1=M1
    changed := false;
    for i in 0 to 63 loop
      wait until rising_edge(clk_jesd);
      if link0_valid = '1' then
        if link0_data(31 downto 0) /= link0_data(63 downto 32) then
          changed := true;
          exit;
        end if;
      end if;
    end loop;
    assert changed
      report "TB-DAC-007 FAIL: lane0=lane1 for 64 clks (I/Q offset missing)"
      severity error;
    if not changed then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-004: Per-DAC sync — deassert frame_ready_1, link1 goes idle
    -- =======================================================================
    report "TB-DAC-004: Per-DAC sync link drop";

    -- Deassert link 1 frame_ready -> sync controller drops group 0 release
    -- (links 0 and 1 are in group 0, so dropping link 1 drops both)
    frame_ready_1 <= '0';
    wait for JESD_CLK_PERIOD * 50;

    valid_count := 0;
    for i in 0 to 63 loop
      wait until rising_edge(clk_jesd);
      if link1_valid = '1' then valid_count := valid_count + 1; end if;
    end loop;
    assert valid_count = 0
      report "TB-DAC-004 FAIL: link1 still valid after frame_ready_1 dropped"
      severity error;
    if valid_count /= 0 then error_count <= error_count + 1; end if;

    -- Re-assert link 1, wait for re-sync on LMFC boundary
    frame_ready_1 <= '1';
    wait for JESD_CLK_PERIOD * 200;

    valid_count := 0;
    for i in 0 to 63 loop
      wait until rising_edge(clk_jesd);
      if link1_valid = '1' then valid_count := valid_count + 1; end if;
    end loop;
    assert valid_count > 50
      report "TB-DAC-004 FAIL: link1 did not recover, got " &
        integer'image(valid_count) & "/64" severity error;
    if valid_count <= 50 then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-005: Status register readback via CDC -> RegBank -> AXI4
    -- =======================================================================
    report "TB-DAC-005: Status register readback";

    -- Allow CDC synchronisers to settle
    wait for AXI_CLK_PERIOD * 30;

    axi4_read(std_logic_vector(C_REG_JESD_SYNC_STATUS), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);

    report "TB-DAC-005: JESD_SYNC_STATUS = 0x" & to_hstring(rd_val);

    -- txlink_ready bits [1:0] must reflect frame_ready_0=1, frame_ready_1=1
    assert rd_val(1 downto 0) = "11"
      report "TB-DAC-005 FAIL: txlink_ready[1:0] expected 11, got " &
        to_hstring(unsigned(rd_val(1 downto 0))) severity error;
    if rd_val(1 downto 0) /= "11" then error_count <= error_count + 1; end if;

    -- group_synced bit[4] (group 0) should be set
    assert rd_val(4) = '1'
      report "TB-DAC-005 FAIL: group_synced[0] not set" severity error;
    if rd_val(4) /= '1' then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-008: Amplitude register write/readback (all four converters)
    -- Default after reset is 0x00007FFF; write distinct values and read back.
    -- =======================================================================
    report "TB-DAC-008: Amplitude register write/readback" severity error;

    axi4_write(std_logic_vector(C_REG_SINE_AMP_M0), x"00004000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_AMP_M1), x"00003000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_AMP_M2), x"00002000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_write(std_logic_vector(C_REG_SINE_AMP_M3), x"00001000",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);

    axi4_read(std_logic_vector(C_REG_SINE_AMP_M0), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"00004000"
      report "TB-DAC-008 FAIL: AMP_M0 got " & to_hstring(rd_val) severity error;
    if rd_val /= x"00004000" then error_count <= error_count + 1; end if;

    axi4_read(std_logic_vector(C_REG_SINE_AMP_M1), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"00003000"
      report "TB-DAC-008 FAIL: AMP_M1 got " & to_hstring(rd_val) severity error;
    if rd_val /= x"00003000" then error_count <= error_count + 1; end if;

    axi4_read(std_logic_vector(C_REG_SINE_AMP_M2), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"00002000"
      report "TB-DAC-008 FAIL: AMP_M2 got " & to_hstring(rd_val) severity error;
    if rd_val /= x"00002000" then error_count <= error_count + 1; end if;

    axi4_read(std_logic_vector(C_REG_SINE_AMP_M3), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"00001000"
      report "TB-DAC-008 FAIL: AMP_M3 got " & to_hstring(rd_val) severity error;
    if rd_val /= x"00001000" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-009: PIO control write/readback; PIO status pass-through
    -- The DUT stubs pio_status = pio_control input from the port.
    -- TB drives pio_control_external_connection_export = 0xDEADC0DE.
    -- =======================================================================
    report "TB-DAC-009: PIO control write/readback and status pass-through" severity error;

    axi4_write(std_logic_vector(C_REG_PIO_CTRL), x"BAADF00D",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    axi4_read(std_logic_vector(C_REG_PIO_CTRL), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"BAADF00D"
      report "TB-DAC-009 FAIL: PIO_CTRL got " & to_hstring(rd_val) severity error;
    if rd_val /= x"BAADF00D" then error_count <= error_count + 1; end if;

    -- PIO status is the DUT's pio_control external input (tied to 0xDEADC0DE in TB)
    axi4_read(std_logic_vector(C_REG_PIO_STATUS), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val = x"DEADC0DE"
      report "TB-DAC-009 FAIL: PIO_STATUS got " & to_hstring(rd_val) severity error;
    if rd_val /= x"DEADC0DE" then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-010: Sync error register readback after link drop; W1C clear
    -- TB-DAC-004 dropped frame_ready_1 while group 0 was running, setting
    -- sync_err_r(1) sticky. Verify it is readable, then clear with W1C.
    -- =======================================================================
    report "TB-DAC-010: Sync error readback and W1C clear" severity error;

    -- Allow sync_err CDC to settle (2-stage, plus any residual pipeline)
    wait for AXI_CLK_PERIOD * 10;

    axi4_read(std_logic_vector(C_REG_JESD_SYNC_ERR), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    report "TB-DAC-010: JESD_SYNC_ERR = 0x" & to_hstring(rd_val) severity error;
    assert rd_val(1) = '1'
      report "TB-DAC-010 FAIL: sync_err[1] not set after link1 drop" severity error;
    if rd_val(1) /= '1' then error_count <= error_count + 1; end if;

    -- Write 1 to bit 1 to clear (W1C)
    axi4_write(std_logic_vector(C_REG_JESD_SYNC_ERR), x"00000002",
      clk_axi, awaddr, awvalid, awready, wdata, wvalid, wready,
      bvalid, bready);
    -- Wait for toggle CDC to cross and the flag to clear in txlink_clk domain,
    -- then propagate back via status CDC (2-stage each way + margin)
    wait for AXI_CLK_PERIOD * 20;

    axi4_read(std_logic_vector(C_REG_JESD_SYNC_ERR), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    assert rd_val(1) = '0'
      report "TB-DAC-010 FAIL: sync_err[1] still set after W1C clear" severity error;
    if rd_val(1) /= '0' then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- TB-DAC-011: Source-status register readback
    -- src_sel = 0 (NCO), so src_active should be 0; src_switch_pending = 0.
    -- =======================================================================
    report "TB-DAC-011: Source-status register readback" severity error;

    -- Allow CDC to settle
    wait for AXI_CLK_PERIOD * 10;

    axi4_read(std_logic_vector(C_REG_JESD_TX_SRC_STAT), rd_val,
      clk_axi, araddr, arvalid, arready, rdata, rvalid, rready);
    report "TB-DAC-011: JESD_TX_SRC_STAT = 0x" & to_hstring(rd_val) severity error;
    -- src_switch_pending [0] = 0 (no pending switch)
    assert rd_val(0) = '0'
      report "TB-DAC-011 FAIL: src_switch_pending unexpectedly set" severity error;
    if rd_val(0) /= '0' then error_count <= error_count + 1; end if;
    -- src_active [1] = 0 (NCO is active source)
    assert rd_val(1) = '0'
      report "TB-DAC-011 FAIL: src_active expected 0 (NCO) got " &
        std_logic'image(rd_val(1)) severity error;
    if rd_val(1) /= '0' then error_count <= error_count + 1; end if;

    -- =======================================================================
    -- Summary
    -- =======================================================================
    wait for AXI_CLK_PERIOD * 10;
    if error_count = 0 then
      report "SIMULATION PASSED" severity error;
    else
      report "SIMULATION FAILED: " & integer'image(error_count) & " errors"
        severity failure;
    end if;
    std.env.stop;
  end process p_stim;

end architecture sim;
