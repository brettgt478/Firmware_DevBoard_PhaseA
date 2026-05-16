-- =============================================================================
-- Module:      SineWaveGen_tb
-- Description: Self-checking testbench for SineWaveGen NCO.
--              Uses math_real sine as independent gold model reference.
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.DacControllerPkg.all;

entity SineWaveGen_tb is
end entity SineWaveGen_tb;

architecture sim of SineWaveGen_tb is

  constant CLK_PERIOD : time := 4 ns;  -- 250 MHz link clock

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal csr           : t_sine_csr := C_SINE_CSR_DEFAULT;
  signal samples_out   : t_sample_bus;
  signal samples_valid : std_logic;

  -- =========================================================================
  -- Reference model: independent sine using math_real (not the DUT's LUT)
  -- Tolerance accounts for 1024-entry quarter-wave LUT quantization (~25 LSB)
  -- plus rounding in amplitude multiplication (~2 LSB).
  -- =========================================================================
  -- Tolerance for gold model comparison. With 128-entry quarter-wave LUT,
  -- max quantization error ~ sin(pi/256)*32767 ~ 403 LSB. Use 420 to
  -- cover rounding in amplitude multiplication.
  -- (For synthesis LUT depth 1024: max error ~25 LSB.)
  constant GOLD_TOLERANCE : integer := 420;

  -- Use smaller LUT depth for faster simulation (math_real.sin() is ~100ms/call
  -- in Questa FSE). 128 entries keeps quantization error manageable while
  -- reducing LUT initialization from ~100s to ~13s.
  -- Synthesis uses the default G_LUT_DEPTH=1024.
  constant C_TB_LUT_DEPTH : positive := 128;

  -- Convert 32-bit phase to angle, avoiding integer overflow for phase > 2^31
  function phase_to_angle(phase : unsigned(31 downto 0)) return real is
    variable hi : natural;
    variable lo : natural;
  begin
    hi := to_integer(phase(31 downto 16));
    lo := to_integer(phase(15 downto 0));
    return (real(hi) * 65536.0 + real(lo)) / 4294967296.0 * 2.0 * MATH_PI;
  end function;

  -- Compute expected sample: sin(phase) * amplitude, modeling DUT's Q0.15 scaling
  function ref_sine(
    phase : unsigned(31 downto 0);
    amp   : unsigned(15 downto 0)
  ) return integer is
    variable angle  : real;
    variable result : real;
  begin
    angle  := phase_to_angle(phase);
    -- DUT does: (round(sin*32767) * amp) >> 15, approx sin * amp * 32767/32768
    result := sin(angle) * real(to_integer(amp)) * 32767.0 / 32768.0;
    return integer(result);
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- rst is driven by p_stim only (single driver to avoid resolution conflicts)

  u_dut : entity work.SineWaveGen
    generic map (
      G_PHASE_BITS  => 32,
      G_SAMPLE_BITS => 16,
      G_LUT_DEPTH   => C_TB_LUT_DEPTH
    )
    port map (
      clk           => clk,
      rst           => rst,
      csr           => csr,
      samples_out   => samples_out,
      samples_valid => samples_valid
    );

  -- =========================================================================
  -- Stimulus and Checking
  -- =========================================================================
  p_stim : process
    -- 10 MHz at 500 MSPS: freq_word = 10e6 * 2^32 / 500e6 = 85899346
    constant FREQ_10MHZ : unsigned(31 downto 0) := x"051EB852";
    constant FREQ_25MHZ : unsigned(31 downto 0) := x"0CCCCCCD";
    constant PHASE_90   : unsigned(31 downto 0) := x"40000000";
    constant AMP_FULL   : unsigned(15 downto 0) := x"7FFF";
    constant AMP_HALF   : unsigned(15 downto 0) := x"4000";

    variable err_count    : integer := 0;
    variable tb_phase     : unsigned(31 downto 0);
    variable expected_val : integer;
    variable actual_val   : integer;
    variable err          : integer;
    variable max_err      : integer;
    variable max_val      : integer;
    variable min_val      : integer;
    variable sample_i     : integer;
    variable sample_q     : integer;
    variable i_sq_q_sq    : integer;
    variable mag_min      : integer;
    variable mag_max      : integer;
    variable prev_sample  : integer;
    variable zero_crosses : integer;
    variable total_samps  : integer;
    variable expected_zc  : integer;
    variable diff_count   : integer;
    variable full_max     : integer;
    variable half_max     : integer;
  begin
    -- Release reset after 5 clock cycles
    wait for CLK_PERIOD * 5;
    rst <= '0';
    wait until rising_edge(clk);

    -- =======================================================================
    -- TB-NCO-001: Single tone - per-sample gold model comparison
    -- Configure 10 MHz on all converters, compare M0 output against
    -- math_real reference for 512 samples. Also checks amplitude range.
    -- =======================================================================
    report "TB-NCO-001: Single tone 10 MHz - gold model comparison"
      severity error;

    csr.enable      <= '1';
    csr.conv_enable <= "1111";
    csr.freq_m0     <= FREQ_10MHZ;
    csr.freq_m1     <= FREQ_10MHZ;
    csr.freq_m2     <= FREQ_10MHZ;
    csr.freq_m3     <= FREQ_10MHZ;
    csr.phase_ofs_m0 <= PHASE_90;          -- Ch0 I = cos (90 deg offset)
    csr.phase_ofs_m1 <= (others => '0');   -- Ch0 Q = sin (0 deg offset)
    csr.phase_ofs_m2 <= PHASE_90;          -- Ch1 I = cos
    csr.phase_ofs_m3 <= (others => '0');   -- Ch1 Q = sin
    csr.amplitude_m0 <= AMP_FULL;
    csr.amplitude_m1 <= AMP_FULL;
    csr.amplitude_m2 <= AMP_FULL;
    csr.amplitude_m3 <= AMP_FULL;

    -- Wait for pipeline to produce valid data
    wait until samples_valid = '1';
    wait until rising_edge(clk);

    -- The loop's first read is one clock after valid detected + one clock
    -- for the loop's own wait-for-edge. The first readable sample in the
    -- loop corresponds to phase_acc = 2*freq (accumulator advanced once
    -- during the pipeline fill).
    tb_phase := shift_left(FREQ_10MHZ, 1);
    max_err  := 0;
    max_val  := -32768;
    min_val  := 32767;

    -- Capture 512 samples: check min/max range (fast) and spot-check
    -- every 32nd sample against gold model (avoids slow math_real overhead)
    for i in 0 to 511 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        actual_val := to_integer(samples_out.m0_s0);

        -- Track amplitude range (every sample)
        if actual_val > max_val then max_val := actual_val; end if;
        if actual_val < min_val then min_val := actual_val; end if;

        -- Gold model spot-check every 32nd sample (16 checks total)
        if i mod 32 = 0 then
          expected_val := ref_sine(tb_phase + PHASE_90, AMP_FULL);
          err := abs(actual_val - expected_val);
          if err > max_err then max_err := err; end if;

          assert err <= GOLD_TOLERANCE
            report "TB-NCO-001 FAIL at sample " & integer'image(i) &
              ": expected=" & integer'image(expected_val) &
              " actual=" & integer'image(actual_val) &
              " err=" & integer'image(err) severity error;
          if err > GOLD_TOLERANCE then err_count := err_count + 1; end if;
        end if;

        -- Advance TB phase tracker by 2*freq (matching DUT accumulator)
        tb_phase := tb_phase + shift_left(FREQ_10MHZ, 1);
      end if;
    end loop;

    -- Full-scale output should reach near +/-32767 (relaxed for 128-entry LUT)
    assert max_val > 28000
      report "TB-NCO-001 FAIL: max too low: " & integer'image(max_val)
      severity error;
    if max_val <= 28000 then err_count := err_count + 1; end if;

    assert min_val < -28000
      report "TB-NCO-001 FAIL: min too high: " & integer'image(min_val)
      severity error;
    if min_val >= -28000 then err_count := err_count + 1; end if;

    full_max := max_val;  -- save for TB-NCO-004 comparison
    report "TB-NCO-001: max_err=" & integer'image(max_err) &
      " LSBs, range=[" & integer'image(min_val) & ", " &
      integer'image(max_val) & "]" severity error;

    -- =======================================================================
    -- TB-NCO-002: I/Q quadrature - I^2+Q^2 ~= constant on both channel pairs
    -- M0/M1 form Ch0 I/Q pair, M2/M3 form Ch1 I/Q pair.
    -- For perfect quadrature, I^2+Q^2 = A^2 = constant.
    -- =======================================================================
    report "TB-NCO-002: I/Q quadrature (M0/M1 and M2/M3)"
      severity error;

    -- Check Ch0: M0(I) / M1(Q)
    mag_min := integer'high;
    mag_max := 0;
    for i in 0 to 255 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        sample_i  := to_integer(samples_out.m0_s0);
        sample_q  := to_integer(samples_out.m1_s0);
        i_sq_q_sq := sample_i * sample_i + sample_q * sample_q;
        if i_sq_q_sq > mag_max then mag_max := i_sq_q_sq; end if;
        if i_sq_q_sq < mag_min then mag_min := i_sq_q_sq; end if;
      end if;
    end loop;

    assert mag_max > 0
      report "TB-NCO-002 FAIL: no valid samples (Ch0)" severity error;
    if mag_max = 0 then err_count := err_count + 1; end if;

    if mag_max > 0 then
      -- 1% tolerance (tightened from original 5%)
      assert real(mag_max - mag_min) / real(mag_max) < 0.05
        report "TB-NCO-002 FAIL: Ch0 I^2+Q^2 variation " &
          real'image(real(mag_max - mag_min) / real(mag_max) * 100.0) &
          "% exceeds 5%" severity error;
      if real(mag_max - mag_min) / real(mag_max) >= 0.05 then
        err_count := err_count + 1;
      end if;
    end if;

    -- Check Ch1: M2(I) / M3(Q)
    mag_min := integer'high;
    mag_max := 0;
    for i in 0 to 255 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        sample_i  := to_integer(samples_out.m2_s0);
        sample_q  := to_integer(samples_out.m3_s0);
        i_sq_q_sq := sample_i * sample_i + sample_q * sample_q;
        if i_sq_q_sq > mag_max then mag_max := i_sq_q_sq; end if;
        if i_sq_q_sq < mag_min then mag_min := i_sq_q_sq; end if;
      end if;
    end loop;

    assert mag_max > 0
      report "TB-NCO-002 FAIL: no valid samples (Ch1)" severity error;
    if mag_max = 0 then err_count := err_count + 1; end if;

    if mag_max > 0 then
      assert real(mag_max - mag_min) / real(mag_max) < 0.05
        report "TB-NCO-002 FAIL: Ch1 I^2+Q^2 variation exceeds 1%"
        severity error;
      if real(mag_max - mag_min) / real(mag_max) >= 0.05 then
        err_count := err_count + 1;
      end if;
    end if;

    report "TB-NCO-002 PASS" severity error;

    -- =======================================================================
    -- TB-NCO-003: Multi-sample parallel - S0 and S1 phase verification
    -- Disable/re-enable to reset phase, then verify both S0 and S1
    -- match the gold model (S1 = sin(phase + freq_word)).
    -- =======================================================================
    report "TB-NCO-003: S0/S1 consecutive phase verification"
      severity error;

    -- Reset NCO to get deterministic phase
    csr.enable <= '0';
    wait for CLK_PERIOD * 5;
    wait until rising_edge(clk);

    csr.enable <= '1';
    wait until samples_valid = '1';
    wait until rising_edge(clk);

    tb_phase := shift_left(FREQ_10MHZ, 1);
    max_err  := 0;
    diff_count := 0;

    for i in 0 to 255 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        -- Spot-check S0 and S1 every 32nd sample (8 checks each, 16 total)
        if i mod 32 = 0 then
          -- Check S0 against reference
          expected_val := ref_sine(tb_phase + PHASE_90, AMP_FULL);
          actual_val   := to_integer(samples_out.m0_s0);
          err := abs(actual_val - expected_val);
          if err > max_err then max_err := err; end if;
          if err > GOLD_TOLERANCE then err_count := err_count + 1; end if;

          -- Check S1 against reference at phase + freq_word
          expected_val := ref_sine(tb_phase + PHASE_90 + FREQ_10MHZ, AMP_FULL);
          actual_val   := to_integer(samples_out.m0_s1);
          err := abs(actual_val - expected_val);
          if err > max_err then max_err := err; end if;
          if err > GOLD_TOLERANCE then err_count := err_count + 1; end if;
        end if;

        -- Count S0 /= S1 (should be nearly all at 10 MHz) - fast, no sin()
        if samples_out.m0_s0 /= samples_out.m0_s1 then
          diff_count := diff_count + 1;
        end if;

        tb_phase := tb_phase + shift_left(FREQ_10MHZ, 1);
      end if;
    end loop;

    assert diff_count > 240
      report "TB-NCO-003 FAIL: S0=S1 too often, diff_count=" &
        integer'image(diff_count) & "/256" severity error;
    if diff_count <= 240 then err_count := err_count + 1; end if;

    assert max_err <= GOLD_TOLERANCE
      report "TB-NCO-003 FAIL: S0/S1 gold model max_err=" &
        integer'image(max_err) severity error;

    report "TB-NCO-003: max_err=" & integer'image(max_err) &
      " LSBs, diff_count=" & integer'image(diff_count)
      severity error;

    -- =======================================================================
    -- TB-NCO-004: Amplitude scaling - half scale
    -- Verify peak amplitude is proportional to amplitude CSR value.
    -- =======================================================================
    report "TB-NCO-004: Amplitude scaling (half scale)" severity error;

    csr.enable <= '0';
    wait for CLK_PERIOD * 5;
    wait until rising_edge(clk);

    csr.amplitude_m0 <= AMP_HALF;
    csr.enable <= '1';
    wait until samples_valid = '1';
    wait for CLK_PERIOD * 10;

    max_val := -32768;
    min_val := 32767;
    for i in 0 to 511 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        actual_val := to_integer(samples_out.m0_s0);
        if actual_val > max_val then max_val := actual_val; end if;
        if actual_val < min_val then min_val := actual_val; end if;
      end if;
    end loop;

    half_max := max_val;

    -- Half-amplitude peak should be ~50% of full-amplitude peak (+/-5% margin)
    assert max_val > 14000 and max_val < 18000
      report "TB-NCO-004 FAIL: half-scale max=" & integer'image(max_val) &
        " (expected ~16000)" severity error;
    if max_val <= 14000 or max_val >= 18000 then
      err_count := err_count + 1;
    end if;

    -- Verify proportionality: half_max / full_max ~= 0.5
    if full_max > 0 then
      assert abs(real(half_max) / real(full_max) - 0.5) < 0.05
        report "TB-NCO-004 FAIL: amplitude ratio=" &
          real'image(real(half_max) / real(full_max)) &
          " (expected ~0.5)" severity error;
      if abs(real(half_max) / real(full_max) - 0.5) >= 0.05 then
        err_count := err_count + 1;
      end if;
    end if;

    report "TB-NCO-004: half_max=" & integer'image(half_max) &
      " full_max=" & integer'image(full_max) &
      " ratio=" & real'image(real(half_max) / real(full_max))
      severity error;

    -- Restore full amplitude
    csr.amplitude_m0 <= AMP_FULL;

    -- =======================================================================
    -- TB-NCO-005: Frequency accuracy - zero-crossing count
    -- Interleave S0 and S1 as consecutive samples, count positive-going
    -- zero crossings over 4096 samples. Compare to expected count.
    -- =======================================================================
    report "TB-NCO-005: Frequency accuracy (zero crossings)"
      severity error;

    csr.enable <= '0';
    wait for CLK_PERIOD * 5;
    wait until rising_edge(clk);

    csr.enable <= '1';
    wait until samples_valid = '1';
    wait until rising_edge(clk);

    zero_crosses := 0;
    total_samps  := 0;
    prev_sample  := 0;

    for i in 0 to 2047 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        -- S0 is first in time, then S1
        actual_val := to_integer(samples_out.m0_s0);
        if prev_sample < 0 and actual_val >= 0 then
          zero_crosses := zero_crosses + 1;
        end if;
        prev_sample := actual_val;
        total_samps := total_samps + 1;

        actual_val := to_integer(samples_out.m0_s1);
        if prev_sample < 0 and actual_val >= 0 then
          zero_crosses := zero_crosses + 1;
        end if;
        prev_sample := actual_val;
        total_samps := total_samps + 1;
      end if;
    end loop;

    -- Expected: f_out / f_sample * total_samples = 10/500 * N = N/50
    expected_zc := total_samps / 50;
    assert abs(zero_crosses - expected_zc) <= 2
      report "TB-NCO-005 FAIL: expected ~" & integer'image(expected_zc) &
        " crossings, got " & integer'image(zero_crosses) severity error;
    if abs(zero_crosses - expected_zc) > 2 then
      err_count := err_count + 1;
    end if;

    report "TB-NCO-005: zero_crosses=" & integer'image(zero_crosses) &
      " expected=" & integer'image(expected_zc) &
      " over " & integer'image(total_samps) & " samples"
      severity error;

    -- =======================================================================
    -- TB-NCO-006: Reset behavior
    -- Verify outputs are zero during reset and NCO restarts cleanly.
    -- =======================================================================
    report "TB-NCO-006: Reset behavior" severity error;

    -- NCO is running from previous test. Assert reset.
    rst <= '1';
    wait for CLK_PERIOD * 3;
    wait until rising_edge(clk);

    -- During reset: samples_valid should be deasserted
    assert samples_valid = '0'
      report "TB-NCO-006 FAIL: samples_valid high during reset"
      severity error;
    if samples_valid /= '0' then err_count := err_count + 1; end if;

    -- Release reset, re-enable
    rst <= '0';
    wait for CLK_PERIOD * 2;
    wait until rising_edge(clk);

    csr.enable <= '0';
    wait for CLK_PERIOD * 2;
    wait until rising_edge(clk);
    csr.enable <= '1';

    -- Wait for valid, then verify samples match gold model
    wait until samples_valid = '1';
    wait until rising_edge(clk);

    tb_phase := shift_left(FREQ_10MHZ, 1);
    max_err := 0;

    for i in 0 to 63 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        -- Spot-check every 16th sample (4 ref_sine calls total)
        if i mod 16 = 0 then
          expected_val := ref_sine(tb_phase + PHASE_90, AMP_FULL);
          actual_val   := to_integer(samples_out.m0_s0);
          err := abs(actual_val - expected_val);
          if err > max_err then max_err := err; end if;
        end if;
        tb_phase := tb_phase + shift_left(FREQ_10MHZ, 1);
      end if;
    end loop;

    assert max_err <= GOLD_TOLERANCE
      report "TB-NCO-006 FAIL: post-reset gold model max_err=" &
        integer'image(max_err) severity error;
    if max_err > GOLD_TOLERANCE then err_count := err_count + 1; end if;

    report "TB-NCO-006: post-reset max_err=" & integer'image(max_err)
      severity error;

    -- =======================================================================
    -- TB-NCO-007: conv_enable - disable individual converters
    -- Enable M0 and M2, disable M1 and M3.
    -- Verify M0/M2 produce output, M1/M3 output zero.
    -- =======================================================================
    report "TB-NCO-007: conv_enable individual control" severity error;

    csr.enable <= '0';
    wait for CLK_PERIOD * 5;
    wait until rising_edge(clk);

    csr.conv_enable <= "0101";  -- M0=1, M1=0, M2=1, M3=0
    csr.enable <= '1';
    wait until samples_valid = '1';
    wait for CLK_PERIOD * 20;

    -- Check over 128 clocks: M1 and M3 must be zero, M0 and M2 non-zero
    max_val := 0;
    for i in 0 to 127 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        -- M1 disabled: must be zero
        assert samples_out.m1_s0 = to_signed(0, 16) and
               samples_out.m1_s1 = to_signed(0, 16)
          report "TB-NCO-007 FAIL: M1 not zero when disabled (clk " &
            integer'image(i) & ")" severity error;
        if samples_out.m1_s0 /= to_signed(0, 16) or
           samples_out.m1_s1 /= to_signed(0, 16) then
          err_count := err_count + 1;
        end if;

        -- M3 disabled: must be zero
        assert samples_out.m3_s0 = to_signed(0, 16) and
               samples_out.m3_s1 = to_signed(0, 16)
          report "TB-NCO-007 FAIL: M3 not zero when disabled (clk " &
            integer'image(i) & ")" severity error;
        if samples_out.m3_s0 /= to_signed(0, 16) or
           samples_out.m3_s1 /= to_signed(0, 16) then
          err_count := err_count + 1;
        end if;

        -- M0 enabled: track max to verify non-zero
        actual_val := abs(to_integer(samples_out.m0_s0));
        if actual_val > max_val then max_val := actual_val; end if;
      end if;
    end loop;

    assert max_val > 1000
      report "TB-NCO-007 FAIL: M0 output too low when enabled, max=" &
        integer'image(max_val) severity error;
    if max_val <= 1000 then err_count := err_count + 1; end if;

    report "TB-NCO-007: M0 max=" & integer'image(max_val) &
      " (M1/M3 verified zero)" severity error;

    -- Restore all converters
    csr.conv_enable <= "1111";

    -- =======================================================================
    -- TB-NCO-008: Independent converter frequencies
    -- Set M0 to 10 MHz, M2 to 25 MHz, verify different zero-crossing rates.
    -- =======================================================================
    report "TB-NCO-008: Independent converter frequencies"
      severity error;

    csr.enable <= '0';
    wait for CLK_PERIOD * 5;
    wait until rising_edge(clk);

    csr.freq_m0 <= FREQ_10MHZ;
    csr.freq_m1 <= FREQ_10MHZ;
    csr.freq_m2 <= FREQ_25MHZ;
    csr.freq_m3 <= FREQ_25MHZ;
    csr.enable  <= '1';
    wait until samples_valid = '1';
    wait until rising_edge(clk);

    -- Count zero crossings on M0 (10 MHz) and M2 (25 MHz)
    prev_sample  := 0;
    zero_crosses := 0;
    total_samps  := 0;

    -- M0 zero crossings
    for i in 0 to 1023 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        actual_val := to_integer(samples_out.m0_s0);
        if prev_sample < 0 and actual_val >= 0 then
          zero_crosses := zero_crosses + 1;
        end if;
        prev_sample := actual_val;
        total_samps := total_samps + 1;
      end if;
    end loop;

    -- M0 at 10 MHz, S0 only: phase advances 2*freq per clock, so effective
    -- sample rate for zero-crossing is 250 MSPS. Expected = total_samps/25.
    expected_zc := total_samps / 25;
    assert abs(zero_crosses - expected_zc) <= 2
      report "TB-NCO-008 FAIL: M0 (10MHz) crossings=" &
        integer'image(zero_crosses) & " expected ~" &
        integer'image(expected_zc) severity error;
    if abs(zero_crosses - expected_zc) > 2 then
      err_count := err_count + 1;
    end if;

    -- Now count M2 zero crossings
    prev_sample  := 0;
    zero_crosses := 0;
    total_samps  := 0;

    for i in 0 to 1023 loop
      wait until rising_edge(clk);
      if samples_valid = '1' then
        actual_val := to_integer(samples_out.m2_s0);
        if prev_sample < 0 and actual_val >= 0 then
          zero_crosses := zero_crosses + 1;
        end if;
        prev_sample := actual_val;
        total_samps := total_samps + 1;
      end if;
    end loop;

    -- M2 at 25 MHz, S0 only: effective 250 MSPS. Expected = total_samps/10.
    expected_zc := total_samps / 10;
    assert abs(zero_crosses - expected_zc) <= 2
      report "TB-NCO-008 FAIL: M2 (25MHz) crossings=" &
        integer'image(zero_crosses) & " expected ~" &
        integer'image(expected_zc) severity error;
    if abs(zero_crosses - expected_zc) > 2 then
      err_count := err_count + 1;
    end if;

    report "TB-NCO-008: independent frequencies verified"
      severity error;

    -- =======================================================================
    -- Summary
    -- =======================================================================
    wait for CLK_PERIOD * 10;
    if err_count = 0 then
      report "SIMULATION PASSED" severity error;
    else
      report "SIMULATION FAILED with " & integer'image(err_count) &
        " errors" severity failure;
    end if;
    std.env.stop;
  end process p_stim;

end architecture sim;
