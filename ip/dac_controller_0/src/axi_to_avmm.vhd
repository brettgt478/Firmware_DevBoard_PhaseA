-- =============================================================================
-- Module:      AxiToAvmm
-- Description: Full AXI4 slave to Avalon-MM master bridge for dac_controller_0.
--              Accepts AXI4 transactions from the Agilex HPS lwhpm2fpga bridge
--              and converts them to Avalon-MM waitrequest-mode transactions for
--              RegBank. Only single-beat transfers are supported (burst length
--              is accepted but only the first beat is forwarded; this matches
--              the lwhpm2fpga bridge which issues single-beat transactions for
--              register access). AXI IDs are echoed back on the response channels.
-- Author:      Brett Taylor
-- Created:     2026-04-06
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AxiToAvmm is
  generic (
    G_ADDR_WIDTH : positive := 10;
    G_DATA_WIDTH : positive := 32;
    G_ID_WIDTH   : positive := 4
  );
  port (
    clk  : in std_logic;
    rst  : in std_logic;
    -- AXI4 slave — write address channel
    s_axi_awid     : in  std_logic_vector(G_ID_WIDTH - 1 downto 0);
    s_axi_awaddr   : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    s_axi_awlen    : in  std_logic_vector(7 downto 0);
    s_axi_awsize   : in  std_logic_vector(2 downto 0);
    s_axi_awburst  : in  std_logic_vector(1 downto 0);
    s_axi_awlock   : in  std_logic;
    s_axi_awcache  : in  std_logic_vector(3 downto 0);
    s_axi_awprot   : in  std_logic_vector(2 downto 0);
    s_axi_awvalid  : in  std_logic;
    s_axi_awready  : out std_logic;
    -- AXI4 slave — write data channel
    s_axi_wdata    : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    s_axi_wstrb    : in  std_logic_vector(G_DATA_WIDTH / 8 - 1 downto 0);
    s_axi_wlast    : in  std_logic;
    s_axi_wvalid   : in  std_logic;
    s_axi_wready   : out std_logic;
    -- AXI4 slave — write response channel
    s_axi_bid      : out std_logic_vector(G_ID_WIDTH - 1 downto 0);
    s_axi_bresp    : out std_logic_vector(1 downto 0);
    s_axi_bvalid   : out std_logic;
    s_axi_bready   : in  std_logic;
    -- AXI4 slave — read address channel
    s_axi_arid     : in  std_logic_vector(G_ID_WIDTH - 1 downto 0);
    s_axi_araddr   : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    s_axi_arlen    : in  std_logic_vector(7 downto 0);
    s_axi_arsize   : in  std_logic_vector(2 downto 0);
    s_axi_arburst  : in  std_logic_vector(1 downto 0);
    s_axi_arlock   : in  std_logic;
    s_axi_arcache  : in  std_logic_vector(3 downto 0);
    s_axi_arprot   : in  std_logic_vector(2 downto 0);
    s_axi_arvalid  : in  std_logic;
    s_axi_arready  : out std_logic;
    -- AXI4 slave — read data channel
    s_axi_rid      : out std_logic_vector(G_ID_WIDTH - 1 downto 0);
    s_axi_rdata    : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    s_axi_rresp    : out std_logic_vector(1 downto 0);
    s_axi_rlast    : out std_logic;
    s_axi_rvalid   : out std_logic;
    s_axi_rready   : in  std_logic;
    -- Avalon-MM master
    avmm_address   : out std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    avmm_read      : out std_logic;
    avmm_write     : out std_logic;
    avmm_writedata : out std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    avmm_readdata  : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    avmm_waitrequest : in std_logic
  );
end entity AxiToAvmm;

architecture rtl of AxiToAvmm is

  type t_state is (S_IDLE, S_WRITE, S_WRITE_RESP, S_READ, S_READ_RESP);
  signal state : t_state;

  signal addr_r   : std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
  signal wdata_r  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  signal rdata_r  : std_logic_vector(G_DATA_WIDTH - 1 downto 0);
  signal id_r     : std_logic_vector(G_ID_WIDTH - 1 downto 0);

  -- Single-cycle handshake outputs
  signal awready_r : std_logic;
  signal wready_r  : std_logic;
  signal arready_r : std_logic;
  signal bvalid_r  : std_logic;
  signal rvalid_r  : std_logic;

  -- Avalon-MM drive registers
  signal avmm_read_r  : std_logic;
  signal avmm_write_r : std_logic;

begin

  s_axi_awready <= awready_r;
  s_axi_wready  <= wready_r;
  s_axi_arready <= arready_r;
  s_axi_bvalid  <= bvalid_r;
  s_axi_bid     <= id_r;
  s_axi_bresp   <= "00";  -- OKAY
  s_axi_rvalid  <= rvalid_r;
  s_axi_rid     <= id_r;
  s_axi_rdata   <= rdata_r;
  s_axi_rresp   <= "00";  -- OKAY
  s_axi_rlast   <= rvalid_r;  -- single-beat: rlast coincides with rvalid

  avmm_address   <= addr_r;
  avmm_read      <= avmm_read_r;
  avmm_write     <= avmm_write_r;
  avmm_writedata <= wdata_r;

  p_fsm : process(clk)
  begin
    if rising_edge(clk) then
      -- Default: deassert single-cycle ready pulses
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
        id_r         <= (others => '0');
      else
        case state is

          -- Wait for either a write (AW+W present) or a read (AR present).
          -- Write takes priority over read (matches HPS bridge behaviour).
          when S_IDLE =>
            if s_axi_awvalid = '1' and s_axi_wvalid = '1' then
              awready_r    <= '1';
              wready_r     <= '1';
              addr_r       <= s_axi_awaddr;
              wdata_r      <= s_axi_wdata;
              id_r         <= s_axi_awid;
              avmm_write_r <= '1';
              state        <= S_WRITE;
            elsif s_axi_arvalid = '1' then
              arready_r   <= '1';
              addr_r      <= s_axi_araddr;
              id_r        <= s_axi_arid;
              avmm_read_r <= '1';
              state       <= S_READ;
            end if;

          -- Hold Avalon-MM write until slave de-asserts waitrequest.
          when S_WRITE =>
            if avmm_waitrequest = '0' then
              avmm_write_r <= '0';
              bvalid_r     <= '1';
              state        <= S_WRITE_RESP;
            end if;

          -- Wait for master to accept write response.
          when S_WRITE_RESP =>
            if s_axi_bready = '1' then
              bvalid_r <= '0';
              state    <= S_IDLE;
            end if;

          -- Hold Avalon-MM read until slave de-asserts waitrequest.
          when S_READ =>
            if avmm_waitrequest = '0' then
              avmm_read_r <= '0';
              rdata_r     <= avmm_readdata;
              rvalid_r    <= '1';
              state       <= S_READ_RESP;
            end if;

          -- Wait for master to accept read data.
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
