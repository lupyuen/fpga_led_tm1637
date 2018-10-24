`include "rom.v"

module LED_TM1637_ROM(
    input [`BLOCK_ROM_INIT_ADDR_WIDTH-1:0] addr,
	output [`BLOCK_ROM_INIT_DATA_WIDTH-1:0] dout
);

//  ROM Memory File was automatically generated from https://docs.google.com/spreadsheets/d/1A8DXZctL5y_flReyj7tDzsaesVAe2RSF4ckzO-_Yqro/edit?usp=sharing
parameter FILENAME="led_tm1637_rom.mem";
localparam LENGTH=2**`BLOCK_ROM_INIT_ADDR_WIDTH;
reg [`BLOCK_ROM_INIT_DATA_WIDTH-1:0] mem [LENGTH-1:0];
initial $readmemh(FILENAME, mem);
assign dout = mem[addr];

endmodule

