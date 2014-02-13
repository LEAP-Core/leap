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


//
// Dynamic parameters are passed from the software during the startup phase.
// The ring protocol breaks messages into 3 parts:  token ID, high half of
// the value and low half of the value.  There is no synchronization ACK
// returned to the software since the local code to read the value of a parameter
// blocks until it has been initialized.
//

`include "awb/rrr/server_stub_PARAMS.bsh"
`include "awb/dict/PARAMS.bsh"


// SOFT_PARAMS_STATE

// An internal datatype to track the state of the params controller

typedef enum
{
    PCS_IDLE,           // Not executing any commands
    PCS_HIGH32,         // Send the high 32 bits
    PCS_LOW32          // Send the low 32 bits
}
SOFT_PARAMS_STATE
    deriving (Eq, Bits);

// mkParamsController

// Abstracts all communication from the main controller to individual stat counters.

module [CONNECTED_MODULE] mkDynamicParametersService
    //interface:
    ();

    // ****** State Elements ******

    // Communication link to the Params themselves
    Connection_Chain#(PARAM_DATA) chain <- mkConnection_Chain(`RINGID_PARAMS);
 
    // Communication to our RRR server
    ServerStub_PARAMS server_stub <- mkServerStub_PARAMS();

    // Our internal state
    Reg#(SOFT_PARAMS_STATE) state <- mkReg(PCS_IDLE);
    
    // ****** Rules ******
    
    // waitForParam
    //    
    // Wait for parameter update request
    
    rule waitForParam (state == PCS_IDLE);
        let c = server_stub.peekRequest_sendParam();

        //
        // The first message on the chain is the parameter ID
        //
        PARAM_DATA msg = tagged PARAM_ID truncate(pack(c.paramID));
        chain.sendToNext(msg);

        state <= PCS_HIGH32;
    endrule
    
    // send
    //
    // State machine for sending parameter values in two 32 bit chunks
    //
    rule sendHigh (state == PCS_HIGH32);
        let c = server_stub.peekRequest_sendParam();

        //
        // Send the high 32 bits first.
        //
        PARAM_DATA msg = tagged PARAM_High32 c.value[63:32];
        chain.sendToNext(msg);
        state <= PCS_LOW32;
    endrule
    
    rule sendLow (state == PCS_LOW32);
        let c <- server_stub.acceptRequest_sendParam();

        PARAM_DATA msg = tagged PARAM_Low32 c.value[31:0];
        chain.sendToNext(msg);
        state <= PCS_IDLE;
    endrule
    
    // receive
    //
    // Sink messages coming around the ring.
    //
    rule receive (True);
        PARAM_DATA msg <- chain.recvFromPrev();
    endrule
endmodule
