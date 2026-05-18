// fmc_handshake.sv -- Stage 5 (merged)
//
// FMC presence + power-good gate for JESD GTS reset deassertion (CLAUDE.md
// s6 #4). Holds fmc_ready low until prsnt_n has been deasserted (FMC card
// detected) and pg_m2c has been asserted (FMC power-good) for at least
// HOLDOFF_CYCLES consecutive cycles. The hold-off filter masks bounce
// during VADJ ramp on the AD9176-FMC-EBZ board.
//
// On the DK-A5E065BB32AES1 dev kit PG_M2C is owned by the on-board MAX10
// board-mgmt FPGA (CLAUDE.md ISSUE-012); the top-level wiring ties
// fmc_pg_m2c to 1'b1 so the prsnt_n debounce is the only effective gate.
// The module still exposes pg_m2c as a port to keep the interface
// symmetric and to leave room for a future stage that exposes pg_m2c
// readback through a board-mgmt-MAX10 sideband path.

`default_nettype none

module fmc_handshake #(
    parameter int HOLDOFF_CYCLES = 32
) (
    input  wire clk,
    input  wire rst,
    input  wire fmc_prsnt_n,
    input  wire fmc_pg_m2c,
    output wire fmc_ready
);
    // 2-stage synchronizers on both inputs (asynchronous to clk).
    reg prsnt_n_sync_q0, prsnt_n_sync_q1;
    reg pg_sync_q0, pg_sync_q1;

    always_ff @(posedge clk) begin
        if (rst) begin
            prsnt_n_sync_q0 <= 1'b1;
            prsnt_n_sync_q1 <= 1'b1;
            pg_sync_q0      <= 1'b0;
            pg_sync_q1      <= 1'b0;
        end else begin
            prsnt_n_sync_q0 <= fmc_prsnt_n;
            prsnt_n_sync_q1 <= prsnt_n_sync_q0;
            pg_sync_q0      <= fmc_pg_m2c;
            pg_sync_q1      <= pg_sync_q0;
        end
    end

    wire ready_now = (~prsnt_n_sync_q1) & pg_sync_q1;

    // Hold-off counter: ready must be stable for HOLDOFF_CYCLES before
    // fmc_ready asserts. Drops fmc_ready immediately on any glitch.
    localparam int CNT_W = $clog2(HOLDOFF_CYCLES + 1);
    reg [CNT_W-1:0] hold_cnt;
    reg ready_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            hold_cnt <= '0;
            ready_q  <= 1'b0;
        end else if (!ready_now) begin
            hold_cnt <= '0;
            ready_q  <= 1'b0;
        end else if (hold_cnt == HOLDOFF_CYCLES[CNT_W-1:0]) begin
            ready_q <= 1'b1;
        end else begin
            hold_cnt <= hold_cnt + 1'b1;
        end
    end

    assign fmc_ready = ready_q;
endmodule

`default_nettype wire
