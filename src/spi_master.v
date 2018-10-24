//  Based on https://opencores.org/project/asynchronous_master_spi

module spi_master #(
		parameter WORD_LEN = 8,
		parameter PRESCALER_SIZE = 8
	)(
        //  Input parameters.
        input  /* wire[0:0] */ diomode,  //  1 if we are sending to a DIO device (TM1637 LED) instead of an SPI device.
        input  wire[1:0] mode,  //  SPI mode.  All four modes are supported.
        input  /* wire[0:0] */ lsbfirst,  //  0 to send most significant bit first, 1 to send least significant bit first.
        input  wire[2:0] prescaler,  //  The prescaler divider is = (1 << prescaler) value between 0 and 7 for dividers by:1,2,4,8,16,32,64,128 and 256.

        //  Input signals.
        input  /* wire[0:0] */ clk,  /* Peripheral clock/not necessary to be core clock, the core clock can be different (input) */
        input  /* wire[0:0] */ rst,  /* Asynchronus reset, is mandatory to provide this signal, active on posedge (input) */
        input  /* wire[0:0] */ wr,  //  1 if we should transmit data, asynchronus with 'clk', active on posedge
        input  /* wire[0:0] */ rd,  //  1 if we should receive data, asynchronus with 'clk', active on posedge
        input  wire[WORD_LEN - 1:0] tx_data,  //  Data to be transmitted to SPI device (1 byte)

        //  Outputs.
        output /* wire[0:0] */ tx_completed,  //  1 if data has been trasmitted (output)
        output /* wire[0:0] */ rx_completed,  //  1 if data was received, if you read the receive buffe this bit will go '0', if you ignore it and continue to send data this bit will remain '1' until you read the read register (output) */
        output reg /* [0:0] */ tx_error,/* If you try to send a character if send buffer is full this bit is set to '1', this can be ignored and if is '1' does not affect the interface (output) */
        input  /* wire[0:0] */ rst_tx_error,/* To reset 'tx_error' signal write '1' wait minimum half core clock and and after '0' to this bit, is asynchronous with 'clk' (input)*/
        output wire[WORD_LEN - 1:0] rx_data,  //  Data received from SPI device (1 byte)

        //  Pins connected to SPI device.
        output /* wire[0:0] */ sck,/* SPI 'sck' signal (output) */
        output /* wire[0:0] */ mosi,/* SPI 'mosi' signal (output) */
        input  /* wire[0:0] */ miso,/* SPI 'miso' signal (input) */
        output reg /* [0:0] */ ss,/* SPI 'ss' signal (if send buffer is maintained full the ss signal will not go high between between transmit chars)(output) */

        //  Debug outputs.
        output reg [3:0] debug,  //  Debug value to be shown on the LEDs.
        output reg [3:0] debug_bit_num,  //  Bit number (0 to 8) being transmitted/received now.
        output wire[(WORD_LEN-1):0] debug_tx_buffer,  //  Byte currently transmitting.
        output wire[(WORD_LEN-1):0] debug_rx_buffer,  //  Byte just received.
        output reg debug_waiting_for_tx_data,  //  1 if we are waiting for data to transmit.
        output reg debug_waiting_for_prescaler  //  1 if we are waiting for prescaler to finish counting.
    );

reg[0:0] _mosi;
reg[0:0] _rx_buffer_occupied;
reg[0:0] _rx_buffer_received;
reg[0:0] _tx_buffer_occupied;
reg[0:0] _tx_buffer_sent;
reg[2:0] _prescaler_buffer;
reg[(WORD_LEN-1):0] _tx_buffer;
reg[(WORD_LEN-1):0] _rx_buffer;

//  Transmission is complete IF...
//  transmit buffer is unoccupied and transmit buffer has not been sent
//  OR transmit buffer is occupied and transmit buffer has been sent
////assign tx_completed = (_tx_buffer_occupied == _tx_buffer_sent);
assign tx_completed = ~(_tx_buffer_occupied ^ _tx_buffer_sent);
assign debug_tx_buffer = _tx_buffer;
assign debug_rx_buffer = _rx_buffer;

///////////////////////////////////////////////////////////////////////////////
//  Asynchronus Send

