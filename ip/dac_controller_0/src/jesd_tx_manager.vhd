-- =============================================================================
-- Module:      JesdTxManager
-- Description: JESD204B Mode 4 transport layer — sample to lane packing
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity JesdTxManager is
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;
    -- Sample input (from NCO or data source MUX)
    samples_in     : in  t_sample_bus;
    samples_valid  : in  std_logic;
    -- Lane data output (to JESD204B IP streaming source)
    lane_data_out  : out t_lane_data;
    lane_valid     : out std_logic
  );
end entity JesdTxManager;

architecture rtl of JesdTxManager is

  -- Registered output
  signal lane_data_r : t_lane_data;
  signal lane_valid_r : std_logic;

begin

  -- =========================================================================
  -- Transport Layer Packing (Table 18, MSB-first byte ordering)
  --
  -- Per link clock cycle, each lane carries 4 octets (2 frames of F=2):
  --   Lane 0: M0_S0[15:8] & M0_S0[7:0] & M0_S1[15:8] & M0_S1[7:0]
  --   Lane 1: M1_S0[15:8] & M1_S0[7:0] & M1_S1[15:8] & M1_S1[7:0]
  --   Lane 2: M2_S0[15:8] & M2_S0[7:0] & M2_S1[15:8] & M2_S1[7:0]
  --   Lane 3: M3_S0[15:8] & M3_S0[7:0] & M3_S1[15:8] & M3_S1[7:0]
  --
  -- One converter per lane (HD=1 degenerates to same mapping as HD=0
  -- for this parameter set).
  --
  -- IMPORTANT: The Intel JESD204B IP requires continuous valid data once
  -- tx_ready is asserted — there is no backpressure mechanism. The upstream
  -- source (NCO or DcFifo) must keep samples_valid asserted at all times
  -- during normal link operation. When samples_valid is low, lane data is
  -- zeroed as a safety fallback (mid-scale = silence on the AD9176), but
  -- this condition should not occur during active transmission.
  -- =========================================================================

  p_pack : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lane_data_r <= C_LANE_DATA_ZERO;
        lane_valid_r <= '0';
      else
        lane_valid_r <= samples_valid;

        if samples_valid = '1' then
          -- Lane 0: Converter M0 (Ch1 I)
          lane_data_r.lane0 <=
            std_logic_vector(samples_in.m0_s0(15 downto 8)) &
            std_logic_vector(samples_in.m0_s0(7 downto 0)) &
            std_logic_vector(samples_in.m0_s1(15 downto 8)) &
            std_logic_vector(samples_in.m0_s1(7 downto 0));

          -- Lane 1: Converter M1 (Ch1 Q)
          lane_data_r.lane1 <=
            std_logic_vector(samples_in.m1_s0(15 downto 8)) &
            std_logic_vector(samples_in.m1_s0(7 downto 0)) &
            std_logic_vector(samples_in.m1_s1(15 downto 8)) &
            std_logic_vector(samples_in.m1_s1(7 downto 0));

          -- Lane 2: Converter M2 (Ch2 I)
          lane_data_r.lane2 <=
            std_logic_vector(samples_in.m2_s0(15 downto 8)) &
            std_logic_vector(samples_in.m2_s0(7 downto 0)) &
            std_logic_vector(samples_in.m2_s1(15 downto 8)) &
            std_logic_vector(samples_in.m2_s1(7 downto 0));

          -- Lane 3: Converter M3 (Ch2 Q)
          lane_data_r.lane3 <=
            std_logic_vector(samples_in.m3_s0(15 downto 8)) &
            std_logic_vector(samples_in.m3_s0(7 downto 0)) &
            std_logic_vector(samples_in.m3_s1(15 downto 8)) &
            std_logic_vector(samples_in.m3_s1(7 downto 0));
        else
          lane_data_r <= C_LANE_DATA_ZERO;
        end if;
      end if;
    end if;
  end process p_pack;

  lane_data_out <= lane_data_r;
  lane_valid    <= lane_valid_r;

end architecture rtl;
