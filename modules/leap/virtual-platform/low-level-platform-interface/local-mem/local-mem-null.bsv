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
// NULL local memory.
//

import List::*;

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/fpga_components.bsh"

typedef `LOCAL_MEM_ADDR_BITS LOCAL_MEM_ADDR_SZ;
`include "awb/provides/local_mem_interface.bsh"


//
// platformHasLocalMem --
//     Allow clients to determine whether local memory actually exists.
//     Some models may wish to change their configuration for NULL local
//     memories.
//
function Bool platformHasLocalMem() = False;

// 
// Allow clients to determine whether and how many distributed local memory banks exist
//
typedef 1 LOCAL_MEM_BANKS;

//
// Define a dummy local memory interface.
//

module mkLocalMem#(LOCAL_MEM_CONFIG conf)
    // interface:
    (LOCAL_MEM);

    method Action readWordReq(LOCAL_MEM_ADDR addr);
        noAction;
    endmethod

    method ActionValue#(LOCAL_MEM_WORD) readWordRsp();
        return ?;
    endmethod


    method Action readLineReq(LOCAL_MEM_ADDR addr);
        noAction;
    endmethod

    method ActionValue#(LOCAL_MEM_LINE) readLineRsp();
        return ?;
    endmethod


    method Action writeWord(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data);
        noAction;
    endmethod

    method Action writeLine(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data);
        noAction;
    endmethod

    method Action writeWordMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data, LOCAL_MEM_WORD_MASK mask);
        noAction;
    endmethod

    method Action writeLineMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data, LOCAL_MEM_LINE_MASK mask);
        noAction;
    endmethod

endmodule
