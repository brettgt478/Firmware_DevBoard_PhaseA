-- =============================================================================
-- Module:      AxiLiteToAvmm
-- Description: Minimal AXI4-Lite slave to Avalon-MM master bridge.
--              Converts the HPS AXI4-Lite interface (separate AW/W/B/AR/R
--              channels) to Avalon-MM waitrequest-mode transactions for RegBank.
-- Author:      Brett Taylor
-- DEPRECATED:  2026-04-06 — superseded by AxiToAvmm (axi_to_avmm.vhd) which
--              handles the full AXI4 interface (with ID signals) exported by
--              the Agilex 5 lwhpm2fpga bridge. Retained for reference.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AxiLiteToAvmm is
  generic (
    G_ADDR_WIDTH : positive := 20;
    G_DATA_WIDTH : positive := 32
  );
  port (
    clk               : in  std_logic;
    rst               : in  std_logic;
    -- AXI4-Lite slave interface
    s_axi_awaddr      : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    s_axi_awvalid     : in  std_logic;
    s_axi_awready     : out std_logic;
    s_axi_wdata       : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    s_axi_wstrb       : in  std_logic_vector(G_DATA_WIDTH / 8 - 1 downto 0);
    s_axi_wvalid      : in  std_logic;
    s_axi_wready      : out std_logic;
    s_axi_bvalid      : out std_logic;
    s_axi_bready      : in  std_logic;
    s_axi_bresp       : out std_logic_vector(1 downto 0);
    s_axi_araddr      : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    s_axi_arvalid     : in  std_logic;
    s_axi_arready     : out std_logic;
    s_axi_rdata       : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    s_axi_rvalid      : out std_logic;
    s_axi_rready      : in  std_logic;
    -- Avalon-MM master interface
    avmm_address      : out std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    avmm_read         : out std_logic;
    avmm_write        : out std_logic;
    avmm_writedata    : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    avmm_readdata     : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    avmm_waitrequest  : in  std_logic
  );
end entity AxiLiteToAvmm;

architecture rtl of AxiLiteToAvmm is

  type t_state is (S_IDLE, S_WRITE, S_WRITE_RESP, S_READ, S_READ_RESP);
  signal state : t_state;

  signal addr_r  : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
  signal wdata_r : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  signal rdata_r : std_logic_vector(G_DATA_WIDTH - 1 downto 0);

  -- Registered handshake outputs (active for exactly 1 cycle)
  signal awready_r : std_logic;
  signal wready_r  : std_logic;
  signal arready_r : std_logic;
  signal bvalid_r  : std_logic;
  signal rvalid_r  : std_logic;

  -- Registered Avalon-MM outputs
  signal avmm_read_r  : std_logic;
  signal avmm_write_r : std_logic;

begin

  -- AXI4-Lite outputs
  s_axi_awready <= awready_r;
  s_axi_wready  <= wready_r;
  s_axi_arready <= arready_r;
  s_axi_bvalid  <= bvalid_r;
  s_axi_bresp   <= "00";  -- OKAY
  s_axi_rvalid  <= rvalid_r;
  s_axi_rdata   <= rdata_r;

  -- Avalon-MM outputs
  avmm_address   <= addr_r;
  avmm_read      <= avmm_read_r;
  avmm_write     <= avmm_write_r;
  avmm_writedata <= wdata_r;

  p_fsm : process(clk)
  begin
    if rising_edge(clk) then
      -- Default: deassert single-cycle handshake pulses
      awready_r <= '0';
      wready_r  <= '0';
      arready_r <= '0';

      if rst = '1' then
        state        <= S_IDLE;
        bvalid_r     <= '0';
        rvalid_r     <= '0';
        avmm_read_r  <= '0';
        avmm_write_r <= '0';
        addr_r       <= (others => '0');
        wdata_r      <= (others => '0');
        rdata_r      <= (others => '0');
      else
        case state is
          when S_IDLE =>
            -- Write takes priority over read
            if s_axi_awvalid = '1' and s_axi_wvalid = '1' then
              awready_r    <= '1';
              wready_r     <= '1';
              addr_r       <= s_axi_awaddr;
              wdata_r      <= s_axi_wdata;
              avmm_write_r <= '1';
              state        <= S_WRITE;
            elsif s_axi_arvalid = '1' then
              arready_r   <= '1';
              addr_r      <= s_axi_araddr;
              avmm_read_r <= '1';
              state       <= S_READ;
            end if;

          when S_WRITE =>
            if avmm_waitrequest = '0' then
              avmm_write_r <= '0';
              bvalid_r     <= '1';
              state        <= S_WRITE_RESP;
            end if;

          when S_WRITE_RESP =>
            if s_axi_bready = '1' then
              bvalid_r <= '0';
              state    <= S_IDLE;
            end if;

          when S_READ =>
            if avmm_waitrequest = '0' then
              avmm_read_r <= '0';
              rdata_r     <= avmm_readdata;
              rvalid_r    <= '1';
              state       <= S_READ_RESP;
            end if;

          when S_READ_RESP =>
            if s_axi_rready = '1' then
              rvalid_r <= '0';
              state    <= S_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process p_fsm;

end architecture rtl;
