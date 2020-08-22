// Module: axi4_adapter
// Description:
//  **IMPORTANT**:
//    This adapter only support narrow on WRITE channel, **Not** on read channel.
//    This adapter only support realgined the started address with ALIGN_ADDR=1'b1
//    on WRITE channel, **Not** on read channel.

`timescale 1ns/1ps

module axi4_adapter #(
  parameter integer                     AXI_ID_WIDTH = 1,
  parameter integer                     AXI_ADDR_WIDTH = 12,
  parameter integer                     AXI_DATA_WIDTH = 32,
  parameter bit                         ALIGN_ADDR = 1'b1,
  // Set this block to the security memory space.
  // If this parameter is asserted, The AXI Lite bus will only have access to
  // the register when AxPROT[1] is high.
  parameter bit                         EN_SEC_MODE = 1'b1,
  // Slience failure when trying to access the register file with AxPROT[1]=0,
  // and EN_SEC_MODE = 1.
  parameter bit                         NO_SEC_FAIL = 0,
  // Whether the AXI-Lite W channel should be decoupled with a register. This
  // can help break long paths at the expense of registers.
  parameter bit                         DECOUPLE_W = 1,
  // Whether the AXI-Lite AR channel should be decoupled with a register. This
  // can help break long paths at the expense of registers.
  // parameter bit                         DECOUPLE_R = 1,
  parameter integer                     AXI_BYTE_COUNT  = AXI_DATA_WIDTH / 8
)(
  input  logic                          aclk,
  input  logic                          aresetn,

  // Write Address channel
  input  logic [AXI_ID_WIDTH-1:0]       awid,
  input  logic [AXI_ADDR_WIDTH-1:0]     awaddr,
  input  logic [7:0]                    awlen,
  input  logic [2:0]                    awsize,
  input  logic [1:0]                    awburst,
  /* verilator lint_off UNUSED */
  input  logic                          awlock,
  input  logic [3:0]                    awcache,
  /* verilator lint_on UNUSED */
  input  logic [2:0]                    awprot,
  /* verilator lint_off UNUSED */
  input  logic [3:0]                    awqos,
  input  logic [3:0]                    awregion,
  /* verilator lint_on UNUSED */
  // input  logic [5:0]                    awatop,
  // input  logic [AXI_AW_USER:0]          awuser,
  input  logic                          awvalid,
  output logic                          awready,

  // Write data channel
  input  logic [AXI_DATA_WIDTH-1:0]     wdata,
  input  logic [AXI_BYTE_COUNT-1:0]     wstrb,
  input  logic                          wlast,
  input  logic                          wvalid,
  output logic                          wready,

  // Write response channel
  output logic [AXI_ID_WIDTH-1:0]       bid,
  output logic [1:0]                    bresp,
  output logic                          bvalid,
  input  logic                          bready,

  // Read Address channel
  input  logic [AXI_ID_WIDTH-1:0]       arid,
  input  logic [AXI_ADDR_WIDTH-1:0]     araddr,
  input  logic [7:0]                    arlen,
  input  logic [2:0]                    arsize,
  input  logic [1:0]                    arburst,
  /* verilator lint_off UNUSED */
  input  logic                          arlock,
  input  logic [3:0]                    arcache,
  /* verilator lint_on UNUSED */
  input  logic [2:0]                    arprot,
  /* verilator lint_off UNUSED */
  input  logic [3:0]                    arqos,
  input  logic [3:0]                    arregion,
  /* verilator lint_on UNUSED */
  // input  logic [5:0]                    aratop,
  // input  logic [AXI_AR_USER:0]          aruser,
  input  logic                          arvalid,
  output logic                          arready,

  // Read data channel
  output logic [AXI_ID_WIDTH-1:0]       rid,
  output logic [AXI_DATA_WIDTH-1:0]     rdata,
  output logic [1:0]                    rresp,
  output logic                          rlast,
  output logic                          rvalid,
  input  logic                          rready,

  // RIF full interface

  // RIF write channel
  output logic [AXI_ADDR_WIDTH-1:0]     rif_waddr,
  input  logic                          rif_wvalid,
  output logic                          rif_wr_req,
  output logic [AXI_BYTE_COUNT-1:0]     rif_wstrb,
  output logic [AXI_DATA_WIDTH-1:0]     rif_wdata,

  // RIF read channel
  output logic [AXI_ADDR_WIDTH-1:0]     rif_raddr,
  input  logic                          rif_rvalid,
  output logic                          rif_rd_req,
  input  logic [AXI_DATA_WIDTH-1:0]     rif_rdata
);

  //----------------------------------------------------------------------------
  // localparams
  //----------------------------------------------------------------------------

  // only used AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWPROT[1] (SECURE BIT)
  localparam AW_DW = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 13 + integer'(EN_SEC_MODE);
  // only used ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARPROT[1] (SECURE BIT)
  // localparam AR_DW = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 13 + integer'(EN_SEC_MODE);

  localparam DSIZE = $clog2(AXI_DATA_WIDTH) - 3;

  // If the AXI_DATA_WIDTH of an axi4_adapter instance doesn't meet the condition,
  // it will fail at optimization/elaboration.
  if (($clog2(AXI_DATA_WIDTH) < 3) || (2 ** $clog2(AXI_DATA_WIDTH) != AXI_DATA_WIDTH)) begin
    $fatal(1, "AXI4 Adapter expected DATA_WIDTH >= 8-bit and be a power of 2, but got DATA_WIDTH = %d", AXI_DATA_WIDTH);
  end

  //----------------------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------------------

  logic                         reset;

  // registered AW* from the AW BUFFER output aw_buffer
  logic [AXI_ID_WIDTH-1:0]      awid_q;
  logic [7:0]                   awlen_q;
  logic [2:0]                   awsize_q;
  logic [1:0]                   awburst_q;
  logic                         aw_sec;

  // WR burst addr
  logic [AXI_ADDR_WIDTH-1:0]    waddr;
  logic [AXI_ADDR_WIDTH-1:0]    next_wr_addr;
  logic [AXI_ADDR_WIDTH-1:0]    next_waddr;

  logic                         wready_d;

  // bvalid/bid skid buffer logic signal
  logic                         i_bvalid;
  logic [AXI_ID_WIDTH-1:0]      i_bid;

  // last w beat
  logic                         w_beat_last;
  // waiting for bready
  logic                         b_wait;

  // registered AR*
  logic [7:0]                   arlen_q;
  logic [2:0]                   arsize_q;
  logic [1:0]                   arburst_q;
  logic                         arport_0_q;
  logic                         ar_sec;

  // WR burst addr
  logic [AXI_ADDR_WIDTH-1:0]    raddr;
  logic [AXI_ADDR_WIDTH-1:0]    next_raddr;

  // AR axi_addr input ARREADY ? AR* : AR*_Q
  logic [AXI_ID_WIDTH-1:0]      i_rid;
  logic [AXI_ADDR_WIDTH-1:0]    i_raddr;
  logic [7:0]                   i_rlen;
  logic [2:0]                   i_rsize;
  logic [1:0]                   i_rburst;

  logic [AXI_ID_WIDTH-1:0]      rid_d;
  logic [AXI_DATA_WIDTH-1:0]    rdata_d;
  logic                         rlast_d;
  logic                         rd_req;

  // RD burst counter
  logic                         load_r_cnt;
  logic                         en_r_cnt_4_0;
  logic                         en_r_cnt_8_5;
  logic [8:0]                   r_cnt;
  logic [4:0]                   r_cnt_4_0;
  logic [3:0]                   r_cnt_8_5;
  logic [8:0]                   next_r_cnt;

  // XRESP[1] error bit
  logic                         wr_err;
  logic                         rd_err;
  logic                         rif_w_err;
  logic                         rif_r_err;
  logic                         rresp_0;

  // aw_buffer signals
  logic [AW_DW-1:0]             aw_buf_wdata;
  logic [AW_DW-1:0]             aw_buf_rdata;
  logic                         aw_buf_wready;
  logic                         aw_buf_wvalid;
  logic                         aw_buf_rready;
  logic                         aw_buf_rvalid;

  logic                         aw_buf_rready_d;
  logic                         i_aw_buf_rready;

  assign reset = ~aresetn;

  //============================================================================
  // AXI WRITE PART
  //============================================================================

  // AW BUFFER *data
  if (EN_SEC_MODE) begin : g_buf_data_with_sec
    assign aw_buf_wdata = {awaddr, awlen, awsize, awburst, awprot[1], awid};
    assign awid_q = aw_buf_rdata[0+:AXI_ID_WIDTH];
  end : g_buf_data_with_sec
  else begin : g_buf_data
    assign aw_buf_wdata = {awaddr, awlen, awsize, awburst, awid};
    assign awid_q = aw_buf_rdata[0+:AXI_ID_WIDTH];
  end : g_buf_data

  //----------------------------------------------------------------------------
  // AW buffer
  //----------------------------------------------------------------------------

  assign aw_buf_wvalid = awvalid;
  assign awready = aw_buf_wready;

  sync_fifo #(
    .FALL_THROUGH   (~DECOUPLE_W),
    .DATA_WIDTH     (AW_DW),
    .DEPTH          (1)
  ) u_aw_buf (
    .clk            (aclk),
    .reset          (reset),

    .flush          (1'b0),

    .wdata          (aw_buf_wdata),
    .wvalid         (aw_buf_wvalid),
    .wready         (aw_buf_wready),

    .rdata          (aw_buf_rdata),
    .rvalid         (aw_buf_rvalid),
    .rready         (aw_buf_rready),

    /* verilator lint_off PINCONNECTEMPTY */
    .data_count     (),
    .empty          (),
    .full           ()
    /* verilator lint_on PINCONNECTEMPTY */
  );

  //----------------------------------------------------------------------------
  // aw buffer pop logic
  //----------------------------------------------------------------------------

  always_comb begin : comb_aw_buf_rready
    aw_buf_rready = i_aw_buf_rready;
    if (wvalid && wready && wlast && (!bvalid || bready))
      aw_buf_rready = 1'b1;
  end : comb_aw_buf_rready

  always_comb begin : c_aw_buf_rready_d
    aw_buf_rready_d = i_aw_buf_rready;
    if (aw_buf_rready && aw_buf_rvalid) begin
      aw_buf_rready_d = 1'b0;
    end
    else if (wvalid & wready) begin
      aw_buf_rready_d = wlast & (~bvalid | bready);
    end
    else if (!awready) begin
      if (wready || (i_bvalid && !bready)) begin
        aw_buf_rready_d = 1'b0;
      end
      else begin
        aw_buf_rready_d = 1'b1;
      end
    end
  end : c_aw_buf_rready_d

  always_ff @(posedge aclk or negedge aresetn) begin : ff_i_aw_buf_rready
    if (!aresetn) begin
      i_aw_buf_rready <= 1'b1;
    end
    else if (aw_buf_rready_d ^ i_aw_buf_rready) begin
      i_aw_buf_rready <= aw_buf_rready_d;
    end
  end : ff_i_aw_buf_rready

  //----------------------------------------------------------------------------
  // write channel control
  //----------------------------------------------------------------------------

  always_comb begin : comb_wready
    wready_d = wready;
    if (aw_buf_rready && aw_buf_rvalid) begin
      wready_d = 1'b1;
    end
    else if (wvalid & wready & wlast) begin
      wready_d = 1'b0;
    end
  end : comb_wready

  always_ff @(posedge aclk or negedge aresetn) begin : ff_wready
    if (!aresetn) begin
      wready <= 1'b0;
    end
    else if (wready ^ wready_d) begin
      wready <= wready_d;
    end
  end : ff_wready

  // registered data from aw buffer
  if (EN_SEC_MODE) begin : g_ff_sec_aw
    always_ff @(posedge aclk or negedge aresetn) begin : ff_aw
      if (!aresetn) begin
        awlen_q   <= '0;
        awsize_q  <= '0;
        awburst_q <= '0;
      end
      else if (aw_buf_rready) begin
        {awlen_q, awsize_q, awburst_q, aw_sec} <= aw_buf_rdata[AW_DW-AXI_ADDR_WIDTH-1:AXI_ID_WIDTH];
      end
    end : ff_aw
  end
  else begin : g_ff_aw
    always_ff @(posedge aclk or negedge aresetn) begin : ff_aw
      if (!aresetn) begin
        awlen_q   <= '0;
        awsize_q  <= '0;
        awburst_q <= '0;
      end
      else if (aw_buf_rready) begin
        {awlen_q, awsize_q, awburst_q} <= aw_buf_rdata[AW_DW-AXI_ADDR_WIDTH-1:AXI_ID_WIDTH];
      end
    end : ff_aw
  end : g_ff_aw

  //----------------------------------------------------------------------------
  // waddr logic
  //----------------------------------------------------------------------------

  always_comb begin : comb_waddr
    next_waddr = waddr;
    if (aw_buf_rready) begin
      next_waddr = aw_buf_rdata[AW_DW-1:AW_DW-AXI_ADDR_WIDTH];
    end
    else if (wvalid) begin
      next_waddr = next_wr_addr;
    end
  end : comb_waddr

  always_ff @(posedge aclk or negedge aresetn) begin : ff_waddr
    if (!aresetn) begin
      waddr <= '0;
    end
    else if (aw_buf_rready || wvalid) begin
      waddr <= next_waddr;
    end
  end : ff_waddr

  axi_addr #(
    .ALIGN_ADDR   (ALIGN_ADDR),
    .ADDR_WIDTH   (AXI_ADDR_WIDTH),
    .DATA_WIDTH   (AXI_DATA_WIDTH)
  ) u_axi_waddr (
  	.addr         (waddr),
    .burst        (awburst_q),
    .size         (awsize_q),
    .len          (awlen_q),
    .next_addr    (next_wr_addr)
  );

  //----------------------------------------------------------------------------
  // RIF write channel
  //----------------------------------------------------------------------------

  assign rif_wr_req = (~EN_SEC_MODE | aw_sec) & wvalid & wready;
  // REALIGNMENT FOR AWSIZE < DSIZE, using WSTRB for properly writing data.
  assign rif_waddr  = (DSIZE > 0) ?
    {waddr[AXI_ADDR_WIDTH-1:DSIZE], {(DSIZE){1'b0}}} : waddr;
  assign rif_wdata  = wdata;
  assign rif_wstrb  = wstrb;

  if (NO_SEC_FAIL) begin : g_w_err
    assign rif_w_err = (EN_SEC_MODE) ? (aw_sec & ~rif_wvalid) : ~rif_wvalid;
  end : g_w_err
  else begin : g_sec_w_err
    assign rif_w_err  = EN_SEC_MODE ? (~aw_sec | ~rif_wvalid) : ~rif_wvalid;
  end : g_sec_w_err

  //----------------------------------------------------------------------------
  // BRESP[1]
  //----------------------------------------------------------------------------

  assign bresp[1] = (bvalid) ? wr_err : 1'b0;
  assign bresp[0] = 1'b0;

  always_ff @(posedge aclk or negedge aresetn) begin : ff_wr_err
    if (!aresetn) begin
      wr_err <= 1'b0;
    end
    else if (wvalid & wready) begin
      wr_err <= wr_err | rif_w_err;
    end
    else if (bready) begin
      wr_err <= 1'b0;
    end
  end : ff_wr_err

  //----------------------------------------------------------------------------
  // B channel
  //----------------------------------------------------------------------------

  assign b_wait = bvalid & ~bready;
  assign w_beat_last = wvalid & wready & wlast;

  // BVALID skid buffer internal logic
  always_ff @(posedge aclk or negedge aresetn) begin : ff_i_bvalid
    if (!aresetn) begin
      i_bvalid <= 1'b0;
    end
    else if (w_beat_last && b_wait) begin
      i_bvalid <= 1'b1;
    end
  end : ff_i_bvalid

  // BVALID
  always_ff @(posedge aclk or negedge aresetn) begin : ff_bvalid
    if (!aresetn) begin
      bvalid <= 1'b0;
    end
    else if (w_beat_last) begin
      bvalid <= 1'b1;
    end
    else if (bready) begin
      bvalid <= i_bvalid;
    end
  end : ff_bvalid

  // BID skid buffer logic
  always_ff @(posedge aclk or negedge aresetn) begin : ff_i_bid
    if (!aresetn) begin
      i_bid <= '0;
    end
    else if (aw_buf_rready) begin
      i_bid <= awid_q;
    end
  end: ff_i_bid

  // BID
  always_ff @(posedge aclk or negedge aresetn) begin : ff_bid
    if (!aresetn) begin
      bid <= '0;
    end
    else if (!bvalid || bready) begin
      bid <= i_bid;
    end
  end: ff_bid

  //============================================================================
  // AXI READ PART
  //============================================================================

  // ARREADY
  always_ff @(posedge aclk or negedge aresetn) begin : ff_aready
    if (!aresetn) begin
      arready <= 1'b1;
    end
    else if (arready & arvalid) begin
      arready <= (arlen == 0) & rd_req;
    end
    // ((!rvalid || rready) && (!arready && rvalid))
    else if (rready && rvalid && !arready) begin
      arready <= (r_cnt <= 2);
    end
  end : ff_aready

  //----------------------------------------------------------------------------
  // R COUNTER
  //----------------------------------------------------------------------------

  assign r_cnt = {r_cnt_8_5, r_cnt_4_0};
  always_comb begin : comb_r_cnt
    next_r_cnt = r_cnt;
    if (load_r_cnt) begin
      next_r_cnt = (arlen + 1) + ((rvalid && !rready) ? 1 : 0);
    end
    else if (rready && rvalid) begin
      next_r_cnt = r_cnt - 1;
    end
  end : comb_r_cnt

  // TODO: refine update
  assign load_r_cnt = arvalid & arready;
  assign en_r_cnt_4_0 = load_r_cnt | (rready & rvalid);
  assign en_r_cnt_8_5 = en_r_cnt_4_0 & (&r_cnt_4_0);

  always_ff @(posedge aclk or negedge aresetn) begin : ff_r_cnt_4_0
    if (!aresetn) begin
      r_cnt_4_0 <= '0;
    end
    else if (en_r_cnt_4_0) begin
      r_cnt_4_0 <= next_r_cnt[4:0];
    end
  end : ff_r_cnt_4_0

  always_ff @(posedge aclk or negedge aresetn) begin : ff_r_cnt_8_5
    if (!aresetn) begin
      r_cnt_8_5 <= '0;
    end
    else if (en_r_cnt_8_5) begin
      r_cnt_8_5 <= next_r_cnt[8:5];
    end
  end : ff_r_cnt_8_5

  //----------------------------------------------------------------------------
  // raddr
  //----------------------------------------------------------------------------

  assign i_raddr  = arready ? araddr  : raddr;
  assign i_rlen   = arready ? arlen   : arlen_q;
  assign i_rsize  = arready ? arsize  : arsize_q;
  assign i_rburst = arready ? arburst : arburst_q;

  always_ff @(posedge aclk or negedge aresetn) begin : ff_raddr
    if (!aresetn) begin
      raddr <= '0;
    end
    else if (rd_req) begin
      raddr <= next_raddr;
    end
    else if (arready) begin
      raddr <= araddr;
    end
  end : ff_raddr

  always_ff @(posedge aclk or negedge aresetn) begin : ff_ar
    if (!aresetn) begin
      arburst_q   <= '0;
      arsize_q    <= '0;
      arlen_q     <= '0;
      arport_0_q  <= '0;
    end
    else if (arready) begin
      arburst_q   <= arburst;
      arsize_q    <= arsize;
      arlen_q     <= arlen;
      arport_0_q  <= arprot[1];
    end
  end : ff_ar

  axi_addr #(
    .ALIGN_ADDR   (ALIGN_ADDR),
    .ADDR_WIDTH   (AXI_ADDR_WIDTH),
    .DATA_WIDTH   (AXI_DATA_WIDTH)
  ) u_axi_raddr (
  	.addr         (i_raddr),
    .burst        (i_rburst),
    .size         (i_rsize),
    .len          (i_rlen),
    .next_addr    (next_raddr)
  );

  //----------------------------------------------------------------------------
  // RID
  //----------------------------------------------------------------------------

  always_ff @(posedge aclk or negedge aresetn) begin : ff_i_rid
    if (!aresetn) begin
      i_rid <= '0;
    end
    else if (arready) begin
      i_rid <= arid;
    end
  end : ff_i_rid

  always_comb begin : comb_rid
    rid_d = rid;
    if (arvalid & arready) begin
      rid_d = arid;
    end
    else begin
      rid_d = i_rid;
    end
  end : comb_rid

  always_ff @(posedge aclk or negedge aresetn) begin : ff_rid
    if (!aresetn) begin
      rid <= '0;
    end
    else if (!arvalid || arready) begin
      rid <= rid_d;
    end
  end : ff_rid

  //----------------------------------------------------------------------------
  // RVALID
  //----------------------------------------------------------------------------

  always_ff @(posedge aclk or negedge aresetn) begin : ff_rvalid
    if (!aresetn) begin
      rvalid <= 1'b0;
    end
    else if (rd_req) begin
      rvalid <= 1'b1;
    end
    else if (rready) begin
      rvalid <= 1'b0;
    end
  end : ff_rvalid

  //----------------------------------------------------------------------------
  // RDATA
  //----------------------------------------------------------------------------

  always_ff @(posedge aclk or negedge aresetn) begin : ff_rdata
    if (!aresetn) begin
      rdata <= '0;
    end
    else if (rd_req) begin
      rdata <= rdata_d;
    end
  end : ff_rdata

  //----------------------------------------------------------------------------
  // RLAST
  //----------------------------------------------------------------------------

  always_comb begin : comb_rlast
    rlast_d = rlast;
    if (!rvalid || rready) begin
      if (arvalid && arready) begin
        rlast_d = (arlen == 0);
      end
      else if (rvalid) begin
        rlast_d = (r_cnt == 2);
      end
      else begin
        rlast_d = (r_cnt == 1);
      end
    end
  end : comb_rlast

  always_ff @(posedge aclk or negedge aresetn) begin : ff_rlast
    if (!aresetn) begin
      rlast <= 1'b0;
    end
    else if (rlast_d ^ rlast) begin
      rlast <= rlast_d;
    end
  end : ff_rlast

  //----------------------------------------------------------------------------
  // RIF read channel
  //----------------------------------------------------------------------------

  always_comb begin : comb_rd_req
    rd_req = arvalid | ~arready;
    if (rvalid && !rready) begin
      rd_req = 1'b0;
    end
  end : comb_rd_req

  assign ar_sec = arready ? arprot[1] : arport_0_q;
  assign rif_raddr = arready ? araddr : raddr;
  assign rif_rd_req = (~EN_SEC_MODE | ar_sec) & rd_req;
  assign rdata_d = (EN_SEC_MODE) ? (ar_sec ? rif_rdata : '0) : rif_rdata;
  assign rresp_0 = 1'b0;
  assign rresp = {rd_err, rresp_0};

  if (NO_SEC_FAIL) begin : g_r_err
    assign rif_r_err = (EN_SEC_MODE) ? (ar_sec & ~rif_rvalid) : ~rif_rvalid;
  end : g_r_err
  else begin : g_sec_r_err
    assign rif_r_err = (EN_SEC_MODE) ? (~ar_sec | ~rif_rvalid) : ~rif_rvalid;
  end : g_sec_r_err

  always_ff @(posedge aclk or negedge aresetn) begin : ff_rd_err
    if (!aresetn) begin
      rd_err <= 1'b0;
    end
    else if (rd_req) begin
      rd_err <= rif_r_err;
    end
    else if (rd_err) begin
      rd_err <= 1'b0;
    end
  end : ff_rd_err

endmodule: axi4_adapter