always @ (posedge wr or posedge rst_tx_error or posedge rst) begin  //  Normally we transmit when "wr" transitions from low to high.
    if (rst) begin
        //  When reset signal transitions from low to high, reset the internal registers.
        _tx_buffer_occupied <= 1'b0;  //  Init transmit buffer as unoccupied.  
        tx_error <= 1'b0;  //  Clear any transmit error.
        _prescaler_buffer <= 3'b0;
    end
    else if (rst_tx_error) begin
        //  When caller requests to reset the transmit error, we clear the error.
        tx_error <= 1'b0;
    end
    else if (wr) begin
        //  When caller requests to transmit data...
        if (!tx_completed) begin  //  If previous transmit has not completed...
            tx_error <= 1'b1;  //  Return an error.
        end
        else begin  //  If previous transmit has completed, we prepare to transmit new data.
            _tx_buffer <= tx_data;  //  Copy the transmit data (1 byte) into the transmit buffer.
            _tx_buffer_occupied <= 1'b1;  //  Mark transmit buffer as occupied.  This marks the transmit as incomplete.
            _prescaler_buffer <= prescaler;  //  Prepare the prescaler counter.
        end
    end
end

///////////////////////////////////////////////////////////////////////////////
//  Synchronous Send

//  Constants to represent the current SPI state: Idle and Busy.
localparam[0:0] STATE_IDLE = 1'b0;
localparam[0:0] STATE_BUSY = 1'b1;
reg[0:0] _state;

//  What's a "Prescaler"?  The FPGA clock runs on 50 MHz but that might be too fast for SPI devices
//  (and might be harder to debug).  So we scale it down by a factor, so that the SPI device will
//  get a slower clock.  The factor is called the Prescaler Value.

