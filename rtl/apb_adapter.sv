`timescale 1ns/1ps

module apb_adapter #(
  parameter                             ADDR_WIDTH = 12,
  parameter                             DATA_WIDTH = 32,
  parameter bit                         BYTE_EN = 1'b0,
  parameter bit                         REPORT_ERROR = 1'b0,
  parameter                             BYTE_COUNT = DATA_WIDTH < 8 ? 1 : 2 ** ($clog2(DATA_WIDTH) - 3)
) (
  input  logic                          pclk,
  input  logic                          presetn,

  input  logic [ADDR_WIDTH-1:0]         paddr,
  input  logic                          psel,
  input  logic                          penable,
  input  logic                          pwrite,
  input  logic [BYTE_COUNT-1:0]         pstrb,
  input  logic [DATA_WIDTH-1:0]         pwdata,
  output logic [DATA_WIDTH-1:0]         prdata,
  output logic                          pready,
  output logic                          pslverr,

  output logic [ADDR_WIDTH-1:0]         rif_addr,
  input  logic                          rif_addr_valid,
  output logic                          rif_wr_req,
  output logic                          rif_rd_req,
  output logic [BYTE_COUNT-1:0]         rif_wstrb,
  output logic [DATA_WIDTH-1:0]         rif_wdata,
  input  logic [DATA_WIDTH-1:0]         rif_rdata
);

  assign rif_addr   = paddr;
  assign rif_wstrb  = BYTE_EN ? pstrb : '1;
  assign rif_wdata  = pwdata;
  assign rif_wr_req = psel &  pwrite & ~penable;
  assign rif_rd_req = psel & ~pwrite & ~penable;

  always_ff @(posedge pclk or negedge presetn) begin : ff_rdata
    if (!presetn) begin
      prdata <= '0;
    end
    else if (rif_rd_req) begin
      prdata <= rif_rdata;
    end
  end : ff_rdata


  if (REPORT_ERROR) begin : g_slverr

    always_ff @(posedge pclk or negedge presetn) begin : ff_slverr
      if (!presetn) begin
        pslverr <= 1'b0;
      end
      else if (pslverr) begin
        pslverr <= 1'b0;
      end
      else if (psel & ~penable) begin
        pslverr <= ~rif_addr_valid;
      end
    end : ff_slverr

  end : g_slverr
  else begin : g_dummy_slverr
    assign pslverr = 1'b0;
  end : g_dummy_slverr

  // APB adapter is always ready for transfer
  assign pready = 1'b1;

endmodule : apb_adapter
