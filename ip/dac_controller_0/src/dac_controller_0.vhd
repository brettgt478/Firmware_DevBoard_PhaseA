-- dac_controller_0.vhd
--
-- Top-level integration for the AD9176-FMC-EBZ DAC controller.
-- Target: Agilex 5 dev board + AD9176-FMC-EBZ eval board (single AD9176).
--
-- Integrates: AxiToAvmm, RegBank, SineWaveGen, JesdTxManager (×2),
--             JesdSyncController, DataSrcMux, DcFifo.
--
-- JESD link assignment (one AD9176, two links):
--   Link 0 (path 0)  → jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_*
--                       DAC core A (primary output)
--   Link 1 (path 1)  → jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_*
--                       DAC core B (added; reconcile port names with
--                       Platform Designer when PD project is updated)
--
-- Ports for a hypothetical second AD9176 have been removed entirely.
--
-- Stubbed / deferred:
--   pio_control_external_connection_export  — implementation deferred
--   pio_status_external_connection_export   — implementation deferred
--   tx_enbl                                 — implementation deferred
--
-- This file will not be automatically regenerated.  You should check it in
-- to your version control system if you want to keep it.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.DacControllerPkg.all;

entity dac_controller_0 is
  generic (
    -- Sine wave LUT depth.  Synthesis default: 1024.
    -- Testbenches should override with a smaller value (e.g. 64) to reduce
    -- elaboration time (ieee.math_real.sin() is called once per LUT entry).
    G_LUT_DEPTH : positive := 1024
  );
  port (
    -- =========================================================================
    -- AXI4 control interface from HPS lwhpm2fpga bridge
    -- =========================================================================
    lwhpm2fpga_awid    : in  std_logic_vector(3 downto 0)  := (others => '0');
    lwhpm2fpga_awaddr  : in  std_logic_vector(9 downto 0)  := (others => '0');
    lwhpm2fpga_awlen   : in  std_logic_vector(7 downto 0)  := (others => '0');
    lwhpm2fpga_awsize  : in  std_logic_vector(2 downto 0)  := (others => '0');
    lwhpm2fpga_awburst : in  std_logic_vector(1 downto 0)  := (others => '0');
    lwhpm2fpga_awlock  : in  std_logic                     := '0';
    lwhpm2fpga_awcache : in  std_logic_vector(3 downto 0)  := (others => '0');
    lwhpm2fpga_awprot  : in  std_logic_vector(2 downto 0)  := (others => '0');
    lwhpm2fpga_awvalid : in  std_logic                     := '0';
    lwhpm2fpga_awready : out std_logic;
    lwhpm2fpga_wdata   : in  std_logic_vector(31 downto 0) := (others => '0');
    lwhpm2fpga_wstrb   : in  std_logic_vector(3 downto 0)  := (others => '0');
    lwhpm2fpga_wlast   : in  std_logic                     := '0';
    lwhpm2fpga_wvalid  : in  std_logic                     := '0';
    lwhpm2fpga_wready  : out std_logic;
    lwhpm2fpga_bid     : out std_logic_vector(3 downto 0);
    lwhpm2fpga_bresp   : out std_logic_vector(1 downto 0);
    lwhpm2fpga_bvalid  : out std_logic;
    lwhpm2fpga_bready  : in  std_logic                     := '0';
    lwhpm2fpga_arid    : in  std_logic_vector(3 downto 0)  := (others => '0');
    lwhpm2fpga_araddr  : in  std_logic_vector(9 downto 0)  := (others => '0');
    lwhpm2fpga_arlen   : in  std_logic_vector(7 downto 0)  := (others => '0');
    lwhpm2fpga_arsize  : in  std_logic_vector(2 downto 0)  := (others => '0');
    lwhpm2fpga_arburst : in  std_logic_vector(1 downto 0)  := (others => '0');
    lwhpm2fpga_arlock  : in  std_logic                     := '0';
    lwhpm2fpga_arcache : in  std_logic_vector(3 downto 0)  := (others => '0');
    lwhpm2fpga_arprot  : in  std_logic_vector(2 downto 0)  := (others => '0');
    lwhpm2fpga_arvalid : in  std_logic                     := '0';
    lwhpm2fpga_arready : out std_logic;
    lwhpm2fpga_rid     : out std_logic_vector(3 downto 0);
    lwhpm2fpga_rdata   : out std_logic_vector(31 downto 0);
    lwhpm2fpga_rresp   : out std_logic_vector(1 downto 0);
    lwhpm2fpga_rlast   : out std_logic;
    lwhpm2fpga_rvalid  : out std_logic;
    lwhpm2fpga_rready  : in  std_logic                     := '0';

    -- =========================================================================
    -- System clock and reset
    -- =========================================================================
    reset_sink_reset : in std_logic := '0';
    clock_sink_clk   : in std_logic := '0';

    -- =========================================================================
    -- GTS JESD reset sequencing (shared across both links)
    -- =========================================================================
    -- in_of_reset: high while the JESD GTS subsystem reset is being asserted
    jesd_gts_ss_TX_intel_jesd_TX_jesd204_tx_in_of_reset_export   : in  std_logic := '0';
    -- rst_n: active-low reset driven by this module to the JESD GTS subsystem
    jesd_gts_ss_tx_outtel_jesd_tx_jesd204_tx_rst_n_reset_n       : out std_logic;
    -- rst_ack_n: active-low acknowledge returned by the GTS subsystem
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_rst_ack_n_export    : in  std_logic := '0';

    -- =========================================================================
    -- GTS reference clock / PLL management
    -- =========================================================================
    jesd_gts_ss_TX_outtel_jesd_TX_txphy_clk_export               : in  std_logic_vector(3 downto 0)   := (others => '0');
    -- rs_priority: select which refclk source drives the GTS (bit 0 = refclk0)
    jesd_gts_ss_TX_outst_src_i_src_rs_priority_src_rs_priority   : out std_logic_vector(3 downto 0);
    jesd_gts_ss_tx_outst_src_o_refclk_fail_status_refclk_fail_status : in  std_logic_vector(7 downto 0)  := (others => '0');
    jesd_gts_ss_tx_outst_src_o_refclk_on_ack_refclk_on_ack       : in  std_logic                     := '0';
    jesd_gts_ss_tx_outst_src_i_refclk_on_refclk_on               : out std_logic_vector(9 downto 0);
    core_pll_locked_export                                        : in  std_logic                     := '0';

    -- =========================================================================
    -- JESD204B link clock (shared by both links, ~250 MHz)
    -- =========================================================================
    jesd204_tx_link_clk_clk : in std_logic := '0';

    -- =========================================================================
    -- JESD TX streaming — Link 0 (path 0, DAC core A)
    -- =========================================================================
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_data          : out std_logic_vector(127 downto 0);
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_valid         : out std_logic;
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_ready         : in  std_logic := '0';
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_somf_export        : in  std_logic_vector(3 downto 0) := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_error_export : out std_logic;
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_ready_export : in  std_logic := '0';

    -- =========================================================================
    -- JESD TX streaming — Link 1 (path 1, DAC core B)
    -- =========================================================================
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_data          : out std_logic_vector(127 downto 0);
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_valid         : out std_logic;
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_ready         : in  std_logic := '0';
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_error_export : out std_logic;
    jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_ready_export : in  std_logic := '0';

    -- =========================================================================
    -- JESD CSR exports (for JESD IP monitoring; all read-only inputs here)
    -- =========================================================================
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_hd_export   : in  std_logic                     := '0';
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_cs_export   : in  std_logic_vector(1 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_l_export    : in  std_logic_vector(4 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_k_export    : in  std_logic_vector(4 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_n_export    : in  std_logic_vector(4 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_np_export   : in  std_logic_vector(4 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_s_export    : in  std_logic_vector(4 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_cf_export   : in  std_logic_vector(4 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_f_export    : in  std_logic_vector(7 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_csr_m_export    : in  std_logic_vector(7 downto 0)  := (others => '0');
    -- Loopback data bus (not used in normal operation, tie off)
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_dlb_data_export       : in  std_logic_vector(127 downto 0) := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_dlb_kchar_data_export : in  std_logic_vector(15 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testmode_export           : in  std_logic_vector(3 downto 0)   := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_a_export      : in  std_logic_vector(31 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_b_export      : in  std_logic_vector(31 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_c_export      : in  std_logic_vector(31 downto 0)  := (others => '0');
    jesd_gts_ss_TX_outtel_jesd_TX_csr_tx_testpattern_d_export      : in  std_logic_vector(31 downto 0)  := (others => '0');

    -- =========================================================================
    -- PIO external connections — stubbed, deferred
    -- =========================================================================
    pio_control_external_connection_export : in  std_logic_vector(31 downto 0) := (others => '0');
    pio_status_external_connection_export  : out std_logic_vector(31 downto 0);

    -- =========================================================================
    -- TX enable — stubbed, deferred
    -- =========================================================================
    tx_enbl : in std_logic := '0'
  );
end entity dac_controller_0;

architecture rtl of dac_controller_0 is

  -- C_LUT_DEPTH intentionally removed; use the G_LUT_DEPTH generic throughout.

  -- =========================================================================
  -- JESD GTS reset sequencer
  -- Assert rst_n for C_RST_HOLD_CYCLES clocks on power-up/reset.
  -- =========================================================================
  constant C_RST_HOLD_CYCLES : positive := 64;
  signal rst_cnt     : unsigned(6 downto 0) := (others => '0');
  signal jesd_rst_n  : std_logic := '0';  -- active low, starts asserted

  -- =========================================================================
  -- Avalon-MM bridge signals
  -- =========================================================================
  signal avmm_address     : std_logic_vector(C_AVMM_ADDR_WIDTH - 1 downto 0);
  signal avmm_read        : std_logic;
  signal avmm_write       : std_logic;
  signal avmm_writedata   : std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
  signal avmm_readdata    : std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
  signal avmm_waitrequest : std_logic;

  -- =========================================================================
  -- RegBank CSR outputs (clock_sink_clk domain)
  -- =========================================================================
  signal sine_csr          : t_sine_csr;
  signal jesd_sync_csr     : t_jesd_sync_csr;
  signal jesd_sync_status  : t_jesd_sync_status;
  signal jesd_sync_err_clr : std_logic_vector(3 downto 0);
  signal pio_ctrl_reg      : std_logic_vector(31 downto 0);

  -- =========================================================================
  -- txlink_clk domain aliases and reset synchronizer
  -- =========================================================================
  signal txlink_clk      : std_logic;
  signal txlink_rst_meta : std_logic := '1';
  signal txlink_rst      : std_logic := '1';

  -- =========================================================================
  -- CDC: clock_sink_clk → txlink_clk (sine CSR quasi-static)
  -- Software must write config before asserting enable (see ISSUE-008 in
  -- iq_router design doc; same constraint applies here).
  -- =========================================================================
  signal sine_enable_meta : std_logic := '0';
  signal sine_enable_sync : std_logic := '0';
  signal sine_csr_txclk   : t_sine_csr := C_SINE_CSR_DEFAULT;

  -- CDC: sync_mode and src_sel (single-bit 2-stage)
  signal sync_mode_meta : std_logic := '0';
  signal sync_mode_sync : std_logic := '0';
  signal src_sel_meta   : std_logic := '0';
  signal src_sel_sync   : std_logic := '0';

  -- CDC: error clear toggle-based pulse (clock_sink_clk → txlink_clk)
  signal err_clr_toggle   : std_logic_vector(3 downto 0) := (others => '0');
  signal err_clr_tog_meta : std_logic_vector(3 downto 0) := (others => '0');
  signal err_clr_tog_sync : std_logic_vector(3 downto 0) := (others => '0');
  signal err_clr_tog_prev : std_logic_vector(3 downto 0) := (others => '0');
  signal err_clr_txclk    : std_logic_vector(3 downto 0);

  -- =========================================================================
  -- CDC: txlink_clk → clock_sink_clk (status readback, 2-stage sync)
  -- =========================================================================
  signal txlink_ready_meta  : std_logic_vector(3 downto 0) := (others => '0');
  signal txlink_ready_sync  : std_logic_vector(3 downto 0) := (others => '0');
  signal group_synced_meta  : std_logic_vector(1 downto 0) := (others => '0');
  signal group_synced_sync  : std_logic_vector(1 downto 0) := (others => '0');
  signal lmfc_aligned_meta  : std_logic := '0';
  signal lmfc_aligned_sync  : std_logic := '0';
  signal sync_err_meta      : std_logic_vector(3 downto 0) := (others => '0');
  signal sync_err_sync      : std_logic_vector(3 downto 0) := (others => '0');
  signal src_pending_meta   : std_logic := '0';
  signal src_pending_sync   : std_logic := '0';
  signal src_active_meta    : std_logic := '0';
  signal src_active_sync    : std_logic := '0';

  -- =========================================================================
  -- txlink_clk domain: txlink_ready inputs
  -- links 0,1 are active (one AD9176); links 2,3 tied low (no second AD9176)
  -- =========================================================================
  signal txlink_ready : std_logic_vector(3 downto 0);

  -- =========================================================================
  -- SineWaveGen output (txlink_clk domain)
  -- =========================================================================
  signal nco_samples : t_sample_bus;
  signal nco_valid   : std_logic;

  -- =========================================================================
  -- DcFifo signals (write side tied off in Phase A)
  -- =========================================================================
  signal fifo_rd_data  : std_logic_vector(C_LINK_DATA_BITS - 1 downto 0);
  signal fifo_rd_valid : std_logic;
  signal fifo_rd_empty : std_logic;
  signal fifo_wr_full  : std_logic;
  signal fifo_fill     : unsigned(clog2(512) downto 0);

  -- =========================================================================
  -- DataSrcMux output (txlink_clk domain)
  -- =========================================================================
  signal mux_samples        : t_sample_bus;
  signal mux_valid          : std_logic;
  signal src_switch_pending : std_logic;
  signal src_active         : std_logic;

  -- =========================================================================
  -- JesdSyncController (txlink_clk domain)
  -- =========================================================================
  signal data_release  : std_logic_vector(3 downto 0);
  signal group_synced  : std_logic_vector(1 downto 0);
  signal lmfc_aligned  : std_logic;
  signal sync_err      : std_logic_vector(3 downto 0);
  signal lmfc_boundary : std_logic;

  -- =========================================================================
  -- JesdTxManager outputs (txlink_clk domain, 2 instances)
  -- =========================================================================
  type t_lane_data_array is array (0 to 1) of t_lane_data;
  signal lane_data  : t_lane_data_array;
  signal lane_valid : std_logic_vector(1 downto 0);

  -- =========================================================================
  -- Flatten t_lane_data to 128-bit vector
  -- Bit mapping: [31:0]=lane0, [63:32]=lane1, [95:64]=lane2, [127:96]=lane3
  -- =========================================================================
  function flatten_lanes(ld : t_lane_data) return std_logic_vector is
  begin
    return ld.lane3 & ld.lane2 & ld.lane1 & ld.lane0;
  end function flatten_lanes;

begin

  -- =========================================================================
  -- txlink_clk alias
  -- =========================================================================
  txlink_clk <= jesd204_tx_link_clk_clk;

  -- =========================================================================
  -- JESD GTS reset sequencer
  -- Holds rst_n low for C_RST_HOLD_CYCLES clocks after reset_sink_reset,
  -- then releases. The ack is monitored but not used to gate further logic
  -- in Phase A (hardware validation will confirm sequencing).
  -- =========================================================================
  p_jesd_rst : process(clock_sink_clk)
  begin
    if rising_edge(clock_sink_clk) then
      if reset_sink_reset = '1' then
        rst_cnt    <= (others => '0');
        jesd_rst_n <= '0';
      elsif rst_cnt /= to_unsigned(C_RST_HOLD_CYCLES - 1, 7) then
        rst_cnt    <= rst_cnt + 1;
        jesd_rst_n <= '0';
      else
        jesd_rst_n <= '1';
      end if;
    end if;
  end process p_jesd_rst;

  jesd_gts_ss_tx_outtel_jesd_tx_jesd204_tx_rst_n_reset_n <= jesd_rst_n;

  -- =========================================================================
  -- txlink_clk domain reset synchronizer
  -- =========================================================================
  p_txlink_rst : process(txlink_clk)
  begin
    if rising_edge(txlink_clk) then
      txlink_rst_meta <= reset_sink_reset;
      txlink_rst      <= txlink_rst_meta;
    end if;
  end process p_txlink_rst;

  -- =========================================================================
  -- GTS reference clock management tie-offs
  -- Enable reference clock 0; set as highest priority source.
  -- Adjust when PLL configuration is finalised with the Agilex 5 PD project.
  -- =========================================================================
  jesd_gts_ss_TX_outst_src_i_src_rs_priority_src_rs_priority <= "0001";
  jesd_gts_ss_tx_outst_src_i_refclk_on_refclk_on             <= "0000000001";

  -- =========================================================================
  -- txlink_ready: connect active links, stub inactive links
  -- =========================================================================
  txlink_ready(0) <= jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_ready_export;
  txlink_ready(1) <= jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_ready_export;
  txlink_ready(2) <= '0';  -- no second AD9176
  txlink_ready(3) <= '0';  -- no second AD9176
  -- NOTE: Group 1 (links 2+3) is permanently unready (no second AD9176), so
  -- lmfc_aligned (JESD_SYNC_STATUS[6]) will always read '0'. HPS software should
  -- use group_synced[0] (JESD_SYNC_STATUS[4]) to confirm the active link pair is ready.

  -- =========================================================================
  -- AXI4 to Avalon-MM Bridge
  -- =========================================================================
  u_axi_bridge : entity work.AxiToAvmm
    generic map (
      G_ADDR_WIDTH => C_AVMM_ADDR_WIDTH,
      G_DATA_WIDTH => C_AVMM_DATA_WIDTH,
      G_ID_WIDTH   => 4
    )
    port map (
      clk              => clock_sink_clk,
      rst              => reset_sink_reset,
      s_axi_awid       => lwhpm2fpga_awid,
      s_axi_awaddr     => lwhpm2fpga_awaddr,
      s_axi_awlen      => lwhpm2fpga_awlen,
      s_axi_awsize     => lwhpm2fpga_awsize,
      s_axi_awburst    => lwhpm2fpga_awburst,
      s_axi_awlock     => lwhpm2fpga_awlock,
      s_axi_awcache    => lwhpm2fpga_awcache,
      s_axi_awprot     => lwhpm2fpga_awprot,
      s_axi_awvalid    => lwhpm2fpga_awvalid,
      s_axi_awready    => lwhpm2fpga_awready,
      s_axi_wdata      => lwhpm2fpga_wdata,
      s_axi_wstrb      => lwhpm2fpga_wstrb,
      s_axi_wlast      => lwhpm2fpga_wlast,
      s_axi_wvalid     => lwhpm2fpga_wvalid,
      s_axi_wready     => lwhpm2fpga_wready,
      s_axi_bid        => lwhpm2fpga_bid,
      s_axi_bresp      => lwhpm2fpga_bresp,
      s_axi_bvalid     => lwhpm2fpga_bvalid,
      s_axi_bready     => lwhpm2fpga_bready,
      s_axi_arid       => lwhpm2fpga_arid,
      s_axi_araddr     => lwhpm2fpga_araddr,
      s_axi_arlen      => lwhpm2fpga_arlen,
      s_axi_arsize     => lwhpm2fpga_arsize,
      s_axi_arburst    => lwhpm2fpga_arburst,
      s_axi_arlock     => lwhpm2fpga_arlock,
      s_axi_arcache    => lwhpm2fpga_arcache,
      s_axi_arprot     => lwhpm2fpga_arprot,
      s_axi_arvalid    => lwhpm2fpga_arvalid,
      s_axi_arready    => lwhpm2fpga_arready,
      s_axi_rid        => lwhpm2fpga_rid,
      s_axi_rdata      => lwhpm2fpga_rdata,
      s_axi_rresp      => lwhpm2fpga_rresp,
      s_axi_rlast      => lwhpm2fpga_rlast,
      s_axi_rvalid     => lwhpm2fpga_rvalid,
      s_axi_rready     => lwhpm2fpga_rready,
      avmm_address     => avmm_address,
      avmm_read        => avmm_read,
      avmm_write       => avmm_write,
      avmm_writedata   => avmm_writedata,
      avmm_readdata    => avmm_readdata,
      avmm_waitrequest => avmm_waitrequest
    );

  -- =========================================================================
  -- Register Bank (clock_sink_clk domain)
  -- =========================================================================
  u_reg_bank : entity work.RegBank
    port map (
      clk               => clock_sink_clk,
      rst               => reset_sink_reset,
      avmm_address      => avmm_address,
      avmm_read         => avmm_read,
      avmm_write        => avmm_write,
      avmm_writedata    => avmm_writedata,
      avmm_readdata     => avmm_readdata,
      avmm_waitrequest  => avmm_waitrequest,
      sine_csr          => sine_csr,
      jesd_sync_csr     => jesd_sync_csr,
      jesd_sync_status  => jesd_sync_status,
      jesd_sync_err_clr => jesd_sync_err_clr,
      pio_ctrl_reg      => pio_ctrl_reg,
      pio_stat_in       => pio_control_external_connection_export
    );

  -- =========================================================================
  -- CDC: clock_sink_clk → txlink_clk
  -- =========================================================================

  -- Sine CSR quasi-static CDC.
  -- All config fields are sampled on txlink_clk while synced enable='0'.
  -- Software must write config BEFORE asserting SINE_CTRL[0].
  p_cdc_sine : process(txlink_clk)
  begin
    if rising_edge(txlink_clk) then
      if txlink_rst = '1' then
        sine_enable_meta <= '0';
        sine_enable_sync <= '0';
        sine_csr_txclk   <= C_SINE_CSR_DEFAULT;
      else
        sine_enable_meta <= sine_csr.enable;
        sine_enable_sync <= sine_enable_meta;

        if sine_enable_sync = '0' then
          sine_csr_txclk.conv_enable  <= sine_csr.conv_enable;
          sine_csr_txclk.freq_m0      <= sine_csr.freq_m0;
          sine_csr_txclk.freq_m1      <= sine_csr.freq_m1;
          sine_csr_txclk.freq_m2      <= sine_csr.freq_m2;
          sine_csr_txclk.freq_m3      <= sine_csr.freq_m3;
          sine_csr_txclk.phase_ofs_m0 <= sine_csr.phase_ofs_m0;
          sine_csr_txclk.phase_ofs_m1 <= sine_csr.phase_ofs_m1;
          sine_csr_txclk.phase_ofs_m2 <= sine_csr.phase_ofs_m2;
          sine_csr_txclk.phase_ofs_m3 <= sine_csr.phase_ofs_m3;
          sine_csr_txclk.amplitude_m0 <= sine_csr.amplitude_m0;
          sine_csr_txclk.amplitude_m1 <= sine_csr.amplitude_m1;
          sine_csr_txclk.amplitude_m2 <= sine_csr.amplitude_m2;
          sine_csr_txclk.amplitude_m3 <= sine_csr.amplitude_m3;
        end if;

        sine_csr_txclk.enable <= sine_enable_sync;
      end if;
    end if;
  end process p_cdc_sine;

  -- Single-bit 2-stage synchronizers for sync_mode and src_sel
  p_cdc_sync_csr : process(txlink_clk)
  begin
    if rising_edge(txlink_clk) then
      if txlink_rst = '1' then
        sync_mode_meta <= '0';
        sync_mode_sync <= '0';
        src_sel_meta   <= '0';
        src_sel_sync   <= '0';
      else
        sync_mode_meta <= jesd_sync_csr.sync_mode;
        sync_mode_sync <= sync_mode_meta;
        src_sel_meta   <= jesd_sync_csr.src_sel;
        src_sel_sync   <= src_sel_meta;
      end if;
    end if;
  end process p_cdc_sync_csr;

  -- Error clear: toggle-based pulse CDC (source side)
  p_err_clr_toggle : process(clock_sink_clk)
  begin
    if rising_edge(clock_sink_clk) then
      if reset_sink_reset = '1' then
        err_clr_toggle <= (others => '0');
      else
        for i in 0 to 3 loop
          if jesd_sync_err_clr(i) = '1' then
            err_clr_toggle(i) <= not err_clr_toggle(i);
          end if;
        end loop;
      end if;
    end if;
  end process p_err_clr_toggle;

  -- Error clear: toggle-based pulse CDC (destination side)
  p_err_clr_cdc : process(txlink_clk)
  begin
    if rising_edge(txlink_clk) then
      if txlink_rst = '1' then
        err_clr_tog_meta <= (others => '0');
        err_clr_tog_sync <= (others => '0');
        err_clr_tog_prev <= (others => '0');
      else
        err_clr_tog_meta <= err_clr_toggle;
        err_clr_tog_sync <= err_clr_tog_meta;
        err_clr_tog_prev <= err_clr_tog_sync;
      end if;
    end if;
  end process p_err_clr_cdc;

  err_clr_txclk <= err_clr_tog_sync xor err_clr_tog_prev;

  -- =========================================================================
  -- CDC: txlink_clk → clock_sink_clk (status readback, 2-stage sync)
  -- =========================================================================
  p_cdc_status : process(clock_sink_clk)
  begin
    if rising_edge(clock_sink_clk) then
      if reset_sink_reset = '1' then
        txlink_ready_meta <= (others => '0');
        txlink_ready_sync <= (others => '0');
        group_synced_meta <= (others => '0');
        group_synced_sync <= (others => '0');
        lmfc_aligned_meta <= '0';
        lmfc_aligned_sync <= '0';
        sync_err_meta     <= (others => '0');
        sync_err_sync     <= (others => '0');
        src_pending_meta  <= '0';
        src_pending_sync  <= '0';
        src_active_meta   <= '0';
        src_active_sync   <= '0';
      else
        txlink_ready_meta <= txlink_ready;
        txlink_ready_sync <= txlink_ready_meta;
        group_synced_meta <= group_synced;
        group_synced_sync <= group_synced_meta;
        lmfc_aligned_meta <= lmfc_aligned;
        lmfc_aligned_sync <= lmfc_aligned_meta;
        sync_err_meta     <= sync_err;
        sync_err_sync     <= sync_err_meta;
        src_pending_meta  <= src_switch_pending;
        src_pending_sync  <= src_pending_meta;
        src_active_meta   <= src_active;
        src_active_sync   <= src_active_meta;
      end if;
    end if;
  end process p_cdc_status;

  jesd_sync_status <= (
    txlink_ready       => txlink_ready_sync,
    group_synced       => group_synced_sync,
    lmfc_aligned       => lmfc_aligned_sync,
    sync_err           => sync_err_sync,
    src_switch_pending => src_pending_sync,
    src_active         => src_active_sync
  );

  -- =========================================================================
  -- Sine Wave Generator (txlink_clk domain)
  -- =========================================================================
  u_sine_wave_gen : entity work.SineWaveGen
    generic map (
      G_PHASE_BITS  => C_PHASE_BITS,
      G_SAMPLE_BITS => C_SAMPLE_BITS,
      G_LUT_DEPTH   => G_LUT_DEPTH
    )
    port map (
      clk           => txlink_clk,
      rst           => txlink_rst,
      csr           => sine_csr_txclk,
      samples_out   => nco_samples,
      samples_valid => nco_valid
    );

  -- =========================================================================
  -- Dual-Clock FIFO (write side tied off — external IQ path deferred to Phase C)
  -- =========================================================================
  u_dc_fifo : entity work.DcFifo
    generic map (
      G_DATA_WIDTH => C_LINK_DATA_BITS,
      G_DEPTH      => 512
    )
    port map (
      wr_clk      => clock_sink_clk,
      wr_rst      => reset_sink_reset,
      wr_data     => (others => '0'),
      wr_valid    => '0',
      wr_full     => fifo_wr_full,
      wr_overflow => open,
      rd_clk      => txlink_clk,
      rd_rst      => txlink_rst,
      rd_data     => fifo_rd_data,
      rd_valid    => fifo_rd_valid,
      rd_en       => '0',
      rd_empty    => fifo_rd_empty,
      fill_level  => fifo_fill
    );

  -- =========================================================================
  -- Data Source Multiplexer (txlink_clk domain)
  -- =========================================================================
  u_data_src_mux : entity work.DataSrcMux
    generic map (
      G_FIFO_DEPTH     => 512,
      G_FILL_THRESHOLD => 256
    )
    port map (
      clk                => txlink_clk,
      rst                => txlink_rst,
      nco_samples        => nco_samples,
      nco_valid          => nco_valid,
      fifo_samples       => C_SAMPLE_BUS_ZERO,
      fifo_valid         => '0',
      fifo_fill_level    => fifo_fill,
      src_sel            => src_sel_sync,
      lmfc_boundary      => lmfc_boundary,
      samples_out        => mux_samples,
      samples_valid      => mux_valid,
      src_switch_pending => src_switch_pending,
      src_active         => src_active
    );

  -- =========================================================================
  -- JESD Sync Controller (txlink_clk domain)
  -- Group 0 = links 0+1 (one AD9176). Group 1 = links 2+3 (stubbed, no DAC).
  -- =========================================================================
  u_jesd_sync_ctrl : entity work.JesdSyncController
    port map (
      clk           => txlink_clk,
      rst           => txlink_rst,
      txlink_ready  => txlink_ready,
      sync_mode     => sync_mode_sync,
      err_clr       => err_clr_txclk,
      data_release  => data_release,
      group_synced  => group_synced,
      lmfc_aligned  => lmfc_aligned,
      sync_err      => sync_err,
      lmfc_boundary => lmfc_boundary
    );

  -- =========================================================================
  -- JESD TX Managers (txlink_clk domain, 2 instances for 1 AD9176)
  -- Instance 0 → Link 0, DAC core A
  -- Instance 1 → Link 1, DAC core B
  -- =========================================================================
  gen_jtxm : for i in 0 to 1 generate
    u_jtxm : entity work.JesdTxManager
      port map (
        clk           => txlink_clk,
        rst           => txlink_rst,
        samples_in    => mux_samples,
        samples_valid => mux_valid,
        lane_data_out => lane_data(i),
        lane_valid    => lane_valid(i)
      );
  end generate gen_jtxm;

  -- =========================================================================
  -- JESD streaming output mapping
  -- data_release(0) and data_release(1) come from group 0 of the sync
  -- controller (links 0 and 1 share group 0 ready status).
  -- =========================================================================

  -- Link 0 (DAC core A)
  jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_data  <= flatten_lanes(lane_data(0));
  jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_link_valid <= lane_valid(0) and data_release(0);
  jesd_gts_ss_TX_outtel_jesd_TX_jesd204_tx_frame_error_export <= '0';

  -- Link 1 (DAC core B)
  jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_data  <= flatten_lanes(lane_data(1));
  jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_link_valid <= lane_valid(1) and data_release(1);
  jesd_gts_ss_TX_outtel_jesd_TX_p1_jesd204_tx_frame_error_export <= '0';

  -- =========================================================================
  -- PIO stub outputs (deferred)
  -- Pass the PIO control register value out as status for now so software
  -- can write and read back during bring-up without assertion errors.
  -- =========================================================================
  pio_status_external_connection_export <= pio_ctrl_reg;

end architecture rtl;
