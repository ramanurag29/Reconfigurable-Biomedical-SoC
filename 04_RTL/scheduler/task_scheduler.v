`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// task_scheduler [synthesizable] : arbiter + context manager for ONE shared mac_unit.
//   Client 0 = FIR engine (task T2), Client 1 = NN engine (task T4).
//   (T1 acquisition, T3 feature, T5 reporting use no MAC; they are added at SoC integration.)
//
// Ownership: exactly one client owns the MAC (st==RUN). grant_c is high only for the owner.
//   Engines gate their own mac_en/mac_clear/mac_load with grant, so a withdrawn grant means
//   "no new MAC op this cycle" and the engine simply holds its state (k / n / hidden buffer).
//
// SAFE PREEMPTION (never corrupts a partial result):
//   a switch happens only when ALL hold in the same cycle
//     - the owner reports at_boundary (not in DRAIN / not between result and use),
//     - no MAC op of the owner is in flight (inflight==0, so `acc` is settled),
//     - the owner is NOT issuing an op this cycle (grant is dropped combinationally: preempt_now).
//   Then acc + overflow are saved into the owner's context slot, the MAC is handed over, and
//   when the preempted client regains the MAC its accumulator is reloaded through the MAC load
//   port (RS1 = load, RS2 = absorb the load's acc_valid, which is NOT forwarded to engines).
//
// Policies (policy[1:0]):   0 fixed priority (default)   1 round-robin (quantum MAC ops)
//                           2 mode-based (mode_sel client is favoured)
//   fixed   : higher prio wins; ties -> client 0.  Preempts if the other's prio is strictly higher.
//   RR      : on idle alternate clients; preempt after `quantum` granted MAC ops if the other waits.
//   mode    : client == mode_sel always wins; may preempt the other.
//   preempt_en=0 -> non-preemptive (run to completion), still arbitrated at idle.
//
// Metrics (cleared by stat_clr): per client wait/exec/latency, deadline misses, MAC utilisation.
//   A task = interval during which req_c is high. Latency = cycles req high. Wait = req high & !grant.
// -----------------------------------------------------------------------------
module task_scheduler #(
    parameter ACC_W = 32,
    parameter A_W   = 11,
    parameter B_W   = 12,
    parameter PIPE  = 0
) (
    input  wire                     clk,
    input  wire                     rst_n,
    // configuration
    input  wire [1:0]               policy,
    input  wire                     mode_sel,       // mode-based: favoured client (0=FIR,1=NN)
    input  wire                     preempt_en,
    input  wire [2:0]               prio0, prio1,   // higher = more urgent
    input  wire [7:0]               quantum,        // RR slice in granted MAC ops (0 = never slice)
    input  wire [15:0]              deadline0, deadline1,   // cycles, 0 = no deadline monitoring
    input  wire                     stat_clr,
    // client 0 (FIR)
    input  wire                     req0, bnd0, clr0, load0, en0,
    input  wire signed [A_W-1:0]    a0,
    input  wire signed [B_W-1:0]    b0,
    input  wire signed [ACC_W-1:0]  lv0,
    output wire                     grant0,
    // client 1 (NN)
    input  wire                     req1, bnd1, clr1, load1, en1,
    input  wire signed [A_W-1:0]    a1,
    input  wire signed [B_W-1:0]    b1,
    input  wire signed [ACC_W-1:0]  lv1,
    output wire                     grant1,
    // results routed back to clients
    output wire signed [ACC_W-1:0]  acc_out,
    output wire                     acc_valid0, acc_valid1,
    output wire                     ovf0, ovf1,
    // status / waveform visibility
    output wire [1:0]               sched_state,
    output wire                     owner_o,
    // metrics
    output reg  [31:0]              m_total_cycles,
    output reg  [31:0]              m_mac_ops,       // client MAC ops issued (restore loads excluded)
    output reg  [15:0]              m_preempts,
    output reg  [31:0]              m_ovh_cycles,    // cycles lost in restore (scheduling overhead)
    output reg  [15:0]              m_tasks0, m_tasks1,
    output reg  [31:0]              m_wait_sum0, m_wait_sum1,
    output reg  [15:0]              m_wait_max0, m_wait_max1,
    output reg  [15:0]              m_lat_max0,  m_lat_max1,
    output reg  [31:0]              m_exec_sum0, m_exec_sum1,
    output reg  [15:0]              m_miss0, m_miss1
);
    localparam [1:0] ST_IDLE = 2'd0, ST_RUN = 2'd1, ST_RS1 = 2'd2, ST_RS2 = 2'd3;

    reg [1:0] st;
    reg       owner;
    reg       rr_last;
    reg [7:0] slice;
    reg [2:0] inflight;
    reg       rs_cnt;              // extra RS2 cycle needed when the MAC is pipelined (PIPE=1)
    reg signed [ACC_W-1:0] ctx_acc0, ctx_acc1;
    reg       ctx_v0, ctx_v1, ctx_o0, ctx_o1;

    assign sched_state = st;
    assign owner_o     = owner;

    // ---------------- owner muxing
    wire        o_req = owner ? req1 : req0;
    wire        o_bnd = owner ? bnd1 : bnd0;
    wire        o_clr = owner ? clr1 : clr0;
    wire        o_lod = owner ? load1 : load0;
    wire        o_en  = owner ? en1  : en0;
    wire        x_req = owner ? req0 : req1;           // the other client
    wire [2:0]  o_pri = owner ? prio1 : prio0;
    wire [2:0]  x_pri = owner ? prio0 : prio1;

    wire m_accv_w;   // = m_accv from the MAC instance below

    // ---------------- preemption decision (combinational; drops grant in that same cycle)
    reg want;
    always @* begin
        case (policy)
            2'd1:    want = (quantum != 8'd0) && (slice >= quantum);
            2'd2:    want = (owner != mode_sel);       // other == mode_sel
            default: want = (x_pri > o_pri);
        endcase
    end
    // preempt_req : a switch is wanted and the owner sits at a safe boundary -> stop granting new
    //               ops immediately so any op already in the MAC pipeline can drain.
    // settled     : no op of the owner is still in flight (an op whose result arrives THIS cycle
    //               is already reflected in `acc`, hence the subtraction of accv_run).
    wire accv_run    = m_accv_w && (st == ST_RUN);
    wire settled     = (inflight == {2'b00, accv_run});
    wire preempt_req = (st == ST_RUN) && preempt_en && o_req && x_req && want && o_bnd;
    wire preempt_now = preempt_req && settled;

    wire run_c = (st == ST_RUN) && !preempt_req;
    assign grant0 = run_c && !owner;
    assign grant1 = run_c &&  owner;

    // ---------------- MAC instance
    wire                     m_clear = (st == ST_RUN) && o_clr;
    wire                     m_load  = ((st == ST_RUN) && o_lod) || (st == ST_RS1);
    wire                     m_en    = (st == ST_RUN) && o_en;
    wire signed [A_W-1:0]    m_a     = owner ? a1 : a0;
    wire signed [B_W-1:0]    m_b     = owner ? b1 : b0;
    wire signed [ACC_W-1:0]  m_lv    = (st == ST_RS1) ? (owner ? ctx_acc1 : ctx_acc0)
                                                       : (owner ? lv1 : lv0);
    wire signed [ACC_W-1:0]  m_acc;
    wire                     m_accv, m_ovf;

    mac_unit #(.A_W(A_W), .B_W(B_W), .ACC_W(ACC_W), .SATURATE(1), .PIPE(PIPE)) u_mac (
        .clk(clk), .rst_n(rst_n), .en(m_en), .clear(m_clear), .load(m_load),
        .a(m_a), .b(m_b), .load_val(m_lv), .acc(m_acc), .acc_valid(m_accv), .overflow(m_ovf));

    assign acc_out    = m_acc;
    assign m_accv_w   = m_accv;                          // restore-load valid (RS2) is masked via accv_run
    assign acc_valid0 = accv_run && !owner;
    assign acc_valid1 = accv_run &&  owner;
    assign ovf0       = m_ovf | ctx_o0;
    assign ovf1       = m_ovf | ctx_o1;

    wire issue = (st == ST_RUN) && (o_clr || o_lod || o_en) && !preempt_req;

    // ---------------- idle arbitration
    reg pick;
    always @* begin
        if (req0 && !req1)      pick = 1'b0;
        else if (req1 && !req0) pick = 1'b1;
        else case (policy)
            2'd1:    pick = ~rr_last;
            2'd2:    pick = mode_sel;
            default: pick = (prio1 > prio0);
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; owner <= 1'b0; rr_last <= 1'b1; slice <= 8'd0; inflight <= 3'd0; rs_cnt <= 1'b0;
            ctx_acc0 <= 0; ctx_acc1 <= 0; ctx_v0 <= 1'b0; ctx_v1 <= 1'b0; ctx_o0 <= 1'b0; ctx_o1 <= 1'b0;
        end else begin
            inflight <= inflight + {2'b00, issue} - {2'b00, accv_run};
            if (issue && slice != 8'hFF) slice <= slice + 8'd1;
            case (st)
                ST_IDLE: if (req0 || req1) begin
                    owner <= pick; rr_last <= pick; slice <= 8'd0;
                    st <= (pick ? ctx_v1 : ctx_v0) ? ST_RS1 : ST_RUN;
                end
                ST_RUN: begin
                    if (preempt_now) begin
                        if (owner) begin ctx_acc1 <= m_acc; ctx_v1 <= 1'b1; ctx_o1 <= ctx_o1 | m_ovf; end
                        else       begin ctx_acc0 <= m_acc; ctx_v0 <= 1'b1; ctx_o0 <= ctx_o0 | m_ovf; end
                        owner <= ~owner; rr_last <= ~owner; slice <= 8'd0;
                        st <= (owner ? ctx_v0 : ctx_v1) ? ST_RS1 : ST_RUN;
                    end else if (!o_req && inflight == 3'd0) begin     // owner's task finished
                        if (owner) begin ctx_v1 <= 1'b0; ctx_o1 <= 1'b0; end
                        else       begin ctx_v0 <= 1'b0; ctx_o0 <= 1'b0; end
                        st <= ST_IDLE;
                    end
                end
                ST_RS1: begin
                    if (owner) ctx_v1 <= 1'b0; else ctx_v0 <= 1'b0;
                    rs_cnt <= (PIPE != 0);
                    st <= ST_RS2;
                end
                ST_RS2: begin                       // wait for the restore-load's acc_valid (PIPE+1 cycles)
                    if (rs_cnt) rs_cnt <= 1'b0; else st <= ST_RUN;
                end
            endcase
        end
    end

    // ---------------- metrics
    reg req0_q, req1_q;
    reg [15:0] wait_c0, wait_c1, lat_c0, lat_c1, exe_c0, exe_c1;
    wire done0 = req0_q && !req0, done1 = req1_q && !req1;
    wire [15:0] lat_f0 = lat_c0, lat_f1 = lat_c1;

    wire clr_all = stat_clr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_total_cycles <= 0; m_mac_ops <= 0; m_preempts <= 0; m_ovh_cycles <= 0;
            m_tasks0 <= 0; m_tasks1 <= 0; m_wait_sum0 <= 0; m_wait_sum1 <= 0;
            m_wait_max0 <= 0; m_wait_max1 <= 0; m_lat_max0 <= 0; m_lat_max1 <= 0;
            m_exec_sum0 <= 0; m_exec_sum1 <= 0; m_miss0 <= 0; m_miss1 <= 0;
            req0_q <= 0; req1_q <= 0; wait_c0 <= 0; wait_c1 <= 0; lat_c0 <= 0; lat_c1 <= 0; exe_c0 <= 0; exe_c1 <= 0;
        end else if (clr_all) begin      // synchronous statistics clear (task-in-flight trackers also restart)
            m_total_cycles <= 0; m_mac_ops <= 0; m_preempts <= 0; m_ovh_cycles <= 0;
            m_tasks0 <= 0; m_tasks1 <= 0; m_wait_sum0 <= 0; m_wait_sum1 <= 0;
            m_wait_max0 <= 0; m_wait_max1 <= 0; m_lat_max0 <= 0; m_lat_max1 <= 0;
            m_exec_sum0 <= 0; m_exec_sum1 <= 0; m_miss0 <= 0; m_miss1 <= 0;
            req0_q <= req0; req1_q <= req1; wait_c0 <= 0; wait_c1 <= 0; lat_c0 <= 0; lat_c1 <= 0; exe_c0 <= 0; exe_c1 <= 0;
        end else begin
            m_total_cycles <= m_total_cycles + 1;
            if (issue) m_mac_ops <= m_mac_ops + 1;
            if (preempt_now) m_preempts <= m_preempts + 1;
            if (st == ST_RS1 || st == ST_RS2) m_ovh_cycles <= m_ovh_cycles + 1;
            req0_q <= req0; req1_q <= req1;

            // client 0
            if (req0) begin
                lat_c0 <= lat_c0 + 1;
                if (grant0) exe_c0 <= exe_c0 + 1; else wait_c0 <= wait_c0 + 1;
            end
            if (done0) begin
                m_tasks0 <= m_tasks0 + 1;
                m_wait_sum0 <= m_wait_sum0 + wait_c0;
                m_exec_sum0 <= m_exec_sum0 + exe_c0;
                if (wait_c0 > m_wait_max0) m_wait_max0 <= wait_c0;
                if (lat_f0  > m_lat_max0)  m_lat_max0  <= lat_f0;
                if (deadline0 != 0 && lat_f0 > deadline0) m_miss0 <= m_miss0 + 1;
                wait_c0 <= 0; lat_c0 <= 0; exe_c0 <= 0;
            end
            // client 1
            if (req1) begin
                lat_c1 <= lat_c1 + 1;
                if (grant1) exe_c1 <= exe_c1 + 1; else wait_c1 <= wait_c1 + 1;
            end
            if (done1) begin
                m_tasks1 <= m_tasks1 + 1;
                m_wait_sum1 <= m_wait_sum1 + wait_c1;
                m_exec_sum1 <= m_exec_sum1 + exe_c1;
                if (wait_c1 > m_wait_max1) m_wait_max1 <= wait_c1;
                if (lat_f1  > m_lat_max1)  m_lat_max1  <= lat_f1;
                if (deadline1 != 0 && lat_f1 > deadline1) m_miss1 <= m_miss1 + 1;
                wait_c1 <= 0; lat_c1 <= 0; exe_c1 <= 0;
            end
        end
    end
endmodule
