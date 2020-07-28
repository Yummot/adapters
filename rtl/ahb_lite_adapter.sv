//  Module: ahb_lite_adapter
//

`timescale 1ns/1ps

module ahb_lite_adapter #(
  parameter integer                     ADDR_WIDTH = 'd12,
  parameter integer                     DATA_WIDTH = 'd32,
  parameter bit                         SEC_TRANS  = 1'b0,
  parameter integer                     BYTE_COUNT = DATA_WIDTH / 8
)(
  input  logic                          HCLK,
  input  logic                          HRESETn,

  input  logic [ADDR_WIDTH-1:0]         HADDR,
  input  logic                          HSEL,
  input  logic                          HNONSEC,
  /* verilator lint_off UNUSED */
  input  logic [2:0]                    HBURST,
  /* verilator lint_on UNUSED */
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
  localparam integer       STRB_WIDTH = DATA_WIDTH / 8;

  localparam logic [127:0] STRB_MAP [8] = '{
    128'h1,
    128'h3,
    128'hf,
    128'hff,
    128'hffff,
    128'hffff_ffff,
    128'hffff_ffff_ffff_ffff,
    128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff
  };

  // enum logic [1:0] { IDLE = 0, BUSY = 1, NONSEQ = 2, SEQ = 3 } htrans_t;

  // DATA WIDTH CHECK
  if ((DATA_WIDTH < 8) && (2 ** $clog2(DATA_WIDTH) != DATA_WIDTH)) begin
    $fatal(1, "AHB Lite Adapter expected DATA_WIDTH to be 8, 16, 32, 64, 128, 256, 512, or 1024-bit wides, but got BUFFER_DEPTH = %d", DATA_WIDTH);
  end

  //----------------------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------------------

  logic [1:0]                           i_hresp;
  logic [2:0]                           i_size;
  logic [ADDR_WIDTH-1:0]                i_addr;
  logic [STRB_WIDTH-1:0]                i_wstrb;
  logic [STRB_WIDTH-1:0]                i_rstrb;
  logic [DATA_WIDTH-1:0]                i_wdata;
  logic [DATA_WIDTH-1:0]                i_rdata;
  logic                                 i_write;
  logic                                 i_nonsec;
  logic                                 i_req;
  logic                                 i_err;
  logic                                 ahb_xseq;
  logic                                 ahb_valid;

  // If AHB transfer, HTRANS[1] = 1'b1 , which is NONSEQ (2'b10) and SEQ (2'b11)
  assign ahb_xseq = HTRANS[1];

  // Indicates an AHB valid address phase to this device.
  assign ahb_valid = HSEL & HREADYIN;

  // There is an error from RIF
  assign i_err = (rif_rd_req | rif_wr_req) & !rif_addr_valid;

  assign HRESP = i_hresp[1];

  //----------------------------------------------------------------------------
  // Byte lanes logic
  //----------------------------------------------------------------------------

  // Internal WSTRB logic
  always_comb begin : comb_wstrb
    // Note that HSIZE will not greater than DATA_WIDTH.
    i_wstrb = '0;
    case (i_size)
      3'b000: i_wstrb = STRB_MAP[0][STRB_WIDTH-1:0]; // Byte
      3'b001: i_wstrb = STRB_MAP[1][STRB_WIDTH-1:0]; // Halfword
      3'b010: i_wstrb = STRB_MAP[2][STRB_WIDTH-1:0]; // Word
      3'b011: i_wstrb = STRB_MAP[3][STRB_WIDTH-1:0]; // Doubleworld
      3'b100: i_wstrb = STRB_MAP[4][STRB_WIDTH-1:0]; // 4-word line
      3'b101: i_wstrb = STRB_MAP[5][STRB_WIDTH-1:0]; // 8-word line
      3'b110: i_wstrb = STRB_MAP[6][STRB_WIDTH-1:0]; // 512-bits width
      3'b111: i_wstrb = STRB_MAP[7][STRB_WIDTH-1:0]; // 1024-bits width
    endcase
  end : comb_wstrb

  // Internal RSTRB logic
  always_comb begin : comb_strb
    // Note that HSIZE will not greater than DATA_WIDTH.
    i_rstrb = '0;
    case (HSIZE)
      3'b000: i_rstrb = STRB_MAP[0][STRB_WIDTH-1:0]; // Byte
      3'b001: i_rstrb = STRB_MAP[1][STRB_WIDTH-1:0]; // Halfword
      3'b010: i_rstrb = STRB_MAP[2][STRB_WIDTH-1:0]; // Word
      3'b011: i_rstrb = STRB_MAP[3][STRB_WIDTH-1:0]; // Doubleworld
      3'b100: i_rstrb = STRB_MAP[4][STRB_WIDTH-1:0]; // 4-word line
      3'b101: i_rstrb = STRB_MAP[5][STRB_WIDTH-1:0]; // 8-word line
      3'b110: i_rstrb = STRB_MAP[6][STRB_WIDTH-1:0]; // 512-bits width
      3'b111: i_rstrb = STRB_MAP[7][STRB_WIDTH-1:0]; // 1024-bits width
    endcase
  end : comb_strb

  // i_wdata mask
  if (SEC_TRANS) begin : g_sec_wdata
    for (genvar i = 0; i < DATA_WIDTH; i += 8) begin : g_i_wdata
      assign i_wdata[i+:8] = (i_wstrb[i/8] & ~i_nonsec) ? HWDATA[i+:8] : '0;
    end : g_i_wdata;
  end : g_sec_wdata
  else begin : g_non_sec_wdata
    for (genvar i = 0; i < DATA_WIDTH; i += 8) begin : g_i_wdata
      assign i_wdata[i+:8] = i_wstrb[i/8] ? HWDATA[i+:8] : '0;
    end : g_i_wdata;
  end : g_non_sec_wdata

  // i_rdata mask
  if (SEC_TRANS) begin : g_sec_rdata
    for (genvar i = 0; i < DATA_WIDTH; i += 8) begin : g_i_rdata
      assign i_rdata[i+:8] = (i_rstrb[i/8] & ~i_nonsec) ? rif_rdata[i+:8] : '0;
    end : g_i_rdata;
  end : g_sec_rdata
  else begin : g_non_sec_rdata
    for (genvar i = 0; i < DATA_WIDTH; i += 8) begin : g_i_rdata
      assign i_rdata[i+:8] = i_rstrb[i/8] ? rif_rdata[i+:8] : '0;
    end : g_i_rdata;
  end : g_non_sec_rdata

  assign HRDATA = i_rdata;

  //----------------------------------------------------------------------------
  // RIF signals connections
  //----------------------------------------------------------------------------
  assign rif_addr   = (HWRITE) ? i_addr : HADDR;
  assign rif_wr_req = i_req &  i_write;
  assign rif_rd_req = ahb_valid & ahb_xseq & ~i_write;
  assign rif_wstrb  = i_wstrb;
  assign rif_wdata  = i_wdata;

  //----------------------------------------------------------------------------
  // Registers signal at the AHB address phase
  //----------------------------------------------------------------------------

  // Latch i_rdata to RDATA
  always_ff @(posedge HCLK or negedge HRESETn) begin : ff_hrdata
    if (!HRESETn) begin
      HRDATA <= '0;
    end
    else if (rif_rd_req) begin
      HRDATA <= i_rdata;
    end
  end : ff_hrdata

  // Latch HADDR and HSIZE
  always_ff @(posedge HCLK or negedge HRESETn) begin : ff_addr_size
    if (!HRESETn) begin
      i_addr  <= '0;
      i_size  <= '0;
      i_nonsec <= '0;
    end
    else if (ahb_valid && ahb_xseq) begin
      i_addr  <= HADDR;
      i_size  <= HSIZE;
      i_nonsec <= HNONSEC;
    end
  end : ff_addr_size

  // Latch HWRITE
  always_ff @(posedge HCLK or negedge HRESETn) begin : ff_wr
    if (!HRESETn) begin
      i_write <= 1'b0;
    end
    else if (ahb_valid && ahb_xseq) begin
      i_write <= HWRITE;
    end
    else if (!HSEL && i_write) begin
      i_write <= 1'b0;
    end
  end : ff_wr

  // Generate internal req
  always_ff @(posedge HCLK or negedge HRESETn) begin : ff_req
    if (!HRESETn) begin
      i_req <= 1'b0;
    end
    else if (ahb_valid && (i_req ^ ahb_xseq)) begin
      i_req <= ahb_xseq;
    end
    else if (!HSEL && i_req) begin
      i_req <= 1'b0;
    end
  end : ff_req

  //----------------------------------------------------------------------------
  // Device HREADYOUT and HRESP
  //----------------------------------------------------------------------------

  always_ff @(posedge HCLK or negedge HRESETn) begin : ff_hready_out
    if (!HRESETn) begin
      HREADYOUT <= 1'b1;
    end
    else if (i_err) begin
      HREADYOUT <= 1'b0;
    end
    else if (!HREADYOUT) begin
      HREADYOUT <= 1'b1;
    end
  end : ff_hready_out

  // slience failed when a non secure transfer if SEC_TRANS = 1'b1
  always_ff @(posedge HCLK or negedge HRESETn) begin : ff_i_hresp
    if (!HRESETn) begin
      i_hresp <= 2'b0;
    end
    else if (i_err) begin
      i_hresp <= 2'b11;
    end
    else if (i_hresp != 0) begin
      i_hresp <= {i_hresp[0], 1'b0};
    end
  end : ff_i_hresp


endmodule: ahb_lite_adapter
