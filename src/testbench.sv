module test;
  reg clk, rst_n, tm1637_clk, tm1637_dio, tm1637_vcc;
  reg[3:0] led;
  reg[6:0] debug_step_id;
  
  // Instantiate device under test
  demo demo1(
    .clk_50M(clk),
    .rst_n(rst_n),
    .led(led),
    .tm1637_clk(tm1637_clk),
    .tm1637_dio(tm1637_dio),
    .tm1637_vcc(tm1637_vcc),
    .debug_step_id(debug_step_id)
  );
  
  // oscillate clock every 10 simulation units
  always #10 clk <= !clk;
  
  // initialise values
  initial #0 begin
    $dumpfile("dump.vcd"); $dumpvars;
    clk = 0;
    rst_n = 1;    
    #1 rst_n = 0;
    #2 rst_n = 1;
    
    // finish after 20000 simulation units
    #20000 $finish;
  end
  
  // monitor results
  always @(negedge clk)
    $display("debug_step_id: %d", debug_step_id);
    
endmodule