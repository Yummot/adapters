`timescale 1ns/1ps

module axi4_lite_adapter_old #(
  parameter integer                     AXI_ID_WIDTH = 0,
  parameter integer                     AXI_ADDR_WIDTH = 12,
  parameter integer                     AXI_DATA_WIDTH = 32,
  parameter integer                     AXI_BYTE_COUNT = AXI_DATA_WIDTH / 8
) (
  input  logic                          aclk,
  input  logic                          aresetn,

  // Write Address channel
  input  logic [AXI_ID_WIDTH-1:0]       awid,
  input  logic [AXI_ADDR_WIDTH-1:0]     awaddr,
  input  logic [2:0]                    awprot,
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
  input  logic [2:0]                    arprot,
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
  // Internal signals
  //----------------------------------------------------------------------------

  // The aw channel enable, indicates that the aw channel is ready for
  // the next transfer.
  logic aw_en;
  logic i_bresp_0, i_bresp_1;
  logic i_rresp_0, i_rresp_1;

  //----------------------------------------------------------------------------
  // The AXI4 Lite AW channel
  //----------------------------------------------------------------------------

  always_ff @(posedge aclk or negedge aresetn) begin : ff_aw_en
    if (!aresetn) begin
      aw_en <= 1'b1;
    end
    else if (~awready & awvalid & wvalid & aw_en) begin
      // find a pending axi wr tranfer
      aw_en <= 1'b0;
    end
    else if (bvalid & bready) begin
      // the pending axi wr transfer is done.
      aw_en <= 1'b1;
    end
  end : ff_aw_en

  // AWREADY
  always_ff @(posedge aclk or negedge aresetn) begin : ff_awready
    if (!aresetn) begin
      awready <= 1'b0;
    end
    else if (~awready & awvalid & wvalid & aw_en) begin
      awready <= 1'b1;
    end
    else if (bvalid & bready) begin
      awready <= 1'b0;
    end
    else if (awready) begin
      awready <= 1'b0;
    end
  end : ff_awready

  // Register the awaddr to rif_waddr
  always_ff @(posedge aclk or negedge aresetn) begin : ff_rif_waddr
    if (!aresetn) begin
      rif_waddr <= '0;
    end
    else if (~awready & awvalid & wvalid & aw_en) begin
      rif_waddr <= awaddr;
    end
  end : ff_rif_waddr

  //----------------------------------------------------------------------------
  // The AXI4 Lite W channel
  //----------------------------------------------------------------------------

  assign rif_wr_req = awready & awvalid & wvalid & wready;

  // WREADY
  always_ff @(posedge aclk or negedge aresetn) begin : ff_wready
    if (!aresetn) begin
      wready <= 1'b0;
    end
    else if (~awready & awvalid & wvalid & aw_en) begin
      wready <= 1'b1;
    end
    else if (wready) begin
      wready <= 1'b0;
    end
  end : ff_wready

  // RIF WDATA and WSTRB
  always_ff @(posedge aclk or negedge aresetn) begin : ff_rif_w
    if (!aresetn) begin
      rif_wdata <= '0;
      rif_wstrb <= '0;
    end
    else if (~awready & awvalid & wvalid & aw_en) begin
      rif_wdata <= wdata;
      rif_wstrb <= wstrb;
    end
  end : ff_rif_w

  //----------------------------------------------------------------------------
  // The AXI4 Lite B channel
  //----------------------------------------------------------------------------

  // BID
  if (AXI_ID_WIDTH > 0) begin :  g_bid
    always_ff @(posedge aclk or negedge aresetn) begin : ff_bid
      if (!aresetn) begin
        bid <= '0;
      end
      else if (awvalid & awready & ~bvalid) begin
        bid <= awid;
      end
      else if (bvalid & bready) begin
        bid <= '0;
      end
    end : ff_bid
  end : g_bid

  always_ff @(posedge aclk or negedge aresetn) begin : ff_bvalid
    if (!aresetn) begin
      bvalid <= 1'b0;
    end
    else if (awvalid & awready & wvalid & wready & ~bvalid) begin
      bvalid <= 1'b1;
    end
    else if (bvalid & bready) begin
      bvalid <= 1'b0;
    end
  end : ff_bvalid

  // BRESP
  assign bresp = {i_bresp_1, i_bresp_0};
  assign i_bresp_0 = 1'b0;

  always_ff @(posedge aclk or negedge aresetn) begin : ff_bresp
    if (!aresetn) begin
      i_bresp_1 <= 1'b0;
    end
    else if (awvalid & awready & wvalid & wready & ~bvalid) begin
      i_bresp_1 <= ~rif_wvalid;
    end
    else if (bvalid & bready) begin
      i_bresp_1 <= 1'b0;
    end
  end : ff_bresp

  //----------------------------------------------------------------------------
  // The AXI4 Lite AR and R channels
  //----------------------------------------------------------------------------
  assign rif_rd_req = arvalid & arready;

  // RID
  if (AXI_ID_WIDTH > 0) begin : g_rid
    always_ff @(posedge aclk or negedge aresetn) begin : ff_rid
      if (!aresetn) begin
        rid <= '0;
      end
      else if (arvalid & ~arready) begin
        rid <= arid;
      end
      else if (rvalid && rready) begin
        rid <= '0;
      end
    end : ff_rid
  end : g_rid

    // Register ARADDR
  always_ff @(posedge aclk or negedge aresetn) begin : ff_rif_raddr
    if (!aresetn) begin
      rif_raddr <= '0;
    end
    else if (arvalid & ~arready) begin
      rif_raddr <= araddr;
    end
  end :ff_rif_raddr

  // ARREADY
  always_ff @(posedge aclk or negedge aresetn) begin : ff_arready
    if (!aresetn) begin
      arready <= 1'b0;
    end
    else if (arvalid & ~arready) begin
      arready <= 1'b1;
    end
    else if (arready) begin
      arready <= 1'b0;
    end
  end : ff_arready

  // RDATA
  always_ff @(posedge aclk or negedge aresetn) begin : ff_rdata
    if (!aresetn) begin
      rdata <= '0;
    end
    else if (arvalid & arready & ~rvalid) begin
      rdata <= rif_rdata;
    end
  end :ff_rdata

  // RVALID
  always_ff @(posedge aclk or negedge aresetn) begin : ff_rvalid
    if (!aresetn) begin
      rvalid <= 1'b0;
    end
    else if (arvalid & arready & ~rvalid) begin
      rvalid <= 1'b1;
    end
    else if (rvalid & rready) begin
      rvalid <= 1'b0;
    end
  end : ff_rvalid

  // RRESP, only uses OKAY (2'b00) and SLVERR (2'b10)
  assign rresp = {i_rresp_1, i_rresp_0};
  assign i_rresp_0 = 1'b0;

  always_ff @(posedge aclk or negedge aresetn) begin : ff_rresp
    if (!aresetn) begin
      i_rresp_1 <= '0;
    end
    else if (arvalid & arready & ~rvalid) begin
      i_rresp_1 <= ~rif_rvalid;
    end
    else if (rvalid & rready) begin
      i_rresp_1 <= '0;
    end
  end :ff_rresp

endmodule : axi4_lite_adapter_old
