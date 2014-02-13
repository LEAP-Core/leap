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
`include "awb/provides/rrr.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/remote_memory.bsh"

`include "awb/rrr/server_stub_SHARED_MEMORY.bsh"
`include "awb/rrr/client_stub_SHARED_MEMORY.bsh"

// types
typedef enum
{
    STATE_init,
    STATE_waiting,
    STATE_ready
}
STATE
    deriving (Bits, Eq);

// hard-code addressable region to 4K size
typedef Bit#(9)                    SHARED_MEMORY_ADDRESS;
typedef REMOTE_MEMORY_DATA         SHARED_MEMORY_DATA;
typedef REMOTE_MEMORY_BURST_LENGTH SHARED_MEMORY_BURST_LENGTH;

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

// ============== mkSharedMemory Module ===============

// Translate our private virtual address to a remote physical address.

module mkSharedMemory
    // interface
        (SHARED_MEMORY);

    // stubs
    ServerStub_SHARED_MEMORY server_stub <- mkServerStub_SHARED_MEMORY();
    ClientStub_SHARED_MEMORY client_stub <- mkClientStub_SHARED_MEMORY();

    // TLB
    Reg#(REMOTE_MEMORY_PHYSICAL_ADDRESS) theOnlyPhysicalAddress <- mkReg(0);

    // get link to remote memory
    REMOTE_MEMORY remoteMemory = llpi.remoteMemory;

    // state
    Reg#(STATE) state <- mkReg(STATE_init);

    // translation macros
    function REMOTE_MEMORY_PHYSICAL_ADDRESS va_to_pa(SHARED_MEMORY_ADDRESS addr) =
        (theOnlyPhysicalAddress | zeroExtend(addr));

    //
    // Rules
    //

    // Wait for translation push from software

    rule wait_for_translation (state == STATE_init);

        let pa <- server_stub.acceptRequest_UpdateTranslation();
        theOnlyPhysicalAddress <= pa;

        server_stub.sendResponse_UpdateTranslation(?);

        state <= STATE_ready;

    endrule

    //
    // Methods
    //

    // line interface

    method Action readLineReq(SHARED_MEMORY_ADDRESS addr) if (state == STATE_ready);

        remoteMemory.readLineReq(va_to_pa(addr));

    endmethod

    method ActionValue#(SHARED_MEMORY_DATA) readLineResp() if (state == STATE_ready);

        let data <- remoteMemory.readLineResp();
        return data;

    endmethod

    method Action writeLine(SHARED_MEMORY_ADDRESS addr,
                            SHARED_MEMORY_DATA    data) if (state == STATE_ready);

        remoteMemory.writeLine(va_to_pa(addr), data);

    endmethod

    // burst interface

    method Action readBurstReq(SHARED_MEMORY_ADDRESS      addr,
                               SHARED_MEMORY_BURST_LENGTH nwords) if (state == STATE_ready);

        remoteMemory.readBurstReq(va_to_pa(addr), nwords);

    endmethod

    method ActionValue#(SHARED_MEMORY_DATA) readBurstResp() if (state == STATE_ready);

        let data <- remoteMemory.readBurstResp();    
        return data;

    endmethod

    // for burst writes, the first data word can only be written in the cycle following
    // the initial write request. Probably easy to optimize this.

    method Action writeBurstReq(SHARED_MEMORY_ADDRESS      addr,
                                SHARED_MEMORY_BURST_LENGTH len) if (state == STATE_ready);

        remoteMemory.writeBurstReq(va_to_pa(addr), len);

    endmethod

    method Action writeBurstData(SHARED_MEMORY_DATA data) if (state == STATE_ready);

        remoteMemory.writeBurstData(data);

    endmethod

endmodule
