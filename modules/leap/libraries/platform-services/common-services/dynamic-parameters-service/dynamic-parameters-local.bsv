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
// @file dynamic-paramters-local.bsv
// @brief Dynamic parameters.  The size of the parameter is an argument to
//        the declaration.  Parameters may be at most 64 bits.
// @author Michael Adler
//

`include "awb/provides/soft_connections.bsh"

`include "awb/dict/PARAMS.bsh"

//
// PARAMETER_NODE
//
// Interface to mkDynamicParameterNode.  Individual parameters constantly
// snoop to see whether their value has arrived on the ring.  They must
// look every cycle since the ring stop guarantees to export a value for only
// a cycle before a new ID might arrive.
//
interface PARAMETER_NODE;
    
    method Maybe#(Bit#(64)) checkForNewValue(PARAMS_DICT_TYPE myID);

endinterface


//
// Param
//
// Interface to a single parameter.  The read method blocks until the parameter
// is initialized by the controller.
//
interface Param#(numeric type bits);

    method Bit#(bits) _read();

endinterface

//
// PARAM_DATA is the message sent along the dynamic parameter ring.  It comes
// in three parts to save wires:  first the parameter ID, then the high 32 bits,
// then the low 32 bits.
//
typedef union tagged
{
    PARAMS_DICT_TYPE PARAM_ID;
    Bit#(32) PARAM_High32;
    Bit#(32) PARAM_Low32;
}
    PARAM_DATA
           deriving (Eq, Bits);


//
// mkDynamicParameterNode --
//
// Every module with dynamic parameters must allocate at least one node to
// receive values.  The node is just a temporary holding point as values
// pass through.  Each individual parameter (see mkDynamicParameter below)
// connects to a ring stop and snoops for incoming updates.
//
module [CONNECTED_MODULE] mkDynamicParameterNode
    //interface:
        (PARAMETER_NODE);

    // Ring connections
    CONNECTION_CHAIN#(PARAM_DATA) chain <- mkConnectionChain("DynamicParamsRing");
    Reg#(Bool) receiving <- mkReg(False);

    // Most recent param that came in on the ring
    Reg#(Bool) validParam <- mkReg(False);
    Reg#(PARAMS_DICT_TYPE) id <- mkReg(?);
    Reg#(Bit#(64)) value <- mkReg(?);
 
    // shift
    //
    // Normal rule for passing messages through the ring.  Look for the
    // right ID and switch to receiving mode if found.
    //
    rule shift (! receiving);
  
        PARAM_DATA param <- chain.recvFromPrev();
        chain.sendToNext(param);

        if (param matches tagged PARAM_ID .new_id)
        begin
            receiving <= True;
            id <= new_id;
            // validParam will be set true after the param value arrives
            validParam <= False;
        end

    endrule
  
    // getParam
    //
    // Get parameter, in parts.  When PARAM_Low32 comes through drop out of
    // receiving mode.
    //
    rule getParam (receiving);
  
        PARAM_DATA param <- chain.recvFromPrev();

        // Forward the data around the ring in case there are multiple readers
        // of the same parameter.
        chain.sendToNext(param);

        case (param) matches
            tagged PARAM_High32 .high32:
            begin
                // High part comes first.
                value[63:32] <= high32;
            end

            tagged PARAM_Low32 .low32:
            begin
                // Low part comes last.  Param is now valid.
                value[31:0] <= low32;
                validParam <= True;
                receiving <= False;
            end
        endcase

    endrule

    // checkForNewValue
    //
    // Individual parameters invoke this method every cycle to receive param
    // values.
    //
    method Maybe#(Bit#(64)) checkForNewValue(PARAMS_DICT_TYPE myID);
        if (validParam && id == myID)
            return tagged Valid value;
        else
            return tagged Invalid;
    endmethod

endmodule


//
// mkDynamicParameter --
//
// Object for an individual parameter.
//
module [CONNECTED_MODULE] mkDynamicParameter#(PARAMS_DICT_TYPE myID, PARAMETER_NODE paramNode)
    //interface:
        (Param#(bits)) provisos (Add#(a__, bits, 64));

    Reg#(Maybe#(Bit#(bits))) value <- mkReg(tagged Invalid);

    // setValue
    //
    // Monitor the parameter node and update the parameter when it comes through.
    //
    rule setValue(True);
        if (paramNode.checkForNewValue(myID) matches tagged Valid .v)
        begin
            value <= tagged Valid truncate(v);
        end
    endrule

    method Bit#(bits) _read() if (value matches tagged Valid .v);
        return v;
    endmethod

endmodule
