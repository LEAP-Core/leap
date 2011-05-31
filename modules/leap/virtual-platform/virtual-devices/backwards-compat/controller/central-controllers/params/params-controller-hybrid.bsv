//
// Copyright (C) 2008 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

//
// @file params-controller-hybrid.bsv
// @brief Receive dynamic parameters from the software side
//
// @author Michael Adler
//

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/rrr.bsh"

`include "awb/rrr/remote_server_stub_PARAMS.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/PARAMS.bsh"

// PARAMS_CONTROLLER: Control all the params throughout the hardware model.

interface PARAMS_CONTROLLER;

endinterface

// PARAMS_CON_STATE

// An internal datatype to track the state of the params controller

typedef enum
{
    PCS_Idle,           // Not executing any commands
    PCS_High32,         // Send the high 32 bits
    PCS_Low32           // Send the low 32 bits
}
    PARAMS_CON_STATE
               deriving (Eq, Bits);

// RRR request DYN_PARAM
typedef struct
{
    PARAMS_DICT_TYPE paramID;
    UINT64 value;
}
    DYN_PARAM
               deriving (Eq, Bits);

// mkParamsController

// Abstracts all communication from the main controller to individual stat counters.

module [CONNECTED_MODULE] mkParamsController
    //interface:
                (PARAMS_CONTROLLER);

    // ****** State Elements ******

    // Communication link to the Params themselves
    Connection_Chain#(PARAM_DATA) chain <- mkConnection_Chain(`RINGID_PARAMS);
 
    // Communication to our RRR server
    ServerStub_PARAMS server_stub <- mkServerStub_PARAMS();
  
    // Our internal state
    Reg#(PARAMS_CON_STATE) state <- mkReg(PCS_Idle);
    Reg#(Bit#(64)) value <- mkRegU();
    
    // ****** Rules ******
    
    // waitForParam
    //    
    // Wait for parameter update request
    
    rule waitForParam (state == PCS_Idle);

        let req <- server_stub.acceptRequest_sendParam();        
        DYN_PARAM p;
        p.paramID = truncate(pack(req.paramID));
        p.value = req.value;

        //
        // The first message on the chain is the parameter ID
        //
        PARAM_DATA msg = tagged PARAM_ID p.paramID;
        chain.sendToNext(msg);

        state <= PCS_High32;
        value <= p.value;

    endrule
    
    // send
    //
    // State machine for sending parameter values in two 32 bit chunks
    //
    rule send (state != PCS_Idle);
  
        PARAM_DATA msg;

        //
        // Send the high 32 bits first and then the low 32 bits.
        //

        if (state == PCS_High32)
        begin
            msg = tagged PARAM_High32 value[63:32];
            state <= PCS_Low32;
        end
        else
        begin
            msg = tagged PARAM_Low32 value[31:0];
            state <= PCS_Idle;
        end
  
        chain.sendToNext(msg);
  
    endrule
    
    // receive
    //
    // Receive messages that completed their journey around the ring.  Drop
    // them.  Send an ACK for PARAMS_NULL.  The software side sends NULL last
    // and waits for the ACK to know that all parameters have been received.
    //
    rule receive (True);
  
        PARAM_DATA msg <- chain.recvFromPrev();

        if (msg matches tagged PARAM_ID .id)
        begin
            server_stub.sendResponse_sendParam(0);
        end
  
    endrule

endmodule
