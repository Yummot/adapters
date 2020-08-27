`timescale 1ns/1ps

// This a generic synchronous FIFO
// It can be used as a AXI-STREAM data fifo. This is the default behavior.
// In such cases, not full/empty signal will be provided unless you specify
// the parameter EN_FULL_PORT and EN_EMPTY_PORT.
//
// If you would like to use full/empty instead of wready and rvalid as
// indicators. Please set EN_FULL_PORT and EN_EMPTY_PORT.
//
// This synchronous FIFO can also run at the First Word Fall Through mode,
// by setting the FALL_THROUGH parameter.
//
// When DEPTH is 0, it will generate as a pass through module.
//
// If you would like to know the current fifo data count, please set the
// EN_DATA_COUNT parameter to 1.

module sync_fifo #(
  parameter integer                 DATA_WIDTH = 8,
  parameter integer                 DEPTH = 8,
  // Enable the First word Fall Through mode
  parameter bit                     FALL_THROUGH = 1'b0,
  // Set rdata = '0, when empty
  parameter bit                     ZERO_IF_EMPTY = 1'b0,
  // Enable data count output
  parameter bit                     EN_DATA_COUNT = 1'b0,
  // Whether to output the full signal. If EN_FULL_PORT=0, the full port will be always 0 and
  // you should not use the full port.
  parameter bit                     EN_FULL_PORT = 1'b0,
  // Whether to output the empty signal. If EN_EMPTY_PORT=1, the empty port will be always 0 and
  // you should not use the empty port.
  parameter bit                     EN_EMPTY_PORT = 1'b0,
  // Derived parameters
  parameter integer                 ADDR_WIDTH = $clog2(DEPTH+1)
) (
  input  logic                      clk,
  input  logic                      reset,

  input  logic                      flush,

  input  logic [DATA_WIDTH-1:0]     wdata,
  input  logic                      wvalid,
  output logic                      wready,

  output logic [DATA_WIDTH-1:0]     rdata,
  output logic                      rvalid,
  input  logic                      rready,

  output logic [ADDR_WIDTH-1:0]     data_count,
  output logic                      empty,
  output logic                      full
);

  // PASS TRHOUGH
  if (DEPTH == 0) begin : g_degenerate
    assign data_count = '0;

    assign rvalid = wvalid;
    assign wready = rready;
    assign rdata  = wdata;
    assign full   = '0;
    assign empty  = '0;
  end : g_degenerate
  else begin : g_fifo
    localparam integer PTR_WIDTH = (DEPTH == 1) ? 2 : $clog2(DEPTH) + 1;
    localparam integer ROLL_OVER = DEPTH - 1;


    //--------------------------------------------------------------------------
    // Internal signals
    //--------------------------------------------------------------------------

    logic                             i_full;
    logic                             i_empty;
    logic                             incr_wptr;
    logic                             incr_rptr;
    logic [PTR_WIDTH-1:0]             wptr;
    logic [PTR_WIDTH-1:0]             rptr;
    logic [PTR_WIDTH-1:0]             next_wptr;
    logic [PTR_WIDTH-1:0]             next_rptr;

    logic [DATA_WIDTH-1:0]            i_rdata;

    // FIFO memory read port output
    logic [DATA_WIDTH-1:0]            mem_rdata;

    assign incr_rptr = rvalid & rready;
    assign incr_wptr = wvalid & wready;

    //--------------------------------------------------------------------------
    // The FALL THROUGH mode relative logic generation
    //--------------------------------------------------------------------------

    // The wvalid and ravlid logic
    assign wready = ~i_full;
    assign full   = EN_FULL_PORT ? i_full : 1'b0;

    if (FALL_THROUGH) begin : g_ft
      logic ft_empty;

      assign i_rdata  = (i_empty & wvalid) ? wdata : mem_rdata;
      assign ft_empty = i_empty & ~wvalid;
      assign empty = EN_EMPTY_PORT ? ft_empty : 0;
      assign rvalid   = ~ft_empty;
    end : g_ft
    else begin : g_normal
      assign i_rdata = mem_rdata;
      assign empty = EN_EMPTY_PORT ? i_empty : 1'b0;
      assign rvalid  = ~i_empty;
    end : g_normal

    //--------------------------------------------------------------------------
    // The rdata ouput generation
    //--------------------------------------------------------------------------

    // set rdata to all zeros if ZERO_IF_EMPTY = 1 and rvalid = 0
    if (ZERO_IF_EMPTY) begin : g_o_zeros
      assign rdata = empty ? '0 : i_rdata;
    end : g_o_zeros
    else begin : g_normal_o
      assign rdata = i_rdata;
    end : g_normal_o

    //--------------------------------------------------------------------------
    // The FIFO data_count logic
    //--------------------------------------------------------------------------
    if (EN_DATA_COUNT) begin : g_data_count_port
      always_comb begin : comb_data_count
        if (i_full) begin
          data_count = ADDR_WIDTH'(DEPTH);
        end
        else if (wptr[PTR_WIDTH-1] == rptr[PTR_WIDTH-1]) begin
          data_count = ADDR_WIDTH'(wptr[PTR_WIDTH-2:0]) - ADDR_WIDTH'(rptr[PTR_WIDTH-2:0]);
        end
        else begin
          data_count = ADDR_WIDTH'(DEPTH) + ADDR_WIDTH'(wptr[PTR_WIDTH-2:0]) - ADDR_WIDTH'(rptr[PTR_WIDTH-2:0]);
        end
      end : comb_data_count
    end : g_data_count_port
    else begin : g_dummy_data_count_port
      assign data_count = '0;
    end :g_dummy_data_count_port

    //--------------------------------------------------------------------------
    // The FIFO pointers Logic
    //--------------------------------------------------------------------------

    // FIFO rptr logic
    always_comb begin : comb_rptr
      next_rptr = rptr;
      if (incr_rptr) begin
        if (rptr[PTR_WIDTH-2:0] == ROLL_OVER[PTR_WIDTH-2:0]) begin
          next_rptr = {~rptr[PTR_WIDTH-1], {(PTR_WIDTH-1){1'b0}}};
        end
        else begin
          next_rptr = rptr + 1'b1;
        end
      end
    end : comb_rptr

    // FIFO wptr logic
    always_comb begin : comb_wptr
      next_wptr = wptr;
      if (incr_wptr) begin
        if (wptr[PTR_WIDTH-2:0] == ROLL_OVER[PTR_WIDTH-2:0]) begin
          next_wptr = {~wptr[PTR_WIDTH-1], {(PTR_WIDTH-1){1'b0}}};
        end
        else begin
          next_wptr = wptr + 1'b1;
        end
      end
    end : comb_wptr

    // register fifo rptr
    always_ff @(posedge clk or posedge reset) begin : ff_rptr
      if (reset) begin
        rptr <= '0;
      end
      else if (flush) begin
        rptr <= '0;
      end
      else if (incr_rptr) begin
        rptr <= next_rptr;
      end
    end : ff_rptr

    // register fifo wptr
    always_ff @(posedge clk or posedge reset) begin : ff_wptr
      if (reset) begin
        wptr <= '0;
      end
      else if (flush) begin
        wptr <= '0;
      end
      else if (incr_wptr) begin
        wptr <= next_wptr;
      end
    end : ff_wptr


    //--------------------------------------------------------------------------
    // The FIFO internal empty/full Logic
    //--------------------------------------------------------------------------

    assign i_full = (wptr == {~rptr[PTR_WIDTH-1], rptr[PTR_WIDTH-2:0]});
    // Note: empty is not the finial output to rvalid if FALL_THROUGH = 1.
    assign i_empty = (wptr == rptr);

    //--------------------------------------------------------------------------
    // The FIFO memory Logic
    //--------------------------------------------------------------------------

    // DEPTH == 1, generate a 1-depth buffer
    if (DEPTH == 1) begin : g_1_depth_buffer
      logic [DATA_WIDTH-1:0] mem;

      assign mem_rdata = mem;
      always_ff @(posedge clk or posedge reset) begin : ff_mem
        if (reset) begin
          mem <= '0;
        end
        else if (incr_wptr) begin
          mem <= wdata;
        end
      end : ff_mem

    end : g_1_depth_buffer
    else begin : g_depth_mem
      logic [DEPTH-1:0][DATA_WIDTH-1:0] mem;

      assign mem_rdata = mem[rptr[PTR_WIDTH-2:0]];
      always_ff @(posedge clk) begin : ff_mem
        if (incr_wptr) begin
          mem[wptr[PTR_WIDTH-2:0]] <= wdata;
        end
      end : ff_mem
    end : g_depth_mem

  end : g_fifo

  //

endmodule
