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

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/scratchpad_memory_service.bsh"

//
// mkWriteValidatedReg --
//     This module provides a register that can be seen as a read-only register
// using write method to intialize its value. This register can only be read
// after initialization. 
//
module mkWriteValidatedReg
    // interface:
    (Reg#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));
    
    Reg#(t_DATA) data <- mkRegU();
    Reg#(Bool) initialized <- mkReg(False);

    method t_DATA _read() if (initialized);
        return data;
    endmethod

    method Action _write(t_DATA val) if (!initialized);
        initialized <= True;
        data <= val;
    endmethod
endmodule

// ====================================================================
//
// Shared scratchpad controller partition modules
//
// ====================================================================

interface SHARED_SCRATCH_PARTITION;
    // Check if the address lies in the local controller's address range
    method Bool isLocalReq(SHARED_SCRATCH_MEM_ADDRESS addr);
    // Convert the address from the shared memory space to the distributed memory space
    method SHARED_SCRATCH_MEM_ADDRESS globalToLocalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
    // Convert the address from the distributed memory space to the shared memory space
    method SHARED_SCRATCH_MEM_ADDRESS localToGlobalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
endinterface

typedef function CONNECTED_MODULE#(SHARED_SCRATCH_PARTITION) f() SHARED_SCRATCH_PARTITION_CONSTRUCTOR;

//
// mkSharedScratchControllerAddrPartition --
//
module [CONNECTED_MODULE] mkSharedScratchControllerAddrPartition#(SHARED_SCRATCH_MEM_ADDRESS inBaseAddr, 
                                                                  SHARED_SCRATCH_MEM_ADDRESS inAddrRange,
                                                                  NumTypeParam#(t_IN_DATA_SZ) inDataSz)
    // interface:
    (SHARED_SCRATCH_PARTITION)
    provisos (// Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_IN_DATA_SZ)), t_NATURAL_SZ),
              Bits#(SHARED_SCRATCH_MEM_VALUE, t_SHARED_SCRATCH_MEM_VALUE_SZ),
              // Compute the container (scratchpad) index size
              NumAlias#(TLog#(TDiv#(t_SHARED_SCRATCH_MEM_VALUE_SZ, t_NATURAL_SZ)), t_NATURAL_IDX_SZ));
    
    SHARED_SCRATCH_MEM_ADDRESS baseAddr  = inBaseAddr >> fromInteger(valueOf(t_NATURAL_IDX_SZ));
    SHARED_SCRATCH_MEM_ADDRESS addrRange = inAddrRange >> fromInteger(valueOf(t_NATURAL_IDX_SZ));

    method Bool isLocalReq(SHARED_SCRATCH_MEM_ADDRESS addr);
        return ((addr >= baseAddr) && (addr < (baseAddr + addrRange)));
    endmethod

    method SHARED_SCRATCH_MEM_ADDRESS globalToLocalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
        return addr - baseAddr;
    endmethod

    method SHARED_SCRATCH_MEM_ADDRESS localToGlobalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
        return addr + baseAddr;
    endmethod
        
endmodule

//
// mkUncachedSharedScratchControllerAddrPartition --
//
module [CONNECTED_MODULE] mkUncachedSharedScratchControllerAddrPartition#(SHARED_SCRATCH_MEM_ADDRESS inBaseAddr, 
                                                                          SHARED_SCRATCH_MEM_ADDRESS inAddrRange)
    // interface:
    (SHARED_SCRATCH_PARTITION);
    
    SHARED_SCRATCH_MEM_ADDRESS baseAddr  = inBaseAddr; 
    SHARED_SCRATCH_MEM_ADDRESS addrRange = inAddrRange;

    method Bool isLocalReq(SHARED_SCRATCH_MEM_ADDRESS addr);
        return ((addr >= baseAddr) && (addr < (baseAddr + addrRange)));
    endmethod

    method SHARED_SCRATCH_MEM_ADDRESS globalToLocalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
        return addr - baseAddr;
    endmethod

    method SHARED_SCRATCH_MEM_ADDRESS localToGlobalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
        return addr + baseAddr;
    endmethod
        
endmodule

//
// mkSharedScratchControllerNullPartition --
//
module [CONNECTED_MODULE] mkSharedScratchControllerNullPartition
    // interface:
    (SHARED_SCRATCH_PARTITION);

    method Bool isLocalReq(SHARED_SCRATCH_MEM_ADDRESS addr) = True;
    method SHARED_SCRATCH_MEM_ADDRESS globalToLocalAddr(SHARED_SCRATCH_MEM_ADDRESS addr) = addr;
    method SHARED_SCRATCH_MEM_ADDRESS localToGlobalAddr(SHARED_SCRATCH_MEM_ADDRESS addr) = addr;

endmodule