reg[2:0] _prescaler;  //  "prescaler" parameter stored locally.
reg[PRESCALER_SIZE - 1:0] _prescaler_cnt;  //  Count down for the prescaler.
wire[7:0] _prescdemux =  //  Compute the demux prescaler.  We will count to this demux value before acting on the clock.  Changes when _prescaler changes.
    (_prescaler == 3'b000) ? 8'b00000001 :
    (_prescaler == 3'b001) ? 8'b00000011 :
    (_prescaler == 3'b010) ? 8'b00000111 :
    (_prescaler == 3'b011) ? 8'b00001111 :
    (_prescaler == 3'b100) ? 8'b00011111 :
    (_prescaler == 3'b101) ? 8'b00111111 :
    (_prescaler == 3'b110) ? 8'b01111111 :
    (_prescaler == 3'b111) ? 8'b11111111 :
    8'b00000001;  //  Should not come here.

//  Shift Registers for transmitting and receiving bits.  They are called "Shift" because we shift the bits out/in while transmitting/receiving bits.
reg[WORD_LEN - 1:0] _shift_reg_tx;  //  Next bits to be transmitted to SPI device.
reg[WORD_LEN - 1:0] _shift_reg_rx;  //  Bits received from the SPI device.

//  Decode _sck into bit number and the clock phase.  If _sck changes, these will also change.
reg[4:0] _sck;  //  Count the number of bits sent and phase of the SPI clock.
wire[3:0] _sck_bit_num = _sck[4:1];   //  Bit number currently being sent. _sck_bit_num=7 when 8 bits have been sent
wire[0:0] _sck_transition = _sck[0];  //  Current high/low transition phase of the clock.  _sck_transition=0 during first transition phase of the clock, 1 during second transition phase

reg[0:0] _lsbfirst;  //  1 if we should send Least Significant Bit first.
wire[0:0] _msbfirst = ~_lsbfirst;  //  1 if we should send Most Significant Bit first.  Changes if _lsbfirst changes.
wire[0:0] msbfirst = ~lsbfirst;  //  1 if we should send Most Significant Bit first.  Changes if lsbfirst changes.

reg[0:0] _diomode;  //  "diomode" parameter stored locally.

//  Decode _mode (Internal SPI Mode) into clock phase and polarity.  If _mode changes, these will also change.
reg[1:0] _mode;
wire[0:0] _mode_clk_phase = _mode[0];     //  Clock Phase: 0 means data is valid when clock transitions from high to low. 1 means low to high.
wire[0:0] _mode_clk_polarity = _mode[1];  //  Clock Polarity: 0 means Idle Low, 1 means Idle High
wire[0:0] _mode_clk_idle_low = ~_mode_clk_polarity;
wire[0:0] _mode_clk_idle_high = _mode_clk_polarity;

//  Decode mode (SPI Mode) into clock phase and polarity.  If mode changes, these will also change.
wire[0:0] mode_clk_phase = mode[0];     //  Clock Phase: 0 means data is valid when clock transitions from high to low. 1 means low to high.
wire[0:0] mode_clk_high_to_low = ~mode_clk_phase;
wire[0:0] mode_clk_low_to_high = mode_clk_phase;

//  For DIO: We transmit 9 data bits instead of the normal 8 data bits for SPI.  The last bit is meant for the DIO device to respond with the acknowledgement bit.
//  The last bit must be 0 to keep the DIO connection open.

//  Number of bits to transmit/receive.
wire[3:0] _num_bits = 
  _diomode ? (WORD_LEN + 1)  //  For DIO: 9 bits, counting the acknowledgement bit from device.
  : WORD_LEN;  //  For SPI: 8 bits.  WORD_LEN is normally 8.

//  Number of extra bits we need to transmit to close the SPI or DIO connection, if there are no more bytes to send.
wire[0:0] _num_close_bits = 
    _diomode && (tx_completed) ? 1'b1   //  For DIO: 1 bit, on top of the 9 bits above
    : 1'b0;  //  For SPI: None.

//  When all the bits have been transmitted, we transmit _empty_tx_bit.  For SPI this is 1.
//  For DIO this is 0, so that the 9th bit is set low to keep the connection open.
wire[0:0] _empty_tx_bit = _diomode ? 1'b0 : 1'b1;

////always @ (posedge clk or negedge rst_n) begin
always @ (posedge clk or posedge rst) begin
    //  When reset signal transitions from low to high, prepare to transmit data to SPI device.
    //  When clock transitions from low to high, transmit 1 bit to SPI device.
    ////if (!rst_n) begin
    if (rst) begin
        //  When reset signal transitions from low to high, prepare to transmit data to SPI device.
        //  Reset the internal registers.
        _state <= STATE_IDLE;  //  Start in Idle state.
        _tx_buffer_sent <= 1'b0;  //  Mark the tx buffer as unsent.
        _rx_buffer_occupied <= 1'b0;  //  Mark the rx buffer as empty.
        _shift_reg_tx <= { WORD_LEN{1'b0} };
        _shift_reg_rx <= { WORD_LEN{1'b0} };
        _rx_buffer <= { WORD_LEN{1'b0} };

        _sck <= 5'b0;   //  Init SPI Clock Pin (SCK) to Idle, which may be Idle High or Idle Low depending on SPI Mode.
        _mosi <= 1'b1;  //  For DIO: Init SPI MOSI Pin (Slave Input) to high.
        ss <= 1'b1;     //  Set Slave Select Pin to high to deactivate the SPI device.  We will activate later.  Not used for DIO Mode.

        _prescaler_cnt <= { PRESCALER_SIZE{1'b0} };
        _prescaler <= prescaler;
        _lsbfirst <= lsbfirst;
        _mode <= mode;  //  Init SPI Mode so that SCK Pin will be output correctly at next clock tick.
        _diomode <= diomode;  //  Init DIO Mode so that SCK Pin will be output correctly at next clock tick.

        debug <= 4'd1;  //  Show the debug value in LEDs.
        debug_bit_num <= 4'b0;
        debug_waiting_for_tx_data <= 1'b0;
        debug_waiting_for_prescaler <= 1'b0;
    end
    else begin
        //  When clock transitions from low to high, transmit 1 bit to SPI device.
        case (_state)
            STATE_IDLE: begin  //  If we are idle now...
                //  If we don't have data to transmit...
                if (tx_completed) begin
                    //  Stay in the Idle State and wait for data to transmit.
                    debug_waiting_for_tx_data <= 1'b1;  //  Waiting for data to transmit.
                end
                //  If we have data to transmit...
                else begin
                    debug_waiting_for_tx_data <= 1'b0;  //  Not waiting for data to transmit.
                    debug <= 4'd2;  //  Show the debug value in LEDs.
                    _tx_buffer_sent <= 1'b1;  //  Mark the tx buffer as sent.
                    ////_tx_buffer_sent <= ~_tx_buffer_sent;  //  Mark the tx buffer as sent.
                    ss <= 1'b0;  //  Set Slave Select Pin to low to activate the SPI device.
                    _prescaler_cnt <= { PRESCALER_SIZE{1'b0} };  //  Reset the prescaler count to 0.                    

                    //  Copy the SPI tx/rx parameters to internal registers so they won't change if the caller changes them.
                    _diomode <= diomode;
                    _mode <= mode;
                    _lsbfirst <= lsbfirst;
                    _prescaler <= _prescaler_buffer;

                    //  Get ready to transmit data to the SPI device.
                    _shift_reg_tx <= _tx_buffer;  //  Copy the byte that will be transmitted.
                    _state <= STATE_BUSY;         //  Transition to the busy state.

                    //  For DIO Mode: Assume SCK Pin is high, MOSI Pin is high.  Set MOSI Pin to low to control the bus.
                    //  SPI Mode should be 3.  We will send when SCK goes low to high.
                    //  lsbfirst should be true.

                    if (diomode) begin
                        _mosi <= 1'b0;  //  Start the DIO bus connection.
                    end

                    //  If SPI Mode is 0 or 2, we are supposed to transmit now...
                    if (mode_clk_high_to_low) begin
                        if (msbfirst)
                            //  For Most Significant Bit mode, set the data output to the next highest bit.
                            _mosi <= _tx_buffer[WORD_LEN - 1];
                        else
                            //  For Least Significant Bit mode, set the data output to the next lowest bit.
                            _mosi <= _tx_buffer[0];
                    end
                end
            end
            //  If no data to transmit, we stay in Idle state.
            //  If we are transmitting data, we will transition to Busy state.

            STATE_BUSY: begin  //  If we are busy now...
                //  If we haven't finished counting the prescaler...
                if (_prescaler_cnt != _prescdemux) begin
                    debug_waiting_for_prescaler <= 1'b1;  //  Waiting for prescaler countdown.
                    //  Continue counting and check again at next clock transition.
                    _prescaler_cnt <= _prescaler_cnt + 1;
                end
                //  If we have finished counting the prescaler...
                else begin
                    debug_waiting_for_prescaler <= 1'b0;  //  Not waiting for prescaler countdown.
                    debug <= 4'd3;  //  Show the debug value in LEDs.
                    _prescaler_cnt <= { PRESCALER_SIZE{1'b0} };  //  Reset the prescaler count to 0.
                    _sck <= _sck + 1;  //  Increment the Internal Clock Pin (5 bits wide), that will be truncated as the SPI Clock Pin (SCK Pin, 1 bit).

                    //  Check the phase of the Internal Clock Pin.  If we should receive data now...
                    if (_sck_transition == _mode_clk_phase) begin
                        debug <= 4'd4;  //  Show the debug value in LEDs.
                        //  Receive and save the next bit shifted in from the MISO Pin.  Prepare the next bit (shift out) to be transmitted.
                        //  When all the bits have been transmitted, transmit _empty_tx_bit (1 for SPI, 0 for DIO mode).
                        //  This keeps the DIO connection active.
                        if (_msbfirst) begin
                            _shift_reg_rx <= { miso, _shift_reg_rx[7:1] };
                            _shift_reg_tx <= { _shift_reg_tx[6:0], _empty_tx_bit };
                        end
                        else begin
                            _shift_reg_rx <= { _shift_reg_rx[6:0], miso };
                            _shift_reg_tx <= { _empty_tx_bit, _shift_reg_tx[7:1] };
                        end
                    end

                    //  If we should transmit data now...
                    else begin
                        debug_bit_num <= _sck_bit_num;
                        //  If we have transmitted all 8 bits for SPI (9 bits for DIO)...
                        //  For DIO, if no more bytes to transmit, we actually transmit 1 more bit (total 10 bits) to close the connection.  
                        //  If there are more bytes to transmit, we transit 9 bits followed by the new byte.
                        if (_sck_bit_num == _num_bits + _num_close_bits) begin  //  num_close_bits=1 for DIO Mode and no more bytes to transmit.
                            debug <= 4'd5;  //  Show the debug value in LEDs.
                            _sck <= 5'b0;  //  Reset the Internal Clock Pin to low.  Which also transitions the SPI Clock Pin (SCK Pin) to low.

                            //  If no more bytes to transmit...
                            if (tx_completed) begin
                                debug <= 4'd6;  //  Show the debug value in LEDs.
                                ss <= 1'b1;  //  Set Slave Select Pin (SS Pin) to high to deactivate the SPI device.  No effect in DIO Mode.
                                if (_diomode) begin 
                                    //  For DIO, transition the MOSI Pin from low to high to close the connection.  Assume clk is now high.
                                    debug <= 4'd7;  //  Show the debug value in LEDs.
                                    _mosi <= 1'b1;  //  Close the DIO bus connection.
                                end
                            end
                            _rx_buffer <= _shift_reg_rx;  //  Copy the byte received into the caller's buffer.
                            if (_rx_buffer_occupied == _rx_buffer_received) begin
                                _rx_buffer_occupied <= 1'b1;  //  Mark receive buffer as occupied.
                                ////_rx_buffer_occupied <= ~_rx_buffer_occupied;
                            end
                            _state <= STATE_IDLE;  //  Return to Idle state so we can wait for data to transmit.
                        end
                        //  If we have not finished transmitting all 8 bits for SPI (9 bits for DIO)...
                        else begin
                            debug <= 4'd8;  //  Show the debug value in LEDs.
                            //  Transmit the next bit to the MOSI Pin (Slave Data In).
                            //  For DIO: The 9th bit transmitted will be 0 (defined earlier as _empty_tx_bit) to keep the connection active.
							if (_msbfirst)
								_mosi <= _shift_reg_tx[WORD_LEN - 1];
							else
								_mosi <= _shift_reg_tx[0];
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
////always @ (posedge rd or negedge rst_n) begin  //  Normally we read when "rd" transitions from low to high.
always @ (posedge rd or posedge rst) begin  //  Normally we read when "rd" transitions from low to high.
    ////if (!rst_n) begin
    if (rst) begin
        //  When reset signal transitions from low to high, reset the internal registers.
        _rx_buffer_received <= 1'b0;
    end
    //  If "rd" signals that we should read from SPI device...
    else begin
        if (_rx_buffer_occupied != _rx_buffer_received) begin
            _rx_buffer_received <= ~_rx_buffer_received;
        end
    end
end

//  If we are receiving data from the SPI device, return the receive buffer to the caller.  Else return a hardcoded value "z" (High Impedence)
assign rx_data = (rd) ? _rx_buffer : { WORD_LEN{1'bz} };

//  Set the value of the SPI Clock Pin (SCK Pin) for the SPI device.  Depending on the mode, we return the same value as the
//  Internal Clock Pin.  Or we return the reverse of the Internal Clock Pin.  "sck" changes whenever "_sck" changes.
//  _mode_clk_idle_high=0 means Idle Low, _mode_clk_idle_high=1 means Idle High

//  For DIO: _mode_clk_idle_high=1 (Idle High) so that SCK Pin stays high before and after transmission.

assign sck = (_mode_clk_idle_high) ? ~_sck[0] : _sck[0];

//  Set the value of the MOSI Pin (Slave Data In) for the SPI device.  If the SPI device is inactive (SS=1),
//  we set to high.  If the SPI device is active (SS=0), we set to the Internal MOSI register.
//  "mosi" changes whenever "ss" or "_mosi" changes.

//  For DIO: SS Pin is not used. MOSI Pin should be high before transmission, low after transmission.
//  Before transmission:    / -- --__ \
//  After transmitting a byte, wait 1 clock tick for device to respond.
//  After transmission:     __ / \
//  After responding, if we have no more bytes to transmit, we set SCK Pin to high and transition MOSI from low to high to terminate transmission.
//  Terminate transmission: __ / __--

assign mosi = _diomode  //  If this is DIO mode...
    //  For DIO Mode: SS Pin is not used.  We transmit the Internal MOSI Pin to the actual SPI MOSI Pin.
    ? _mosi
    //  For SPI Mode, check the SS Pin.
    : (ss)
        ? 1'b1    //  If SS=high, SPI device is inactive. Set SPI MOSI Pin to high.  We will transmit to SPI MOSI Pin later when ready.
        : _mosi;  //  If SS=low, SPI device is active. Set SPI MOSI Pin to the Internal MOSI Pin.

assign rx_completed = (_rx_buffer_occupied ^ _rx_buffer_received);

endmodule

//  DIO Protocol:
//  Before transmission:    / -- --__ \
//  Transmit byte in LSB:   0x40
//  After transmission:     __ / \
//  Terminate transmission: __ / __--
