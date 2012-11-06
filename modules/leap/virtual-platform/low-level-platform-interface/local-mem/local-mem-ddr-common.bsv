//
// Copyright (C) 2012 Intel Corporation
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
