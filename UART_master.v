`ifndef CLK_FREQUENCY
  `define CLK_FREQUENCY 100_000
`endif

`ifndef BAUD_RATE
  `define BAUD_RATE 9600
`endif

module top(
  input clk, rst,
  
  // TX
  input start,
  input [7:0] data_in,
  output transmit, done_tx,
  
  // RX
  input rx,
  output [7:0] dout,
  output done_rx, error_rx
);
  
  uart_master_transmit TX(clk, rst, start, data_in, transmit, done_tx);
  uart_master_receive RX(clk, rst, rx, dout, done_rx, error_rx);
  
endmodule



module uart_master_transmit(
  input clk, rst,
  input start,
  input [7:0] data_in,
  output reg transmit, done_tx // SENDING MSB FIRST
);
  
  // GENERATING UART CLOCK
  
  localparam clk_count = (`CLK_FREQUENCY/`BAUD_RATE)&(~1);// to make last bit even for 50% duty cycle
  integer count;
  
  reg uart_clk;
  
  always@(posedge clk) begin
    if(rst) begin
      count <= 0;
      uart_clk <= 1'b0;
    end
    else begin
      if(count < (clk_count/2)-1) begin
        count <= count + 1;
      end
      else begin
        count <= 0;
        uart_clk <= ~uart_clk;
      end
    end
  end
  
  // FSM for master transmit
  
  typedef enum bit [1:0]{IDLE_TX, DATA_TX, PARITY_TX, STOP_TX} states;
  states state;
  
  reg [7:0] temp;
  reg [3:0] counter;
  reg parity;
  
  always@(posedge uart_clk, posedge rst) begin
    if(rst) begin
      temp <= 0;
      state <= IDLE_TX;
      counter <= 0;
      done_tx <= 1'b0;
      transmit <= 1'b1;
      parity <= 1'b0;
    end
    else begin
      case(state)
        IDLE_TX: begin
          done_tx <= 1'b0;
          if(start) begin
            state <= DATA_TX;
            transmit <= 1'b0; // START BIT
            temp <= data_in;
            parity <= ^data_in;
            counter <= 0;
          end
          else begin
            state <= IDLE_TX;
            transmit <= 1'b1;
            parity <= 1'b0;
          end
        end
        DATA_TX: begin
          transmit <= temp[7-counter];
          if(counter<7) begin
            counter <= counter + 1;
            state <= DATA_TX;
          end
          else begin
            counter <= 0;
            state <= PARITY_TX;
          end
        end
        PARITY_TX: begin
          transmit <= parity;
          state <= STOP_TX;
        end
        STOP_TX: begin
          done_tx <= 1'b1;
          transmit <= 1'b1;
          state <= IDLE_TX;
        end
        default: state <= IDLE_TX;
      endcase
    end
  end
  
endmodule

module uart_master_receive(
  input clk, rst,
  input rx,
  output [7:0] dout,
  output reg done_rx, error_rx
);
  
  // GENERATING UART CLOCK
  
  localparam clk_count = (`CLK_FREQUENCY/`BAUD_RATE)&(~1);// to make last bit even for 50% duty cycle
  integer count;
  
  reg uart_clk;
  
  always@(posedge clk) begin
    if(rst) begin
      count <= 0;
      uart_clk <= 1'b0;
    end
    else begin
      if(count < (clk_count/2)-1) begin
        count <= count + 1;
      end
      else begin
        count <= 0;
        uart_clk <= ~uart_clk;
      end
    end
  end
  
  // FSM for mater receive
  
  typedef enum bit [1:0] {DETECT_RX, RECEIVE_RX, PARITY_RX, STOP_RX} states;
  states state;
  
  reg [3:0] counter;
  reg [7:0] temp;
  reg parity;
  
  always@(posedge uart_clk, posedge rst) begin
    if(rst) begin
      temp <= 0;
      counter <= 0;
      state <= DETECT_RX;
      parity <= 1'b0;
      done_rx <= 1'b0;
      error_rx <= 1'b0;
    end
    else begin
      case(state)
        DETECT_RX: begin
          done_rx <= 1'b0;
          error_rx <= 1'b0;
          parity <= 1'b0;
          if(!rx) begin
            counter <= 0;
            state <= RECEIVE_RX;
            temp <= 0;
          end
          else begin
            state <= DETECT_RX;
          end
        end
        RECEIVE_RX: begin
          temp[7-counter] <= rx;
          if(counter<7) begin
            counter <= counter + 1;
            state <= RECEIVE_RX;
          end
          else begin
            state <= PARITY_RX;
            counter <= 0;
          end
        end
        PARITY_RX: begin
          parity = ^temp;
          if(parity == rx) error_rx <= 1'b0;
          else error_rx <= 1'b1;
          state <= STOP_RX;
        end
        STOP_RX: begin
          if(rx) begin
            done_rx <= 1'b1;
          	state <= DETECT_RX;
          end
        end
        default: state <= DETECT_RX;
      endcase
    end
  end
  
  assign dout = (rst)? 0:temp;
  
endmodule