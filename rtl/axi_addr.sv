`timescale 1ns/1ps

// Module: axi_addr
//
module axi_addr #(
  parameter bit     ALIGN_ADDR = 1'b1,
  parameter         ADDR_WIDTH = 12,
  parameter         DATA_WIDTH = 32
)(
  input  logic [ADDR_WIDTH-1:0]     addr,
  input  logic [1:0]                burst,
  input  logic [2:0]                size,
  input  logic [7:0]                len,
  output logic [ADDR_WIDTH-1:0]     next_addr
);

  //----------------------------------------------------------------------------
  // typedefs and localparams
  //----------------------------------------------------------------------------

  localparam        DATA_SIZE = $clog2(DATA_WIDTH) - 3;

  typedef enum bit [1:0] {
    FIXED = 0,
    INCR = 1,
    WRAP = 2,
    RESERVED = 3
  } burst_e;

  function automatic logic [6:0] gen_align_mask(input bit [2:0] sz);
    case (sz)
      3'b000: gen_align_mask = 7'h7f;
      3'b001: gen_align_mask = 7'h7e;
      3'b010: gen_align_mask = 7'h7c;
      3'b011: gen_align_mask = 7'h78;
      3'b100: gen_align_mask = 7'h70;
      3'b101: gen_align_mask = 7'h60;
      3'b110: gen_align_mask = 7'h40;
      3'b111: gen_align_mask = 7'h00;
    endcase
  endfunction : gen_align_mask


  //----------------------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------------------

  logic [ADDR_WIDTH-1:0]    wrap_mask;
  logic [6:0]               align_mask;
  logic [ADDR_WIDTH-1:0]    n_bytes;
  burst_e                   i_burst;

  assign i_burst = burst_e'(burst);
  // AxSIZE will never be greater than DATA_SIZE
  assign n_bytes = 'h1 << size;
  // WRAP MASK
  assign wrap_mask = {{(ADDR_WIDTH-4){1'b0}}, len[3:0]} << size;

  always_comb begin : comb_next_addr
    align_mask = '0;
    next_addr = (i_burst == FIXED) ? addr : addr + n_bytes;
    unique if (i_burst == INCR) begin
      // For INCR BURST, do realignment if there is not interconnect,
      // and ALIGN_ADDR = 1'b1.
      if (ALIGN_ADDR) begin : g_align_addr
        // alignment mask
        align_mask = gen_align_mask(size);
        next_addr[DATA_SIZE-1:0] = next_addr[DATA_SIZE-1:0] & align_mask[DATA_SIZE-1:0];
      end : g_align_addr
    end
    else if (i_burst == WRAP) begin
      // For WRAPPING BURST the address must be aligned,
      // so we don't need to do realignment.
      next_addr = (addr & ~wrap_mask) | (next_addr & wrap_mask);
    end
    else begin
      next_addr = next_addr;
    end
  end : comb_next_addr

endmodule: axi_addr
