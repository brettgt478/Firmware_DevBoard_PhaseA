-- =============================================================================
-- Module:      JesdSyncController_tb
-- Description: Self-checking testbench for JESD multi-link sync controller
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity JesdSyncController_tb is
end entity JesdSyncController_tb;

architecture sim of JesdSyncController_tb is

  constant CLK_PERIOD : time := 4 ns;  -- 250 MHz

  signal clk            : std_logic := '0';
  signal rst            : std_logic := '1';
  signal txlink_ready   : std_logic_vector(3 downto 0) := "0000";
  signal sync_mode      : std_logic := '0';
  signal err_clr        : std_logic_vector(3 downto 0) := "0000";
  signal data_release   : std_logic_vector(3 downto 0);
  signal group_synced   : std_logic_vector(1 downto 0);
  signal lmfc_aligned   : std_logic;
  signal sync_err       : std_logic_vector(3 downto 0);
  signal lmfc_boundary  : std_logic;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_dut : entity work.JesdSyncController
    port map (
      clk           => clk,
      rst           => rst,
      txlink_ready  => txlink_ready,
      sync_mode     => sync_mode,
      err_clr       => err_clr,
      data_release  => data_release,
      group_synced  => group_synced,
      lmfc_aligned  => lmfc_aligned,
      sync_err      => sync_err,
      lmfc_boundary => lmfc_boundary
    );

  -- Single stimulus process drives all inputs (avoids multi-driver issues)
  p_stim : process
    variable v_err : integer := 0;
  begin
    -- Initial reset
    rst <= '1';
    wait for CLK_PERIOD * 5;
    rst <= '0';
    wait until rising_edge(clk);

    -- =======================================================================
    -- TB-SYNC-001: Staggered link lock (per-DAC mode)
    -- =======================================================================
    report "TB-SYNC-001: Staggered link lock" severity error;
    sync_mode <= '0';  -- per-DAC mode

    -- Group 0: link 0 locks first
    txlink_ready <= "0001";  -- link 0 only
    for i in 1 to 12 loop
      wait until rising_edge(clk);
    end loop;

    -- data_release should still be 0 (both links not ready)
    assert data_release(0) = '0'
      report "TB-SYNC-001 FAIL: premature release with only link 0"
      severity error;
    if data_release(0) /= '0' then v_err := v_err + 1; end if;

    -- Link 1 locks 50 clocks later
    for i in 1 to 50 loop
      wait until rising_edge(clk);
    end loop;
    txlink_ready <= "0011";  -- links 0 and 1

    -- Wait for next LMFC boundary + FSM transition + output settle
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- data_release for group 0 should now be asserted
    assert data_release(0) = '1'
      report "TB-SYNC-001 FAIL: group 0 not released after LMFC"
      severity error;
    if data_release(0) /= '1' then v_err := v_err + 1; end if;
    assert data_release(1) = '1'
      report "TB-SYNC-001 FAIL: link 1 not released" severity error;
    if data_release(1) /= '1' then v_err := v_err + 1; end if;

    -- Group 1 should still be waiting (links 2,3 not ready)
    assert data_release(2) = '0'
      report "TB-SYNC-001 FAIL: group 1 prematurely released"
      severity error;
    if data_release(2) /= '0' then v_err := v_err + 1; end if;

    assert group_synced(0) = '1'
      report "TB-SYNC-001 FAIL: group_synced(0) not set" severity error;
    if group_synced(0) /= '1' then v_err := v_err + 1; end if;

    -- Now bring up group 1
    txlink_ready <= "1111";
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release(2) = '1'
      report "TB-SYNC-001 FAIL: group 1 not released" severity error;
    if data_release(2) /= '1' then v_err := v_err + 1; end if;
    assert lmfc_aligned = '1'
      report "TB-SYNC-001 FAIL: lmfc_aligned not set" severity error;
    if lmfc_aligned /= '1' then v_err := v_err + 1; end if;

    for i in 1 to 20 loop
      wait until rising_edge(clk);
    end loop;

    -- =======================================================================
    -- TB-SYNC-002: Link drop after sync (with group isolation & sticky error)
    -- =======================================================================
    report "TB-SYNC-002: Link drop after sync" severity error;

    -- All 4 links synced and running from TB-SYNC-001
    -- Drop link 1 while running
    txlink_ready <= "1101";  -- link 1 drops
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Group 0 should lose sync, error flag should be set
    assert data_release(0) = '0'
      report "TB-SYNC-002 FAIL: group 0 still releasing after link drop"
      severity error;
    if data_release(0) /= '0' then v_err := v_err + 1; end if;

    assert sync_err(1) = '1'
      report "TB-SYNC-002 FAIL: sync_err(1) not set" severity error;
    if sync_err(1) /= '1' then v_err := v_err + 1; end if;

    -- Verify group 1 is UNAFFECTED by group 0 link drop
    assert data_release(2) = '1'
      report "TB-SYNC-002 FAIL: group 1 disrupted by group 0 fault"
      severity error;
    if data_release(2) /= '1' then v_err := v_err + 1; end if;
    assert data_release(3) = '1'
      report "TB-SYNC-002 FAIL: link 3 disrupted by group 0 fault"
      severity error;
    if data_release(3) /= '1' then v_err := v_err + 1; end if;
    assert group_synced(1) = '1'
      report "TB-SYNC-002 FAIL: group_synced(1) dropped during group 0 fault"
      severity error;
    if group_synced(1) /= '1' then v_err := v_err + 1; end if;

    -- Verify sticky error flag persists across multiple clocks
    for i in 1 to 10 loop
      wait until rising_edge(clk);
    end loop;
    assert sync_err(1) = '1'
      report "TB-SYNC-002 FAIL: sync_err(1) not sticky (cleared prematurely)"
      severity error;
    if sync_err(1) /= '1' then v_err := v_err + 1; end if;

    -- Clear error
    err_clr <= "0010";
    wait until rising_edge(clk);
    err_clr <= "0000";
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert sync_err(1) = '0'
      report "TB-SYNC-002 FAIL: sync_err(1) not cleared" severity error;
    if sync_err(1) /= '0' then v_err := v_err + 1; end if;

    -- Restore link 1 and re-sync (guard: wait a few clocks for FSM to
    -- reach WAIT_LMFC before looking for an LMFC boundary)
    txlink_ready <= "1111";
    for i in 1 to 3 loop
      wait until rising_edge(clk);
    end loop;
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release(0) = '1'
      report "TB-SYNC-002 FAIL: group 0 didn't re-sync" severity error;
    if data_release(0) /= '1' then v_err := v_err + 1; end if;

    -- Reset for next test
    rst <= '1';
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    wait until rising_edge(clk);
    txlink_ready <= "0000";
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;

    -- =======================================================================
    -- TB-SYNC-003: All-four-link sync mode
    -- =======================================================================
    report "TB-SYNC-003: All-four-link mode" severity error;
    sync_mode <= '1';  -- all-four mode

    -- Staggered lock: each link at different times
    txlink_ready <= "0001";
    for i in 1 to 20 loop
      wait until rising_edge(clk);
    end loop;
    assert data_release = "0000"
      report "TB-SYNC-003 FAIL: released with only 1 link" severity error;
    if data_release /= "0000" then v_err := v_err + 1; end if;

    txlink_ready <= "0011";
    for i in 1 to 20 loop
      wait until rising_edge(clk);
    end loop;
    assert data_release = "0000"
      report "TB-SYNC-003 FAIL: released with only 2 links" severity error;
    if data_release /= "0000" then v_err := v_err + 1; end if;

    txlink_ready <= "0111";
    for i in 1 to 20 loop
      wait until rising_edge(clk);
    end loop;
    assert data_release = "0000"
      report "TB-SYNC-003 FAIL: released with only 3 links" severity error;
    if data_release /= "0000" then v_err := v_err + 1; end if;

    -- 4th link locks
    txlink_ready <= "1111";
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release = "1111"
      report "TB-SYNC-003 FAIL: not all released after 4th lock + LMFC"
      severity error;
    if data_release /= "1111" then v_err := v_err + 1; end if;

    -- Reset for next test
    rst <= '1';
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    wait until rising_edge(clk);
    txlink_ready <= "0000";
    sync_mode <= '0';
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;

    -- =======================================================================
    -- TB-SYNC-004: LMFC boundary release timing
    -- Verify release only occurs on LMFC boundary and document timing.
    -- See doc/potential_issues.md for analysis of LMFC coincidence.
    -- =======================================================================
    report "TB-SYNC-004: LMFC boundary release timing" severity error;
    sync_mode <= '0';

    -- Synchronize to a known LMFC boundary, then wait one clock past it
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    -- Set links ready just after the LMFC boundary has passed.
    -- The FSM should transition WAIT_LOCK -> WAIT_LMFC, then wait
    -- for the next LMFC boundary (~14 clocks away).
    txlink_ready <= "0011";

    -- Verify data_release stays low until the next LMFC boundary
    for i in 1 to 12 loop
      wait until rising_edge(clk);
      assert data_release(0) = '0'
        report "TB-SYNC-004 FAIL: premature release at clock " &
          integer'image(i) & " after lock"
        severity error;
      if data_release(0) /= '0' then v_err := v_err + 1; end if;
    end loop;

    -- Wait for next LMFC boundary — release should happen
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release(0) = '1'
      report "TB-SYNC-004 FAIL: not released at LMFC boundary"
      severity error;
    if data_release(0) /= '1' then v_err := v_err + 1; end if;

    -- Reset for next test
    rst <= '1';
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    wait until rising_edge(clk);
    txlink_ready <= "0000";
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;

    -- =======================================================================
    -- TB-SYNC-005: Transient 1-clock link glitch recovery
    -- Verify FSM recovers after a single-clock link drop (tests the
    -- ST_ERROR unconditional-to-WAIT_LOCK fix).
    -- =======================================================================
    report "TB-SYNC-005: Transient 1-clock link glitch" severity error;
    sync_mode <= '0';

    -- Bring up all links and get to RUNNING
    txlink_ready <= "1111";
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    -- Allow 1 extra LMFC for both groups to sync
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release = "1111"
      report "TB-SYNC-005 FAIL: setup - not all releasing" severity error;
    if data_release /= "1111" then v_err := v_err + 1; end if;

    -- Drop link 0 for exactly 1 clock
    txlink_ready <= "1110";
    wait until rising_edge(clk);
    txlink_ready <= "1111";  -- restore immediately

    -- Error flag should be set for link 0
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    assert sync_err(0) = '1'
      report "TB-SYNC-005 FAIL: sync_err(0) not set after glitch"
      severity error;
    if sync_err(0) /= '1' then v_err := v_err + 1; end if;

    -- data_release should have dropped for group 0
    -- (FSM went RUNNING -> ERROR -> WAIT_LOCK -> WAIT_LMFC)
    -- It should recover on the next LMFC boundary
    for i in 1 to 3 loop
      wait until rising_edge(clk);
    end loop;
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release(0) = '1'
      report "TB-SYNC-005 FAIL: group 0 didn't recover after glitch"
      severity error;
    if data_release(0) /= '1' then v_err := v_err + 1; end if;

    -- Clear the error flag
    err_clr <= "0001";
    wait until rising_edge(clk);
    err_clr <= "0000";
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert sync_err(0) = '0'
      report "TB-SYNC-005 FAIL: sync_err(0) not cleared" severity error;
    if sync_err(0) /= '0' then v_err := v_err + 1; end if;

    -- Reset for next test
    rst <= '1';
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    wait until rising_edge(clk);
    txlink_ready <= "0000";
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;

    -- =======================================================================
    -- TB-SYNC-006: sync_mode change while running
    -- Switching from per-DAC to all-four mode with only 2 links ready
    -- should cause FSM disruption; verify graceful recovery.
    -- =======================================================================
    report "TB-SYNC-006: sync_mode change while running" severity error;
    sync_mode <= '0';  -- per-DAC mode

    -- Bring up only group 0 (links 0+1)
    txlink_ready <= "0011";
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release(0) = '1'
      report "TB-SYNC-006 FAIL: setup - group 0 not releasing" severity error;
    if data_release(0) /= '1' then v_err := v_err + 1; end if;
    assert data_release(2) = '0'
      report "TB-SYNC-006 FAIL: setup - group 1 releasing without links"
      severity error;
    if data_release(2) /= '0' then v_err := v_err + 1; end if;

    -- Switch to all-four mode. grp0_all_ready now requires all 4 links,
    -- so it becomes '0'. Group 0 FSM should go RUNNING -> ERROR -> WAIT_LOCK.
    sync_mode <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release(0) = '0'
      report "TB-SYNC-006 FAIL: group 0 still releasing after mode switch"
      severity error;
    if data_release(0) /= '0' then v_err := v_err + 1; end if;

    -- Bring up all 4 links to recover
    txlink_ready <= "1111";
    for i in 1 to 3 loop
      wait until rising_edge(clk);
    end loop;
    wait until lmfc_boundary = '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);

    assert data_release = "1111"
      report "TB-SYNC-006 FAIL: not all released after recovery"
      severity error;
    if data_release /= "1111" then v_err := v_err + 1; end if;

    -- =======================================================================
    -- Summary
    -- =======================================================================
    for i in 1 to 10 loop
      wait until rising_edge(clk);
    end loop;
    if v_err = 0 then
      report "SIMULATION PASSED" severity error;
    else
      report "SIMULATION FAILED with " & integer'image(v_err) &
        " errors" severity failure;
    end if;
    std.env.stop;
  end process p_stim;

end architecture sim;
