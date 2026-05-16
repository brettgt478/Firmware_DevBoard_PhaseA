-- =============================================================================
-- Module:      DataSrcMux
-- Description: LMFC-aligned data source MUX with FIFO pre-fill threshold
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity DataSrcMux is
  generic (
    G_FIFO_DEPTH     : positive := 512;
    G_FILL_THRESHOLD : positive := 256  -- 50% of FIFO depth
  );
  port (
    clk              : in  std_logic;
    rst              : in  std_logic;
    -- Source 0: NCO (sine_wave_gen)
    nco_samples      : in  t_sample_bus;
    nco_valid        : in  std_logic;
    -- Source 1: External FIFO
    fifo_samples     : in  t_sample_bus;
    fifo_valid       : in  std_logic;
    fifo_fill_level  : in  unsigned;
    -- Control (from shadow register)
    src_sel          : in  std_logic;  -- 0 = NCO, 1 = FIFO
    lmfc_boundary    : in  std_logic;
    -- Output
    samples_out      : out t_sample_bus;
    samples_valid    : out std_logic;
    -- Status
    src_switch_pending : out std_logic;
    src_active         : out std_logic  -- 0 = NCO active, 1 = FIFO active
  );
end entity DataSrcMux;

architecture rtl of DataSrcMux is

  signal active_src      : std_logic;  -- current active source
  signal pending         : std_logic;  -- switch pending flag
  signal shadow_src      : std_logic;  -- latched requested source

begin

  -- =========================================================================
  -- Double-Buffered Source Select
  -- Shadow → Active on LMFC boundary, with pre-fill check for FIFO
  -- =========================================================================
  p_switch : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        active_src <= '0';  -- default to NCO
        pending    <= '0';
        shadow_src <= '0';
      else
        -- Latch shadow register whenever src_sel changes
        shadow_src <= src_sel;

        -- Single priority chain: revert > switch > set-pending
        if shadow_src = active_src then
          -- No switch needed (or shadow reverted before LMFC)
          pending <= '0';

        elsif pending = '1' and lmfc_boundary = '1' then
          -- Execute switch on LMFC boundary
          if shadow_src = '0' then
            -- Switching to NCO: unconditional
            active_src <= '0';
            pending    <= '0';
          elsif fifo_fill_level >= G_FILL_THRESHOLD then
            -- Switching to FIFO: threshold met
            active_src <= '1';
            pending    <= '0';
          end if;
          -- else: FIFO below threshold, keep pending

        else
          -- Shadow differs from active, not yet at LMFC boundary
          pending <= '1';
        end if;
      end if;
    end if;
  end process p_switch;

  -- =========================================================================
  -- Output MUX
  -- =========================================================================
  p_mux : process(all)
  begin
    if active_src = '0' then
      samples_out   <= nco_samples;
      samples_valid <= nco_valid;
    else
      samples_out   <= fifo_samples;
      samples_valid <= fifo_valid;
    end if;
  end process p_mux;

  src_switch_pending <= pending;
  src_active         <= active_src;

end architecture rtl;
