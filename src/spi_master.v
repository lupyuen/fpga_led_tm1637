`timescale 1ns / 1ps
//  Based on https://git.morgothdisk.com/VERILOG/VERILOG-UTIL-IP/blob/master/spi_master
////////////////////////////////////////////////////////////////////////////////
////                                                                        ////
//// Project Name: ASYNCHRONOUS SPI MASTER (Verilog)                        ////
////                                                                        ////
//// Module Name: spi_master                                                ////
////                                                                        ////
////                                                                        ////
////  Author(s):                                                            ////
////      Iulian Gheorghiu                                                  ////
////                                                                        ////
////  Create Date: 01/17/2017 11:21:57 AM                                   ////
////  Refer to simulate.v for more information                              ////
////  Revision 0.01 - File Created                                          ////
////                                                                        ////
////////////////////////////////////////////////////////////////////////////////

module spi_master #(
		parameter WORD_LEN = 8,
		parameter PRESCALLER_SIZE = 8
	)(
        input rst,/* Asynchronus reset, is mandatory to provide this signal, active on posedge (input) */
        input clk,/* Peripheral clock/not necessary to be core clock, the core clock can be different (input) */
        ////inout [WORD_LEN - 1:0]bus,/* In/Out data(bidirectional) */  ////TODO
        input[WORD_LEN - 1:0] data_in, //// In data
        output[WORD_LEN - 1:0] data_out, //// Out data
        input wr,/* Should send data, asynchronus with 'clk', active on posedge or negedge (input) */
        input rd,/* Should read data, asynchronus with 'clk', active on posedge or negedge (input) */
        output buffempty,/* '1' if transmit buffer is empty (output) */
        input[2:0] prescaller,/* The prescaller divider is = (1 << prescaller) value between 0 and 7 for dividers by:1,2,4,8,16,32,64,128 and 256 (input)*/
        output sck,/* SPI 'sck' signal (output) */
        output mosi,/* SPI 'mosi' signal (output) */
        input miso,/* SPI 'miso' signal (input) */
        output reg ss,/* SPI 'ss' signal (if send buffer is maintained full the ss signal will not go high between between transmit chars)(output) */
        input lsbfirst,/* If '0' msb is send first, if '1' lsb is send first (input) */
        input[1:0] mode,/* All four modes is supported (input) */
        output reg senderr,/* If you try to send a character if send buffer is full this bit is set to '1', this can be ignored and if is '1' does not affect the interface (output) */
        input res_senderr,/* To reset 'senderr' signal write '1' wait minimum half core clock and and after '0' to this bit, is asynchronous with 'clk' (input)*/
        output charreceived,/* Is set to '1' if a character is received, if you read the receive buffe this bit will go '0', if you ignore it and continue to send data this bit will remain '1' until you read the read register (output) */
        output reg[3:0] debug  //  Debug value to be shown on the LEDs.
    );

reg _mosi;

reg charreceivedp;
reg charreceivedn;

reg inbufffullp = 1'b0;
reg inbufffulln = 1'b0;

reg[WORD_LEN - 1:0] input_buffer;
reg[WORD_LEN - 1:0] output_buffer;

assign buffempty = ~(inbufffullp ^ inbufffulln);
reg[2:0] prescallerbuff;

/***********************************************/
/************* Asynchronus send ****************/
/***********************************************/
/*
 *  You need to put the data on the bus and wait a half of core clock to assert the wr signal(see simulation).
 */
`ifdef WRITE_ON_NEG_EDGE == 1
always @ (negedge wr)  //  Not used.
`else
always @ (posedge wr)  //  Normally we send when "wr" transitions from low to high.
`endif
begin
    //  If we should send data and the send buffer is empty...
    if (wr && inbufffullp == inbufffulln && buffempty) begin
        //  Copy the send data (1 byte) into the send buffer.
        input_buffer <= data_in; ////
        ////input_buffer <= bus;
    end
end

