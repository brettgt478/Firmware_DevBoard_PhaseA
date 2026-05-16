-- =============================================================================
-- Module:      DacControllerPkg
-- Description: Shared types, constants, and register definitions for
--              dac_controller_0. Targets the AD9176-FMC-EBZ eval board on an
--              Agilex 5 dev board (single AD9176, two JESD links).
--              Successor to IqRouterPkg — see iq_router_pkg.vhd (deprecated).
-- Author:      Brett Taylor
-- Created:     2026-04-06
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package DacControllerPkg is

  -- ===========================================================================
  -- JESD204B Link Parameters (Mode 4, per-link)
  -- One AD9176 with two JESD links (link 0 = DAC core A, link 1 = DAC core B).
  -- ===========================================================================
  constant C_JESD_M  : positive := 4;   -- converters per link
  constant C_JESD_L  : positive := 4;   -- lanes per link
  constant C_JESD_F  : positive := 2;   -- octets per frame per lane
  constant C_JESD_S  : positive := 1;   -- samples per converter per frame
  constant C_JESD_N  : positive := 16;  -- converter resolution (bits)
  constant C_JESD_NP : positive := 16;  -- JESD word size (bits)
  constant C_JESD_K  : positive := 32;  -- frames per multiframe
  constant C_JESD_HD : positive := 1;   -- high density mode

  -- Two active links (one AD9176); two more stubbed for future second AD9176.
  constant C_NUM_LINKS       : positive := 4;
  constant C_NUM_ACTIVE_LINKS : positive := 2;  -- links 0 and 1 only

  constant C_SAMPLES_PER_CLK : positive := 2;   -- S0 and S1 per converter
  constant C_SAMPLE_BITS     : positive := 16;
  constant C_PHASE_BITS      : positive := 32;
  constant C_LANE_DATA_BITS  : positive := 32;  -- per lane per clock
  constant C_LINK_DATA_BITS  : positive := 128; -- per streaming source

  -- LMFC period in link clocks: K * F / (L * 4) = 32 * 2 / 16 = 4 frames/clk
  -- → LMFC period = K / frames_per_clk = 32 / 2 = 16 link clocks
  constant C_LMFC_PERIOD : positive := 16;

  -- ===========================================================================
  -- Sample Bus Type (8 samples per clock: 4 converters × 2 samples)
  -- ===========================================================================
  type t_sample_array is array (natural range <>) of
    signed(C_SAMPLE_BITS - 1 downto 0);

  type t_sample_bus is record
    m0_s0 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 0, Sample 0
    m0_s1 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 0, Sample 1
    m1_s0 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 1, Sample 0
    m1_s1 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 1, Sample 1
    m2_s0 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 2, Sample 0
    m2_s1 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 2, Sample 1
    m3_s0 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 3, Sample 0
    m3_s1 : signed(C_SAMPLE_BITS - 1 downto 0);  -- Converter 3, Sample 1
  end record t_sample_bus;

  constant C_SAMPLE_BUS_ZERO : t_sample_bus := (
    m0_s0 => (others => '0'), m0_s1 => (others => '0'),
    m1_s0 => (others => '0'), m1_s1 => (others => '0'),
    m2_s0 => (others => '0'), m2_s1 => (others => '0'),
    m3_s0 => (others => '0'), m3_s1 => (others => '0')
  );

  -- ===========================================================================
  -- Lane Data Type (4 lanes × 32 bits = 128 bits per streaming source)
  -- ===========================================================================
  type t_lane_data is record
    lane0 : std_logic_vector(C_LANE_DATA_BITS - 1 downto 0);
    lane1 : std_logic_vector(C_LANE_DATA_BITS - 1 downto 0);
    lane2 : std_logic_vector(C_LANE_DATA_BITS - 1 downto 0);
    lane3 : std_logic_vector(C_LANE_DATA_BITS - 1 downto 0);
  end record t_lane_data;

  constant C_LANE_DATA_ZERO : t_lane_data := (
    lane0 => (others => '0'), lane1 => (others => '0'),
    lane2 => (others => '0'), lane3 => (others => '0')
  );

  -- ===========================================================================
  -- Avalon-MM Interface Constants
  -- 10-bit address space (1 KB) to match the lwhpm2fpga AXI address width.
  -- ===========================================================================
  constant C_AVMM_ADDR_WIDTH : positive := 10;
  constant C_AVMM_DATA_WIDTH : positive := 32;

  -- ===========================================================================
  -- Register Map (10-bit byte-addressed offsets, 0x000–0x3FF)
  -- Base address on lwhps2fpga bridge: TBD in Platform Designer project.
  -- ===========================================================================

  -- Scratchpad (0x000–0x00F): HPS bridge connectivity test
  constant C_REG_SCRATCH0          : unsigned(9 downto 0) := "00" & x"00";  -- 0x000
  constant C_REG_SCRATCH1          : unsigned(9 downto 0) := "00" & x"04";  -- 0x004
  constant C_REG_SCRATCH2          : unsigned(9 downto 0) := "00" & x"08";  -- 0x008
  constant C_REG_SCRATCH3          : unsigned(9 downto 0) := "00" & x"0C";  -- 0x00C

  -- JESD TX CSR (0x020–0x03C)
  constant C_REG_JESD_SYNC_CTRL    : unsigned(9 downto 0) := "00" & x"20";  -- 0x020
  constant C_REG_JESD_SYNC_STATUS  : unsigned(9 downto 0) := "00" & x"24";  -- 0x024
  constant C_REG_JESD_SYNC_ERR     : unsigned(9 downto 0) := "00" & x"28";  -- 0x028
  constant C_REG_JESD_TX_SRC_SEL   : unsigned(9 downto 0) := "00" & x"30";  -- 0x030
  constant C_REG_JESD_TX_SRC_STAT  : unsigned(9 downto 0) := "00" & x"34";  -- 0x034

  -- Sine Wave Gen CSR (0x040–0x07C)
  constant C_REG_SINE_CTRL         : unsigned(9 downto 0) := "00" & x"40";  -- 0x040
  constant C_REG_SINE_FREQ_CH1_I   : unsigned(9 downto 0) := "00" & x"50";  -- 0x050
  constant C_REG_SINE_FREQ_CH1_Q   : unsigned(9 downto 0) := "00" & x"54";  -- 0x054
  constant C_REG_SINE_FREQ_CH2_I   : unsigned(9 downto 0) := "00" & x"58";  -- 0x058
  constant C_REG_SINE_FREQ_CH2_Q   : unsigned(9 downto 0) := "00" & x"5C";  -- 0x05C
  constant C_REG_SINE_PHASE_M0     : unsigned(9 downto 0) := "00" & x"60";  -- 0x060
  constant C_REG_SINE_PHASE_M1     : unsigned(9 downto 0) := "00" & x"64";  -- 0x064
  constant C_REG_SINE_PHASE_M2     : unsigned(9 downto 0) := "00" & x"68";  -- 0x068
  constant C_REG_SINE_PHASE_M3     : unsigned(9 downto 0) := "00" & x"6C";  -- 0x06C
  constant C_REG_SINE_AMP_M0       : unsigned(9 downto 0) := "00" & x"70";  -- 0x070
  constant C_REG_SINE_AMP_M1       : unsigned(9 downto 0) := "00" & x"74";  -- 0x074
  constant C_REG_SINE_AMP_M2       : unsigned(9 downto 0) := "00" & x"78";  -- 0x078
  constant C_REG_SINE_AMP_M3       : unsigned(9 downto 0) := "00" & x"7C";  -- 0x07C

  -- PIO CSR (0x080–0x084): stubbed, deferred
  constant C_REG_PIO_CTRL          : unsigned(9 downto 0) := "00" & x"80";  -- 0x080
  constant C_REG_PIO_STATUS        : unsigned(9 downto 0) := "00" & x"84";  -- 0x084

  -- ===========================================================================
  -- Sine Wave Gen CSR Record
  -- ===========================================================================
  type t_sine_csr is record
    enable       : std_logic;
    conv_enable  : std_logic_vector(3 downto 0);
    freq_m0      : unsigned(C_PHASE_BITS - 1 downto 0);
    freq_m1      : unsigned(C_PHASE_BITS - 1 downto 0);
    freq_m2      : unsigned(C_PHASE_BITS - 1 downto 0);
    freq_m3      : unsigned(C_PHASE_BITS - 1 downto 0);
    phase_ofs_m0 : unsigned(C_PHASE_BITS - 1 downto 0);
    phase_ofs_m1 : unsigned(C_PHASE_BITS - 1 downto 0);
    phase_ofs_m2 : unsigned(C_PHASE_BITS - 1 downto 0);
    phase_ofs_m3 : unsigned(C_PHASE_BITS - 1 downto 0);
    amplitude_m0 : unsigned(C_SAMPLE_BITS - 1 downto 0);
    amplitude_m1 : unsigned(C_SAMPLE_BITS - 1 downto 0);
    amplitude_m2 : unsigned(C_SAMPLE_BITS - 1 downto 0);
    amplitude_m3 : unsigned(C_SAMPLE_BITS - 1 downto 0);
  end record t_sine_csr;

  constant C_SINE_CSR_DEFAULT : t_sine_csr := (
    enable       => '0',
    conv_enable  => (others => '0'),
    freq_m0      => (others => '0'),
    freq_m1      => (others => '0'),
    freq_m2      => (others => '0'),
    freq_m3      => (others => '0'),
    phase_ofs_m0 => (others => '0'),
    phase_ofs_m1 => (others => '0'),
    phase_ofs_m2 => (others => '0'),
    phase_ofs_m3 => (others => '0'),
    amplitude_m0 => x"7FFF",
    amplitude_m1 => x"7FFF",
    amplitude_m2 => x"7FFF",
    amplitude_m3 => x"7FFF"
  );

  -- ===========================================================================
  -- JESD Sync CSR Record
  -- ===========================================================================
  type t_jesd_sync_csr is record
    sync_mode : std_logic;  -- 0 = per-DAC (2-link groups), 1 = all-four
    src_sel   : std_logic;  -- 0 = NCO, 1 = FIFO (shadow register)
  end record t_jesd_sync_csr;

  type t_jesd_sync_status is record
    txlink_ready       : std_logic_vector(3 downto 0);
    group_synced       : std_logic_vector(1 downto 0);
    lmfc_aligned       : std_logic;
    sync_err           : std_logic_vector(3 downto 0);
    src_switch_pending : std_logic;
    src_active         : std_logic;
  end record t_jesd_sync_status;

  -- ===========================================================================
  -- Utility Functions
  -- ===========================================================================
  function clog2(val : positive) return positive;

end package DacControllerPkg;

package body DacControllerPkg is

  function clog2(val : positive) return positive is
    variable v : positive := 1;
    variable n : natural  := 0;
  begin
    while v < val loop
      v := v * 2;
      n := n + 1;
    end loop;
    return n;
  end function clog2;

end package body DacControllerPkg;
