//  Based on https://github.com/MorgothCreator/Verilog_SSD1306_CFG_IP
`include "rom.v"

module	LED_TM1637(
    input   wire[0:0] clk_50M,  //  Onboard clock is 50MHz.  Pin 6.
    input   wire[0:0] rst_n,    //  TODO: Reset pin is also an Input, triggered by board restart or reset button.
	output  wire[0:0] tm1637_clk,  //  Pin 131, IO_TYPE=LVCMOS33 BANK_VCCIO=3.3
	output  wire[0:0] tm1637_dio,  //  Pin 132, IO_TYPE=LVCMOS33 BANK_VCCIO=3.3
    output  wire[3:0] led,  //  LED is actually 4 discrete LEDs at 4 Output signals. Each LED Output is 1 bit.  Use FloorPlanner to connect led[0 to 4] to Pins 47, 57, 60, 61
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
reg[24:0] cnt = 25'h0;
reg[27:0] elapsed_time = 28'h0;
reg[27:0] saved_elapsed_time = 28'h0;
reg[14:0] repeat_count = 15'h0;
reg[7:0] rx_data = 8'h0;
reg[3:0] spi_debug = 4'h0;
reg[7:0] test_display_on = 8'h8f;
reg[7:0] test_display_off = 8'h80;

//  switches[3:0] is {1,1,1,1} when all switches {SW4, SW5, SW6, SW7} are in the down position.
//  We normalise switches[3:0] to {0,0,0,0} such that down=0, up=1.  SW4 is the highest bit, SW7 is the lowest bit.
wire[3:0] normalised_switches = { ~switches[0], ~switches[1], ~switches[2], ~switches[3] };

// assign led = { ~spi_debug[0], ~spi_debug[1], ~spi_debug[2], ~spi_debug[3] };  //  Show the debug value in LED.
// assign led = { ~step_id[0], ~step_id[1], ~step_id[2], ~step_id[3] };  //  Show the state machine step ID in LED.
// assign led = { ~step_id[0], ~step_id[1], ~spi_debug[0], ~spi_debug[1] };  //  Show the state machine step ID and debug in LED.
assign led = { ~normalised_switches[0], ~normalised_switches[1], ~normalised_switches[2], ~normalised_switches[3] };

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
    posedge clk_50M  //  When the clock signal transitions from low to high (positive edge) OR
    // or negedge rst_n       //  When the reset signal transitions from high to low (negative edge) which
    ) begin             //  happens when the board restarts or reset button is pressed.

/*
    if (!rst_n) begin     //  If board restarts or reset button is pressed...
        clk_led <= 1'b0;  //  Init clk_led and cnt to 0. "1'b0" means "1-Bit, Binary Value 0"
        cnt <= 25'd0;     //  "25'd0" means "25-bit, Decimal Value 0"
    end
    else begin
    */
        ////if (cnt == 25'd249_9999) begin  //  If our counter has reached its limit...
        if (cnt == 25'd2499_9999) begin  //  If our counter has reached its limit...
            clk_led <= ~clk_led;  //  Toggle the clk_led from 0 to 1 (and 1 to 0).
            cnt <= 25'd0;         //  Reset the counter to 0.
        end
        else begin
            cnt <= cnt + 25'd1;  //  Else increment counter by 1. "25'd1" means "25-bit, Decimal Value 1"
        end
    //end
end

spi_master # (
.WORD_LEN(8),        //  Default 8
.PRESCALLER_SIZE(8)  //  Default 8, Max 8
)
spi0(
    ////.clk(clk_50M),  //  Fast clock.
	.clk(clk_led),  //  Very slow clock.

	.prescaller(3'h0),  //  No prescaler.  Fast.
	////.prescaller(3'h2),  //  Prescale by 4.  Slow.

	////.rst(rst_n),
    .rst(rst_led),  //  Start sending when rst_led transitions from low to hi.

	////.tx_data(step_tx_data),  //  Send real data.
	.tx_data(test_display_on),  //  Send test data to switch on display (0xAF).

	.rx_data(rx_data),
	.wr(wr_spi),
	.rd(rd_spi),
	.tx_buffer_is_empty(tx_buffer_is_empty),
	.sck(tm1637_clk),
	.mosi(tm1637_dio),
	.miso(1'b1),
	.ss(ss),
	.lsbfirst(1'b1),  //  Transmit least significant bit first.
	.mode(2'b11),  //  SPI Transmit Phase = Low to High, Clock Polarity = Idle High
	//.senderr(senderr),
	.res_senderr(1'b0),
	.charreceived(charreceived),
    .diomode(1'b1),
    .debug(spi_debug)
);

//  Synchronous lath to out commands directly from ROM except when is a repeat count load.
always @ (posedge clk_led)
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

always @ (posedge clk_led)
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
