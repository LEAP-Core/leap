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
// Standard interface to local memory.  Implementations of local memory
// are in the local-mem subdirectory.
//

import Vector::*;

//
// Local memory is the interface between a single local memory device (e.g.
// the DDR2 driver) and one or more clients of the local memory.  All of local
// memory is exposed as fixed sized words.  Groups of words may also be
// accessed as a fixed size line, allowing for efficient caches using local
// memory as storage.
//
// The word and line sizes must be chosen carefully to match the capabilities
// of the physical memory device and the needs of the local memory clients.
//

typedef `LOCAL_MEM_WORD_BITS LOCAL_MEM_WORD_SZ;
typedef `LOCAL_MEM_WORDS_PER_LINE LOCAL_MEM_WORDS_PER_LINE;
typedef TMul#(LOCAL_MEM_WORD_SZ, LOCAL_MEM_WORDS_PER_LINE) LOCAL_MEM_LINE_SZ;

typedef Bit#(LOCAL_MEM_WORD_SZ) LOCAL_MEM_WORD;
typedef Bit#(LOCAL_MEM_LINE_SZ) LOCAL_MEM_LINE;

// Index of a word within a line.  ASSUMES A POWER OF 2 WORDS PER LINE!
typedef TLog#(LOCAL_MEM_WORDS_PER_LINE) LOCAL_MEM_WORD_IDX_SZ;
typedef Bit#(LOCAL_MEM_WORD_IDX_SZ) LOCAL_MEM_WORD_IDX;


// Mask bytes within words and lines
typedef TDiv#(LOCAL_MEM_WORD_SZ, 8) LOCAL_MEM_BYTES_PER_WORD;
typedef Vector#(LOCAL_MEM_BYTES_PER_WORD, Bool) LOCAL_MEM_WORD_MASK;
typedef Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD_MASK) LOCAL_MEM_LINE_MASK;


// Address size comes from the underlying memory.  For real memory (e.g.
// DDR) it is a function of the hardware.  The address is for words.
typedef Bit#(LOCAL_MEM_ADDR_SZ) LOCAL_MEM_ADDR;

// Address of a line (drops the word index)
typedef TSub#(LOCAL_MEM_ADDR_SZ, LOCAL_MEM_WORD_IDX_SZ) LOCAL_MEM_LINE_ADDR_SZ;
typedef Bit#(LOCAL_MEM_LINE_ADDR_SZ) LOCAL_MEM_LINE_ADDR;


interface LOCAL_MEM;
    //
    // The implementation of reading words and lines may use a shared FIFO.
    // Callers must expect to receive the response from alternating word and
    // line read requests in order to avoid deadlocks.
    //
    method Action readWordReq(LOCAL_MEM_ADDR addr);
    method ActionValue#(LOCAL_MEM_WORD) readWordRsp();

    method Action readLineReq(LOCAL_MEM_ADDR addr);
    method ActionValue#(LOCAL_MEM_LINE) readLineRsp();
    
    //
    // Write requests.
    //
    method Action writeWord(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data);
    method Action writeLine(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data);

    // Only write bytes in a line with corresponding True in mask
    method Action writeWordMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data, LOCAL_MEM_WORD_MASK mask);
    method Action writeLineMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data, LOCAL_MEM_LINE_MASK mask);

    //
    // debugScanState -- Return state for scanning.  Platform code can't
    // create soft connections and must export the list to code that can.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
endinterface: LOCAL_MEM


//
// localMemSeparateAddr --
//     Separate an address into a line-aligned address and a word offset.
//
function Tuple2#(LOCAL_MEM_LINE_ADDR,
                 LOCAL_MEM_WORD_IDX) localMemSeparateAddr(LOCAL_MEM_ADDR addr);
    return unpack(addr);
endfunction

function LOCAL_MEM_LINE_ADDR localMemLineAddr(LOCAL_MEM_ADDR addr) =
    tpl_1(localMemSeparateAddr(addr));
    
function LOCAL_MEM_WORD_IDX localMemWordIdx(LOCAL_MEM_ADDR addr) =
    tpl_2(localMemSeparateAddr(addr));
    
    
//
// localMemLineAddrToAddr --
//     Convert a local memory line-space address to a full local memory
//     address in word space.
//
function LOCAL_MEM_ADDR localMemLineAddrToAddr(LOCAL_MEM_LINE_ADDR lineAddr);
    LOCAL_MEM_WORD_IDX w_idx = 0;
    return { lineAddr, w_idx };
endfunction
