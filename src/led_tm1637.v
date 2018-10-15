//  Based on https://github.com/MorgothCreator/Verilog_SSD1306_CFG_IP
`timescale 20ns
`include "rom.v"

module	LED_TM1637(
    input   wire[0:0] clk_50M,  //  Onboard clock is 50MHz.  Pin 6.
    input   wire[0:0] rst_n,    //  TODO: Reset pin is also an Input, triggered by board restart or reset button.
	output  wire[0:0] tm1637_clk,  //  Pin 131, IO_TYPE=LVCMOS33 BANK_VCCIO=3.3
	output  wire[0:0] tm1637_dio,  //  Pin 132, IO_TYPE=LVCMOS33 BANK_VCCIO=3.3
    output  reg[3:0] led,  //  LED is actually 4 discrete LEDs at 4 Output signals. Each LED Output is 1 bit.  Use FloorPlanner to connect led[0 to 4] to Pins 47, 57, 60, 61
    input   wire[3:0] switches  //  SW4-SW7 for controlling the debug LED.  Use FloorPlanner to connect switches[0 to 4] to Pins 68, 69, 79, 80
);

//  The step ID that we are now executing: 0, 1, 2, ...
reg[`BLOCK_ROM_INIT_ADDR_WIDTH-1:0] step_id;
//  The step details, encoded in 48 bits.  This will be refetched whenever step_id changes.
wire[`BLOCK_ROM_INIT_DATA_WIDTH-1:0] encoded_step;
//  Whenever step_id is updated, fetch the encoded step from ROM.
LED_TM1637_ROM oled_rom_init(
	.addr(step_id),
	.dout(encoded_step)
);

//  We define convenience wires to decode our encoded step.  Prefix by "step" so we don't mix up our local registers vs decoded values.
//  If encoded_step is changed, these will automatically change.
wire[0:0] step_backward = encoded_step[47];  //  1 if next step is backwards i.e. a negative offset.
wire[2:0] step_next = encoded_step[46:44];  //  Offset to the next step, i.e. 1=go to following step.  If step_backward=1, go backwards.
wire[23:0] step_time = encoded_step[39:16];  //  Number of clk_led clock cycles to wait before starting this step. This time is relative to the time of power on.
wire[7:0] step_tx_data = encoded_step[15:8];  //  Data to be transmitted via SPI (1 byte).
wire[0:0] step_should_repeat = encoded_step[7];  //  1 if step should be repeated.
wire[14:0] step_repeat = { encoded_step[6:0], step_tx_data };  //  How many times the step should be repeated.  Only if step_should_repeat=1

// wire[0:0] step_oled_vdd = encoded_step[6];
// wire[0:0] step_oled_vbat = encoded_step[5];
// wire[0:0] step_oled_res = encoded_step[4];
// wire[0:0] step_oled_dc = encoded_step[3];
wire[0:0] step_wr_spi = encoded_step[2];
wire[0:0] step_rd_spi = encoded_step[1];
wire[0:0] step_wait_spi = encoded_step[0];
wire[0:0] tx_buffer_is_empty;
wire[0:0] charreceived;

reg[0:0] wait_spi = 1'b0;
reg[0:0] rd_spi = 1'b0;
reg[0:0] wr_spi = 1'b0;				
reg[0:0] clk_led = 1'b0;
reg[0:0] rst_led = 1'b0;
reg[0:0] internal_state_machine = 1'b0;
reg[15:0] cnt = 16'h0;
reg[27:0] elapsed_time = 28'h0;
reg[27:0] saved_elapsed_time = 28'h0;
reg[14:0] repeat_count = 15'h0;
reg[7:0] rx_data = 8'h0;
reg[3:0] spi_debug = 4'h0;
reg[7:0] test_display_on = 8'h8f;
reg[7:0] test_display_off = 8'h80;

//  switches[3:0] is {1,1,1,1} when all onboard switches {SW4, SW5, SW6, SW7} are in the down position.
//  We normalise switches[3:0] to {0,0,0,0} such that down=0, up=1.  SW4 is the highest bit, SW7 is the lowest bit.  So {0,0,1,0} becomes value 4'b0010 (decimal 2).
wire[3:0] normalised_switches = { ~switches[0], ~switches[1], ~switches[2], ~switches[3] };

