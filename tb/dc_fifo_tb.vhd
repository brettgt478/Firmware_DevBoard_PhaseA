-- =============================================================================
-- Module:      DcFifo_tb
-- Description: Self-checking testbench for dual-clock async FIFO
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity DcFifo_tb is
end entity DcFifo_tb;

architecture sim of DcFifo_tb is

  constant WR_CLK_PERIOD : time := 5 ns;   -- 200 MHz (PCIe domain)
  constant RD_CLK_PERIOD : time := 4 ns;   -- 250 MHz (JESD domain)
  constant DATA_WIDTH    : positive := 32;  -- narrower for easier testing
  constant FIFO_DEPTH    : positive := 16;  -- small for quick test
  constant ADDR_W        : positive := clog2(FIFO_DEPTH);

  -- CDC propagation allowance (2 sync stages + margin)
  constant CDC_SETTLE    : time := WR_CLK_PERIOD * 6;

  signal wr_clk     : std_logic := '0';
  signal rd_clk     : std_logic := '0';
  signal wr_rst     : std_logic := '1';
  signal rd_rst     : std_logic := '1';

  signal wr_data    : std_logic_vector(DATA_WIDTH - 1 downto 0) :=
    (others => '0');
  signal wr_valid   : std_logic := '0';
  signal wr_full    : std_logic;
  signal wr_overflow : std_logic;

  signal rd_data    : std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal rd_valid   : std_logic;
  signal rd_en      : std_logic := '0';
  signal rd_empty   : std_logic;

  signal fill_level : unsigned(ADDR_W downto 0);

  -- Handshake: write process drives wr_phase, read process drives rd_phase.
  -- Each process waits on the other's phase signal to synchronize.
  signal wr_phase : integer := 0;
  signal rd_phase : integer := 0;

  -- Write-side check results (driven only by write process, read by
  -- read process for final tally)
  signal wr_error_count : integer := 0;

