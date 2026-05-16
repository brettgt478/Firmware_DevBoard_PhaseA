-- =============================================================================
-- Module:      JesdTxManager_tb
-- Description: Self-checking testbench for JESD204B transport layer packing
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity JesdTxManager_tb is
end entity JesdTxManager_tb;

architecture sim of JesdTxManager_tb is

  constant CLK_PERIOD : time := 4 ns;  -- 250 MHz

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal samples_in    : t_sample_bus := C_SAMPLE_BUS_ZERO;
  signal samples_valid : std_logic := '0';
  signal lane_data_out : t_lane_data;
  signal lane_valid    : std_logic;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_dut : entity work.JesdTxManager
    port map (
      clk           => clk,
      rst           => rst,
      samples_in    => samples_in,
      samples_valid => samples_valid,
      lane_data_out => lane_data_out,
      lane_valid    => lane_valid
    );

  -- Single stimulus process drives rst, inputs, and checks outputs.
  p_stim : process
    variable v_err_count : integer := 0;
    variable expected_lane0 : std_logic_vector(31 downto 0);
    variable expected_lane1 : std_logic_vector(31 downto 0);
    variable expected_lane2 : std_logic_vector(31 downto 0);
    variable expected_lane3 : std_logic_vector(31 downto 0);
    variable v_valid_gaps   : integer := 0;
    variable v_data_errs    : integer := 0;
  begin
    -- Hold reset for 5 cycles
    wait for CLK_PERIOD * 5;
    rst <= '0';
    wait until rising_edge(clk);

    -- =======================================================================
    -- TB-JTXM-001: Static pattern — known samples, all 4 lanes
    -- =======================================================================
    report "TB-JTXM-001: Static pattern lane packing" severity error;

    samples_in.m0_s0 <= to_signed(16#1234#, 16);
    samples_in.m0_s1 <= to_signed(16#5678#, 16);
    samples_in.m1_s0 <= to_signed(-16#0ABC#, 16);  -- negative: 0xF544
    samples_in.m1_s1 <= to_signed(16#0DEF#, 16);
    samples_in.m2_s0 <= to_signed(16#2222#, 16);
    samples_in.m2_s1 <= to_signed(16#3333#, 16);
    samples_in.m3_s0 <= to_signed(16#4444#, 16);
    samples_in.m3_s1 <= to_signed(16#5555#, 16);
    samples_valid <= '1';

    wait until rising_edge(clk);
    wait until rising_edge(clk);  -- 1 clk pipeline latency

    -- Lane 0: M0_S0=0x1234, M0_S1=0x5678 -> 0x12345678
    expected_lane0 := x"12345678";
    assert lane_data_out.lane0 = expected_lane0
      report "TB-JTXM-001 FAIL: lane0 = " &
        to_hstring(unsigned(lane_data_out.lane0)) &
        " expected " & to_hstring(unsigned(expected_lane0))
      severity error;
    if lane_data_out.lane0 /= expected_lane0 then
      v_err_count := v_err_count + 1;
    end if;

    -- Lane 1: M1_S0=-0x0ABC=0xF544, M1_S1=0x0DEF -> 0xF5440DEF
    expected_lane1 := x"F5440DEF";
    assert lane_data_out.lane1 = expected_lane1
      report "TB-JTXM-001 FAIL: lane1 = " &
        to_hstring(unsigned(lane_data_out.lane1)) &
        " expected " & to_hstring(unsigned(expected_lane1))
      severity error;
    if lane_data_out.lane1 /= expected_lane1 then
      v_err_count := v_err_count + 1;
    end if;

    -- Lane 2: M2_S0=0x2222, M2_S1=0x3333 -> 0x22223333
    expected_lane2 := x"22223333";
    assert lane_data_out.lane2 = expected_lane2
      report "TB-JTXM-001 FAIL: lane2 = " &
        to_hstring(unsigned(lane_data_out.lane2)) &
        " expected " & to_hstring(unsigned(expected_lane2))
      severity error;
    if lane_data_out.lane2 /= expected_lane2 then
      v_err_count := v_err_count + 1;
    end if;

    -- Lane 3: M3_S0=0x4444, M3_S1=0x5555 -> 0x44445555
    expected_lane3 := x"44445555";
    assert lane_data_out.lane3 = expected_lane3
      report "TB-JTXM-001 FAIL: lane3 = " &
        to_hstring(unsigned(lane_data_out.lane3)) &
        " expected " & to_hstring(unsigned(expected_lane3))
      severity error;
    if lane_data_out.lane3 /= expected_lane3 then
      v_err_count := v_err_count + 1;
    end if;

    assert lane_valid = '1'
      report "TB-JTXM-001 FAIL: lane_valid not asserted" severity error;
    if lane_valid /= '1' then v_err_count := v_err_count + 1; end if;

    -- =======================================================================
    -- TB-JTXM-002: Continuous stream — 1000 cycles, spot-check for gaps
    --              and data correctness
    -- =======================================================================
    report "TB-JTXM-002: Continuous stream stability" severity error;

    v_valid_gaps := 0;
    v_data_errs  := 0;

    for i in 0 to 999 loop
      samples_in.m0_s0 <= to_signed(i mod 32768, 16);
      samples_in.m0_s1 <= to_signed((i + 1) mod 32768, 16);
      samples_in.m1_s0 <= to_signed(i mod 32768, 16);
      samples_in.m1_s1 <= to_signed((i + 1) mod 32768, 16);
      samples_in.m2_s0 <= to_signed(i mod 32768, 16);
      samples_in.m2_s1 <= to_signed((i + 1) mod 32768, 16);
      samples_in.m3_s0 <= to_signed(i mod 32768, 16);
      samples_in.m3_s1 <= to_signed((i + 1) mod 32768, 16);
      samples_valid <= '1';
      wait until rising_edge(clk);

      -- After pipeline latency (i >= 1), check valid every cycle
      -- and spot-check data every 100th cycle
      if i >= 1 then
        if lane_valid /= '1' then
          v_valid_gaps := v_valid_gaps + 1;
        end if;

        -- Spot-check lane data every 100 cycles
        if (i mod 100) = 0 then
          -- Previous cycle's data should be on output (pipeline delay)
          -- Input was (i-1) mod 32768 for S0, i mod 32768 for S1
          expected_lane0 :=
            std_logic_vector(to_unsigned((i - 1) mod 32768, 16)) &
            std_logic_vector(to_unsigned(i mod 32768, 16));
          if lane_data_out.lane0 /= expected_lane0 then
            v_data_errs := v_data_errs + 1;
            report "TB-JTXM-002 FAIL: data mismatch at cycle " &
              integer'image(i) & " lane0 = " &
              to_hstring(unsigned(lane_data_out.lane0)) &
              " expected " & to_hstring(unsigned(expected_lane0))
              severity error;
          end if;
        end if;
      end if;
    end loop;

    assert v_valid_gaps = 0
      report "TB-JTXM-002 FAIL: " & integer'image(v_valid_gaps) &
        " valid gaps detected in 1000-cycle stream" severity error;
    if v_valid_gaps /= 0 then v_err_count := v_err_count + 1; end if;

    assert v_data_errs = 0
      report "TB-JTXM-002 FAIL: " & integer'image(v_data_errs) &
        " data mismatches in spot-checks" severity error;
    if v_data_errs /= 0 then v_err_count := v_err_count + 1; end if;

    samples_valid <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Valid should deassert after input goes low (1 clk later)
    assert lane_valid = '0'
      report "TB-JTXM-002 FAIL: lane_valid didn't deassert" severity error;
    if lane_valid /= '0' then v_err_count := v_err_count + 1; end if;

    -- =======================================================================
    -- TB-JTXM-003: Byte ordering — 0xFF00 pattern (MSB=1 exercises sign bit)
    -- =======================================================================
    report "TB-JTXM-003: Byte ordering verification" severity error;

    -- 0xFF00 as signed 16-bit = -256; bit pattern is exactly 0xFF00
    samples_in.m0_s0 <= to_signed(-256, 16);
    samples_in.m0_s1 <= to_signed(-256, 16);
    samples_in.m1_s0 <= to_signed(-256, 16);
    samples_in.m1_s1 <= to_signed(-256, 16);
    samples_in.m2_s0 <= to_signed(-256, 16);
    samples_in.m2_s1 <= to_signed(-256, 16);
    samples_in.m3_s0 <= to_signed(-256, 16);
    samples_in.m3_s1 <= to_signed(-256, 16);
    samples_valid <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- MSB-first: lane should be 0xFF00FF00
    -- Byte sequence: 0xFF, 0x00, 0xFF, 0x00
    assert lane_data_out.lane0 = x"FF00FF00"
      report "TB-JTXM-003 FAIL: byte ordering lane0 = " &
        to_hstring(unsigned(lane_data_out.lane0)) &
        " expected FF00FF00" severity error;
    if lane_data_out.lane0 /= x"FF00FF00" then
      v_err_count := v_err_count + 1;
    end if;

    assert lane_data_out.lane1 = x"FF00FF00"
      report "TB-JTXM-003 FAIL: byte ordering lane1 = " &
        to_hstring(unsigned(lane_data_out.lane1)) &
        " expected FF00FF00" severity error;
    if lane_data_out.lane1 /= x"FF00FF00" then
      v_err_count := v_err_count + 1;
    end if;

    assert lane_data_out.lane2 = x"FF00FF00"
      report "TB-JTXM-003 FAIL: byte ordering lane2 = " &
        to_hstring(unsigned(lane_data_out.lane2)) &
        " expected FF00FF00" severity error;
    if lane_data_out.lane2 /= x"FF00FF00" then
      v_err_count := v_err_count + 1;
    end if;

    assert lane_data_out.lane3 = x"FF00FF00"
      report "TB-JTXM-003 FAIL: byte ordering lane3 = " &
        to_hstring(unsigned(lane_data_out.lane3)) &
        " expected FF00FF00" severity error;
    if lane_data_out.lane3 /= x"FF00FF00" then
      v_err_count := v_err_count + 1;
    end if;

    -- =======================================================================
    -- TB-JTXM-004: Lane mapping — unique pattern per converter
    -- =======================================================================
    report "TB-JTXM-004: Lane mapping verification" severity error;

    samples_in.m0_s0 <= x"0A0A";  -- unique per converter
    samples_in.m0_s1 <= x"0A0A";
    samples_in.m1_s0 <= x"0B0B";
    samples_in.m1_s1 <= x"0B0B";
    samples_in.m2_s0 <= x"0C0C";
    samples_in.m2_s1 <= x"0C0C";
    samples_in.m3_s0 <= x"0D0D";
    samples_in.m3_s1 <= x"0D0D";
    samples_valid <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert lane_data_out.lane0 = x"0A0A0A0A"
      report "TB-JTXM-004 FAIL: lane0 = " &
        to_hstring(unsigned(lane_data_out.lane0)) &
        " expected 0A0A0A0A" severity error;
    if lane_data_out.lane0 /= x"0A0A0A0A" then
      v_err_count := v_err_count + 1;
    end if;

    assert lane_data_out.lane1 = x"0B0B0B0B"
      report "TB-JTXM-004 FAIL: lane1 = " &
        to_hstring(unsigned(lane_data_out.lane1)) &
        " expected 0B0B0B0B" severity error;
    if lane_data_out.lane1 /= x"0B0B0B0B" then
      v_err_count := v_err_count + 1;
    end if;

    assert lane_data_out.lane2 = x"0C0C0C0C"
      report "TB-JTXM-004 FAIL: lane2 = " &
        to_hstring(unsigned(lane_data_out.lane2)) &
        " expected 0C0C0C0C" severity error;
    if lane_data_out.lane2 /= x"0C0C0C0C" then
      v_err_count := v_err_count + 1;
    end if;

    assert lane_data_out.lane3 = x"0D0D0D0D"
      report "TB-JTXM-004 FAIL: lane3 = " &
        to_hstring(unsigned(lane_data_out.lane3)) &
        " expected 0D0D0D0D" severity error;
    if lane_data_out.lane3 /= x"0D0D0D0D" then
      v_err_count := v_err_count + 1;
    end if;

    -- =======================================================================
    -- Summary
    -- =======================================================================
    samples_valid <= '0';
    wait for CLK_PERIOD * 5;

    if v_err_count = 0 then
      report "SIMULATION PASSED" severity error;
    else
      report "SIMULATION FAILED with " & integer'image(v_err_count) &
        " errors" severity failure;
    end if;
    std.env.stop;
  end process p_stim;

end architecture sim;