//  normalised_led[3:0] displays a binary value using onboard LEDs, e.g. it displays {0,0,1,0} when value is 4'b0010 (decimal 2).  {1} means LED On, {0} means LED Off.
wire[3:0] normalised_led = //  Depending on the onboard switches {SW4, SW5, SW6, SW7}, we show different debug values with the onboard LEDs...
    (normalised_switches == 4'b0000) ? step_id :    //  If {SW4,5,6,7}={0,0,0,0}, show the TM1637 ROM step ID that we are executing.
    (normalised_switches == 4'b0001) ? spi_debug :  //  If {SW4,5,6,7}={0,0,0,1}, show the SPI step ID that we are executing.
    (normalised_switches == 4'b0010) ? {   //  If {SW4,5,6,7}={0,0,1,0}, 
        clk_led[0], ~clk_led[0],           //  show clk_led (left 2 LEDs, {1,0}=High, {0,1}=Low)
        rst_led[0], ~rst_led[0] } :        //  and rst_led (right 2 LEDs, {1,0}=High, {0,1}=Low).
    (normalised_switches == 4'b0011) ? {   //  If {SW4,5,6,7}={0,0,1,1}, 
        tm1637_clk[0], ~tm1637_clk[0],     //  show the CLK Pin (left 2 LEDs, {1,0}=High, {0,1}=Low)
        tm1637_dio[0], ~tm1637_dio[0] } :  //  and DIO Pin (right 2 LEDs, {1,0}=High, {0,1}=Low).
    normalised_switches;  //  Else show normalised switches using onboard LEDs.

//  Flip the normalised_led bits around to match the onboard LED pins.  {1} means LED Off, {0} means LED Off.  Also the rightmost LED (D6) should show the lowest bit.
//  assign led = { ~normalised_led[0], ~normalised_led[1], ~normalised_led[2], ~normalised_led[3] };

/*
    reg [3:0]clk_div;
    wire clk;
    assign clk = (step_next) ? clk_div[3] : 1'b0;

    always @ (posedge clk_led)
    begin
        //if(btnc)
            //clk_div <= 4'h0;
        //else
            clk_div <= clk_div + 1;
    end
*/

always@(  //  Code below is always triggered when these conditions are true...
    posedge clk_50M[0]  //  When the clock signal transitions from low to high (positive edge) OR
    // or negedge rst_n       //  When the reset signal transitions from high to low (negative edge) which
    ) begin             //  happens when the board restarts or reset button is pressed.

    /*
    if (!rst_n) begin     //  If board restarts or reset button is pressed...
        clk_led <= 1'b0;  //  Init clk_led and cnt to 0. "1'b0" means "1-Bit, Binary Value 0"
        cnt <= 25'd0;     //  "25'd0" means "25-bit, Decimal Value 0"
    end
    else begin
    */
    ////if (cnt >= 24'h000fff) begin  //  (Slow) If our counter has reached its limit...
    if (cnt == 16'h00ff) begin  //  (Fast) If our counter has reached its limit...
        clk_led <= ~clk_led;  //  Toggle the clk_led from 0 to 1 (and 1 to 0).
        cnt <= 16'h0;         //  Reset the counter to 0.
    end
    else begin
        cnt <= cnt + 16'h1;  //  Else increment counter by 1. "16'h1" means "16-bit, Hexadecimal Value 1"
    end
    //end

    //  Display debug values on the onboard LED.  Flip the normalised_led bits around to match the onboard LED pins.  {1} means LED Off, {0} means LED Off.  Also the rightmost LED (D6) should show the lowest bit.
    led <= { ~normalised_led[0], ~normalised_led[1], ~normalised_led[2], ~normalised_led[3] };
    //led <= { ~clk_led[0], ~cnt[3], ~cnt[4], ~cnt[5] };
end

spi_master # (
.WORD_LEN(8),        //  Default 8
.PRESCALLER_SIZE(8)  //  Default 8, Max 8
)
spi0(
	.clk(clk_led),  //  Use the LED clock.

	////.prescaller(3'h0),  //  No prescaler (fast).
	.prescaller(3'h1),  //  Prescale by 2 (slow).
	////.prescaller(3'h2),  //  Prescale by 4 (slower).

    .rst(rst_led),  //  Start transmitting to SPI device when rst_led transitions from low to high.

	////.tx_data(step_tx_data),  //  Transmit real data to SPI device.
	.tx_data(test_display_on),  //  Transmit test data to switch on display (0xAF).

	.rx_data(rx_data),
	.wr(wr_spi),
	.rd(rd_spi),
	.tx_buffer_is_empty(tx_buffer_is_empty),
	.sck(tm1637_clk),
	.mosi(tm1637_dio),
	.miso(1'b1),
	.ss(ss),  //  SPI SS Pin is not used in DIO Mode.
	.lsbfirst(1'b1),  //  Transmit least significant bit first.
	.mode(2'b11),  //  SPI Transmit Phase = Low to High, Clock Polarity = Idle High
	//.senderr(senderr),
	.res_senderr(1'b0),
	.charreceived(charreceived),
    .diomode(1'b1),  //  Select DIO Mode instead of SPI Mode.
    .debug(spi_debug)
);

//  Synchronous lath to out commands directly from ROM except when is a repeat count load.
always @ (posedge clk_led[0])
begin
/*
    if (!rst_n) begin     //  If board restarts or reset button is pressed...
        //  Init the SPI default values.
        oled_vdd <= 1'b1;
		oled_vbat <= 1'b1;
		oled_res <= 1'b0;
		oled_dc <= 1'b0;
		wr_spi <= 1'b0;
		rd_spi <= 1'b0;
		wait_spi <= 1'b0;
    end
    else 
    */
    //  If this is not a repeated step...
    if (!step_should_repeat) begin
        //  Copy the decoded values into registers so they won't change when we go to next step.
        // oled_vdd <= step_oled_vdd;
        // oled_vbat <= step_oled_vbat;
        // oled_res <= step_oled_res;
        // oled_dc <= step_oled_dc;
        wr_spi <= step_wr_spi;
        rd_spi <= step_rd_spi;
        wait_spi <= step_wait_spi;
    end
end

always @ (posedge clk_led[0])
begin
/*
    if (!rst_n) begin     //  If board restarts or reset button is pressed...
        //  Init the state machine.
		elapsed_time <= 28'h0;
		saved_elapsed_time <= 28'h0;
		step_id <= `BLOCK_ROM_INIT_ADDR_WIDTH'h0;
		internal_state_machine <= 1'b0;
		repeat_count <= 15'h0;
    end
*/

    //led <= { ~step_id[0], ~step_id[1], ~step_id[2], ~step_id[3] };

    //  If the start time is up and the step is ready to execute...
    if (elapsed_time >= step_time) begin
        case(internal_state_machine)
            //  First Part: Set up repeating steps.
            1'b0 : begin
                //  If this is a repeating step...
                if (step_should_repeat) begin
                    //  Remember in a register how many times to repeat.
                    repeat_count <= step_repeat;
                    //  Remember the elapsed time for recalling later.
                    saved_elapsed_time <= elapsed_time + 1;
                end
                //  If this is not a repeating step...
                else begin
                    //  If we are still repeating...
                    if (repeat_count && step_next > 1) begin
                        //  Count down number of times to repeat.
                        repeat_count <= repeat_count - 15'h1;
                    end
                end
                //  Handle as a normal step in the next clock tick.
                internal_state_machine <= 1'b1;

                if (rd_spi || wr_spi) begin
                    //  If this is an SPI read or write step, signal to SPI module to start the transfer (rst_led low to high transition).
                    rst_led <= 1'b1;
                end
                else begin
                    //  Reset rst_led to low in case we have previously set to high due to SPI read or write step.
                    rst_led <= 1'b0;
                end

            end
            //  Second Part: Execute the step.
            1'b1 : begin
                //  Reset rst_led to low in case we have previously set to high due to SPI read or write step.
                ////rst_led <= 1'b0;

                //  If we are waiting for SPI command to complete...
                if (wait_spi) begin
                    //  If SPI command has completed...
                    if (charreceived) begin
                        internal_state_machine <= 1'b0;
                        //  If we are still repeating...
                        if (repeat_count) begin
                            //  Restore the elapsed time.
                            elapsed_time <= saved_elapsed_time;
                            //  Jump to the step we should repeat.
                            if (step_backward)
                                step_id <= step_id + ~step_next;
                            else
                                step_id <= step_id + step_next;
                        end
                        //  If we are not repeating, or repeat has completed...
                        else begin
                            elapsed_time <= elapsed_time + 1;
                            //  Move to following step.
                            step_id <= step_id + `BLOCK_ROM_INIT_ADDR_WIDTH'h1;
                        end
                    end
                    //  Else continue waiting for SPI command to complete.
                end
                //  Else we are not waiting for SPI command to complete...
                else begin
                    internal_state_machine <= 1'b0;
                    //  If we are still repeating...
                    if (repeat_count) begin
                        //  Restore the elapsed time.
                        elapsed_time <= saved_elapsed_time;
                        //  Jump to the step we should repeat.
                        if (step_backward)
                            step_id <= step_id + ~step_next;
                        else
                            step_id <= step_id + step_next;
                    end
                    //  If we are not repeating, or repeat has completed...
                    else begin
                        elapsed_time <= elapsed_time + 1;
                        //  Move to following step.
                        step_id <= step_id + `BLOCK_ROM_INIT_ADDR_WIDTH'h1;
                    end
                end
            end
        endcase
    end
    //  If the step start time has not been reached...
    else begin
        //  Wait until the step start time has elapsed.
        elapsed_time <= elapsed_time + 1;
    end
end

endmodule
