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
// platformHasLocalMem --
//     Allow clients to determine whether local memory actually exists.
//     Some models may wish to change their configuration for NULL local
//     memories.
//
function Bool platformHasLocalMem() = True;


// ========================================================================
//
// Derive standard local memory properties from the device properties
//
// ========================================================================

// How many FPGA DDR words in a local memory word?
typedef TDiv#(LOCAL_MEM_WORD_SZ, FPGA_DDR_WORD_SZ) DDR_WORDS_PER_LOCAL_WORD;

// Compute the address space size available to local memory:  total FPGA
// words across all DDR banks, referenced as local words.
typedef TSub#(TAdd#(FPGA_DDR_ADDRESS_SZ, TLog#(FPGA_DDR_BANKS)),
              TLog#(DDR_WORDS_PER_LOCAL_WORD)) LOCAL_MEM_ADDR_SZ;

// ========================================================================
//
// Construct a LOCAL_MEM_LINE from FPGA DDR banks, bursts and words.
//
// ========================================================================

// The DRAM driver breaks reads and writes into multi-cycle bursts.
typedef TMul#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_DUALEDGE_BEAT_SZ) DDR_BURST_DATA_SZ;
typedef Bit#(DDR_BURST_DATA_SZ) DDR_BURST_DATA;

// Compute index of the DDR words within a burst
typedef TMul#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_WORDS_PER_BEAT) DDR_WORDS_PER_BURST;
typedef TLog#(DDR_WORDS_PER_BURST) DDR_BURST_WORD_IDX_SZ;
typedef Bit#(DDR_BURST_WORD_IDX_SZ) DDR_BURST_WORD_IDX;

// Compute burst-aligned address sizes in DDR-space within a single bank
typedef TSub#(FPGA_DDR_ADDRESS_SZ, DDR_BURST_WORD_IDX_SZ) DDR_BURST_ADDRESS_SZ;
typedef Bit#(DDR_BURST_ADDRESS_SZ) DDR_BURST_ADDRESS;

// Bank index
typedef Bit#(TLog#(FPGA_DDR_BANKS)) DDR_BANK_IDX;


//
// checkDDRMemSizesValid --
//   Confirm that local memory and device word and line widths are acceptable.
//
module checkDDRMemSizesValid ();
    if (valueOf(IS_POWER_OF_2#(LOCAL_MEM_WORD_SZ)) == 0)
        errorM("LOCAL_MEM_WORD_SZ must be a power of 2.");

    if (valueOf(IS_POWER_OF_2#(LOCAL_MEM_LINE_SZ)) == 0)
        errorM("LOCAL_MEM_LINE_SZ must be a power of 2.");

    if (valueOf(IS_POWER_OF_2#(FPGA_DDR_DUALEDGE_BEAT_SZ)) == 0)
        errorM("FPGA_DDR_DUALEDGE_BEAT_SZ must be a power of 2.");

    if (valueOf(IS_POWER_OF_2#(FPGA_DDR_BURST_LENGTH)) == 0)
        errorM("FPGA_DDR_BURST_LENGTH must be a power of 2.");

    if (valueOf(IS_POWER_OF_2#(FPGA_DDR_BANKS)) == 0)
        errorM("FPGA_DDR_BANKS must be a power of 2.");
endmodule


//
// Read or write request address.  Requests are either for full lines or for
// words.
//
typedef union tagged
{
    LOCAL_MEM_ADDR MEM_REQ_LINE;
    LOCAL_MEM_ADDR MEM_REQ_WORD;
}
LOCAL_MEM_REQ
    deriving (Bits, Eq);
