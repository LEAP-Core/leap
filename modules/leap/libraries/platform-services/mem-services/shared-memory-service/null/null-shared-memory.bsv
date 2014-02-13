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

//
// Although this is a NULL module, we need to have a fleshed-out
// interface because Platform Interface translates these methods
// into soft connections.
//

// hard-code addressable region to 4K size
typedef Bit#(0) SHARED_MEMORY_ADDRESS;
typedef Bit#(0) SHARED_MEMORY_DATA;
typedef Bit#(0) SHARED_MEMORY_BURST_LENGTH;

typedef struct
{
    SHARED_MEMORY_ADDRESS addr;
    SHARED_MEMORY_BURST_LENGTH len;
}
SHARED_MEMORY_REQ_INFO
    deriving (Bits, Eq);

typedef union tagged
{
    SHARED_MEMORY_REQ_INFO SHARED_MEMORY_READ;
    SHARED_MEMORY_REQ_INFO SHARED_MEMORY_WRITE;
}
SHARED_MEMORY_REQUEST
    deriving (Bits, Eq);

// ============== SHARED_MEMORY Interface ===============

// This device should export the generic MEMORY_IFC interface, but for debugging
// purposes we will use the basic hard-wired REMOTE_MEMORY interface for now.
// Also, MEMORY_IFC needs to be updated to include methods for burst access.

interface SHARED_MEMORY;

    // line interface
    method Action                           readLineReq(SHARED_MEMORY_ADDRESS addr);
    method ActionValue#(SHARED_MEMORY_DATA) readLineResp();
    method Action                           writeLine(SHARED_MEMORY_ADDRESS addr,
                                                      SHARED_MEMORY_DATA    data);
    
    // burst interface -- assumption: burst word == single word
    method Action                           readBurstReq(SHARED_MEMORY_ADDRESS      addr,
                                                         SHARED_MEMORY_BURST_LENGTH len);
    method ActionValue#(SHARED_MEMORY_DATA) readBurstResp();
    method Action                           writeBurstReq(SHARED_MEMORY_ADDRESS      addr,
                                                          SHARED_MEMORY_BURST_LENGTH len);
    method Action                           writeBurstData(SHARED_MEMORY_DATA data);    
        
endinterface

module mkSharedMemory
    // interface
        (SHARED_MEMORY);
    
    // line interface
    method Action readLineReq(SHARED_MEMORY_ADDRESS addr);
        noAction;
    endmethod
    
    method ActionValue#(SHARED_MEMORY_DATA) readLineResp();
        noAction;
        return ?;
    endmethod
    
    method Action writeLine(SHARED_MEMORY_ADDRESS addr,
                            SHARED_MEMORY_DATA    data);
        noAction;
    endmethod
    
    // burst interface -- assumption: burst word == single word
    method Action readBurstReq(SHARED_MEMORY_ADDRESS      addr,
                               SHARED_MEMORY_BURST_LENGTH len);
        noAction;
    endmethod
    
    method ActionValue#(SHARED_MEMORY_DATA) readBurstResp();
        noAction;
        return ?;
    endmethod
    
    method Action writeBurstReq(SHARED_MEMORY_ADDRESS      addr,
                                SHARED_MEMORY_BURST_LENGTH len);
        noAction;
    endmethod
    
    method Action writeBurstData(SHARED_MEMORY_DATA data);
        noAction;
    endmethod

endmodule
