`timescale 1ns/1ps

module axi4_lite_adapter #(
  parameter integer                     AXI_ID_WIDTH = 1,
  parameter integer                     AXI_ADDR_WIDTH = 12,
  parameter integer                     AXI_DATA_WIDTH = 32,
  // Buffer depth, control how many outstanding transactions do we allow)
  parameter integer                     BUFFER_DEPTH = 2,
  // Set this block to the security memory space.
  // If this parameter is asserted, The AXI Lite bus will only have access to
  // the register when AxPROT[1] is high.
  parameter bit                         EN_SEC_MODE = 1,
  parameter integer                     AXI_BYTE_COUNT = AXI_DATA_WIDTH / 8
) (
  input  logic                          aclk,
  input  logic                          aresetn,

  // Write Address channel
  input  logic [AXI_ID_WIDTH-1:0]       awid,
  input  logic [AXI_ADDR_WIDTH-1:0]     awaddr,
  /* verilator lint_off UNUSED */
  input  logic [2:0]                    awprot,
  /* verilator lint_on UNUSED */
  input  logic                          awvalid,
  output logic                          awready,

  // Write data channel
  input  logic [AXI_DATA_WIDTH-1:0]     wdata,
  input  logic [AXI_BYTE_COUNT-1:0]     wstrb,
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
  /* verilator lint_off UNUSED */
  input  logic [2:0]                    arprot,
  /* verilator lint_off UNUSED */
  input  logic                          arvalid,
  output logic                          arready,

  // Read data channel
  output logic [AXI_ID_WIDTH-1:0]       rid,
  output logic [AXI_DATA_WIDTH-1:0]     rdata,
  output logic [1:0]                    rresp,
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

  // DATA Width for the FIFO parameters
  localparam W_DATA_WIDTH  = AXI_ID_WIDTH + AXI_ADDR_WIDTH + AXI_DATA_WIDTH + AXI_DATA_WIDTH / 8 + integer'(EN_SEC_MODE);
  localparam B_DATA_WIDTH  = AXI_ID_WIDTH + 1;
  localparam AR_DATA_WIDTH = AXI_ID_WIDTH + AXI_ADDR_WIDTH + integer'(EN_SEC_MODE);
  localparam R_DATA_WIDTH  = AXI_ID_WIDTH + AXI_DATA_WIDTH + 1;

  // If the BUFFER_DEPTH of an axi4_lite_adapter instance doesn't meet the condition,
  // it will fail at optimization/elaboration.
  if (BUFFER_DEPTH < 1) begin
    $fatal(1, "AXI4 Lite Adapter expected BUFFER_DEPTH > 0, but got BUFFER_DEPTH = %d", BUFFER_DEPTH);
  end


  //----------------------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------------------

  logic                         reset;

  // Mirror back AxID to xID
  logic [AXI_ID_WIDTH-1:0]      bid_in;
  logic [AXI_ID_WIDTH-1:0]      rid_in;

  // waddr & wdata & strb from the FIFO output wFIFO -> RIF W channel
  logic [AXI_ADDR_WIDTH-1:0]    i_waddr;
  logic [AXI_DATA_WIDTH-1:0]    i_wdata;
  logic [AXI_DATA_WIDTH/8-1:0]  i_wstrb;
  logic                         i_wr_err;

  // raddr from the arFIFO rdata arFIFO -> RIF R channel
  logic [AXI_ADDR_WIDTH-1:0]    i_raddr;
  logic [AXI_DATA_WIDTH-1:0]    i_rdata;
  logic                         i_rd_err;

  // AxPROT security bit from wFIFO/arFIFO
  logic                         aw_sec;
  logic                         ar_sec;

  // xRESP[1] bit from bFIFO/rFIFO
  logic                         wr_err;
  logic                         rd_err;


  // wFIFO signals
  logic [W_DATA_WIDTH-1:0]      w_fifo_wdata;
  logic [W_DATA_WIDTH-1:0]      w_fifo_rdata;
  logic                         w_fifo_wready;
  logic                         w_fifo_wvalid;
  logic                         w_fifo_rready;
  logic                         w_fifo_rvalid;

  // bFIFO signals
  logic [B_DATA_WIDTH-1:0]      b_fifo_wdata;
  logic [B_DATA_WIDTH-1:0]      b_fifo_rdata;
  logic                         b_fifo_wready;
  logic                         b_fifo_wvalid;
  logic                         b_fifo_rready;
  logic                         b_fifo_rvalid;

  // arFIFO signals
  logic [AR_DATA_WIDTH-1:0]     ar_fifo_wdata;
  logic [AR_DATA_WIDTH-1:0]     ar_fifo_rdata;
  logic                         ar_fifo_wready;
  logic                         ar_fifo_wvalid;
  logic                         ar_fifo_rready;
  logic                         ar_fifo_rvalid;

  // rFIFO signals
  logic [R_DATA_WIDTH-1:0]      r_fifo_wdata;
  logic [R_DATA_WIDTH-1:0]      r_fifo_rdata;
  logic                         r_fifo_wready;
  logic                         r_fifo_wvalid;
  logic                         r_fifo_rready;
  logic                         r_fifo_rvalid;

  assign reset = ~aresetn;

  //----------------------------------------------------------------------------
  // FIFOs data port connections
  //----------------------------------------------------------------------------

  if (AXI_ID_WIDTH > 0 && EN_SEC_MODE) begin : g_fifo_data_with_id_sec
    // wFIFO
    assign w_fifo_wdata = { awid, awaddr, wdata, wstrb, awprot[1] };
    assign { bid_in, i_waddr, i_wdata, i_wstrb, aw_sec } = w_fifo_rdata;

    // bFIFO
    assign b_fifo_wdata = { bid_in, i_wr_err };
    assign { bid, wr_err } = b_fifo_rdata;

    // arFIFO
    assign ar_fifo_wdata = { arid, araddr, arprot[1] };
    assign { rid_in, i_raddr, ar_sec } = ar_fifo_rdata;

    // rFIFO
    assign r_fifo_wdata = { rid_in, i_rdata, i_rd_err };
    assign { rid, rdata, rd_err } = r_fifo_rdata;
  end : g_fifo_data_with_id_sec
  else if (AXI_ID_WIDTH > 0 && !EN_SEC_MODE) begin : g_fifo_data_with_id
    // wFIFO
    assign w_fifo_wdata = {awid, awaddr, wdata, wstrb};
    assign {bid_in, i_waddr, i_wdata, i_wstrb } = w_fifo_rdata;

    // bFIFO
    assign b_fifo_wdata = { bid_in, i_wr_err };
    assign { bid, wr_err } = b_fifo_rdata;

    // arFIFO
    assign ar_fifo_wdata = { arid, araddr };

    assign { rid_in, i_raddr } = ar_fifo_rdata;

    // rFIFO
    assign r_fifo_wdata = { rid_in, i_rdata, i_rd_err };
    assign { rid, rdata, rd_err } = r_fifo_rdata;
  end : g_fifo_data_with_id
  else if (AXI_ID_WIDTH <= 0 && EN_SEC_MODE) begin : g_fifo_data_with_sec
    // wFIFO
    assign w_fifo_wdata = { awaddr, wdata, wstrb, awprot[1] };
    assign { i_waddr, i_wdata, i_wstrb, aw_sec } = w_fifo_rdata;

    // bFIFO
    assign b_fifo_wdata = i_wr_err;
    assign wr_err = b_fifo_rdata;

    // arFIFO
    assign ar_fifo_wdata = { araddr, arprot[1] };
    assign { i_raddr, ar_sec } = ar_fifo_rdata;

    // rFIFO
    assign r_fifo_wdata = { i_rdata, i_rd_err };
    assign { rdata, rd_err } = r_fifo_rdata;
  end : g_fifo_data_with_sec
  else begin : g_fifo_data
    // wFIFO
    assign w_fifo_wdata = { awaddr, wdata, wstrb };
    assign { i_waddr, i_wdata, i_wstrb } = w_fifo_rdata;

    // bFIFO
    assign b_fifo_wdata = i_wr_err;
    assign wr_err = b_fifo_rdata;

    // arFIFO
    assign ar_fifo_wdata = araddr;
    assign i_raddr = ar_fifo_rdata;

    // rFIFO
    assign r_fifo_wdata = { i_rdata, i_rd_err };
    assign { rdata, rd_err } = r_fifo_rdata;
  end : g_fifo_data

  //----------------------------------------------------------------------------
  // RIF signals
  //----------------------------------------------------------------------------

  // RIF write channel
  assign rif_waddr  = i_waddr;
  assign i_wr_err   = (EN_SEC_MODE) ? (~aw_sec & ~rif_wvalid) : ~rif_wvalid;
  assign rif_wr_req = w_fifo_rvalid  & b_fifo_wready;

  if (EN_SEC_MODE) begin : g_sec_wr
    assign rif_wdata = aw_sec ? i_wdata : '0;
    assign rif_wstrb = aw_sec ? i_wstrb : '0;
  end : g_sec_wr
  else begin : g_no_sec_wr
    assign rif_wdata = i_wdata;
    assign rif_wstrb = i_wstrb;
  end : g_no_sec_wr

  // RIF read channel
  assign rif_raddr  = i_raddr;
  assign i_rd_err   = (EN_SEC_MODE) ? (~ar_sec & ~rif_rvalid) : ~rif_rvalid;
  assign rif_rd_req = ar_fifo_rvalid & r_fifo_wready;

  if (EN_SEC_MODE) begin : g_sec_rd
    assign i_rdata = ar_sec ? rif_rdata : '0;
  end : g_sec_rd
  else begin : g_no_sec_rd
    assign i_rdata = rif_rdata;
  end : g_no_sec_rd


  //----------------------------------------------------------------------------
  // AXI AW & W channel <-> wFIFO
  // Combine AW and W channel
  //----------------------------------------------------------------------------

  assign awready = w_fifo_wvalid;
  assign wready = w_fifo_wready;
  assign w_fifo_rready = rif_wr_req;
  assign w_fifo_wvalid = awvalid & wvalid & w_fifo_wready;

  sync_fifo #(
    .FALL_THROUGH   (1'b1),
    .DATA_WIDTH     (W_DATA_WIDTH),
    .DEPTH          (BUFFER_DEPTH)
  ) u_w_fifo(
    .clk            (aclk),
    .reset          (reset),

    .flush          (1'b0),

    .wdata          (w_fifo_wdata),
    .wvalid         (w_fifo_wvalid),
    .wready         (w_fifo_wready),

    .rdata          (w_fifo_rdata),
    .rvalid         (w_fifo_rvalid),
    .rready         (w_fifo_rready),

    /* verilator lint_off PINCONNECTEMPTY */
    .data_count     (),
    .empty          (),
    .full           ()
    /* verilator lint_on PINCONNECTEMPTY */
  );

  //----------------------------------------------------------------------------
  // AXI B channel <-> bFIFO
  //----------------------------------------------------------------------------

  assign bresp = {wr_err, 1'b0};
  assign bvalid = b_fifo_rvalid;
  assign b_fifo_rready = bvalid & bready;
  assign b_fifo_wvalid = rif_wr_req;

  sync_fifo #(
    .FALL_THROUGH   (1'b1),
    .DATA_WIDTH     (B_DATA_WIDTH),
    .DEPTH          (BUFFER_DEPTH)
  ) u_b_fifo(
    .clk            (aclk),
    .reset          (reset),

    .flush          (1'b0),

    .wdata          (b_fifo_wdata),
    .wvalid         (b_fifo_wvalid),
    .wready         (b_fifo_wready),

    .rdata          (b_fifo_rdata),
    .rvalid         (b_fifo_rvalid),
    .rready         (b_fifo_rready),

    /* verilator lint_off PINCONNECTEMPTY */
    .data_count     (),
    .empty          (),
    .full           ()
    /* verilator lint_on PINCONNECTEMPTY */
  );

  //----------------------------------------------------------------------------
  // AXI AR channel <-> arFIFO
  //----------------------------------------------------------------------------

  assign arready = ar_fifo_wready;
  assign ar_fifo_rready = rif_rd_req;
  assign ar_fifo_wvalid = arvalid & arready;

  sync_fifo #(
    .DATA_WIDTH     (AR_DATA_WIDTH),
    .DEPTH          (BUFFER_DEPTH)
  ) u_ar_fifo(
    .clk            (aclk),
    .reset          (reset),

    .flush          (1'b0),

    .wdata          (ar_fifo_wdata),
    .wvalid         (ar_fifo_wvalid),
    .wready         (ar_fifo_wready),

    .rdata          (ar_fifo_rdata),
    .rvalid         (ar_fifo_rvalid),
    .rready         (ar_fifo_rready),

    /* verilator lint_off PINCONNECTEMPTY */
    .data_count     (),
    .empty          (),
    .full           ()
    /* verilator lint_on PINCONNECTEMPTY */
  );

  //----------------------------------------------------------------------------
  // AXI R channel <-> rFIFO
  //----------------------------------------------------------------------------

  assign rresp = {rd_err, 1'b1};
  assign rvalid = r_fifo_rvalid;
  assign r_fifo_rready = rvalid & rready;
  assign r_fifo_wvalid = rif_rd_req;


  sync_fifo #(
    .DATA_WIDTH     (R_DATA_WIDTH),
    .DEPTH          (BUFFER_DEPTH)
  ) u_r_fifo(
    .clk            (aclk),
    .reset          (reset),

    .flush          (1'b0),

    .wdata          (r_fifo_wdata),
    .wvalid         (r_fifo_wvalid),
    .wready         (r_fifo_wready),

    .rdata          (r_fifo_rdata),
    .rvalid         (r_fifo_rvalid),
    .rready         (r_fifo_rready),

    /* verilator lint_off PINCONNECTEMPTY */
    .data_count     (),
    .empty          (),
    .full           ()
    /* verilator lint_on PINCONNECTEMPTY */
  );

endmodule : axi4_lite_adapter
