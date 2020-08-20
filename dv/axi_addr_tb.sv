`timescale 1ns/1ps

//  Interface: axi_addr_if
//
interface axi_addr_if #(
  parameter bit     ALIGN_ADDR = 1'b1,
  parameter         ADDR_WIDTH = 12,
  parameter         DATA_WIDTH = 32
);

logic                       clk;
logic [ADDR_WIDTH-1:0]      addr;
logic [1:0]                 burst;
logic [2:0]                 size;
logic [7:0]                 len;
logic [ADDR_WIDTH-1:0]      next_addr;

initial begin
  clk = 0;
  addr <= 0;
  burst <= 0;
  size <= 0;
  len <= 0;
  fork
    forever #2ns clk = ~clk;
  join_none
end

endinterface: axi_addr_if


// Module: axi_addr_tb
//
module axi_addr_tb;
  localparam bit     ALIGN_ADDR = 1'b1;
  localparam         ADDR_WIDTH = 12;
  localparam         DATA_WIDTH = 64;
  localparam time    TIMEOUT    = 2us;

  axi_addr_if #(
    .ALIGN_ADDR(ALIGN_ADDR),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) axi_addr_vif();
  event tb_done;

  initial begin : g_timeout
    fork
      #TIMEOUT;
      @tb_done;
    join_any

    $finish();
  end : g_timeout

  initial begin : g_drv
    $timeformat(-9,0,"ns",8);

    // FIXED
    @(posedge axi_addr_vif.clk);
    axi_addr_vif.addr <= 0;
    axi_addr_vif.burst <= 0;
    axi_addr_vif.size <= 2;
    axi_addr_vif.len <= 2;

    for (int i = 0; i < 2; i++) begin
      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 0);
    end

    // AMBA AXI5 example test sequence
    if (DATA_WIDTH == 32) begin
      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 0;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 1;

      for (int i = 0; i < 2; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == (i + 1) * 4);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end

      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 'h1;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 3;

      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 4);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;

      for (int i = 1; i < 4; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == (i + 1) * 4);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end

      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 0;
      axi_addr_vif.burst <= 0;
      axi_addr_vif.size <= 2;
      axi_addr_vif.len <= 2;

      for (int i = 0; i < 2; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == 0);
      end

      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 0;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 1;

      for (int i = 0; i < 2; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == (i + 1) * 4);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end

      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 'h1;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 3;

      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 4);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;

      for (int i = 1; i < 4; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == (i + 1) * 4);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end

      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 'h7;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 4;

      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 8);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;

      for (int i = 1; i < 5; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == 8 + i * 4);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end
    end

    if (DATA_WIDTH == 64) begin
      // incr
      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 'h0;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 3;

      for (int i = 0; i < 4; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == (i + 1) * 4)
          else $error("%0t %0h %0h", $time, axi_addr_vif.addr, axi_addr_vif.next_addr);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end

      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 'h7;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 3;

      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 8);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;

      for (int i = 1; i < 4; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == (i + 2) * 4)
          else $error("%0t %0h %0h", $time, axi_addr_vif.addr, axi_addr_vif.next_addr);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end

      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 'h7;
      axi_addr_vif.burst <= 2'b01;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 4;

      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 8);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;

      for (int i = 1; i < 5; i++) begin
        @(posedge axi_addr_vif.clk);
        assert (axi_addr_vif.next_addr == (i + 2) * 4)
          else $error("%0t %0h %0h", $time, axi_addr_vif.addr, axi_addr_vif.next_addr);
        axi_addr_vif.addr <= axi_addr_vif.next_addr;
      end

      // wrapping
      @(posedge axi_addr_vif.clk);
      axi_addr_vif.addr <= 'h4;
      axi_addr_vif.burst <= 2'b10;
      axi_addr_vif.size <= 3'b010;
      axi_addr_vif.len <= 3;

      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 8);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;
      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 12);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;
      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 0);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;
      @(posedge axi_addr_vif.clk);
      assert (axi_addr_vif.next_addr == 4);
      axi_addr_vif.addr <= axi_addr_vif.next_addr;
    end

    repeat (2) @(posedge axi_addr_vif.clk);
    -> tb_done;
  end : g_drv

  axi_addr #(
    .ALIGN_ADDR (ALIGN_ADDR),
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_axi_addr (
  	.addr      (axi_addr_vif.addr),
    .burst     (axi_addr_vif.burst),
    .size      (axi_addr_vif.size),
    .len       (axi_addr_vif.len),
    .next_addr (axi_addr_vif.next_addr)
  );


endmodule: axi_addr_tb
