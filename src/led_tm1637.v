//  Based on https://github.com/MorgothCreator/Verilog_SSD1306_CFG_IP

`include "rom.v"

module demo (  //  Declare our demo module.
    input   /* wire[0:0] */ clk_50M,  //  Onboard clock is 50MHz.  Pin 6.
    input   /* wire[0:0] */ rst_n,    //  TODO: Reset pin is also an Input, triggered by board restart or reset button.
    output  /* wire[0:0] */ tm1637_clk,  //  IO_TYPE=LVCMOS33 BANK_VCCIO=3.3
    output  /* wire[0:0] */ tm1637_dio,  //  IO_TYPE=LVCMOS33 BANK_VCCIO=3.3
    output  /* wire[0:0] */ tm1637_clk_drain,  //  Pin 131, IO_TYPE=LVCMOS33 DRIVE=24 OPEN_DRAIN=ON BANK_VCCIO=3.3; (with pull-up resistors)
    output  /* wire[0:0] */ tm1637_dio_drain,  //  Pin 132, IO_TYPE=LVCMOS33 DRIVE=24 OPEN_DRAIN=ON BANK_VCCIO=3.3; (with pull-up resistors)
    output  reg tm1637_vcc,  //  Pin 133, IO_TYPE=LVCMOS33 DRIVE=24 BANK_VCCIO=3.3
    output  reg [3:0] led,  //  LED is actually 4 discrete LEDs at 4 Output signals. Each LED Output is 1 bit.  Use FloorPlanner to connect led[0 to 4] to Pins 47, 57, 60, 61
    input   wire[3:0] switches  //  SW4-SW7 for controlling the debug LED.  Use FloorPlanner to connect switches[0 to 4] to Pins 68, 69, 79, 80
);

//  For Open Drain Pins: High=High Impedence (Z), Low=Gnd.  We convert CLK and DIO pins to Open Drain.
assign tm1637_clk_drain = tm1637_clk ? 1'bz : 1'b0;
assign tm1637_dio_drain = tm1637_dio ? 1'bz : 1'b0;

reg[24:0] cnt;
reg clk_led;

//  The step ID that we are now executing: 0, 1, 2, ...
reg[`BLOCK_ROM_INIT_ADDR_WIDTH-1:0] step_id;
//  The step details, encoded in 48 bits.  This will be refetched whenever step_id changes.
wire[`BLOCK_ROM_INIT_DATA_WIDTH-1:0] encoded_step;
//  Whenever step_id is updated, fetch the encoded step from ROM.
LED_TM1637_ROM oled_rom_init(
    .addr(step_id),
    .dout(encoded_step)
);

//  This block increments a counter and flips the clk_led bit on or off upon overflow.
always@(                //  Code below is always triggered when these conditions are true...
    posedge clk_50M or  //  When the clock signal transitions from low to high (positive edge) OR
    negedge rst_n       //  When the reset signal transitions from high to low (negative edge) which
    ) begin             //  happens when the board restarts or reset button is pressed.

    if (!rst_n) begin     //  If board restarts or reset button is pressed...
        clk_led <= 1'b0;  //  Init clk_led and cnt to 0. "1'b0" means "1-Bit, Binary Value 0"
        cnt <= 25'd0;     //  "25'd0" means "25-bit, Decimal Value 0"
    end
    else begin
        if (cnt == 25'd2499_9999) begin  //  If our counter has reached its limit...
            clk_led <= ~clk_led;  //  Toggle the clk_led from 0 to 1 (and 1 to 0).
            cnt <= 25'd0;         //  Reset the counter to 0.
        end
        else begin
            cnt <= cnt + 25'd1;  //  Else increment counter by 1. "25'd1" means "25-bit, Decimal Value 1"
        end
    end
end

reg[24:0] cnt2;  //// TODO
reg[0:0] wait_spi; // = 1'b0;
reg[0:0] rd_spi; // = 1'b0;
reg[0:0] wr_spi; // = 1'b0;
reg[0:0] rst_led; // = 1'b0;
reg[0:0] internal_state_machine; // = 1'b0;
reg[27:0] elapsed_time; // = 28'h0;
reg[27:0] saved_elapsed_time; // = 28'h0;
reg[14:0] repeat_count; // = 15'h0;
reg[7:0] tx_data; // = 8'h0;
reg[7:0] test_display_on; // = 8'h8f;
reg[7:0] test_display_off; // = 8'h80;
reg[0:0] debug_waiting_for_step_time; // = 1'b0;
reg[0:0] debug_waiting_for_spi; // = 1'b0;

wire[7:0] rx_data; // = 8'h0;
wire[3:0] spi_debug; // = 4'h0;
wire[3:0] spi_debug_bit_num; // = 4'h0;
wire[0:0] ss; // = 1'b0;  //  Not used for DIO Mode.
wire[0:0] debug_waiting_for_tx_data;
wire[0:0] debug_waiting_for_prescaller;
wire[7:0] debug_tx_buffer;
wire[7:0] debug_rx_buffer;
wire[0:0] tx_buffer_is_empty;
wire[0:0] charreceived;

spi_master # (
    .WORD_LEN(8),        //  Default 8
    .PRESCALLER_SIZE(8)  //  Default 8, Max 8
)
spi0(
    .clk(clk_led),  //  Use the LED clock.

    ////.prescaller(3'h0),  //  No prescaler (fast).
    .prescaller(3'h1),  //  Prescale by 2 (slow).
    ////.prescaller(3'h2),  //  Prescale by 4 (slower).

    .rst_n(rst_n),  //  Init connection to SPI device when rst_n transitions from high to low.

    .tx_data(tx_data),  //  Transmit real data to SPI device.
    //.tx_data(test_display_on),  //  Transmit test data to switch on display (0xAF).

    .rx_data(rx_data),
    .wr(wr_spi),
    .rd(rd_spi),
    .tx_buffer_is_empty(tx_buffer_is_empty),
    .sck(tm1637_clk),
    .mosi(tm1637_dio),
    .miso(1'b1),  //  MISO Pin is not used in DIO Mode.
    .ss(ss),  //  SPI SS Pin is not used in DIO Mode.
    .lsbfirst(1'b1),  //  Transmit least significant bit first.
    .mode(2'b11),  //  SPI Transmit Phase = Low to High, Clock Polarity = Idle High
    //.senderr(senderr),
    .res_senderr(1'b0),
    .charreceived(charreceived),
    .diomode(1'b1),  //  Select DIO Mode instead of SPI Mode.

    //  Debug output for tracing the SPI operations.
    .debug(spi_debug),
    .debug_bit_num(spi_debug_bit_num),
    .debug_tx_buffer(debug_tx_buffer),
    .debug_rx_buffer(debug_rx_buffer),
    .debug_waiting_for_tx_data(debug_waiting_for_tx_data),
    .debug_waiting_for_prescaller(debug_waiting_for_prescaller)
);

//  switches[3:0] is {1,1,1,1} when all onboard switches {SW4, SW5, SW6, SW7} are in the down position.
//  We normalise switches[3:0] to {0,0,0,0} such that down=0, up=1.  SW4 is the highest bit, SW7 is the lowest bit.  So {0,0,1,0} becomes value 4'b0010 (decimal 2).
wire[3:0] normalised_switches = { ~switches[0], ~switches[1], ~switches[2], ~switches[3] };

//  normalised_led[3:0] displays a binary value using onboard LEDs, e.g. it displays {0,0,1,0} when value is 4'b0010 (decimal 2).  {1} means LED On, {0} means LED Off.
wire[3:0] normalised_led = //  Depending on the onboard switches {SW4, SW5, SW6, SW7}, we show different debug values with the onboard LEDs...
    (normalised_switches == 4'b0000) ? cnt2[3:0] :  //  If {SW4,5,6,7}={0,0,0,0}, show the cnt2 counter, which is always increasing.
    (normalised_switches == 4'b0001) ? step_id :    //  If {SW4,5,6,7}={0,0,0,1}, show the TM1637 ROM step ID that we are executing.
    (normalised_switches == 4'b0010) ? spi_debug :  //  If {SW4,5,6,7}={0,0,1,0}, show the SPI step ID that we are executing.
    (normalised_switches == 4'b0011) ? spi_debug_bit_num :  //  If {SW4,5,6,7}={0,0,1,1}, show the SPI bit number being sent/received.
    (normalised_switches == 4'b0100) ? debug_tx_buffer[3:0] :  //  If {SW4,5,6,7}={0,1,0,0}, show the byte being sent (lowest 4 bits).
    (normalised_switches == 4'b0101) ? debug_rx_buffer[3:0] :  //  If {SW4,5,6,7}={0,1,0,1}, show the byte just received (lowest 4 bits).
    (normalised_switches == 4'b0110) ? {   //  If {SW4,5,6,7}={0,1,1,0},
        clk_led[0], ~clk_led[0],           //  show clk_led (left 2 LEDs, {1,0}=High, {0,1}=Low)
        rst_led[0], ~rst_led[0] } :        //  and rst_led (right 2 LEDs, {1,0}=High, {0,1}=Low).
    (normalised_switches == 4'b0111) ? {   //  If {SW4,5,6,7}={0,1,1,1},
        tm1637_clk[0], ~tm1637_clk[0],     //  show the CLK Pin (left 2 LEDs, {1,0}=High, {0,1}=Low)
        tm1637_dio[0], ~tm1637_dio[0] } :  //  and DIO Pin (right 2 LEDs, {1,0}=High, {0,1}=Low).
    (normalised_switches == 4'b1000) ? {   //  If {SW4,5,6,7}={1,0,0,0}, 
        debug_waiting_for_step_time[0], 
        debug_waiting_for_spi[0],
        debug_waiting_for_tx_data[0], 
        debug_waiting_for_prescaller[0] } :
    normalised_switches;  //  Else show normalised switches using onboard LEDs.

//  Display debug values on the onboard LED.  Flip the normalised_led bits around to match the onboard LED pins.  {1} means LED Off, {0} means LED Off.  Also the rightmost LED (D6) should show the lowest bit.
assign led =
    (!rst_n) ? 4'b1111 :     //  If board restarts or reset button is pressed, switch on all 4 LEDs.
    { ~normalised_led[0], ~normalised_led[1], ~normalised_led[2], ~normalised_led[3] };  //  Else show the debug values.
//  assign led = { ~cnt2[0], ~cnt2[1], ~cnt2[2], ~cnt2[3] };

//  We define convenience wires to decode our encoded step.  Prefix by "step" so we don't mix up our local registers vs decoded values.
//  If encoded_step is changed, these will automatically change.
wire[0:0] step_backward = encoded_step[47];  //  1 if next step is backwards i.e. a negative offset.
wire[2:0] step_next = encoded_step[46:44];  //  Offset to the next step, i.e. 1=go to following step.  If step_backward=1, go backwards.
wire[23:0] step_time = encoded_step[39:16];  //  Number of clk_led clock cycles to wait before starting this step. This time is relative to the time of power on.
// wire[23:0] step_time = 24'h1; //// TODO: Hardcoded step_time to avoid waiting.
wire[7:0] step_tx_data = encoded_step[15:8];  //  Data to be transmitted via SPI (1 byte).
wire[0:0] step_should_repeat = encoded_step[7];  //  1 if step should be repeated.
wire[3:0] step_repeat = encoded_step[6:3];  //  How many times the step should be repeated.  Only if step_should_repeat=1

// wire[0:0] step_oled_vdd = encoded_step[6];
// wire[0:0] step_oled_vbat = encoded_step[5];
// wire[0:0] step_oled_res = encoded_step[4];
// wire[0:0] step_oled_dc = encoded_step[3];
wire[0:0] step_wr_spi = encoded_step[2];
wire[0:0] step_rd_spi = encoded_step[1];
wire[0:0] step_wait_spi = encoded_step[0];

always@(                //  Code below is always triggered when these conditions are true...
    posedge clk_led or  //  When the clk_led register transitions from low to high (positive edge) OR
    negedge rst_n       //  When the reset signal transitions from high to low (negative edge) which
    ) begin             //  happens when the board restarts or reset button is pressed.

    if (!rst_n) begin     //  If board restarts or reset button is pressed...
        //clk_led2 <= 1'b0;
        cnt2 <= 25'd0;

        //  Init registers here.
        tm1637_vcc <= 1'b1;  //  Turn on power supply.
        step_id <= `BLOCK_ROM_INIT_ADDR_WIDTH'h0;
        /* reg[0:0] */ wait_spi <= 1'b0;
        /* reg[0:0] */ rd_spi <= 1'b0;
        /* reg[0:0] */ wr_spi <= 1'b0;
        /* reg[0:0] */ rst_led <= 1'b0;
        /* reg[0:0] */ internal_state_machine <= 1'b0;
        /* reg[27:0] */ elapsed_time <= 28'h0;
        /* reg[27:0] */ saved_elapsed_time <= 28'h0;
        /* reg[14:0] */ repeat_count <= 4'h0;
        ///* reg[7:0] */ rx_data <= 8'h0;
        ///* reg[3:0] */ spi_debug <= 4'h0;
        ///* reg[3:0] */ spi_debug_bit_num <= 4'h0;
        /* reg[7:0] */ test_display_on <= 8'h8f;
        /* reg[7:0] */ test_display_off <= 8'h80;
        ///* reg[0:0] */ ss <= 1'b0;  //  Not used for DIO Mode.
        /* reg[0:0] */ debug_waiting_for_step_time <= 1'b0;
        /* reg[0:0] */ debug_waiting_for_spi <= 1'b0;
        ///* reg[0:0] */ debug_waiting_for_tx_data <= 1'b0;
        ///* reg[0:0] */ debug_waiting_for_prescaller <= 1'b0;
    end
    else begin
        if (cnt2 == 25'd2499_9999) begin  //  If our counter has reached its limit...
            //clk_led2 <= ~clk_led2;
            cnt2 <= 25'd0;
        end
        else begin
            cnt2 <= cnt2 + 25'd1;
        end

        //  If this is not a repeated step...
        if (!step_should_repeat) begin
            //  Copy the decoded values into registers so they won't change when we go to next step.
            //  Values are valid only in next clk_led tick.
            tx_data <= step_tx_data;
            wr_spi <= step_wr_spi;
            rd_spi <= step_rd_spi;
            wait_spi <= step_wait_spi;
        end

        //  If the step start time has not been reached...
        if (elapsed_time < step_time) begin
            debug_waiting_for_step_time <= 1'b1;  //  Waiting for step start time.
            //  Wait until the step start time has elapsed.
            elapsed_time <= elapsed_time + 28'h1;
        end
        //  If the start time is up and the step is ready to execute...
        else begin
            debug_waiting_for_step_time <= 1'b0;  //  Not waiting for step start time.
            //  Execute the steps for First Tick and Second Tick of clk_led...
            case (internal_state_machine)
                //  First Tick: Set up repeating steps.  Don't use wr_spi, rd_spi, wait_spi here because they are only valud in the next clk_led tick.
                1'b0 : begin
                    //  If this is a repeating step...
                    if (step_should_repeat) begin
                        //  Remember in a register how many times to repeat.
                        repeat_count <= step_repeat;
                        //  Remember the elapsed time for recalling later.
                        saved_elapsed_time <= elapsed_time + 28'h1;
                    end
                    //  If this is not a repeating step...
                    else begin
                        //  If we are still repeating...
                        if (repeat_count && step_next > 1) begin
                            //  Count down number of times to repeat.
                            repeat_count <= repeat_count - 4'h1;
                        end
                    end

                    if (step_rd_spi || step_wr_spi) begin
                        //  If this is an SPI read or write step, signal to SPI module to start the transfer (rst_led low to high transition).
                        ////rst_led <= 1'b1;
                    end
                    else begin
                        //  Reset rst_led to low in case we have previously set to high due to SPI read or write step.
                        ////rst_led <= 1'b0;
                    end

                    //  Jump to Second Tick step below in the next clock tick.
                    internal_state_machine <= 1'b1;
                end

                //  Second Tick: Execute the step.  We can use wr_spi, rd_spi, wait_spi here because this is already the next clk_led tick.
                1'b1 : begin
                    //  Reset rst_led to low in case we have previously set to high due to SPI read or write step.
                    ////rst_led <= 1'b0;

                    //  If we are waiting for SPI command to complete...
                    if (wait_spi) begin
                        //  If SPI command has completed...
                        if (charreceived) begin
                            debug_waiting_for_spi <= 1'b0;  //  SPI command has just completed.
                            internal_state_machine <= 1'b0;  //  Will resume at First Tick.

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
                                elapsed_time <= elapsed_time + 28'h1;
                                //  Move to following step.
                                step_id <= step_id + `BLOCK_ROM_INIT_ADDR_WIDTH'h1;
                            end
                        end
                        //  Else continue waiting for SPI command to complete.
                        else begin
                            debug_waiting_for_spi <= 1'b1;  //  Waiting for SPI command to complete.
                            //  Continue waiting for SPI command to complete.  Will resume at Second Tick.
                        end
                    end
                    //  Else we are not waiting for SPI command to complete...
                    else begin
                        debug_waiting_for_spi <= 1'b0;  //  Not waiting for SPI command to complete.
                        internal_state_machine <= 1'b0;  //  Will resume at First Tick.

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
                            elapsed_time <= elapsed_time + 28'h1;
                            //  Move to following step.
                            step_id <= step_id + `BLOCK_ROM_INIT_ADDR_WIDTH'h1;
                        end
                    end
                end
            endcase
        end

    end
end

endmodule

