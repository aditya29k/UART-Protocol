`timescale 1ns/1ps;

`ifndef CLK_FREQUENCY
	`define CLK_FREQUENCY 100_000
`endif

`ifndef BAUD_RATE
	`define BAUD_RATE 9600
`endif

interface uart_intf;
    logic clk, rst;

    logic start;
    logic [7:0] data_in;
    logic transmit, done_tx;

    logic rx;
    logic [7:0] dout;
    logic done_rx, error_rx;

    logic clk_tx, clk_rx;
endinterface

class transaction;

    rand bit start;
    rand bit [7:0] data_in;
    bit transmit, done_tx;

    bit rx;
    bit [7:0] dout;
    bit done_rx, error_rx;

    function transaction copy();
        copy = new();
        copy.start = this.start;
        copy.data_in = this.data_in;
        copy.transmit = this.transmit;
        copy.done_tx = this.done_tx;
        copy.rx = this.rx;
        copy.dout = this.dout;
        copy.done_rx = this.done_rx;
        copy.error_rx = this.error_rx; 
    endfunction

    constraint start_cons1 {start dist {1:=8, 0:=2}; }
    constraint start_cons2 {start == 1 -> data_in != 0;}
    constraint data_in_cons1 { start == 0 -> data_in == 0;}
    constraint data_in_cons2 {data_in inside {[0:15]};}

endclass

class generator;

    transaction trans;

    mailbox #(transaction) mbxgd;

    event drvnxt, sconxt;
    event done;

    int count;

    function new(mailbox #(transaction) mbxgd);
        this.mbxgd = mbxgd;
        trans = new();
    endfunction

    task run();
        repeat(count) begin
            $display("-------------");
            assert(trans.randomize) else $error("[GEN] RANDOMIZATION FAILED");
            mbxgd.put(trans.copy());
            $display("[GEN] start: %0d data_in: %0d", trans.start, trans.data_in);
            @(drvnxt);
        end
        ->done;
    endtask

endclass

class driver;

    transaction trans;

    mailbox #(transaction) mbxgd;
    mailbox #(bit [8:0]) mbxds1;
    mailbox #(bit [7:0]) mbxds2;

    virtual uart_intf intf;

    event drvnxt;

    function new(mailbox #(transaction) mbxgd, mailbox #(bit [8:0]) mbxds1, mailbox #(bit [7:0]) mbxds2);
        this.mbxgd = mbxgd;
        this.mbxds1 = mbxds1;
        this.mbxds2 = mbxds2;
    endfunction

    task reset();
        intf.rst <= 1'b1;
        intf.start <= 1'b0;
        intf.data_in <= 0;
        intf.rx <= 1'b1;
        repeat(5)@(posedge intf.clk);
        intf.rst <= 1'b0;
        $display("[DRV] SYSTEM RESETED");
        @(posedge intf.clk);
    endtask
  
  	reg [8:0] temp; // parity + transmission from master

    function check_parity();

      if(^temp[7:0] != temp[8]) begin
        $display("[DRV] DATA CORRUPTED data:%b, parity: %b", temp[7:0], temp[8]);
      end

    endfunction

    task receive();
		temp = 0;
        @(posedge intf.clk_tx);
        intf.start <= trans.start;
        intf.data_in <= trans.data_in;
        @(posedge intf.clk_tx);
      	intf.start <= 0;
        if(!trans.start) begin
          	$display("[DRV RECV] NO RX OCCURING");
        end
        else begin
            @(posedge intf.clk_tx);
            for(int i = 0; i<8; i++) begin
                @(posedge intf.clk_tx);
                temp[7:0] <= {temp[6:0], intf.transmit};
            end
            @(posedge intf.clk_tx);
            temp[8] <= intf.transmit;
            wait(intf.done_tx);
          	check_parity();
          	$display("[DRV RECV] RECEIVE data: %b, parity: %b", temp[7:0], temp[8]);
          
          if(temp[7:0] == intf.data_in) $display("[DRV RECV] DATA MATCH");
          	else $display("[DRV RECV] DATA MISMATCH");
            mbxds1.put(temp);
        end

    endtask

    reg oper;
    reg [7:0] val;
    reg parity_val;
  
  	task check_result();
      
      if(val == intf.dout) begin
        $display("[DRV TRANS] DATA MATCH");
      end
      else begin
        $display("[DRV TRANS] DATA MISMATCH");
      end
      
  	endtask
  
    task transmit();
        oper = $urandom; // 1 means start transmission of data
      	$display("[DRV TRANS] sending data: %b", oper);
        if(oper) begin
          	val = $urandom_range(0,15);
          	parity_val = ^val;
            intf.rx <= 1'b0;
            @(posedge intf.clk_rx);
            for(int i = 0; i<8; i++) begin
              	intf.rx <= val[7-i];
                @(posedge intf.clk_rx);
            end
            intf.rx <= parity_val;
          	@(posedge intf.clk_rx);
          	intf.rx <= 1'b1;
            wait(intf.done_rx);
            mbxds2.put(val);
          	if(intf.error_rx) $display("[DRV TRANS] ERROR IN DATA TRANSMISSION");
          	$display("[DRV TRANS] TRANSMIT data: %b", val[7:0]);
          	check_result();
        end
        else intf.rx <= 1'b1;
    endtask

    task run();
        forever begin
            mbxgd.get(trans);
          	fork
              receive();
              transmit();
            join
            ->drvnxt;
        end
    endtask

endclass

class environment;

    transaction trans;
    generator gen;
    driver drv;

    mailbox #(transaction) mbxgd;
    mailbox #(bit [8:0]) mbxds1;
    mailbox #(bit [7:0]) mbxds2;

    virtual uart_intf intf;

    event done;

    function new(virtual uart_intf intf);

        mbxgd = new();
        mbxds1 = new();
        mbxds2 = new();

        trans = new();
        gen = new(mbxgd);
        drv = new(mbxgd, mbxds1, mbxds2);

        this.done = gen.done;
        gen.drvnxt = drv.drvnxt;

        this.intf = intf;
        drv.intf = intf;

        gen.count = 5;

    endfunction

    task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.run();
            drv.run();
        join_any
    endtask

    task post_test();
        wait(done.triggered);
        $finish();
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask

endclass

module tb;

    uart_intf intf();

    environment env;

    top DUT (intf.clk, intf.rst, intf.start, intf.data_in, intf.transmit, intf.done_tx, intf.rx, intf.dout, intf.done_rx, intf.error_rx);

    initial begin
        intf.clk <= 1'b0;
    end

    always #5000 intf.clk <= ~intf.clk;

    assign intf.clk_rx = DUT.RX.uart_clk;
    assign intf.clk_tx = DUT.TX.uart_clk;

    initial begin
        env = new(intf);
        env.run();
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

endmodule