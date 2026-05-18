-- sysref_capture.vhd -- Stage 5 (merged)
--
-- Captures the differential SYSREF input (FMC LA00_CC, HSIO 3B LVDS 1.2-V)
-- into the JESD TX link clock domain. The differential LVDS_RX buffer is
-- inferred by Quartus from the "1.2-V TRUE DIFFERENTIAL SIGNALING"
-- IO_STANDARD assignment in agilex5_devkit.qsf; only the _p pad is named
-- in the RTL port list, the _n location uses the "name(n)" syntax.
--
-- A 2-stage synchronizer registers the SYSREF into link_clk to handle
-- metastability. JESD204B subclass-1 deterministic latency relies on the
-- AD9176-FMC-EBZ source-synchronous SYSREF<->GBTCLK0 phasing on the AD9176
-- board, not on FPGA capture timing -- this synchronizer's job is purely
-- to bring the asynchronous input into the link clock for the GTS IP.

library ieee;
use ieee.std_logic_1164.all;

entity sysref_capture is
  port (
    sysref_in  : in  std_logic;   -- LVDS_RX from FMC LA00_CC (single-ended
                                  -- view after Quartus's inferred LVDS buffer)
    link_clk   : in  std_logic;   -- jesd204_tx_link_clk (~312.5 MHz)
    rst_n      : in  std_logic;   -- active-low, gated on fmc_ready
    sysref_out : out std_logic    -- single bit, link_clk domain, fans to
                                  -- both u_jesd_link0 and u_jesd_link1
  );
end entity sysref_capture;

architecture rtl of sysref_capture is
  signal sync_q0 : std_logic := '0';
  signal sync_q1 : std_logic := '0';
begin
  p_sync : process (link_clk)
  begin
    if rising_edge(link_clk) then
      if rst_n = '0' then
        sync_q0 <= '0';
        sync_q1 <= '0';
      else
        sync_q0 <= sysref_in;
        sync_q1 <= sync_q0;
      end if;
    end if;
  end process p_sync;

  sysref_out <= sync_q1;
end architecture rtl;
