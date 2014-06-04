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

// traffic-light-function.bsv

// Model of a traffic light inspired by the Bluespec, Inc tutorial.
// This model corresponds roughly to "TL0.bsv" and can be used as
// a starting point for adapting the rest of the tutorial into LEAP.
//
// The major differences from the Bluespec tutorial version are:
// * Use of LEAP coding and file naming conventions.
// * Use of SIGNAL_CHANGE_DELAY AWB parameter to control delay 
//   between state transitions.
// * Use of soft connections/smart synthesis boundaries.
// * Use of the LEAP "Front Panel" service to blink LEDs on
//   the FPGA platform.


// ****** Includes of LEAP platform ******

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/front_panel_device.bsh"


// ****** Datatype Definitions ******

// TRAFFIC_LIGHT_STATE

// Describes the current state of the traffic light FSM.

typedef enum 
{
   GREEN_NS, AMBER_NS, RED_AFTER_NS,
   GREEN_E, AMBER_E, RED_AFTER_E,
   GREEN_W, AMBER_W, RED_AFTER_W
} 
TRAFFIC_LIGHT_STATE deriving (Eq, Bits);


// ****** Module Definitions ******


// mkTrafficLightFunction

// Encapsulation of the traffic light FSM.

// Note: the [CONNECTED_MODULE] syntax indicates that the module 
// uses soft connections. This allows it to communicate with other
// modules while still having an Empty interface.

module [CONNECTED_MODULE] mkTrafficLightFunction
    // interface:
        (Empty);

    // ****** Local State ******

    // Current traffic light state.
    Reg#(TRAFFIC_LIGHT_STATE) state <- mkReg(RED_AFTER_W);
    
    // Count down to zero before transitioning.
    Reg#(Bit#(32)) waitCount <- mkReg(`SIGNAL_CHANGE_DELAY);


    // ****** Soft Connections ******

    // Communication to the front panel.
    Connection_Send#(FRONTP_MASKED_LEDS) linkLEDs <- mkConnection_Send("fpga_leds");


    // ****** Rules ******

    rule waiting (waitCount != 0);

        waitCount <= waitCount - 1;

    endrule


    rule fromGreenNS (state == GREEN_NS && waitCount == 0);

        state <= AMBER_NS;
        waitCount <= `SIGNAL_CHANGE_DELAY;
  
    endrule


    rule fromAmberNS (state == AMBER_NS && waitCount == 0);

        state <= RED_AFTER_NS;
        waitCount <= `SIGNAL_CHANGE_DELAY;

    endrule


    rule fromRedAfterNS (state == RED_AFTER_NS && waitCount == 0);

        state <= GREEN_E;
        linkLEDs.send(FRONTP_MASKED_LEDS {state: 'b0100, mask: 'b1111});
        waitCount <= `SIGNAL_CHANGE_DELAY;

    endrule


    rule fromGreenE (state == GREEN_E && waitCount == 0);

        state <= AMBER_E;
        waitCount <= `SIGNAL_CHANGE_DELAY;

    endrule


    rule fromAmberE (state == AMBER_E && waitCount == 0);

        state <= RED_AFTER_E;
        waitCount <= `SIGNAL_CHANGE_DELAY;

    endrule


    rule fromRedAfterE (state == RED_AFTER_E && waitCount == 0);

        state <= GREEN_W;
        linkLEDs.send(FRONTP_MASKED_LEDS {state: 'b0001, mask: 'b1111});
        waitCount <= `SIGNAL_CHANGE_DELAY;

    endrule


    rule fromGreenW (state == GREEN_W && waitCount == 0);

        state <= AMBER_W;
        waitCount <= `SIGNAL_CHANGE_DELAY;
 
    endrule


    rule fromAmberW (state == AMBER_W && waitCount == 0);

        state <= RED_AFTER_W;
        waitCount <= `SIGNAL_CHANGE_DELAY;

    endrule


    rule fromRedAfterW (state == RED_AFTER_W && waitCount == 0);

        state <= GREEN_NS;
        linkLEDs.send(FRONTP_MASKED_LEDS {state: 'b1010, mask: 'b1111});
        waitCount <= `SIGNAL_CHANGE_DELAY;

    endrule

endmodule