begin

  wr_clk <= not wr_clk after WR_CLK_PERIOD / 2;
  rd_clk <= not rd_clk after RD_CLK_PERIOD / 2;

  u_dut : entity work.DcFifo
    generic map (
      G_DATA_WIDTH => DATA_WIDTH,
      G_DEPTH      => FIFO_DEPTH
    )
    port map (
      wr_clk     => wr_clk,
      wr_rst     => wr_rst,
      wr_data    => wr_data,
      wr_valid   => wr_valid,
      wr_full    => wr_full,
      wr_overflow => wr_overflow,
      rd_clk     => rd_clk,
      rd_rst     => rd_rst,
      rd_data    => rd_data,
      rd_valid   => rd_valid,
      rd_en      => rd_en,
      rd_empty   => rd_empty,
      fill_level => fill_level
    );

  -- =========================================================================
  -- Write-side stimulus
  -- Drives: wr_rst, rd_rst, wr_data, wr_valid, wr_phase, wr_error_count
  -- =========================================================================
  p_write_stim : process
    variable overflow_seen : boolean;
    variable v_wr_errors   : integer := 0;
  begin
    -- Hold reset for 5 write clocks
    wr_rst <= '1';
    rd_rst <= '1';
    wait for WR_CLK_PERIOD * 5;
    wr_rst <= '0';
    rd_rst <= '0';
    wait until rising_edge(wr_clk);

    -- =======================================================================
    -- TB-FIFO-001: Write 8 words
    -- =======================================================================
    report "TB-FIFO-001: Write 8 words, verify data integrity"
      severity error;
    wr_phase <= 1;

    for i in 0 to 7 loop
      wr_data  <= std_logic_vector(to_unsigned(16#A000# + i, DATA_WIDTH));
      wr_valid <= '1';
      wait until rising_edge(wr_clk);
    end loop;
    wr_valid <= '0';

    -- Signal that writes are complete
    wr_phase <= 2;

    -- Wait for read side to finish TB-FIFO-001 and TB-FIFO-003
    wait until rd_phase = 3;

    -- =======================================================================
    -- TB-FIFO-002: Fill to capacity
    -- =======================================================================
    report "TB-FIFO-002: Fill to capacity, verify full flag and fill_level"
      severity error;
    wr_phase <= 4;

    for i in 0 to FIFO_DEPTH - 1 loop
      wr_data  <= std_logic_vector(to_unsigned(16#B000# + i, DATA_WIDTH));
      wr_valid <= '1';
      wait until rising_edge(wr_clk);
    end loop;
    wr_valid <= '0';

    -- Wait for full flag to settle
    wait until rising_edge(wr_clk);
    wait until rising_edge(wr_clk);

    assert wr_full = '1'
      report "TB-FIFO-002 FAIL: not full after writing FIFO_DEPTH words"
      severity error;
    if wr_full /= '1' then v_wr_errors := v_wr_errors + 1; end if;

    -- Signal writes done, wait for drain
    wr_phase <= 5;
    wait until rd_phase = 5;

    -- =======================================================================
    -- TB-FIFO-004: CDC stress -- sustained write at 200 MHz
    -- =======================================================================
    report "TB-FIFO-004: CDC stress -- sustained write 200 MHz, read 250 MHz"
      severity error;
    wr_phase <= 6;

    -- Write 64 words with backpressure handling
    for i in 0 to 63 loop
      while wr_full = '1' loop
        wr_valid <= '0';
        wait until rising_edge(wr_clk);
      end loop;
      wr_data  <= std_logic_vector(to_unsigned(16#C000# + i, DATA_WIDTH));
      wr_valid <= '1';
      wait until rising_edge(wr_clk);
    end loop;
    wr_valid <= '0';

    -- Signal writes done
    wr_phase <= 7;
    wait until rd_phase = 7;

    -- =======================================================================
    -- TB-FIFO-005: Overflow rejection
    -- =======================================================================
    report "TB-FIFO-005: Overflow rejection -- write to full FIFO"
      severity error;
    wr_phase <= 8;

    -- Fill the FIFO completely
    for i in 0 to FIFO_DEPTH - 1 loop
      wr_data  <= std_logic_vector(to_unsigned(16#D000# + i, DATA_WIDTH));
      wr_valid <= '1';
      wait until rising_edge(wr_clk);
    end loop;
    wr_valid <= '0';

    -- Wait for full flag
    wait until rising_edge(wr_clk);
    wait until rising_edge(wr_clk);

    assert wr_full = '1'
      report "TB-FIFO-005 FAIL: FIFO not full before overflow test"
      severity error;
    if wr_full /= '1' then v_wr_errors := v_wr_errors + 1; end if;

    -- Attempt 4 writes while full
    overflow_seen := false;
    for i in 0 to 3 loop
      wr_data  <= std_logic_vector(
        to_unsigned(16#DEAD0# + i, DATA_WIDTH));
      wr_valid <= '1';
      wait until rising_edge(wr_clk);
      if wr_overflow = '1' then
        overflow_seen := true;
      end if;
    end loop;
    wr_valid <= '0';
    wait until rising_edge(wr_clk);

    assert overflow_seen
      report "TB-FIFO-005 FAIL: overflow flag never asserted"
      severity error;
    if not overflow_seen then v_wr_errors := v_wr_errors + 1; end if;

    -- Publish error count and signal ready for drain
    wr_error_count <= v_wr_errors;
    wait for CDC_SETTLE;
    wr_phase <= 9;

    wait;
  end process p_write_stim;

  -- =========================================================================
  -- Read-side stimulus and checking
  -- Drives: rd_en, rd_phase
  -- =========================================================================
  p_read_stim : process
    variable expected    : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable read_count  : integer;
    variable error_count : integer := 0;
  begin
    -- Wait for reset release
    wait until wr_rst = '0';
    wait until rising_edge(rd_clk);

    -- =======================================================================
    -- TB-FIFO-001: Read 8 words and verify data integrity + fill_level
    -- =======================================================================
    wait until wr_phase = 2;

    -- Wait for CDC propagation so empty flag clears
    wait for CDC_SETTLE;
    wait until rising_edge(rd_clk);

    -- Verify fill_level (may lag by up to 2 due to synchronizer)
    assert fill_level >= 6 and fill_level <= 8
      report "TB-FIFO-001 FAIL: fill_level=" &
        integer'image(to_integer(fill_level)) &
        " expected 6..8 after writing 8 words" severity error;
    if fill_level < 6 or fill_level > 8 then
      error_count := error_count + 1;
    end if;

    -- Read and verify all 8 words
    read_count := 0;
    while read_count < 8 loop
      rd_en <= '1';
      wait until rising_edge(rd_clk);
      if rd_valid = '1' then
        expected :=
          std_logic_vector(to_unsigned(16#A000# + read_count, DATA_WIDTH));
        assert rd_data = expected
          report "TB-FIFO-001 FAIL: word " & integer'image(read_count) &
            " data=0x" & to_hstring(unsigned(rd_data)) &
            " expected=0x" & to_hstring(unsigned(expected))
          severity error;
        if rd_data /= expected then error_count := error_count + 1; end if;
        read_count := read_count + 1;
      end if;
    end loop;
    rd_en <= '0';

    -- Verify empty after draining
    wait for CDC_SETTLE;
    wait until rising_edge(rd_clk);
    assert rd_empty = '1'
      report "TB-FIFO-001 FAIL: not empty after reading all words"
      severity error;
    if rd_empty /= '1' then error_count := error_count + 1; end if;

    -- Verify fill_level is 0
    assert fill_level = 0
      report "TB-FIFO-001 FAIL: fill_level=" &
        integer'image(to_integer(fill_level)) &
        " expected 0 after draining" severity error;
    if fill_level /= 0 then error_count := error_count + 1; end if;

    -- =======================================================================
    -- TB-FIFO-003: Read when empty
    -- =======================================================================
    report "TB-FIFO-003: Read when empty" severity error;

    wait until rising_edge(rd_clk);

    assert rd_empty = '1'
      report "TB-FIFO-003 FAIL: not empty before empty-read test"
      severity error;
    if rd_empty /= '1' then error_count := error_count + 1; end if;

    -- Attempt reads on an empty FIFO
    for i in 0 to 3 loop
      rd_en <= '1';
      wait until rising_edge(rd_clk);
      assert rd_valid = '0'
        report "TB-FIFO-003 FAIL: valid asserted on empty read (cycle " &
          integer'image(i) & ")" severity error;
      if rd_valid /= '0' then error_count := error_count + 1; end if;
    end loop;
    rd_en <= '0';

    -- Signal write side: ready for TB-FIFO-002
    rd_phase <= 3;

    -- =======================================================================
    -- TB-FIFO-002: Drain full FIFO, verify data integrity and fill_level
    -- =======================================================================
    wait until wr_phase = 5;
    wait for CDC_SETTLE;
    wait until rising_edge(rd_clk);

    -- Verify fill_level near capacity (may lag by up to 2)
    assert fill_level >= FIFO_DEPTH - 2
      report "TB-FIFO-002 FAIL: fill_level=" &
        integer'image(to_integer(fill_level)) &
        " expected >=" & integer'image(FIFO_DEPTH - 2) &
        " when full" severity error;
    if fill_level < FIFO_DEPTH - 2 then
      error_count := error_count + 1;
    end if;

    -- Drain and verify data integrity
    read_count := 0;
    while read_count < FIFO_DEPTH loop
      rd_en <= '1';
      wait until rising_edge(rd_clk);
      if rd_valid = '1' then
        expected :=
          std_logic_vector(to_unsigned(16#B000# + read_count, DATA_WIDTH));
        assert rd_data = expected
          report "TB-FIFO-002 FAIL: word " & integer'image(read_count) &
            " data=0x" & to_hstring(unsigned(rd_data)) &
            " expected=0x" & to_hstring(unsigned(expected))
          severity error;
        if rd_data /= expected then error_count := error_count + 1; end if;
        read_count := read_count + 1;
      end if;
    end loop;
    rd_en <= '0';

    assert read_count = FIFO_DEPTH
      report "TB-FIFO-002 FAIL: only read " &
        integer'image(read_count) & " of " &
        integer'image(FIFO_DEPTH) & " words" severity error;
    if read_count /= FIFO_DEPTH then
      error_count := error_count + 1;
    end if;

    -- Verify empty and fill_level after drain
    wait for CDC_SETTLE;
    wait until rising_edge(rd_clk);
    assert rd_empty = '1'
      report "TB-FIFO-002 FAIL: not empty after draining" severity error;
    if rd_empty /= '1' then error_count := error_count + 1; end if;

    assert fill_level = 0
      report "TB-FIFO-002 FAIL: fill_level=" &
        integer'image(to_integer(fill_level)) &
        " expected 0 after draining" severity error;
    if fill_level /= 0 then error_count := error_count + 1; end if;

    rd_phase <= 5;

    -- =======================================================================
    -- TB-FIFO-004: Sustained simultaneous read during CDC stress
    -- =======================================================================
    wait until wr_phase = 6;

    read_count := 0;
    while read_count < 64 loop
      rd_en <= '1';
      wait until rising_edge(rd_clk);
      if rd_valid = '1' then
        expected :=
          std_logic_vector(to_unsigned(16#C000# + read_count, DATA_WIDTH));
        assert rd_data = expected
          report "TB-FIFO-004 FAIL: word " & integer'image(read_count) &
            " data=0x" & to_hstring(unsigned(rd_data)) &
            " expected=0x" & to_hstring(unsigned(expected))
          severity error;
        if rd_data /= expected then error_count := error_count + 1; end if;
        read_count := read_count + 1;
      end if;
    end loop;
    rd_en <= '0';

    assert read_count = 64
      report "TB-FIFO-004 FAIL: only read " &
        integer'image(read_count) & " of 64 words" severity error;
    if read_count /= 64 then error_count := error_count + 1; end if;

    rd_phase <= 7;

    -- =======================================================================
    -- TB-FIFO-005: Drain after overflow, verify original data intact
    -- =======================================================================
    wait until wr_phase = 9;
    wait until rising_edge(rd_clk);

    read_count := 0;
    while read_count < FIFO_DEPTH loop
      rd_en <= '1';
      wait until rising_edge(rd_clk);
      if rd_valid = '1' then
        -- Original data should be intact (0xD000+i), NOT 0xDEAD0+i
        expected :=
          std_logic_vector(to_unsigned(16#D000# + read_count, DATA_WIDTH));
        assert rd_data = expected
          report "TB-FIFO-005 FAIL: data corrupted by overflow -- word " &
            integer'image(read_count) &
            " data=0x" & to_hstring(unsigned(rd_data)) &
            " expected=0x" & to_hstring(unsigned(expected))
          severity error;
        if rd_data /= expected then error_count := error_count + 1; end if;
        read_count := read_count + 1;
      end if;
    end loop;
    rd_en <= '0';

    assert read_count = FIFO_DEPTH
      report "TB-FIFO-005 FAIL: only read " &
        integer'image(read_count) & " of " &
        integer'image(FIFO_DEPTH) & " words after overflow"
      severity error;
    if read_count /= FIFO_DEPTH then
      error_count := error_count + 1;
    end if;

    -- =======================================================================
    -- Summary
    -- =======================================================================
    wait for RD_CLK_PERIOD * 10;

    -- Combine write-side and read-side errors
    error_count := error_count + wr_error_count;

    if error_count = 0 then
      report "SIMULATION PASSED" severity error;
    else
      report "SIMULATION FAILED with " & integer'image(error_count) &
        " errors" severity failure;
    end if;
    std.env.stop;
  end process p_read_stim;

end architecture sim;
