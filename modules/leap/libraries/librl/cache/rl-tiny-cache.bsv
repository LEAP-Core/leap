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
// Author: Michael Adler
//
// A generic n entry cache class with same-cycle results for read.  Don't
// make the number of entries too big since all of them are searched in a
// single cycle!  Two or four entries are usually the best choices.
//

// Library imports.

import FIFO::*;
import Vector::*;

// Project foundation imports.

`include "awb/provides/fpga_components.bsh"


// ===================================================================
//
// PUBLIC DATA STRUCTURES
//
// ===================================================================

//
// Tiny cache interface.  nTagExtraLowBits is used just for debugging.
// This specified number of low bits are prepanded to cache tags so
// addresses match those seen in other modules.
//
interface RL_TINY_CACHE#(type t_CACHE_ADDR,
                         type t_CACHE_DATA,
                         numeric type nEntries,
                         numeric type nTagExtraLowBits);

    // Read a line, returns invalid if not found.
    method ActionValue#(Maybe#(t_CACHE_DATA)) read(t_CACHE_ADDR addr);
    
    // Write
    method Action write(t_CACHE_ADDR addr, t_CACHE_DATA data);

    // Update -- only write if addr already present in cache
    method Action update(t_CACHE_ADDR addr, t_CACHE_DATA data);

    // Invalidate
    method Action inval(t_CACHE_ADDR addr);

    // Invalidate entire cache
    method Action invalAll();

endinterface: RL_TINY_CACHE


// ===================================================================
//
// PRIVATE DATA STRUCTURES
//
// ===================================================================

typedef UInt#(TLog#(nEntries))
    RL_TINY_CACHE_IDX#(numeric type nEntries);

typedef Vector#(nEntries, RL_TINY_CACHE_IDX#(nEntries))
    RL_TINY_CACHE_LRU#(numeric type nEntries);

module mkTinyCache#(DEBUG_FILE debugLog)
    // interface:
    (RL_TINY_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_DATA, nEntries, nTagExtraLowBits))
    provisos (Bits#(t_CACHE_DATA, t_CACHE_DATA_SZ),
              Log#(nEntries, TLog#(nEntries)),
              // Silly, but required by compiler...
              Add#(t_CACHE_ADDR_SZ, nTagExtraLowBits, TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)),

              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              Alias#(RL_TINY_CACHE_IDX#(nEntries), t_IDX),
              Alias#(RL_TINY_CACHE_LRU#(nEntries), t_LRU));

    Reg#(Vector#(nEntries, Bool)) cacheValid <- mkReg(Vector::replicate(False));
    Reg#(Vector#(nEntries, t_CACHE_ADDR)) cacheTag <- mkRegU();
    Reg#(Vector#(nEntries, t_CACHE_DATA)) cacheData <- mkRegU();
    Reg#(t_LRU) cacheLRU <- mkReg(Vector::genWith(fromInteger));

    //
    // debugAddr --
    //     Pretty printer for converting cache addresses to system addresses.
    //     Adds trailing 0's that were dropped from cache addresses because they
    //     are inside a cache line.
    //
    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddr(t_CACHE_ADDR addr);
        
        Bit#(nTagExtraLowBits) zero = 0;
        return { addr, zero };

    endfunction


    // ***** LRU Management *****

    //
    // getLRU --
    //   Least recently used entry in the cache.
    //
    function t_IDX getLRU(t_LRU list);
        return list[valueOf(nEntries) - 1];
    endfunction


    //
    // pushMRU --
    //   Update MRU list, moving an entry to the head of the list.
    //
    //   We could optimize the LRU vector for a 2 entry cache by reducing
    //   the LRU to one bit, but that would save a single bit and the code
    //   here would be less general.
    //
    function t_LRU pushMRU(t_LRU curLRU, t_IDX mru);
        t_LRU new_list = curLRU;
    
        //
        // Find the new MRU value in the current list
        //
        if (findElem(mru, curLRU) matches tagged Valid .mru_pos)
        begin
            //
            // Shift older references out of the MRU slot
            //
            for (t_IDX w = 0; w < mru_pos; w = w + 1)
            begin
                new_list[w + 1] = curLRU[w];
            end

            // MRU is slot 0
            new_list[0] = mru;
        end

        return new_list;
    endfunction


    function Maybe#(UInt#(TLog#(nEntries))) lookupAddr(t_CACHE_ADDR addr);
        Vector#(nEntries, Bool) way_match = replicate(False);

        for (Integer w = 0; w < valueOf(nEntries); w = w + 1)
        begin
            way_match[w] = (cacheValid[w] && (cacheTag[w] == addr));
        end

        return findElem(True, way_match);
    endfunction


    // Read a line, returns invalid if not found.
    method ActionValue#(Maybe#(t_CACHE_DATA)) read(t_CACHE_ADDR addr);
        Maybe#(t_CACHE_DATA) result = tagged Invalid;

        if (lookupAddr(addr) matches tagged Valid .hit_idx)
        begin
            result = tagged Valid cacheData[hit_idx];
            cacheLRU <= pushMRU(cacheLRU, hit_idx);
            debugLog.record($format("  TinyCache READ HIT, way=%0d, addr=0x%x", hit_idx, debugAddr(addr)));
        end

        return result;
    endmethod
    

    // Write
    method Action write(t_CACHE_ADDR addr, t_CACHE_DATA data);
        t_IDX i;

        // If address already in cache reuse entry.  Otherwise get a new way.
        if (lookupAddr(addr) matches tagged Valid .hit_idx)
            i = hit_idx;
        else
            i = getLRU(cacheLRU);

        cacheValid[i] <= True;
        cacheTag[i] <= addr;
        cacheData[i] <= data;

        cacheLRU <= pushMRU(cacheLRU, i);

        debugLog.record($format("  TinyCache WRITE, way=%0d, addr=0x%x", i, debugAddr(addr)));
    endmethod


    // Update
    method Action update(t_CACHE_ADDR addr, t_CACHE_DATA data);
        // Update an entry if the address is already in the cache
        if (lookupAddr(addr) matches tagged Valid .i)
        begin
            cacheData[i] <= data;
            cacheLRU <= pushMRU(cacheLRU, i);
            debugLog.record($format("  TinyCache UPDATE, way=%0d, addr=0x%x", i, debugAddr(addr)));
        end
        else
        begin
            debugLog.record($format("  TinyCache UPDATE skipped (addr=0x%x)", debugAddr(addr)));
        end
    endmethod


    // Invalidate address if in cache
    method Action inval(t_CACHE_ADDR addr);
        Vector#(nEntries, Bool) valid = cacheValid;

        for (Integer i = 0; i < valueOf(nEntries); i = i + 1)
        begin
            if (cacheTag[i] == addr)
            begin
                valid[i] = False;
                debugLog.record($format("  TinyCache INVAL, way=%0d, addr=0x%x", i, debugAddr(addr)));
            end
        end

        cacheValid <= valid;
    endmethod


    // Invalidate entire cache
    method Action invalAll();
        cacheValid <= Vector::replicate(False);
        debugLog.record($format("  TinyCache INVAL ALL"));
    endmethod

endmodule


//
// mkTinyCache1 --
//     Special case for single entry cache.
//
module mkTinyCache1#(DEBUG_FILE debugLog)
    // interface:
    (RL_TINY_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_DATA, 1, nTagExtraLowBits))
    provisos (Bits#(t_CACHE_DATA, t_CACHE_DATA_SZ),
              // Silly, but required by compiler...
              Add#(t_CACHE_ADDR_SZ, nTagExtraLowBits, TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)),

              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR));

    Reg#(Bool) cacheValid <- mkReg(False);
    Reg#(t_CACHE_ADDR) cacheTag <- mkRegU();
    Reg#(t_CACHE_DATA) cacheData <- mkRegU();


    //
    // debugAddr --
    //     Pretty printer for converting cache addresses to system addresses.
    //     Adds trailing 0's that were dropped from cache addresses because they
    //     are inside a cache line.
    //
    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddr(t_CACHE_ADDR addr);
        
        Bit#(nTagExtraLowBits) zero = 0;
        return { addr, zero };

    endfunction


    // Read a line, returns invalid if not found.
    method ActionValue#(Maybe#(t_CACHE_DATA)) read(t_CACHE_ADDR addr);
        if (cacheValid && (cacheTag == addr))
        begin
            debugLog.record($format("  TinyCache1 READ HIT, addr=0x%x", debugAddr(addr)));
            return tagged Valid cacheData;
        end
        else
        begin
            return tagged Invalid;
        end
    endmethod
    

    // Write
    method Action write(t_CACHE_ADDR addr, t_CACHE_DATA data);
        cacheValid <= True;
        cacheTag <= addr;
        cacheData <= data;

        debugLog.record($format("  TinyCache1 WRITE, addr=0x%x", debugAddr(addr)));
    endmethod


    // Update
    method Action update(t_CACHE_ADDR addr, t_CACHE_DATA data);
        if (cacheValid && (cacheTag == addr))
        begin
            cacheData <= data;
            debugLog.record($format("  TinyCache1 UPDATE, addr=0x%x", debugAddr(addr)));
        end
        else
        begin
            debugLog.record($format("  TinyCache1 UPDATE skipped (addr=0x%x)", debugAddr(addr)));
        end
    endmethod


    // Invalidate address if in cache
    method Action inval(t_CACHE_ADDR addr);
        if (cacheTag == addr)
        begin
            cacheValid <= False;
            debugLog.record($format("  TinyCache1 INVAL, addr=0x%x", debugAddr(addr)));
        end
    endmethod


    // Invalidate entire cache
    method Action invalAll();
        cacheValid <= False;
        debugLog.record($format("  TinyCache1 INVAL ALL"));
    endmethod

endmodule
