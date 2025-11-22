`ifndef CLK_FREQUENCY
	`define CLK_FREQUENCY 100000
`endif

`ifndef BAUD_RATE
	`define BAUD_RATE 9600
`endif

`ifndef COUNT
	`define COUNT (`CLK_FREQUENCY/`BAUD_RATE)&(~1)
`endif

`ifndef DATA_WIDTH
	`define DATA_WIDTH 8
`endif


interface uart_intf;
  
  logic clk, rst;
  
  logic rx;
  logic [`DATA_WIDTH-1:0] dout;
  logic done_rx;
  
  logic tx;
  logic done_tx;
  logic [`DATA_WIDTH-1:0] din;
  logic start;
  
endinterface

module tb;
  
  uart_intf intf();
  
  top DUT (intf.clk, intf.rst, intf.rx, intf.dout , intf.done_rx, intf.tx, intf.done_tx, intf.din, intf.start);
  
  initial begin
    intf.clk <= 1'b0;
  end
  
  always #5 intf.clk <= ~intf.clk;
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
  task reset();
    intf.rst <= 1'b1;
    intf.start <= 1'b0;
    intf.din <= 0;
    intf.rx <= 1'b1;
    repeat(`COUNT/2)@(posedge intf.clk);
    intf.rst <= 1'b0;
    $display("System Reseted");
    $display("-------------");
  endtask
  
  int count1;
  reg [`DATA_WIDTH-1:0] slave_recv;
  reg check_parity;
  
  task trans(); // SLAVE RECEPTION
    count1 = 0;
    intf.start <= 1'b1;
    intf.din <= $urandom_range(1,15);
    
    wait(DUT.m0.state == 1);
    $display("[MASTER TRANSMIT] din: %0d", intf.din);
    @(posedge DUT.m0.uart_clk); // this is for start bit to pass
    forever begin
       @(posedge DUT.m0.uart_clk);
      slave_recv[count1] = intf.tx;
      count1 = count1 + 1;
      if(count1 == 8) begin
        break;
      end
    end
    
    repeat(2)@(posedge DUT.m0.uart_clk);
    check_parity = intf.tx;
    
    wait(intf.done_tx);
    intf.start <= 1'b0;
    #100; // added to check parity
    if(slave_recv == intf.din) $display("[MASTER TRANSMIT SUCCESSFULL] DATA MATCHED");
    else $display("[MASTER TRANSMIT FAILED]");
    
    if(check_parity == ^slave_recv) $display("[MASTER TRANSMIT CORRECT PARITY]");
    
    $display("-------------------");
    
  endtask
  
  reg [7:0] slv_data = 8'b10010110; // this can be randomize too
  int index = 0;
  
  task recv(); // SLAVE SENDING
    
    intf.rx <= 1'b0;
    repeat(8) @(posedge DUT.s0.uart_clk) begin
      intf.rx <= slv_data[index];
      index = index + 1;
    end
     @(posedge DUT.s0.uart_clk)
    intf.rx <= ^slv_data;
    if(!DUT.s0.err) $display("[MASTER RECEPTION SUCCESSFULL]");
    $display("---------------------");
    wait(intf.done_rx);
    
  endtask
  
  task run();
    fork
      trans();
      recv();
    join
  endtask
  
  initial begin
    reset();
    run();
    $finish();
  end
  
endmodule