`ifdef WRITE_ON_NEG_EDGE == 1
always @ (negedge wr or posedge res_senderr or posedge rst)  //  Not used.
`else
always @ (posedge wr or posedge res_senderr or posedge rst)  //  Normally we send when "wr" transitions from low to high.
`endif
begin
    if (rst) begin
        //  When reset signal transitions from low to high, reset the internal registers.
        inbufffullp <= 1'b0;
        senderr <= 1'b0;
        prescallerbuff <= 3'b000;
    end
    else
    if (res_senderr)
        senderr <= 1'b0;
    else
    //  If we should send data and the send buffer is empty...
    if (wr && inbufffullp == inbufffulln && buffempty) begin
        inbufffullp <= ~inbufffullp;
        prescallerbuff <= prescaller;
    end
    else
    //  If we should send data and the send buffer is full...
    if (!buffempty)
        senderr <= 1'b1;  //  Return an error.
end

/***********************************************/
/************ !Asynchronus send ****************/
/***********************************************/

//  Constants to represent the current SPI state: Idle and Busy.
localparam state_idle = 1'b0;
localparam state_busy = 1'b1;
reg state;

//  What's a "Prescaller"?  The FPGA clock runs on 50 MHz but that might be too fast for SPI devices
//  (and might be harder to debug).  So we scale it down by a factor, so that the SPI device will
//  get a slower clock.  The factor is called the Prescaller Value.

reg[PRESCALLER_SIZE - 1:0] prescaller_cnt;  //  Count down for the prescaller.
reg[WORD_LEN - 1:0] shift_reg_out;  //  Next bits to be sent to SPI device.
reg[WORD_LEN - 1:0] shift_reg_in;  //  Bits received from the SPI device.
reg[4:0] sckint;  //  Count the phase of the SPI clock.
//reg sckintn;
reg[2:0] prescallerint;
reg[7:0] prescdemux;  //  The demux prescaller.

always @ (*) begin  //  This code is triggered when any of the module's inputs change.
    //  Compute the demux prescaller.  The prescaller indicates the power of 2 to count down,
    //  so demux(0)=1, demux(1)=3, demux(2)=7, ...
    if (prescallerint < PRESCALLER_SIZE) begin
        case (prescallerint)
            3'b000: prescdemux <= 8'b00000001;
            3'b001: prescdemux <= 8'b00000011;
            3'b010: prescdemux <= 8'b00000111;
            3'b011: prescdemux <= 8'b00001111;
            3'b100: prescdemux <= 8'b00011111;
            3'b101: prescdemux <= 8'b00111111;
            3'b110: prescdemux <= 8'b01111111;
            3'b111: prescdemux <= 8'b11111111;
        endcase
    end
    //  If prescaller is invalid...
    else begin
        prescdemux <= 8'b00000001;  //  Assume demux=1.
    end
end

reg lsbfirstint;
reg [1:0]modeint;

always @ (posedge clk or posedge rst) begin
    //  When reset signal transitions from low to high, prepare to send data to SPI device.
    //  When clock transitions from low to high, send 1 bit to SPI device.
    if (rst) begin
        //  When reset signal transitions from low to high, prepare to send data to SPI device.
        //  Reset the internal registers.
        debug <= 4'd1;  //  Show the debug value in LEDs.
        inbufffulln <= 1'b0;  //  Mark the tx buffer as empty.
        ss <= 1'b1;  //  Set Slave Select Pin to high to deactivate the SPI device.  We will activate later.
        state <= state_idle;  //  Start in Idle state.
        prescaller_cnt <= { PRESCALLER_SIZE{1'b0} };
        prescallerint <= { PRESCALLER_SIZE{3'b0} };
        shift_reg_out <= { WORD_LEN{1'b0} };
        shift_reg_in <= { WORD_LEN{1'b0} };
        sckint <= { 5{1'b0} };
        _mosi <= 1'b1;
        output_buffer <= { WORD_LEN{1'b0} };
        charreceivedp <= 1'b0;
        lsbfirstint <= 1'b0;
        modeint <= 2'b00;
    end
    else begin
        //  When clock transitions from low to high, send 1 bit to SPI device.
        case (state)
            state_idle: begin  //  If we are idle now...            
                //  If we have data to send...
                if (inbufffullp != inbufffulln) begin
                    debug <= 4'd2;  //  Show the debug value in LEDs.
                    inbufffulln <= ~inbufffulln;  //  Mark the data sent.
                    ss <= 1'b0;  //  Set Slave Select Pin to low to activate the SPI device.
                    prescaller_cnt <= { PRESCALLER_SIZE{1'b0} };  //  Reset the prescaller count to 0.

                    //  Copy the SPI tx/rx parameters to internal registers so they won't change if the caller changes them.
                    prescallerint <= prescallerbuff;
                    lsbfirstint <= lsbfirst;
                    modeint <= mode;

                    //  Get ready to send data to the SPI device.
                    shift_reg_out <= input_buffer;  //  Copy the byte that will be sent.
                    state <= state_busy;  //  Transition to the busy state.

                    //  For DIO: Assume SCK Pin is high, MOSI Pin is high.  Set MOSI Pin to low to control the bus.
                    //  SPI Mode should be 1 or 3.  We will send when SCK goes low to high.

                    //  If SPI Mode is 0 or 2, we are supposed to send now...
                    if (!mode[0]) begin
                        if (!lsbfirst)
                            //  For Most Significant Bit mode, set the data output to the next highest bit.
                            _mosi <= input_buffer[WORD_LEN - 1];
                        else
                            //  For Least Significant Bit mode, set the data output to the next lowest bit.
                            _mosi <= input_buffer[0];
                    end
                end
            end
            //  If no data to send, we stay in Idle state.
            //  If we are sending data, we will transition to Busy state.

            state_busy: begin  //  If we are busy now...
                //  If we haven't finished counting the prescaller...
                if (prescaller_cnt != prescdemux) begin
                    //  Continue counting and check again at next clock transition.
                    prescaller_cnt <= prescaller_cnt + 1;
                end
                //  If we have finished counting the prescaller...
                else begin
                    debug <= 4'd3;  //  Show the debug value in LEDs.
                    prescaller_cnt <= { PRESCALLER_SIZE{1'b0} };  //  Reset the prescaller count to 0.
                    sckint <= sckint + 1;  //  Increment the Internal Clock Pin (5 bits wide), that will be truncated as the Output Clock Pin.

                    //  Check the phase of the Internal Clock Pin.  If we should read data now...
                    if (sckint[0] == modeint[0]) begin
                        debug <= 4'd4;  //  Show the debug value in LEDs.
                        //  Read the next bit from the MISO Pin.  Prepare the next bit to be sent.
                        if (!lsbfirstint) begin
                            shift_reg_in <= { miso, shift_reg_in[7:1] };
                            shift_reg_out <= { shift_reg_out[6:0], 1'b1 };
                        end
                        else begin
                            shift_reg_in <= { shift_reg_in[6:0], miso };
                            shift_reg_out <= { 1'b1, shift_reg_out[7:1] };
                        end
                    end

                    //  If we should send data now...
                    else begin
                        //  If we have sent all 8 bits...
                        if (sckint[4:1] == WORD_LEN - 1) begin
                            debug <= 4'd5;  //  Show the debug value in LEDs.
                            sckint <= { 5{1'b0} };  //  Reset the Internal Clock Pin to low.  Which also transitions the SPI Clock Pin to low.
                            //  If no more bytes to send...
                            if (inbufffullp == inbufffulln) begin
                                debug <= 4'd6;  //  Show the debug value in LEDs.
                                ss <= 1'b1;  //  Set Slave Select Pin to high to deactivate the SPI device.
                            end
                            output_buffer <= shift_reg_in;  //  Copy the byte received into the caller's buffer.
                            if (charreceivedp == charreceivedn)
                                charreceivedp <= ~charreceivedp;
                            state <= state_idle;  //  Return to Idle state so we can wait for data to send.
                        end
                        //  If we have not finished sending all 8 bits...
                        else begin
                            debug <= 4'd6;  //  Show the debug value in LEDs.
                            //  Send the next bit to the MOSI Pin (Slave Data In).
							if (!lsbfirstint)
								_mosi <= shift_reg_out[WORD_LEN - 1];
							else
								_mosi <= shift_reg_out[0];
                        end
                    end
                end
            end
        endcase
    end
end
/*
 *  You need to assert rd signal, wait a half core clock and after read the data(see simulation).
 */
`ifdef READ_ON_NEG_EDGE == 1
always @ (negedge rd or posedge rst)  //  Not used.
`else
always @ (posedge rd or posedge rst)  //  Normally we read when "rd" transitions from low to high.
`endif
begin
    if (rst)
        //  When reset signal transitions from low to high, reset the internal registers.
        charreceivedn <= 1'b0;
    else
    if (charreceivedp != charreceivedn)
        charreceivedn <= ~charreceivedn;
end

//  If we are reading from the SPI device, return the read buffer to the caller.  Else return a hardcoded value ("z" = High Impedence)
assign data_out = (rd) ? output_buffer : { WORD_LEN{1'bz} }; ////
////assign bus = (rd) ? output_buffer : { WORD_LEN{1'bz} };

//  Set the value of the Clock Pin for the SPI device.  Depending on the mode, we return the same value as the
//  Internal Clock Pin.  Or we return the reverse of the Internal Clock Pin.  "sck" changes whenever "sckint" changes.
//  modeint[1]=0 means Idle Low, modeint[1]=1 means Idle High
//  For DIO: modeint[1]=1 for Idle High
assign sck = (modeint[1]) ? ~sckint : sckint;

//  Set the value of the MOSI Pin (Slave Data In) for the SPI device.  If the SPI device is inactive (SS=1),
//  we set to high.  If the SPI device is active (SS=0), we set to the Internal MOSI register.
//  "mosi" changes whenever "ss" or "_mosi" changes.
//  For DIO: When SS=1 (inactive), MOSI Pin should be high
assign mosi = (ss) ? 1'b1 : _mosi;

assign charreceived = (charreceivedp ^ charreceivedn);

endmodule
