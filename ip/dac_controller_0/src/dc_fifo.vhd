-- =============================================================================
-- Module:      DcFifo
-- Description: Dual-clock async FIFO with gray-coded pointers
-- Author:      Brett Taylor
-- Created:     2026-03-15
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.DacControllerPkg.all;

entity DcFifo is
  generic (
    G_DATA_WIDTH : positive := 128;
    G_DEPTH      : positive := 512   -- must be power of 2
  );
  port (
    -- Write side
    wr_clk       : in  std_logic;
    wr_rst       : in  std_logic;
    wr_data      : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    wr_valid     : in  std_logic;
    wr_full      : out std_logic;
    wr_overflow  : out std_logic;  -- pulses '1' when write attempted while full
    -- Read side
    rd_clk       : in  std_logic;
    rd_rst       : in  std_logic;
    rd_data      : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    rd_valid     : out std_logic;
    rd_en        : in  std_logic;
    rd_empty     : out std_logic;
    -- Fill level (read clock domain, for MUX pre-fill check)
    fill_level   : out unsigned(clog2(G_DEPTH) downto 0)
  );
end entity DcFifo;

architecture rtl of DcFifo is

  constant C_ADDR_W : positive := clog2(G_DEPTH);

  -- Binary to Gray conversion
  function bin2gray(b : unsigned) return unsigned is
  begin
    return b xor ('0' & b(b'high downto 1));
  end function;

  -- Gray to Binary conversion
  function gray2bin(g : unsigned) return unsigned is
    variable b : unsigned(g'range);
  begin
    b(g'high) := g(g'high);
    for i in g'high - 1 downto 0 loop
      b(i) := b(i + 1) xor g(i);
    end loop;
    return b;
  end function;

  -- Memory
  type t_mem is array (0 to G_DEPTH - 1) of
    std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  signal mem : t_mem;

  -- Write pointer (binary and gray, write clock domain)
  signal wr_ptr_bin  : unsigned(C_ADDR_W downto 0) := (others => '0');
  signal wr_ptr_gray : unsigned(C_ADDR_W downto 0) := (others => '0');

  -- Read pointer (binary and gray, read clock domain)
  signal rd_ptr_bin  : unsigned(C_ADDR_W downto 0) := (others => '0');
  signal rd_ptr_gray : unsigned(C_ADDR_W downto 0) := (others => '0');

  -- Synchronized pointers (2-stage synchronizers)
  signal wr_ptr_gray_rd_meta : unsigned(C_ADDR_W downto 0) :=
    (others => '0');
  signal wr_ptr_gray_rd_sync : unsigned(C_ADDR_W downto 0) :=
    (others => '0');

  signal rd_ptr_gray_wr_meta : unsigned(C_ADDR_W downto 0) :=
    (others => '0');
  signal rd_ptr_gray_wr_sync : unsigned(C_ADDR_W downto 0) :=
    (others => '0');

  -- Status
  signal full_i  : std_logic;
  signal empty_i : std_logic;

begin

  -- =========================================================================
  -- Write Logic
  -- =========================================================================
  p_write : process(wr_clk)
  begin
    if rising_edge(wr_clk) then
      if wr_rst = '1' then
        wr_ptr_bin  <= (others => '0');
        wr_ptr_gray <= (others => '0');
        wr_overflow <= '0';
      else
        wr_overflow <= '0';
        if wr_valid = '1' then
          if full_i = '0' then
            mem(to_integer(wr_ptr_bin(C_ADDR_W - 1 downto 0))) <= wr_data;
            wr_ptr_bin  <= wr_ptr_bin + 1;
            wr_ptr_gray <= bin2gray(wr_ptr_bin + 1);
          else
            wr_overflow <= '1';
          end if;
        end if;
      end if;
    end if;
  end process p_write;

  -- Full: write pointer + depth == read pointer (in gray, MSBs differ)
  full_i <= '1' when (wr_ptr_gray(C_ADDR_W) /=
    rd_ptr_gray_wr_sync(C_ADDR_W)) and
    (wr_ptr_gray(C_ADDR_W - 1) /=
    rd_ptr_gray_wr_sync(C_ADDR_W - 1)) and
    (wr_ptr_gray(C_ADDR_W - 2 downto 0) =
    rd_ptr_gray_wr_sync(C_ADDR_W - 2 downto 0))
    else '0';
  wr_full <= full_i;

  -- =========================================================================
  -- Read Logic
  -- =========================================================================
  p_read : process(rd_clk)
  begin
    if rising_edge(rd_clk) then
      if rd_rst = '1' then
        rd_ptr_bin  <= (others => '0');
        rd_ptr_gray <= (others => '0');
        rd_valid    <= '0';
      else
        rd_valid <= '0';
        if rd_en = '1' and empty_i = '0' then
          rd_data  <= mem(to_integer(rd_ptr_bin(C_ADDR_W - 1 downto 0)));
          rd_ptr_bin  <= rd_ptr_bin + 1;
          rd_ptr_gray <= bin2gray(rd_ptr_bin + 1);
          rd_valid <= '1';
        end if;
      end if;
    end if;
  end process p_read;

  -- Empty: read pointer == write pointer (in gray)
  empty_i <= '1' when rd_ptr_gray = wr_ptr_gray_rd_sync else '0';
  rd_empty <= empty_i;

  -- =========================================================================
  -- Pointer Synchronizers (2-stage)
  -- =========================================================================

  -- Write pointer → read clock domain
  p_sync_wr2rd : process(rd_clk)
  begin
    if rising_edge(rd_clk) then
      if rd_rst = '1' then
        wr_ptr_gray_rd_meta <= (others => '0');
        wr_ptr_gray_rd_sync <= (others => '0');
      else
        wr_ptr_gray_rd_meta <= wr_ptr_gray;
        wr_ptr_gray_rd_sync <= wr_ptr_gray_rd_meta;
      end if;
    end if;
  end process p_sync_wr2rd;

  -- Read pointer → write clock domain
  p_sync_rd2wr : process(wr_clk)
  begin
    if rising_edge(wr_clk) then
      if wr_rst = '1' then
        rd_ptr_gray_wr_meta <= (others => '0');
        rd_ptr_gray_wr_sync <= (others => '0');
      else
        rd_ptr_gray_wr_meta <= rd_ptr_gray;
        rd_ptr_gray_wr_sync <= rd_ptr_gray_wr_meta;
      end if;
    end if;
  end process p_sync_rd2wr;

  -- =========================================================================
  -- Fill Level (read clock domain)
  -- =========================================================================
  p_fill : process(all)
    variable wr_bin_in_rd : unsigned(C_ADDR_W downto 0);
  begin
    wr_bin_in_rd := gray2bin(wr_ptr_gray_rd_sync);
    fill_level <= wr_bin_in_rd - rd_ptr_bin;
  end process p_fill;

end architecture rtl;
