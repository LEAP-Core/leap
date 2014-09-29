//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/physical_platform.bsh"

`include "awb/rrr/service_ids.bsh"
`include "awb/rrr/server_stub_FRONT_PANEL.bsh"
`include "awb/rrr/client_stub_FRONT_PANEL.bsh"

`define FP_POLL_INTERVAL    1000

typedef Bit#(4) FRONTP_LEDS;
typedef SizeOf#(FRONTP_LEDS) FRONTP_NUM_LEDS;

//
// Data structure for updating specific LEDs and leaving others unchanged.
//
typedef struct
{
    FRONTP_LEDS state;
    FRONTP_LEDS mask;
}
FRONTP_MASKED_LEDS deriving (Eq, Bits);

typedef Bit#(4) FRONTP_SWITCHES;
typedef SizeOf#(FRONTP_SWITCHES) FRONTP_NUM_SWITCHES;

typedef Bit#(5) FRONTP_BUTTONS;
typedef SizeOf#(FRONTP_BUTTONS) FRONTP_NUM_BUTTONS;

typedef struct
{
    Bit#(1) bUp;
    Bit#(1) bDown;
    Bit#(1) bLeft;
    Bit#(1) bRight;
    Bit#(1) bCenter;
}
FRONTP_BUTTON_INFO
    deriving (Eq, Bits);

typedef Bit#(32) FRONTP_INPUT_STATE;

// Although this is a simulator, we need to retain access to llpi --
// fpga-front panels will need to be tied to physical wires.

module [CONNECTED_MODULE] mkFrontPanel#(LowLevelPlatformInterface llpi) (Empty);

    // Connections to user code.  Note that the connections are optional. 
    Connection_Receive#(FRONTP_MASKED_LEDS) linkLEDs     <- mkConnectionRecvOptional("fpga_leds");
    Connection_Send#(FRONTP_SWITCHES)       linkSwitches <- mkConnectionSendOptional("fpga_switches");
    Connection_Send#(FRONTP_BUTTON_INFO)    linkButtons  <- mkConnectionSendOptional("fpga_buttons");


    // state
    Reg#(FRONTP_INPUT_STATE)    inputCache  <- mkReg(0);
    Reg#(FRONTP_LEDS)           ledState    <- mkReg(0);

    // stubs
    ServerStub_FRONT_PANEL server_stub <- mkServerStub_FRONT_PANEL();
    ClientStub_FRONT_PANEL client_stub <- mkClientStub_FRONT_PANEL();

    // read incoming updates for switch/button state
    rule probeUpdates (True);
        UINT32 data <- server_stub.acceptRequest_UpdateSwitchesButtons();
        inputCache <= unpack(data);
    endrule

    // return switch state from input cache
    rule readSwitches;
        linkSwitches.send(unpack(inputCache[3:0]));
    endrule

    // return switch state from input cache
    rule readButtons;
        linkButtons.send(unpack(inputCache[8:4]));
    endrule

    // write to LEDs
    rule writeLEDs;
        let incoming_state = linkLEDs.receive();
        linkLEDs.deq();
        FRONTP_LEDS new_state = (ledState & ~incoming_state.mask) | (incoming_state.state & incoming_state.mask);
        if (new_state != ledState)
        begin
            ledState <= new_state;
            client_stub.makeRequest_UpdateLEDs(zeroExtend(pack(new_state)));
        end
    endrule

endmodule
