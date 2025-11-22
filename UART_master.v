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

module top(
  input clk, rst,
  
  input rx,
  output [`DATA_WIDTH-1:0] dout,
  output done_rx,
  
  output tx,
  output done_tx,
  input [`DATA_WIDTH-1:0] din,
  input start
  
);
  
  wire err;
  
  uart_master_tx m0 (clk, rst, tx, done_tx, din, start);
  uart_master_rx s0 (clk, rst, rx, dout, err, done_rx );
  
endmodule

module uart_master_tx(
  input clk, rst,
  output reg tx, done_tx,
  input [`DATA_WIDTH-1:0] din,
  input start
);
  
  // Generation of clock
  
  reg uart_clk;
  int clk_count;
  
  always@(posedge clk) begin
    if(rst) begin
      clk_count <= 0;
      uart_clk <= 1'b0;
    end
    else begin
      if(clk_count == (`COUNT/2) - 1) begin
        clk_count <= 0;
        uart_clk <= ~uart_clk;
      end
      else begin
        clk_count <= clk_count + 1;
      end
    end
  end
  
  // FSM for transmit
  
  typedef enum bit [1:0] {IDLE, TRANS, PARITY, STOP} states;
  states state;
  
  reg parity;
  
  reg [`DATA_WIDTH-1:0] temp;
  integer data_count;
  
  always@(posedge uart_clk) begin
    if(rst) begin
      data_count <= 0;
      temp <= 0;
      state <= IDLE;
      tx <= 1'b1;
      done_tx <= 1'b0;
      parity <= 1'b0;
    end
    else begin
      case(state)
        
        IDLE: begin
          done_tx <= 1'b0;
          if(start) begin
            temp <= din;
            data_count <= 0;
            state <= TRANS;
            tx <= 1'b0; // START BIT
            parity <= ^din;
          end
          else begin
            temp <= 0;
            data_count <= 0;
            state <= IDLE;
            tx <= 1'b1;
            parity <= 1'b0;
          end
        end
        
        TRANS: begin
          if(data_count<=7) begin
            tx <= temp[data_count]; // UART SENDS LSB FIRST
            data_count <= data_count + 1;
            state <= TRANS;
          end
          else begin
            state <= PARITY;
          end
        end
        
        PARITY: begin
          tx <= parity;
          state <= STOP;
        end
        
        STOP: begin
          done_tx <= 1'b1;
          tx <= 1'b1;
          state <= IDLE;
        end
        
      endcase
    end
  end
  
endmodule

module uart_master_rx(
  input clk, rst,
  input rx,
  output [`DATA_WIDTH-1:0] dout,
  output reg err,
  output reg done_rx
);
  
  // Generation of clock
  
  reg uart_clk;
  int clk_count;
  
  always@(posedge clk) begin
    if(rst) begin
      clk_count <= 0;
      uart_clk <= 1'b0;
    end
    else begin
      if(clk_count == (`COUNT/2) - 1) begin
        clk_count <= 0;
        uart_clk <= ~uart_clk;
      end
      else begin
        clk_count <= clk_count + 1;
      end
    end
  end
  
  // FSM for reception
  
  typedef enum bit [1:0] {START, RECV, CHECK, STOP} states;
  states state;
  
  reg [`DATA_WIDTH-1:0] temp;
  
  integer data_count;
  
  always@(posedge uart_clk) begin
    if(rst) begin
      temp <= 0;
      state <= START;
      err <= 1'b0;
      done_rx <= 1'b0;
      data_count <= 0;
    end
    else begin
      case(state)
        
        START: begin
          temp <= 0;
          err <= 1'b0;
          data_count <= 0;
          done_rx <= 1'b0;
          if(!rx) begin
            state <= RECV;
          end
          else begin
            state <= START;
          end
        end
        
        RECV: begin
          if(data_count<=7) begin
            temp[data_count] <= rx;
            data_count <= data_count + 1;
            state <= RECV;
          end
          else begin
            state <= CHECK;
          end
        end
        
        CHECK: begin
          if(rx != ^temp) begin
            err <= 1'b1;
          end
          state <= STOP;
        end
        
        STOP: begin
          done_rx <= 1'b1;
          state <= START;
        end
        
      endcase
    end
  end
  
  assign dout = temp;
  
endmodule
