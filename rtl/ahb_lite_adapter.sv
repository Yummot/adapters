//  Module: ahb_lite_adapter
//

`timescale 1ns/1ps

module ahb_lite_adapter #(
  parameter integer                     ADDR_WIDTH = 'd12,
  parameter integer                     DATA_WIDTH = 'd32,
  parameter bit                         SEC_TRANS  = 1'b0
)(
  input  logic                          HCLK,
  input  logic                          HCLKn,

  input  logic [ADDR_WIDTH-1:0]         HADDR,
  input  logic                          HSEL,
  input  logic                          HNONSEC,
  input  logic [2:0]                    HBURST,
  input  logic [2:0]                    HSIZE,
  input  logic [1:0]                    HTRANS,
  input  logic                          HWRITE,
  input  logic [DATA_WIDTH-1:0]         HWDATA,
  output logic [DATA_WIDTH-1:0]         HRDATA,
  output logic                          HRESP,
  input  logic                          HREADYIN,
  output logic                          HREADYOUT,

  output logic [ADDR_WIDTH-1:0]         rif_addr,
  input  logic                          rif_addr_valid,
  output logic                          rif_wr_req,
  output logic                          rif_rd_req,
  output logic [BYTE_COUNT-1:0]         rif_wstrb,
  output logic [DATA_WIDTH-1:0]         rif_wdata,
  input  logic [DATA_WIDTH-1:0]         rif_rdata
);

  //----------------------------------------------------------------------------
  // localparams and functions
  //----------------------------------------------------------------------------
  localparam integer STRB_WIDTH = DATA_WIDTH / 8;

  enum logic [1:0] { IDLE = 0, BUSY = 1, NONSEQ = 2, SEQ = 3 } htrans_t;

  // DATA WIDTH CHECK
  if ((DATA_WIDTH < 8) && (2 ** $clog2(DATA_WIDTH) != DATA_WIDTH)) begin
    $fatal(1, "AHB Lite Adapter expected DATA_WIDTH to be 8, 16, 32, 64, 128, 256, 512, or 1024-bit wides, but got BUFFER_DEPTH = %d", DATA_WIDTH);
  end

  //----------------------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------------------


endmodule: ahb_lite_adapter
