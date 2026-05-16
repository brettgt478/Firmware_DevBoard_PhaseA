-- =============================================================================
-- Module:      JesdSyncController
-- Description: Multi-link JESD204B synchronization with LMFC-aligned release
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity JesdSyncController is
  port (
    clk            : in  std_logic;
    rst            : in  std_logic;
    -- Link status inputs (one per JESD link)
    txlink_ready   : in  std_logic_vector(3 downto 0);
    -- Configuration
    sync_mode      : in  std_logic;  -- 0=per-DAC, 1=all-four
    -- Error clear (write-1-to-clear from CSR)
    err_clr        : in  std_logic_vector(3 downto 0);
    -- Outputs
    data_release   : out std_logic_vector(3 downto 0);
    -- Status
    group_synced   : out std_logic_vector(1 downto 0);
    lmfc_aligned   : out std_logic;
    sync_err       : out std_logic_vector(3 downto 0);
    -- LMFC boundary output (useful for other modules)
    lmfc_boundary  : out std_logic
  );
end entity JesdSyncController;

architecture rtl of JesdSyncController is

  -- LMFC counter
  signal lmfc_count     : unsigned(3 downto 0);  -- 0 to C_LMFC_PERIOD-1
  signal lmfc_bound     : std_logic;

  -- Per-group FSM
  type t_sync_state is (ST_WAIT_LOCK, ST_WAIT_LMFC, ST_RUNNING, ST_ERROR);
  signal grp0_state     : t_sync_state;
  signal grp1_state     : t_sync_state;

  -- Group ready signals
  signal grp0_all_ready : std_logic;
  signal grp1_all_ready : std_logic;

  -- Data release per group
  signal grp0_release   : std_logic;
  signal grp1_release   : std_logic;

  -- Sticky error flags
  signal sync_err_r     : std_logic_vector(3 downto 0);

begin

  -- =========================================================================
  -- LMFC Boundary Counter
  -- =========================================================================
  p_lmfc : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        lmfc_count <= (others => '0');
        lmfc_bound <= '0';
      else
        if lmfc_count = to_unsigned(C_LMFC_PERIOD - 1, 4) then
          lmfc_count <= (others => '0');
          lmfc_bound <= '1';
        else
          lmfc_count <= lmfc_count + 1;
          lmfc_bound <= '0';
        end if;
      end if;
    end if;
  end process p_lmfc;

  lmfc_boundary <= lmfc_bound;

  -- =========================================================================
  -- Group Ready Logic
  -- =========================================================================
  p_grp_ready : process(all)
  begin
    if sync_mode = '0' then
      -- Per-DAC mode: Group 0 = links 0+1, Group 1 = links 2+3
      grp0_all_ready <= txlink_ready(0) and txlink_ready(1);
      grp1_all_ready <= txlink_ready(2) and txlink_ready(3);
    else
      -- All-four mode: single group needs all 4
      grp0_all_ready <= txlink_ready(0) and txlink_ready(1) and
                        txlink_ready(2) and txlink_ready(3);
      grp1_all_ready <= txlink_ready(0) and txlink_ready(1) and
                        txlink_ready(2) and txlink_ready(3);
    end if;
  end process p_grp_ready;

  -- =========================================================================
  -- Group 0 FSM
  -- =========================================================================
  p_grp0 : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        grp0_state   <= ST_WAIT_LOCK;
        grp0_release <= '0';
      else
        case grp0_state is
          when ST_WAIT_LOCK =>
            grp0_release <= '0';
            if grp0_all_ready = '1' then
              grp0_state <= ST_WAIT_LMFC;
            end if;

          when ST_WAIT_LMFC =>
            if grp0_all_ready = '0' then
              grp0_state <= ST_WAIT_LOCK;
            elsif lmfc_bound = '1' then
              grp0_state   <= ST_RUNNING;
              grp0_release <= '1';
            end if;

          when ST_RUNNING =>
            grp0_release <= '1';
            if grp0_all_ready = '0' then
              grp0_state   <= ST_ERROR;
              grp0_release <= '0';
            end if;

          when ST_ERROR =>
            grp0_release <= '0';
            -- Unconditionally return to wait_lock to attempt re-sync.
            -- This avoids deadlock when a link drops for only 1 clock
            -- (grp_all_ready goes low then immediately back high).
            grp0_state <= ST_WAIT_LOCK;
        end case;
      end if;
    end if;
  end process p_grp0;

  -- =========================================================================
  -- Group 1 FSM
  -- =========================================================================
  p_grp1 : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        grp1_state   <= ST_WAIT_LOCK;
        grp1_release <= '0';
      else
        case grp1_state is
          when ST_WAIT_LOCK =>
            grp1_release <= '0';
            if grp1_all_ready = '1' then
              grp1_state <= ST_WAIT_LMFC;
            end if;

          when ST_WAIT_LMFC =>
            if grp1_all_ready = '0' then
              grp1_state <= ST_WAIT_LOCK;
            elsif lmfc_bound = '1' then
              grp1_state   <= ST_RUNNING;
              grp1_release <= '1';
            end if;

          when ST_RUNNING =>
            grp1_release <= '1';
            if grp1_all_ready = '0' then
              grp1_state   <= ST_ERROR;
              grp1_release <= '0';
            end if;

          when ST_ERROR =>
            grp1_release <= '0';
            -- Unconditionally return to wait_lock to attempt re-sync.
            grp1_state <= ST_WAIT_LOCK;
        end case;
      end if;
    end if;
  end process p_grp1;

  -- =========================================================================
  -- Sticky Error Flags
  -- =========================================================================
  p_err : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sync_err_r <= (others => '0');
      else
        -- Clear first, set below. VHDL last-assignment wins: if err_clr and
        -- a link fault are both active in the same cycle, the set below takes
        -- priority and the clear is discarded (cannot clear an active fault).
        for i in 0 to 3 loop
          if err_clr(i) = '1' then
            sync_err_r(i) <= '0';
          end if;
        end loop;

        -- Group 0: links 0, 1
        if grp0_state = ST_RUNNING and grp0_all_ready = '0' then
          if txlink_ready(0) = '0' then sync_err_r(0) <= '1'; end if;
          if txlink_ready(1) = '0' then sync_err_r(1) <= '1'; end if;
        end if;

        -- Group 1: links 2, 3
        if grp1_state = ST_RUNNING and grp1_all_ready = '0' then
          if txlink_ready(2) = '0' then sync_err_r(2) <= '1'; end if;
          if txlink_ready(3) = '0' then sync_err_r(3) <= '1'; end if;
        end if;
      end if;
    end if;
  end process p_err;

  -- =========================================================================
  -- Output Assignments
  -- =========================================================================

  -- Data release: per-link, based on group membership
  data_release(0) <= grp0_release;
  data_release(1) <= grp0_release;
  data_release(2) <= grp1_release;
  data_release(3) <= grp1_release;

  group_synced(0) <= '1' when grp0_state = ST_RUNNING else '0';
  group_synced(1) <= '1' when grp1_state = ST_RUNNING else '0';

  lmfc_aligned <= '1' when grp0_state = ST_RUNNING and
    grp1_state = ST_RUNNING else '0';

  sync_err <= sync_err_r;

end architecture rtl;
