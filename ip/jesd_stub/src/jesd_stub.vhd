-- jesd_stub.vhd
--
-- Synthesis terminator for the **non-data** JESD-side conduits of
-- dac_controller_0. Stage 5 (merged) keeps this module to terminate the
-- status/refclk/csr/pio/tx_enbl conduits that have no native counterpart on
-- Intel's JESD204B GTS Subsystem IP. The two AVST data paths
-- (jesd_link0_data, jesd_link1_data) are now wired to the real GTS IPs in
-- ip/dac_subsys/dac_subsys.tcl and have been removed from this stub.
--
-- A future stage can delete this stub entirely once dac_controller_0_hw.tcl
-- is redesigned to drop its now-unused JESD status/control conduits.
--
-- Interface mirror (this module is the conjugate of dac_controller_0):
--   jesd_link0_status   : conduit          (drives somf, frame_ready; sinks frame_error)
--   jesd_link1_status   : conduit          (drives frame_ready;       sinks frame_error)
--   jesd_reset_seq      : conduit          (drives in_of_reset, rst_ack_n; sinks rst_n)
--   jesd_refclk_ctrl    : conduit          (drives txphy_clk, refclk_fail_status,
--                                            refclk_on_ack, core_pll_locked;
--                                            sinks rs_priority, refclk_on)
--   jesd_csr_readback   : conduit          (drives all JESD link config readback fields
--                                            with JESD204B mode-4 spec-encoded nominals
--                                            per PLAN.md Appendix C)
--   pio_control         : conduit          (drives 32 zeros)
--   pio_status          : conduit          (sinks 32 bits, ignored)
--   tx_enbl             : conduit          (drives '0' -- dac_controller_0 ignores it)
--
-- All conduit *inputs* on the dac_controller_0 side are unreferenced by its
-- architecture body (verified 2026-05-16: jesd_csr_*, refclk_*, in_of_reset,
-- rst_ack_n, pio_control_*, tx_enbl all declared-but-unused). The values
-- driven below are chosen for readability when poking around in System
-- Console, NOT for any functional dependency.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity jesd_stub is
  port (
    -- ===================================================================
    -- Clock + reset (jesd_tx_link_clk domain, used only for AVST handshake)
    -- ===================================================================
    jesd204_tx_link_clk_clk : in std_logic;
    reset_sink_reset        : in std_logic;

    -- ===================================================================
    -- Conduit: JESD link 0 status
    -- ===================================================================
    jesd_link0_status_somf        : out std_logic_vector(3 downto 0);
    jesd_link0_status_frame_error : in  std_logic;
    jesd_link0_status_frame_ready : out std_logic;

    -- ===================================================================
    -- Conduit: JESD link 1 status (no somf on link 1)
    -- ===================================================================
    jesd_link1_status_frame_error : in  std_logic;
    jesd_link1_status_frame_ready : out std_logic;

    -- ===================================================================
    -- Conduit: JESD reset sequencing
    -- ===================================================================
    jesd_reset_seq_in_of_reset : out std_logic;
    jesd_reset_seq_rst_n       : in  std_logic;
    jesd_reset_seq_rst_ack_n   : out std_logic;

    -- ===================================================================
    -- Conduit: JESD reference clock / PLL management
    -- ===================================================================
    jesd_refclk_ctrl_txphy_clk          : out std_logic_vector(3 downto 0);
    jesd_refclk_ctrl_rs_priority        : in  std_logic_vector(3 downto 0);
    jesd_refclk_ctrl_refclk_fail_status : out std_logic_vector(7 downto 0);
    jesd_refclk_ctrl_refclk_on_ack      : out std_logic;
    jesd_refclk_ctrl_refclk_on          : in  std_logic_vector(9 downto 0);
    jesd_refclk_ctrl_core_pll_locked    : out std_logic;

    -- ===================================================================
    -- Conduit: JESD CSR readback (JESD spec field encodings, mode 4)
    --   L,K,N,NP,S,F,M readback = "actual_value - 1"  per JESD204B link
    --   configuration octets. PLAN.md Appendix C: M=4, L=4, F=2, S=1,
    --   N=NP=16, K=32, HD=1, CS=0, CF=0.
    -- ===================================================================
    jesd_csr_readback_csr_hd        : out std_logic;
    jesd_csr_readback_csr_cs        : out std_logic_vector(1 downto 0);
    jesd_csr_readback_csr_l         : out std_logic_vector(4 downto 0);
    jesd_csr_readback_csr_k         : out std_logic_vector(4 downto 0);
    jesd_csr_readback_csr_n         : out std_logic_vector(4 downto 0);
    jesd_csr_readback_csr_np        : out std_logic_vector(4 downto 0);
    jesd_csr_readback_csr_s         : out std_logic_vector(4 downto 0);
    jesd_csr_readback_csr_cf        : out std_logic_vector(4 downto 0);
    jesd_csr_readback_csr_f         : out std_logic_vector(7 downto 0);
    jesd_csr_readback_csr_m         : out std_logic_vector(7 downto 0);
    jesd_csr_readback_dlb_data      : out std_logic_vector(127 downto 0);
    jesd_csr_readback_dlb_kchar     : out std_logic_vector(15 downto 0);
    jesd_csr_readback_testmode      : out std_logic_vector(3 downto 0);
    jesd_csr_readback_testpattern_a : out std_logic_vector(31 downto 0);
    jesd_csr_readback_testpattern_b : out std_logic_vector(31 downto 0);
    jesd_csr_readback_testpattern_c : out std_logic_vector(31 downto 0);
    jesd_csr_readback_testpattern_d : out std_logic_vector(31 downto 0);

    -- ===================================================================
    -- Conduit: PIO control (drives dac_controller_0's pio_control input)
    -- ===================================================================
    pio_control_pio_control : out std_logic_vector(31 downto 0);

    -- ===================================================================
    -- Conduit: PIO status (sinks dac_controller_0's pio_status output)
    -- ===================================================================
    pio_status_pio_status : in std_logic_vector(31 downto 0);

    -- ===================================================================
    -- Conduit: TX enable (drives dac_controller_0's tx_enbl input)
    -- ===================================================================
    tx_enbl_tx_enbl : out std_logic
  );
end entity jesd_stub;

architecture rtl of jesd_stub is

begin

  -- =====================================================================
  -- JESD link status: drive somf=0 and frame_ready=0
  -- (frame_ready='0' keeps Phase A's JesdSyncController out of the
  --  "links ready" state, which is the correct stubbed behaviour: no GTS,
  --  no link.)
  -- =====================================================================
  jesd_link0_status_somf        <= (others => '0');
  jesd_link0_status_frame_ready <= '0';
  jesd_link1_status_frame_ready <= '0';

  -- =====================================================================
  -- JESD reset sequencing:
  --   in_of_reset='0' — pretend the GTS subsystem is NOT in reset
  --   rst_ack_n  ='1' — deasserted ack (active-low signal idle)
  -- =====================================================================
  jesd_reset_seq_in_of_reset <= '0';
  jesd_reset_seq_rst_ack_n   <= '1';

  -- =====================================================================
  -- JESD reference clock / PLL management tie-offs
  --   refclk_on_ack='1', core_pll_locked='1' — claim the PLL is up so
  --   nothing downstream is gated on a "PLL not ready" signal.
  -- =====================================================================
  jesd_refclk_ctrl_txphy_clk          <= (others => '0');
  jesd_refclk_ctrl_refclk_fail_status <= (others => '0');
  jesd_refclk_ctrl_refclk_on_ack      <= '1';
  jesd_refclk_ctrl_core_pll_locked    <= '1';

  -- =====================================================================
  -- JESD CSR readback (mode 4, JESD spec field encodings)
  -- =====================================================================
  jesd_csr_readback_csr_hd <= '1';                       -- HD = 1 (high density)
  jesd_csr_readback_csr_cs <= "00";                      -- CS = 0 control bits
  jesd_csr_readback_csr_l  <= std_logic_vector(to_unsigned(3,  5)); -- L=4 → field=3
  jesd_csr_readback_csr_k  <= std_logic_vector(to_unsigned(31, 5)); -- K=32 → field=31
  jesd_csr_readback_csr_n  <= std_logic_vector(to_unsigned(15, 5)); -- N=16 → field=15
  jesd_csr_readback_csr_np <= std_logic_vector(to_unsigned(15, 5)); -- NP=16 → field=15
  jesd_csr_readback_csr_s  <= std_logic_vector(to_unsigned(0,  5)); -- S=1 → field=0
  jesd_csr_readback_csr_cf <= std_logic_vector(to_unsigned(0,  5)); -- CF=0
  jesd_csr_readback_csr_f  <= std_logic_vector(to_unsigned(1,  8)); -- F=2 → field=1
  jesd_csr_readback_csr_m  <= std_logic_vector(to_unsigned(3,  8)); -- M=4 → field=3

  jesd_csr_readback_dlb_data      <= (others => '0');
  jesd_csr_readback_dlb_kchar     <= (others => '0');
  jesd_csr_readback_testmode      <= (others => '0');
  jesd_csr_readback_testpattern_a <= (others => '0');
  jesd_csr_readback_testpattern_b <= (others => '0');
  jesd_csr_readback_testpattern_c <= (others => '0');
  jesd_csr_readback_testpattern_d <= (others => '0');

  -- =====================================================================
  -- PIO + TX enable stubs
  -- =====================================================================
  pio_control_pio_control <= (others => '0');
  tx_enbl_tx_enbl         <= '0';

  -- pio_status_pio_status is an input that we deliberately leave
  -- unreferenced. Suppress synthesis "unused port" warning by reading
  -- it into an unused signal.
  p_consume : process(jesd204_tx_link_clk_clk)
    variable v_pio_unused  : std_logic_vector(31 downto 0);
    variable v_link0_ferr  : std_logic;
    variable v_link1_ferr  : std_logic;
    variable v_rst_n       : std_logic;
    variable v_rs_pri      : std_logic_vector(3 downto 0);
    variable v_refclk_on   : std_logic_vector(9 downto 0);
  begin
    if rising_edge(jesd204_tx_link_clk_clk) then
      if reset_sink_reset = '1' then
        v_pio_unused  := (others => '0');
        v_link0_ferr  := '0';
        v_link1_ferr  := '0';
        v_rst_n       := '0';
        v_rs_pri      := (others => '0');
        v_refclk_on   := (others => '0');
      else
        v_pio_unused  := pio_status_pio_status;
        v_link0_ferr  := jesd_link0_status_frame_error;
        v_link1_ferr  := jesd_link1_status_frame_error;
        v_rst_n       := jesd_reset_seq_rst_n;
        v_rs_pri      := jesd_refclk_ctrl_rs_priority;
        v_refclk_on   := jesd_refclk_ctrl_refclk_on;
      end if;
    end if;
  end process p_consume;

end architecture rtl;
