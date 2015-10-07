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

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections.bsh"

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

//
// Compute the address space size available to local memory:  
// 
// Unified local memory (LOCAL_MEM_UNIFIED == 1): 
//     total FPGA words across all DDR banks, referenced as local words
// 
// Distributed local memory (LOCAL_MEM_UNIFIED == 0): 
//     FPGA words per DDR bank, referenced as local words
//
typedef TMin#(1, `LOCAL_MEM_UNIFIED) LOCAL_MEM_UNIFIED;
typedef TSub#(TAdd#(FPGA_DDR_ADDRESS_SZ, 
              TMul#(LOCAL_MEM_UNIFIED, TLog#(FPGA_DDR_BANKS))),
              TLog#(DDR_WORDS_PER_LOCAL_WORD)) LOCAL_MEM_ADDR_SZ;
// 
// Allow clients to determine whether and how many distributed local memory banks exist
//
typedef TMax#(1, TMul#(TSub#(1, LOCAL_MEM_UNIFIED), FPGA_DDR_BANKS)) LOCAL_MEM_BANKS;


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

// Local memory burst data size
typedef DDR_BURST_DATA_SZ LOCAL_MEM_BURST_DATA_SZ;

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


//
// DRAM is accessed via soft connections.  Wrap the soft connections in a
// method interface.  The methods simply forward requests to the corresponding
// soft connections.
//
interface LOCAL_MEM_DDR_BANK;
    method Action readReq(FPGA_DDR_ADDRESS addr);
    method ActionValue#(FPGA_DDR_DUALEDGE_BEAT) readRsp();

    method Action writeReq(FPGA_DDR_ADDRESS addr);
    method Action writeData(FPGA_DDR_DUALEDGE_BEAT data, FPGA_DDR_DUALEDGE_BEAT_MASK mask);
endinterface

typedef Vector#(FPGA_DDR_BANKS, LOCAL_MEM_DDR_BANK) LOCAL_MEM_DDR;


module [CONNECTED_MODULE] mkLocalMemDDRConnection
    // Interface:
    (LOCAL_MEM_DDR);

    LOCAL_MEM_DDR banks <- genWithM(mkLocalMemDDRBankConnection);
    return banks;
endmodule


module [CONNECTED_MODULE] mkLocalMemDDRBankConnection#(Integer bankIdx)
    // Interface:
    (LOCAL_MEM_DDR_BANK);

    String platformName <- getSynthesisBoundaryPlatform();
    String ddrName = "DRAM_Bank" + integerToString(bankIdx) + "_" + platformName + "_";

    CONNECTION_SEND#(FPGA_DDR_REQUEST) commandQ <-
        mkConnectionSend(ddrName + "command");

    CONNECTION_RECV#(FPGA_DDR_DUALEDGE_BEAT) readRspQ <-
        mkConnectionRecv(ddrName + "readResponse");

    CONNECTION_SEND#(Tuple2#(FPGA_DDR_DUALEDGE_BEAT, FPGA_DDR_DUALEDGE_BEAT_MASK)) writeDataQ <-
        mkConnectionSend(ddrName + "writeData");

    method Action readReq(FPGA_DDR_ADDRESS addr);
        commandQ.send(tagged DRAM_READ addr);
    endmethod

    method ActionValue#(FPGA_DDR_DUALEDGE_BEAT) readRsp();
        let d = readRspQ.receive();
        readRspQ.deq();

        return d;
    endmethod

    method Action writeReq(FPGA_DDR_ADDRESS addr);
        commandQ.send(tagged DRAM_WRITE addr);
    endmethod

    method Action writeData(FPGA_DDR_DUALEDGE_BEAT data, FPGA_DDR_DUALEDGE_BEAT_MASK mask);
        writeDataQ.send(tuple2(data, mask));
    endmethod
endmodule


// ========================================================================
//
//   Functions to help with formatting debugging strings.
//
// ========================================================================

//
// Compute the stdio string format for a word.
//
function String localMemFmtWord();
    String wordFmt = "%016llx";

    let word_sz = valueOf(LOCAL_MEM_WORD_SZ);
    if (word_sz == 32)
        wordFmt = "%08lx";
    else if (word_sz == 16)
        wordFmt = "%04x";
    else if (word_sz == 8)
        wordFmt = "%02x";

    return wordFmt;
endfunction

//
// Compute the stdio string format for a line.
//
function String localMemFmtLine();
    let word_fmt = localMemFmtWord();

    String line_fmt = "";
    for (Integer i = 0; i < valueOf(LOCAL_MEM_WORDS_PER_LINE); i = i + 1)
    begin
        if (i != 0)
        begin
            line_fmt = line_fmt + " ";
        end

        line_fmt = line_fmt + word_fmt;
    end

    return line_fmt;
endfunction

//
// Format an address
//
function String localMemFmtAddr();
    return "%016llx";
endfunction


//
// Turn an address into a list for printing.
//
function List#(Bit#(64)) localMemAddrToStdioList(LOCAL_MEM_ADDR a);
    return list(zeroExtend(a));
endfunction


//
// Turn a word into a list for printing.
//
function List#(Bit#(64)) localMemWordToStdioList(LOCAL_MEM_WORD v);
    return list(zeroExtend(v));
endfunction

//
// Turn a line into a list of words for printing.
//
function List#(Bit#(64)) localMemLineToStdioList(LOCAL_MEM_LINE v);
    // Convert to a vector of 64 bit objects since our debug stdio node takes
    // 64 bit entries.
    Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD) vw = unpack(pack(v));
    Vector#(LOCAL_MEM_WORDS_PER_LINE, Bit#(64)) v64 = map(zeroExtend, vw);

    // Convert to a list
    let lst = toList(v64);

    // Convert to stdio order (low bits at the end of the list)
    return List::reverse(lst);
endfunction
