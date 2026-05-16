-- =============================================================================
-- Module:      DataSrcMux_tb
-- Description: Self-checking testbench for LMFC-aligned data source MUX
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================
-- Timing note: The DUT has a 1-clock pipeline on shadow_src (shadow_src <= src_sel).
-- This means pending takes 2 clocks to assert after src_sel changes, and the
-- switch result is visible 1 clock after the LMFC boundary where p_switch acts.
-- All checks use "wait_clks(N)" to account for these pipeline delays.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity DataSrcMux_tb is
end entity DataSrcMux_tb;

architecture sim of DataSrcMux_tb is

  constant CLK_PERIOD      : time := 4 ns;  -- 250 MHz
  constant FIFO_DEPTH      : positive := 512;
  constant FILL_THRESHOLD  : positive := 256;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- NCO source
  signal nco_samples : t_sample_bus := C_SAMPLE_BUS_ZERO;
  signal nco_valid   : std_logic := '0';

  -- FIFO source
  signal fifo_samples    : t_sample_bus := C_SAMPLE_BUS_ZERO;
  signal fifo_valid      : std_logic := '0';
  signal fifo_fill_level : unsigned(9 downto 0) := (others => '0');

  -- Control
  signal src_sel        : std_logic := '0';
  signal lmfc_boundary  : std_logic := '0';

  -- Output
  signal samples_out       : t_sample_bus;
  signal samples_valid     : std_logic;
  signal src_switch_pending : std_logic;
  signal src_active        : std_logic;

  signal error_count : integer := 0;

  -- LMFC generator
  signal lmfc_count : unsigned(3 downto 0) := (others => '0');

  -- Helper: set all fields of a sample bus to the same value
  procedure set_sample_bus(
    signal bus_out : out t_sample_bus;
    constant val   : in  signed(C_SAMPLE_BITS - 1 downto 0)
  ) is
  begin
    bus_out.m0_s0 <= val;
    bus_out.m0_s1 <= val;
    bus_out.m1_s0 <= val;
    bus_out.m1_s1 <= val;
    bus_out.m2_s0 <= val;
    bus_out.m2_s1 <= val;
    bus_out.m3_s0 <= val;
    bus_out.m3_s1 <= val;
  end procedure;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- LMFC boundary generator
  p_lmfc : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lmfc_count    <= (others => '0');
        lmfc_boundary <= '0';
      else
        if lmfc_count = to_unsigned(C_LMFC_PERIOD - 1, 4) then
          lmfc_count    <= (others => '0');
          lmfc_boundary <= '1';
        else
          lmfc_count    <= lmfc_count + 1;
          lmfc_boundary <= '0';
        end if;
      end if;
    end if;
  end process p_lmfc;

  u_dut : entity work.DataSrcMux
    generic map (
      G_FIFO_DEPTH     => FIFO_DEPTH,
      G_FILL_THRESHOLD => FILL_THRESHOLD
    )
    port map (
      clk              => clk,
      rst              => rst,
      nco_samples      => nco_samples,
      nco_valid        => nco_valid,
      fifo_samples     => fifo_samples,
      fifo_valid       => fifo_valid,
      fifo_fill_level  => fifo_fill_level,
      src_sel          => src_sel,
      lmfc_boundary    => lmfc_boundary,
      samples_out      => samples_out,
      samples_valid    => samples_valid,
      src_switch_pending => src_switch_pending,
      src_active       => src_active
    );

  -- Single stimulus process: drives rst, all inputs, checks all outputs
  p_stim : process
    variable v_err : integer := 0;
  begin
    -- =========================================================================
    -- Reset phase
    -- =========================================================================
    set_sample_bus(nco_samples,  signed'(x"1111"));
    set_sample_bus(fifo_samples, signed'(x"2222"));
    nco_valid  <= '1';
    fifo_valid <= '0';

    wait for CLK_PERIOD * 5;
    rst <= '0';
    -- Wait 3 clocks for reset release to propagate through all pipeline stages
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Verify defaults after reset
    assert src_active = '0'
      report "Default source not NCO" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    assert samples_out.m0_s0 = signed'(x"1111")
      report "Default output not NCO data" severity error;
    if samples_out.m0_s0 /= signed'(x"1111") then v_err := v_err + 1; end if;

    assert samples_valid = '1'
      report "Default valid not following NCO valid" severity error;
    if samples_valid /= '1' then v_err := v_err + 1; end if;

    -- =========================================================================
    -- TB-MUX-001: Switch NCO -> FIFO on LMFC boundary
    -- =========================================================================
    report "TB-MUX-001: LMFC-aligned switch NCO->FIFO->NCO" severity error;

    -- Pre-fill FIFO above threshold
    fifo_fill_level <= to_unsigned(300, 10);
    fifo_valid <= '1';

    -- Request switch to FIFO
    src_sel <= '1';

    -- Wait for LMFC boundary to execute the switch.
    -- Pipeline: src_sel → shadow_src (1 clk) → pending (1 clk) → LMFC switch
    -- After LMFC: p_switch acts on next rising_edge, result visible 1 clk later.
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);  -- p_switch sees lmfc_boundary='1', schedules switch
    wait until rising_edge(clk);  -- switch result now visible

    assert src_active = '1'
      report "TB-MUX-001 FAIL: didn't switch to FIFO on LMFC" severity error;
    if src_active /= '1' then v_err := v_err + 1; end if;

    assert src_switch_pending = '0'
      report "TB-MUX-001 FAIL: pending not cleared" severity error;
    if src_switch_pending /= '0' then v_err := v_err + 1; end if;

    -- Verify output is FIFO data
    assert samples_out.m0_s0 = signed'(x"2222")
      report "TB-MUX-001 FAIL: output not FIFO data" severity error;
    if samples_out.m0_s0 /= signed'(x"2222") then v_err := v_err + 1; end if;

    -- Verify samples_valid follows FIFO valid
    assert samples_valid = '1'
      report "TB-MUX-001 FAIL: valid not following FIFO valid" severity error;
    if samples_valid /= '1' then v_err := v_err + 1; end if;

    -- Switch back to NCO
    src_sel <= '0';
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);  -- p_switch acts
    wait until rising_edge(clk);  -- result visible

    assert src_active = '0'
      report "TB-MUX-001 FAIL: didn't switch back to NCO" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    -- Verify output returns to NCO data
    assert samples_out.m0_s0 = signed'(x"1111")
      report "TB-MUX-001 FAIL: output not NCO data after switch-back"
      severity error;
    if samples_out.m0_s0 /= signed'(x"1111") then v_err := v_err + 1; end if;

    -- Verify valid follows NCO valid
    assert samples_valid = '1'
      report "TB-MUX-001 FAIL: valid not following NCO valid after switch-back"
      severity error;
    if samples_valid /= '1' then v_err := v_err + 1; end if;

    wait for CLK_PERIOD * 5;

    -- =========================================================================
    -- TB-MUX-002: Switch to FIFO delayed by insufficient fill, hold across
    --             multiple LMFC boundaries
    -- =========================================================================
    report "TB-MUX-002: Delayed switch (insufficient fill)" severity error;

    fifo_fill_level <= to_unsigned(100, 10);  -- below threshold
    src_sel <= '1';

    -- Wait for 3 LMFC boundaries — should NOT switch on any of them
    for i in 1 to 3 loop
      wait until lmfc_boundary = '1';
      wait until rising_edge(clk);  -- p_switch acts (but threshold not met)
      wait until rising_edge(clk);  -- result visible

      assert src_active = '0'
        report "TB-MUX-002 FAIL: switched despite low fill (LMFC " &
          integer'image(i) & ")" severity error;
      if src_active /= '0' then v_err := v_err + 1; end if;

      assert src_switch_pending = '1'
        report "TB-MUX-002 FAIL: pending not asserted (LMFC " &
          integer'image(i) & ")" severity error;
      if src_switch_pending /= '1' then v_err := v_err + 1; end if;
    end loop;

    -- Now fill FIFO above threshold
    fifo_fill_level <= to_unsigned(300, 10);

    -- Wait for next LMFC — should now switch
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);  -- p_switch acts
    wait until rising_edge(clk);  -- result visible

    assert src_active = '1'
      report "TB-MUX-002 FAIL: didn't switch after fill" severity error;
    if src_active /= '1' then v_err := v_err + 1; end if;

    assert src_switch_pending = '0'
      report "TB-MUX-002 FAIL: pending not cleared after switch"
      severity error;
    if src_switch_pending /= '0' then v_err := v_err + 1; end if;

    -- Clean up: switch back to NCO
    src_sel <= '0';
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    wait for CLK_PERIOD * 5;

    -- =========================================================================
    -- TB-MUX-003: Glitch rejection — toggle src_sel between LMFC boundaries
    -- =========================================================================
    report "TB-MUX-003: Glitch rejection (mid-frame toggle)" severity error;

    -- Verify precondition: NCO active
    assert src_active = '0'
      report "TB-MUX-003 FAIL: precondition - not on NCO" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    fifo_fill_level <= to_unsigned(300, 10);

    -- Wait until just after an LMFC boundary so we have a full period to toggle
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Toggle src_sel rapidly: FIFO -> NCO -> FIFO -> NCO mid-frame
    src_sel <= '1';
    wait for CLK_PERIOD * 2;
    src_sel <= '0';
    wait for CLK_PERIOD * 2;
    src_sel <= '1';
    wait for CLK_PERIOD * 2;
    src_sel <= '0';
    -- Let shadow pipeline settle (3 clocks: src_sel → shadow → pending logic)
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Output must remain NCO throughout — no switch without LMFC
    assert src_active = '0'
      report "TB-MUX-003 FAIL: switched without LMFC boundary" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    assert samples_out.m0_s0 = signed'(x"1111")
      report "TB-MUX-003 FAIL: output changed without LMFC" severity error;
    if samples_out.m0_s0 /= signed'(x"1111") then v_err := v_err + 1; end if;

    -- Final state: src_sel='0' = NCO, so pending should be clear
    assert src_switch_pending = '0'
      report "TB-MUX-003 FAIL: pending still set after revert" severity error;
    if src_switch_pending /= '0' then v_err := v_err + 1; end if;

    -- Confirm no switch on next LMFC either
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert src_active = '0'
      report "TB-MUX-003 FAIL: unexpected switch after glitch" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    wait for CLK_PERIOD * 5;

    -- =========================================================================
    -- TB-MUX-004: Reset during active FIFO streaming
    -- =========================================================================
    report "TB-MUX-004: Reset reverts to NCO" severity error;

    -- First switch to FIFO
    fifo_fill_level <= to_unsigned(300, 10);
    fifo_valid <= '1';
    src_sel <= '1';
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert src_active = '1'
      report "TB-MUX-004 FAIL: precondition - not on FIFO" severity error;
    if src_active /= '1' then v_err := v_err + 1; end if;

    -- Assert reset
    rst <= '1';
    wait for CLK_PERIOD * 5;
    wait until rising_edge(clk);

    -- Verify reset state
    assert src_active = '0'
      report "TB-MUX-004 FAIL: not reverted to NCO on reset" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    assert src_switch_pending = '0'
      report "TB-MUX-004 FAIL: pending not cleared on reset" severity error;
    if src_switch_pending /= '0' then v_err := v_err + 1; end if;

    -- Release reset and verify NCO data flows
    src_sel <= '0';
    rst <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert samples_out.m0_s0 = signed'(x"1111")
      report "TB-MUX-004 FAIL: output not NCO after reset release"
      severity error;
    if samples_out.m0_s0 /= signed'(x"1111") then v_err := v_err + 1; end if;

    wait for CLK_PERIOD * 5;

    -- =========================================================================
    -- TB-MUX-005: src_sel revert cancels pending switch
    -- =========================================================================
    report "TB-MUX-005: Shadow revert cancels pending" severity error;

    fifo_fill_level <= to_unsigned(300, 10);
    src_sel <= '1';

    -- Wait for pending to assert: src_sel → shadow (1 clk) → pending (1 clk) → visible (1 clk)
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert src_switch_pending = '1'
      report "TB-MUX-005 FAIL: pending not asserted" severity error;
    if src_switch_pending /= '1' then v_err := v_err + 1; end if;

    -- Revert src_sel back to NCO before LMFC
    src_sel <= '0';
    -- Wait for revert to propagate: same pipeline delay
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert src_switch_pending = '0'
      report "TB-MUX-005 FAIL: pending not cancelled on revert"
      severity error;
    if src_switch_pending /= '0' then v_err := v_err + 1; end if;

    assert src_active = '0'
      report "TB-MUX-005 FAIL: source changed despite revert" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    -- Confirm no switch on next LMFC
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert src_active = '0'
      report "TB-MUX-005 FAIL: switched on LMFC after revert" severity error;
    if src_active /= '0' then v_err := v_err + 1; end if;

    wait for CLK_PERIOD * 5;

    -- =========================================================================
    -- TB-MUX-006: Continuous streaming with changing data
    -- =========================================================================
    report "TB-MUX-006: Changing data through switch" severity error;

    -- Drive incrementing NCO pattern
    nco_valid  <= '1';
    fifo_valid <= '1';
    fifo_fill_level <= to_unsigned(300, 10);

    -- Start on NCO with pattern A
    set_sample_bus(nco_samples,  signed'(x"A000"));
    set_sample_bus(fifo_samples, signed'(x"B000"));
    src_sel <= '0';
    -- Let state settle
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Verify NCO data before switch
    assert samples_out.m0_s0 = signed'(x"A000")
      report "TB-MUX-006 FAIL: wrong NCO data before switch" severity error;
    if samples_out.m0_s0 /= signed'(x"A000") then v_err := v_err + 1; end if;

    -- Request switch to FIFO
    src_sel <= '1';

    -- Keep updating both sources each clock until switch happens
    for i in 1 to 64 loop
      wait until rising_edge(clk);
      set_sample_bus(nco_samples,
        signed(to_unsigned(16#A000# + i, C_SAMPLE_BITS)));
      set_sample_bus(fifo_samples,
        signed(to_unsigned(16#B000# + i, C_SAMPLE_BITS)));

      -- Check output source: top nibble identifies NCO (0xA) vs FIFO (0xB)
      -- Note: output MUX is combinational on active_src, which is registered,
      -- so samples_out reflects the current active source's data.
      if src_active = '0' then
        assert samples_out.m0_s0(15 downto 12) = x"A"
          report "TB-MUX-006 FAIL: FIFO data leaking before switch at clk " &
            integer'image(i) severity error;
        if samples_out.m0_s0(15 downto 12) /= x"A" then
          v_err := v_err + 1;
        end if;
      else
        assert samples_out.m0_s0(15 downto 12) = x"B"
          report "TB-MUX-006 FAIL: NCO data leaking after switch at clk " &
            integer'image(i) severity error;
        if samples_out.m0_s0(15 downto 12) /= x"B" then
          v_err := v_err + 1;
        end if;
      end if;
    end loop;

    -- Verify we actually switched during the loop
    assert src_active = '1'
      report "TB-MUX-006 FAIL: never switched to FIFO" severity error;
    if src_active /= '1' then v_err := v_err + 1; end if;

    -- Clean up: switch back to NCO
    src_sel <= '0';
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Restore static patterns for remaining tests
    set_sample_bus(nco_samples,  signed'(x"1111"));
    set_sample_bus(fifo_samples, signed'(x"2222"));
    wait until rising_edge(clk);

    -- =========================================================================
    -- TB-MUX-007: samples_valid follows active source valid
    -- =========================================================================
    report "TB-MUX-007: samples_valid tracks active source" severity error;

    -- Ensure NCO active
    src_sel <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Toggle nco_valid off, verify samples_valid follows
    -- Output MUX is combinational, so valid change is immediate (no pipeline)
    nco_valid <= '0';
    wait until rising_edge(clk);
    assert samples_valid = '0'
      report "TB-MUX-007 FAIL: valid not '0' when NCO valid deasserted"
      severity error;
    if samples_valid /= '0' then v_err := v_err + 1; end if;

    nco_valid <= '1';
    wait until rising_edge(clk);
    assert samples_valid = '1'
      report "TB-MUX-007 FAIL: valid not '1' when NCO valid reasserted"
      severity error;
    if samples_valid /= '1' then v_err := v_err + 1; end if;

    -- Switch to FIFO and test fifo_valid propagation
    fifo_fill_level <= to_unsigned(300, 10);
    fifo_valid <= '1';
    src_sel <= '1';
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Verify on FIFO now
    assert src_active = '1'
      report "TB-MUX-007 FAIL: precondition - not on FIFO" severity error;
    if src_active /= '1' then v_err := v_err + 1; end if;

    fifo_valid <= '0';
    wait until rising_edge(clk);
    assert samples_valid = '0'
      report "TB-MUX-007 FAIL: valid not '0' when FIFO valid deasserted"
      severity error;
    if samples_valid /= '0' then v_err := v_err + 1; end if;

    fifo_valid <= '1';
    wait until rising_edge(clk);
    assert samples_valid = '1'
      report "TB-MUX-007 FAIL: valid not '1' when FIFO valid reasserted"
      severity error;
    if samples_valid /= '1' then v_err := v_err + 1; end if;

    -- =========================================================================
    -- Summary
    -- =========================================================================
    wait for CLK_PERIOD * 10;
    if v_err = 0 then
      report "SIMULATION PASSED" severity error;
    else
      report "SIMULATION FAILED with " & integer'image(v_err) &
        " errors" severity failure;
    end if;
    std.env.stop;
  end process p_stim;

end architecture sim;
