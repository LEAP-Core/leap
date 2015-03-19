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
// A generic cache class (n-way set associative) for caching data in BRAM.
// Classes building a cache must provide an interface class to the source
// data of type RL_SA_CACHE_SOURCE_DATA (defined below).  The cache
// takes a number of parameters: the address and data types, the number of
// sets and the number of ways within each set.
//
// The cache may either be write-back (the default) or write-through.  For
// write through caches it is the callers responsibility to do the write
// to backing storage.  This cache class merely skips setting of the dirty
// bit on writes in write-through mode.
//

// Library imports.

import FIFO::*;
import FIFOF::*;
import Vector::*;
import SpecialFIFOs::*;
import List::*;
import DefaultValue::*;

// Project foundation imports.

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/fpga_components.bsh"

// ===================================================================
//
// PUBLIC DATA STRUCTURES
//
// ===================================================================

//
// Set associative cache interface.  nTagExtraLowBits is used just for
// debugging.  This specified number of low bits are prepanded to cache
// tags so addresses match those seen in other modules.
//
// t_CACHE_READ_META is metadata associated with a reference.  Metadata is
// passed to the backing store for fills.  The metadata is not stored in
// the cache.
//
interface RL_SA_BRAM_CACHE#(type t_CACHE_ADDR,
                            type t_CACHE_WORD,
                            numeric type nWordsPerLine,
                            type t_CACHE_READ_META);

    // Read up to a full line.  Read from backing store if not already cached.
    // The read response is guaranteed to return at least the requested
    // word in the line.  If more of the line is already available it will
    // be returned as well.
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

    method ActionValue#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META)) readResp();

    // Some clients need the address to route responses.  Having a peek method
    // for response addresses avoids extra buffering in these clients.
    method t_CACHE_ADDR peekRespAddr();

    // Predicate to test whether a read response is ready this cycle.
    method Bool readRespReady();
    

    // Write a word to a cache line.  Word index 0 corresponds to the
    // low bits of a cache line.
    method Action write(t_CACHE_ADDR addr,
                        t_CACHE_WORD val,
                        Bit#(TLog#(nWordsPerLine)) wordIdx);
    
    // Invalidate & flush requests.  Both write dirty lines back.  Invalidate drops
    // the line from the cache.  Flush keeps the line in the cache.  A response
    // is returned for invalOrFlushWait iff sendAck is true.
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action invalOrFlushWait();
    
    //
    // Set cache mode.  Mostly useful for debugging.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
    method Action setRecentLineCacheMode(Bool enabled);

    //
    // Debug scan state.  The cache can't instantiate a debug scan node because
    // the debug scan code depends on libRL.  Instantiating a node here would
    // create a source dependence loop.  Instead, a list of name/value pairs
    // is available for use by a client.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
    
    interface RL_CACHE_STATS stats;

endinterface: RL_SA_BRAM_CACHE

//
// Source data fill response
//
typedef struct
{
    t_CACHE_LINE val;
    t_CACHE_ADDR addr;
    Bool isCacheable;
    t_CACHE_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_SA_BRAM_CACHE_FILL_RESP#(type t_CACHE_LINE,
                            type t_CACHE_ADDR,
                            type t_CACHE_META)
    deriving (Eq, Bits);


//
// The caller must provide an instance of the RL_SA_BRAM_CACHE_SOURCE_DATA interface
// so the cache can read and write data from the next level in the hierarchy.
//
interface RL_SA_BRAM_CACHE_SOURCE_DATA#(type t_CACHE_ADDR,
                                        type t_CACHE_LINE,
                                        numeric type nWordsPerLine,
                                        type t_CACHE_META);

    // Read request and response with data
    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
    
    method ActionValue#(RL_SA_BRAM_CACHE_FILL_RESP#(t_CACHE_LINE,
                                                    t_CACHE_ADDR, 
                                                    t_CACHE_META)) readResp();
    // Asynchronous write (no response)
    method Action write(t_CACHE_ADDR addr, 
                        Vector#(nWordsPerLine, Bool) wordValidMask, 
                        t_CACHE_LINE val);
    
    // Pass invalidate and flush requests down the hierarchy.  If sendAck is
    // true then invalOrFlushWait must block until the operation is complete.
    // If sendAck is false invalOrflushWait will not be called.
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action invalOrFlushWait();

endinterface: RL_SA_BRAM_CACHE_SOURCE_DATA

typedef 256 RL_SA_BRAM_CACHE_MAF_ENTRIES;

typedef enum
{
    RL_SA_CACHE_READ,
    RL_SA_CACHE_WRITE,
    RL_SA_CACHE_FLUSH,
    RL_SA_CACHE_INVAL
}
RL_SA_BRAM_CACHE_ACTION
    deriving (Eq, Bits);

//
// Basic request information constructed when a new request arrives.
//
typedef struct
{
    t_CACHE_TAG     tag;
    t_CACHE_SET_IDX set;
    t_CACHE_WAY_IDX way;
}
RL_SA_BRAM_CACHE_REQ_BASE#(type t_CACHE_TAG,
                           type t_CACHE_SET_IDX,
                           type t_CACHE_WAY_IDX)
    deriving(Bits, Eq);

typedef struct
{
    Bit#(TLog#(nWordsPerLine)) wordIdx;
    // Meta-data associated with the reference.  Meta-data has meaning only to the
    // caller.
    t_CACHE_READ_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_SA_BRAM_CACHE_READ_REQ#(numeric type nWordsPerLine, 
                           type t_CACHE_READ_META)
    deriving (Eq, Bits);

//
// Meta-data associated with a write request.
//
typedef struct
{
    Bit#(WRITE_DATA_HEAP_IDX_SZ) dataIdx;
    Bit#(TLog#(nWordsPerLine)) wordIdx;
}
RL_SA_BRAM_CACHE_WRITE_REQ#(numeric type nWordsPerLine)
    deriving (Eq, Bits);

typedef union tagged
{
    RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META) HCOP_READ;
    RL_SA_BRAM_CACHE_WRITE_REQ#(nWordsPerLine) HCOP_WRITE;
    Bool HCOP_INVAL;
    Bool HCOP_FLUSH_DIRTY;
}
RL_SA_BRAM_CACHE_REQ#(numeric type nWordsPerLine, 
                      type t_CACHE_READ_META)
    deriving(Bits, Eq);

typedef enum
{
    RL_SA_BRAM_CACHE_DATA_READ_HIT,
    RL_SA_BRAM_CACHE_DATA_FLUSH, 
    RL_SA_BRAM_CACHE_DATA_MISS
}
RL_SA_BRAM_CACHE_DATA_LOOKUP_TYPE
    deriving (Eq, Bits);

//
// Specify read client for cache meta reads.
//
typedef enum
{
    RL_SA_BRAM_CACHE_META_CLIENT_STD,
    RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE,
    RL_SA_BRAM_CACHE_META_CLIENT_INVALID
}
RL_SA_BRAM_CACHE_META_CLIENT
    deriving (Eq, Bits);

// ========================================================================
//
// mkCacheSetAssocWithBRAM --
//     Set associative cache implemented with BRAM.
//
//    NOTE: mkCacheSetAssocWithBRAM may return read responses out of order 
//          relative to the request order!  For in-order responses the 
//          caller must add a tag to the t_CACHE_READ_META type and use the
//          tag to sort the responses.  A SCOREBOARD_FIFO would do the job.
//
// ========================================================================

module mkCacheSetAssocWithBRAM#(RL_SA_BRAM_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_MAF_IDX) sourceData,
                                NumTypeParam#(nSets) param0,
                                NumTypeParam#(nWays) param1,
                                NumTypeParam#(nTagExtraLowBits) param2,
                                DEBUG_FILE debugLog)
    // interface:
        (RL_SA_BRAM_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_LINE, t_CACHE_LINE_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),

              // Write word size must tile into cache line
              Bits#(Vector#(nWordsPerLine, t_CACHE_WORD), t_CACHE_LINE_SZ),

              // Cache address size must be no larger than 128 bits because
              // of the hash function.
              Add#(t_CACHE_ADDR_SZ, a__, 128),

              // Set index and tag.  Set index size + tag size == address size.
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Bits#(t_CACHE_SET_IDX, t_CACHE_SET_IDX_SZ),
              Alias#(RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets), t_CACHE_TAG),

              // Set size must be no longer than 32 bits (for set filter)
              Add#(t_CACHE_SET_IDX_SZ, b__, 32),

              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              Alias#(RL_SA_CACHE_WAY_IDX#(nWays), t_CACHE_WAY_IDX),
              Alias#(RL_SA_CACHE_DATA_IDX#(nWays, t_CACHE_SET_IDX), t_CACHE_DATA_IDX),
              Alias#(RL_SA_CACHE_WAY_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets), t_METADATA),
              Alias#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META), t_CACHE_LOAD_RESP),
              Alias#(Vector#(nWays, RL_SA_CACHE_WAY_IDX#(nWays)), t_LRU_LIST),
              Alias#(Vector#(nWays, Maybe#(t_METADATA)), t_METADATA_VECTOR),
              Alias#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays), t_SET_METADATA),
              Alias#(RL_SA_BRAM_CACHE_REQ_BASE#(t_CACHE_TAG, t_CACHE_SET_IDX, t_CACHE_WAY_IDX), t_CACHE_REQ_BASE),
              Alias#(RL_SA_BRAM_CACHE_REQ#(nWordsPerLine, t_CACHE_READ_META), t_CACHE_REQ),
              Alias#(Bit#(TLog#(nWordsPerLine)), t_CACHE_WORD_IDX),
              Alias#(RL_SA_CACHE_WRITE_INFO#(t_CACHE_WORD, t_CACHE_WORD_IDX), t_CACHE_WRITE_INFO),
              Alias#(Vector#(nWordsPerLine, Bool), t_CACHE_WORD_VALID_MASK),
       
              Bits#(t_CACHE_REQ, t_CACHE_REQ_SZ),

              Alias#(Bit#(TLog#(RL_SA_BRAM_CACHE_MAF_ENTRIES)), t_MAF_IDX),

              // Unbelievably ugly tautologies required by the compiler:
              Add#(TSub#(t_CACHE_ADDR_SZ, TLog#(nSets)), TLog#(nSets), t_CACHE_ADDR_SZ),
              Add#(t_CACHE_ADDR_SZ, nTagExtraLowBits, TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)),
              Log#(nWays, TLog#(nWays)),
              Add#(TLog#(TExp#(TLog#(nSets))), 0, TLog#(nSets)),
              Add#(TLog#(TDiv#(TExp#(TLog#(nSets)), 2)), x__, TLog#(nSets)));

    // ***** Elaboration time checks of types"
    // The interface allows for a number of sets that isn't a
    // power of 2, but the implementation currently does not.
    if(valueof(nSets) != valueof(TExp#(TLog#(nSets))))
    begin
        error("nSets must be a power of 2");
    end
    
    // Cache Storage
    
    // Metadata
    BRAM#(RL_SA_CACHE_SET_IDX#(nSets), t_SET_METADATA) metaStore = ?; 
    
    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        metaStore <- mkBRAMInitialized(defaultValue);
    end
    else if(`RL_SA_BRAM_CACHE_BRAM_TYPE == 1)
    begin
        metaStore <- mkBRAMInitializedMultiBank(defaultValue);
    end
    else
    begin
        metaStore <- mkBRAMInitializedClockDivider(defaultValue);
    end

    // Values
    Vector#(nWordsPerLine, BRAM#(t_CACHE_DATA_IDX, t_CACHE_WORD)) dataStore <- replicateM(mkBRAM());

    // ***** Internal state *****

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(Bit#(WRITE_DATA_HEAP_IDX_SZ), t_CACHE_WRITE_INFO) reqInfo_writeData <- mkMemoryHeapLUTRAM();
    MEMORY_HEAP#(t_MAF_IDX,Tuple4#(t_CACHE_READ_META, t_CACHE_WORD_IDX, t_CACHE_WORD_VALID_MASK, t_CACHE_WAY_IDX)) mafTable <- mkMemoryHeapUnionBRAM();

    // Is the cache write back?  If not, never set a dirty bit.  It is then the
    // responsibility of the caller to write values to backing storage.
    Reg#(RL_SA_CACHE_MODE) cacheMode <- mkReg(RL_SA_MODE_WRITE_BACK);
    function Bool writeBackCache() = (cacheMode == RL_SA_MODE_WRITE_BACK);
    function Bool cacheEnabled() = (pack(cacheMode)[1] == 0);

    // Filter for allowing one live operation per cache set.
    COUNTING_FILTER#(t_CACHE_SET_IDX, 1) setFilter <- mkCountingFilter(debugLog);

    // ***** Queues between internal pipeline stages *****

    // Incoming requests
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) newReqQ <- mkFIFOF();
    // Cache meta lookup queue
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, RL_SA_BRAM_CACHE_META_CLIENT)) metaLookupQ = ?;
    // Cache data lookup queue
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK, RL_SA_BRAM_CACHE_DATA_LOOKUP_TYPE)) dataLookupQ = ?;

    // Queues on miss path
    FIFOF#(Tuple3#(t_SET_METADATA, t_CACHE_WAY_IDX, t_MAF_IDX)) lineMissQ = ?;
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK, t_MAF_IDX)) wordMissQ <- mkFIFOF();

    // Fill for read path
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_MAF_IDX, RL_CACHE_GLOBAL_READ_META)) fillLineRequestQ <- mkFIFOF();
    FIFOF#(t_CACHE_WORD_VALID_MASK) fillLineUncacheableQ = ?;
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, t_CACHE_LINE, RL_CACHE_GLOBAL_READ_META, t_MAF_IDX, Bool)) mafLookupQ <- mkFIFOF();

    // Write data to an allocated queue entry
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, RL_SA_BRAM_CACHE_WRITE_REQ#(nWordsPerLine))) writeDataQ <- mkFIFOF();

    // Inval or flush path
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, Bool)) invalOrFlushQ <- mkFIFOF();

    // Exit from all paths
    FIFOF#(t_CACHE_SET_IDX) doneQ <- mkFIFOF();

    // Read responses may be returned out of order relative to request order!
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META), t_CACHE_LINE, t_CACHE_WORD_VALID_MASK, Bool)) readRespToClientQ_OOO <- mkFIFOF();

    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        metaLookupQ <- mkFIFOF();
        dataLookupQ <- mkFIFOF();
        lineMissQ   <- mkFIFOF();
        fillLineUncacheableQ <- mkFIFOF();
    end
    else
    begin
        metaLookupQ <- mkSizedFIFOF(4);
        dataLookupQ <- mkSizedFIFOF(4);
        lineMissQ   <- mkSizedFIFOF(4);
        fillLineUncacheableQ <- mkSizedFIFOF(4);
    end

    PulseWire readMissW          <- mkPulseWire();
    PulseWire writeMissW         <- mkPulseWire();
    PulseWire readHitW           <- mkPulseWire();
    PulseWire writeHitW          <- mkPulseWire();
    PulseWire newMRUW            <- mkPulseWire();
    PulseWire invalEntryW        <- mkPulseWire();
    PulseWire forceInvalLineW    <- mkPulseWire();
    PulseWire dirtyEntryFlushW   <- mkPulseWire();

    // ***** Indexing functions *****
    //
    // getDataIdx --
    //     Index in the cache data BRAM given a set and way.
    //
    function t_CACHE_DATA_IDX getDataIdx (t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        t_CACHE_DATA_IDX idx;
        idx.set = set;
        idx.way = way;
        return idx;
    endfunction

    //
    // Functions for converting from address to tag and set or vice versa.
    //
    function Tuple2#(t_CACHE_TAG, t_CACHE_SET_IDX) cacheTagAndSet(t_CACHE_ADDR addr);
        return unpack(hashBits(addr));
    endfunction

    function t_CACHE_ADDR cacheAddr(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        t_CACHE_ADDR hashed_addr = { tag, pack(set) };
        return hashBits_inv(hashed_addr);
    endfunction

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

    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddrFromTag(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        Bit#(nTagExtraLowBits) zero = 0;
        return { cacheAddr(tag, set), zero };
    endfunction


    // ***** Meta data searches *****

    function t_METADATA metaData(t_CACHE_TAG tag,
                                 Bool dirty,
                                 t_CACHE_WORD_VALID_MASK wordValid);
        t_METADATA meta;
        meta.tag = tag;
        meta.dirty = dirty;
        meta.wordValid = wordValid;
    
        return meta;
    endfunction


    function Maybe#(Tuple2#(t_CACHE_WAY_IDX, t_METADATA)) findWayMatch(t_CACHE_TAG tag, t_SET_METADATA meta);
        Vector#(nWays, Bool) way_match = replicate(False);

        for (Integer w = 0; w < valueOf(nWays); w = w + 1)
        begin
            way_match[w] = case (meta.ways[w]) matches
                               tagged Valid .m: (m.tag == tag);
                               default: False;
                           endcase;
        end

        let way = findElem(True, way_match);
        if (cacheEnabled() &&& way matches tagged Valid .w)
            return tagged Valid tuple2(w, validValue(meta.ways[w]));
        else
            return tagged Invalid;
    endfunction


    function Bool isInvalid(Maybe#(t) m) = ! isValid(m);


    function Maybe#(t_CACHE_WAY_IDX) findFirstInvalid(t_METADATA_VECTOR meta);
        return findIndex(isInvalid, meta);
    endfunction


    // ***** LRU Management ***** //

    t_CACHE_WAY_IDX mruIDX = fromInteger(valueOf(TSub#(nWays, 1)));

    //
    // getLRU --
    //   Least recently used way in a set.
    //
    function t_CACHE_WAY_IDX getLRU(t_LRU_LIST list);
        return validValue(findElem(0, list));
    endfunction


    //
    // getMRU --
    //   Most recently used way in a set.
    //

    function t_CACHE_WAY_IDX getMRU(t_LRU_LIST list);
        return validValue(findElem(mruIDX, list));
    endfunction


    //
    // pushMRU --
    //   Update MRU list, moving a way to the head of the list.
    //
    function t_LRU_LIST pushMRU(t_LRU_LIST curLRU, t_CACHE_WAY_IDX mru);
        t_CACHE_WAY_IDX cur_priority = curLRU[mru];
    
        //
        // Shift older references out of the MRU slot
        //
        t_LRU_LIST new_list = newVector();

        for (Integer w = 0; w < valueOf(nWays); w = w + 1)
        begin
            if (fromInteger(w) == mru)
            begin
                new_list[w] = mruIDX;
            end
            else if (curLRU[w] > cur_priority)
            begin
                new_list[w] = curLRU[w] - 1;
            end
            else
            begin
                new_list[w] = curLRU[w];
            end
        end

        return new_list;
    endfunction

    function ActionValue#(t_LRU_LIST) cacheLRUUpdate(t_CACHE_SET_IDX set,
                                                     t_CACHE_WAY_IDX way,
                                                     t_LRU_LIST cur_lru);
        actionvalue
        let new_lru = pushMRU(cur_lru, way);

        if ((getMRU(cur_lru) != way) || (cur_lru != new_lru))
        begin
            debugLog.record($format("    Update LRU (set=0x%x): MRU %0d / %b -> %b", set, way, cur_lru, new_lru));
        end
        if (getMRU(new_lru) != way)
        begin
            debugLog.record($format("    ***ERROR*** expected MRU to be 0x%x but it is 0x%x", way, getMRU(new_lru)));
        end

        return new_lru;
        endactionvalue
    endfunction


    // cache access functions
    function Action cacheLineDataReadReq(t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        action
            let data_idx = getDataIdx(set, way); 
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                dataStore[b].readReq(data_idx);
            end
        endaction
    endfunction
    
    function Action cacheLineDataWrite(t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way, t_CACHE_WORD_VALID_MASK mask, t_CACHE_LINE val);
        action
            Vector#(nWordsPerLine, t_CACHE_WORD) words = unpack(pack(val));
            let data_idx = getDataIdx(set, way); 
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                if (mask[b])
                begin
                    dataStore[b].write(data_idx, words[b]);
                end
            end
        endaction
    endfunction

    function ActionValue#(t_CACHE_LINE) getCacheLineDataResp();
        actionvalue
            Vector#(nWordsPerLine, t_CACHE_WORD) v = newVector();
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                let d <- dataStore[b].readRsp();
                v[b] = d;
            end
            t_CACHE_LINE line_data = unpack(pack(v));
            return line_data;
        endactionvalue
    endfunction

    // ***** Rules ***** //

    // ====================================================================
    //
    // All incoming requests start here with handleIncomingReq
    //
    // ====================================================================

    //
    // Maintain a side buffer of requests to cache sets that already have
    // in-flight conflicting requests.  This allows non-conflicting requests
    // to proceed.
    //
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) sideReqQ <-
        mkSizedFIFOF(valueOf(RL_SA_CONFLICTQ_ENTRIES));

    // A very simple filter to detect lines with requests already in the side
    // cache.
    LUTRAM#(Bit#(6), Bit#(3)) sideReqFilter <- mkLUTRAM(0);
    Reg#(Bit#(2)) newReqArb <- mkReg(0);
    Wire#(Tuple3#(Bool,
                  Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ),
                  Maybe#(CF_OPAQUE#(t_CACHE_SET_IDX, 1)))) curReq <- mkWire();

    (* fire_when_enabled, no_implicit_conditions *)
    rule incrReqArb (True);
        newReqArb <= newReqArb + 1;
    endrule

    RWire#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, RL_SA_BRAM_CACHE_META_CLIENT)) metaLookupReqW <- mkRWire();
    PulseWire metaLookupReqValidW <- mkPulseWire();

    //
    // pickReqQ --
    //     Decide whether to consider the new request or side request queue
    //     this cycle.  Filtering both is too expensive.
    //
    rule pickReqQueue (True);
        // New requests win over side requests if there is a new request
        // and the arbiter is non-zero.  If the arbitration counter newReqArb
        // is larger than 1 bit this favors new requests over side-buffer
        // requests in an effort to have as many requests in flight as possible.
        Bool pick_new_req = newReqQ.notEmpty &&
                            ((newReqArb != 0) || ! sideReqQ.notEmpty);

        let r = pick_new_req ? newReqQ.first() : sideReqQ.first();

        match {.req_base, .req} = r;
        let tag = req_base.tag;
        let set = req_base.set;
        
        // speculatively read meta data and LRU hints
        metaStore.readReq(req_base.set);
        metaLookupReqW.wset(tuple3(req_base, req, RL_SA_BRAM_CACHE_META_CLIENT_STD));

        // In order to preserve read/write and write/write order, the
        // request must either come from the side buffer or be a new request
        // referencing a line not already in the side buffer.
        //
        // The array sideReqFilter tracks lines active in the side request
        // queue.
        if (! pick_new_req || sideReqFilter.sub(resize(set)) == 0)
        begin
            curReq <= tuple3(pick_new_req, r, setFilter.test(set));
        end
        else
        begin
            curReq <= tuple3(pick_new_req, r, tagged Invalid);
        end
    endrule

    //
    // startReq --
    //     Start the current request if the line is not busy.
    //
    (* fire_when_enabled *)
    rule startReq (tpl_3(curReq) matches tagged Valid .filter_state);
        match {.pick_new_req, .r, .cf_opaque} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        setFilter.set(filter_state);

        metaLookupReqValidW.send();

        debugLog.record($format("  FWD %s to ReqQ: addr=0x%x, set=0x%x",
                                pick_new_req ? "new" : "side",
                                debugAddrFromTag(tag, set), set));

        if (pick_new_req)
        begin
            newReqQ.deq();
        end
        else
        begin
            sideReqQ.deq();
            sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) - 1);
        end
    endrule

    //
    // shuntNewReq --
    //     If the current request is new (not a shunted request) and the
    //     line is busy, shunt the new request to a side queue in order to
    //     attempt to process a later request that may be ready to go.
    //
    //     This rule will not fire if startReq fires.
    //
    match {.curReq_req_base, .curReq_req} = tpl_2(curReq);
    
    function Bool isOrderedReq(t_CACHE_REQ req);
        if (req matches tagged HCOP_READ .rReq &&& rReq.globalReadMeta.orderedSourceDataReqs == True)
            return True;
        else
            return False;
    endfunction

    (* fire_when_enabled *)
    rule shuntNewReq (tpl_1(curReq) &&
                      ! isOrderedReq(curReq_req) &&
                      (sideReqFilter.sub(resize(curReq_req_base.set)) != maxBound) &&
                      ! isValid(tpl_3(curReq)) &&
                      cacheEnabled);
        match {.pick_new_req, .r, .cf_opaque} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        debugLog.record($format("  SIDE shunt req: addr=0x%x, set=0x%x",
                                debugAddrFromTag(tag, set), set));

        sideReqQ.enq(r);
        newReqQ.deq();

        // Note line present in sideReqQ
        sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) + 1);
    endrule
    
    //
    // Write metaLookupQ to indicate whether a new request was started
    //
    (* fire_when_enabled *)
    rule checkMetaLookup (metaLookupReqW.wget() matches tagged Valid .lookup_req);
        // Was a valid new request started?
        match {.req_base, .req, .lookup_type} = lookup_req;
        if (lookup_type == RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE || metaLookupReqValidW)
        begin
            metaLookupQ.enq(lookup_req);
        end
        else
        begin
            metaLookupQ.enq(tuple3(?, ?, RL_SA_BRAM_CACHE_META_CLIENT_INVALID));
        end
    endrule

    // drop invalid meta lookup
    rule drainMetaRead (tpl_3(metaLookupQ.first) == RL_SA_BRAM_CACHE_META_CLIENT_INVALID);
        metaLookupQ.deq();
        let cur_meta <- metaStore.readRsp();
    endrule

    // ====================================================================
    //
    // Two stage path for invalidate or flush requests.  First stage
    // looks up the address in the cache.  If the line is present and dirty,
    // the second stage flushes it to the backing storage.  The third
    // stage responds with an ACK that storage is consistent, if requested.
    //
    // ====================================================================

    function Bool reqIsInvalOrFlush(t_CACHE_REQ req);
        if (req matches tagged HCOP_INVAL .needAck)
            return True;
        else if (req matches tagged HCOP_FLUSH_DIRTY .needAck)
            return True;
        else
            return False;
    endfunction

    //
    // handleInvalOrFlush --
    //     Invalidate and flush requests have similar handling.  Both write
    //     back a dirty matching line.  Flush preserves the now clean line
    //     in the cache.
    //
    (* conservative_implicit_conditions *)
    rule handleInvalOrFlush (tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_STD && reqIsInvalOrFlush(tpl_2(metaLookupQ.first())));

        match {.req_base_in, .req, .lookup_type} = metaLookupQ.first();
        metaLookupQ.deq();
        let meta <- metaStore.readRsp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        Bool need_ack = ?;
        Bool is_inval = ?;

        case (req) matches
        tagged HCOP_INVAL .needACK:
        begin
            need_ack = needACK;
            is_inval = True;
            debugLog.record($format("  Process request: INVAL addr=0x%x, set=0x%x, needAck=%s", 
                            debugAddrFromTag(tag, set), set, needACK? "True" : "False"));
        end
        tagged HCOP_FLUSH_DIRTY .needACK:
        begin
            need_ack = needACK;
            is_inval = False;
            debugLog.record($format("  Process request: FLUSH addr=0x%x, set=0x%x, needAck=%s", 
                            debugAddrFromTag(tag, set), set, needACK? "True" : "False"));
        end
        endcase

        Bool found_dirty_line = False;
        let req_base_out = req_base_in;

        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            let meta_upd = meta;

            if (way_meta.dirty)
            begin
                // Found dirty line.  Prepare for write back.
                req_base_out.way = way;
                dataLookupQ.enq(tuple4(req_base_out, req, way_meta.wordValid, RL_SA_BRAM_CACHE_DATA_FLUSH));
                found_dirty_line = True;
                cacheLineDataReadReq(set, way);
                if (! is_inval)
                begin
                    // FLUSH:  Line no longer dirty.  Update meta data.
                    let new_meta = way_meta;
                    new_meta.dirty = False;
                    meta_upd.ways[way] = tagged Valid new_meta;
                end
            end

            if (is_inval)
            begin
                // Invalidate line
                meta_upd.ways[way] = tagged Invalid;
                forceInvalLineW.send();
            end

            metaStore.write(set, meta_upd);
            debugLog.record($format("  FLUSH/INVAL HIT %s: addr=0x%x, set=0x%x, way=%0d", (found_dirty_line ? "dirty" : "clean"), debugAddrFromTag(tag, set), set, way));
        end
        
        if (!found_dirty_line)
        begin
            if (need_ack)
            begin
                invalOrFlushQ.enq(tuple2(req_base_out, is_inval)); 
            end
            else
            begin
                doneQ.enq(set);
            end
        end
    endrule


    //
    // flushDirtyLine --
    //   Flush a dirty line and continue on to fill, if appropriate.
    //
    rule flushDirtyLine (reqIsInvalOrFlush(tpl_2(dataLookupQ.first())));
        match {.req_base, .req, .word_valid_mask, .req_type} = dataLookupQ.first();
        dataLookupQ.deq();

        t_CACHE_LINE flush_data <- getCacheLineDataResp();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        dirtyEntryFlushW.send();
        debugLog.record($format("  Write back DIRTY: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                        debugAddrFromTag(tag, set), set, word_valid_mask, flush_data));

        // Flush for invalidate request.
        sourceData.write(cacheAddr(tag, set), word_valid_mask, flush_data);
        
        if (req matches tagged HCOP_FLUSH_DIRTY .needAck &&& needAck == True)
        begin
            invalOrFlushQ.enq(tuple2(req_base, False));
        end
        else
        begin
            doneQ.enq(set);        
        end
    endrule

    //
    //  fwdInvalOrFlush --
    //    Forward invalidate or flush requests down to next level memory
    //
    rule fwdInvalOrFlush (True);
        match {.req_base, .is_inval} = invalOrFlushQ.first();
        let set = req_base.set;
        let tag = req_base.tag;
        if (is_inval)
        begin
            sourceData.invalReq(cacheAddr(tag, set), True);
        end
        else
        begin
            sourceData.flushReq(cacheAddr(tag, set), True);
        end
        doneQ.enq(set);
    endrule

    // ====================================================================
    //
    // Read and Write data path.
    //
    // ====================================================================

    //
    // handleRead --
    //     First stage of cache READ path.
    //
    (* conservative_implicit_conditions *)
    rule handleRead (tpl_2(metaLookupQ.first()) matches tagged HCOP_READ .rReq &&& tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_STD);
        
        match {.req_base_in, .req, .lookup_type} = metaLookupQ.first();
        metaLookupQ.deq();
        let meta <- metaStore.readRsp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;
        
        debugLog.record($format("  Process request: READ addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        Bool need_set_data = False;
        let req_base_out = req_base_in;

        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            //
            // Line hit!
            //
            req_base_out.way = way;

            // Update LRU
            let meta_upd = meta;
            meta_upd.lru <- cacheLRUUpdate(set, way, meta.lru);

            if (way_meta.wordValid[rReq.wordIdx])
            begin
                // Word hit!
                readHitW.send();
                need_set_data = True;
                dataLookupQ.enq(tuple4(req_base_out, req, way_meta.wordValid, RL_SA_BRAM_CACHE_DATA_READ_HIT));
                cacheLineDataReadReq(set, way);
                if (meta_upd.lru != meta.lru)
                begin
                    // LRU changed.  Update metadata.
                    metaStore.write(set, meta_upd);
                    newMRUW.send();
                end
            end
            else
            begin
                // Line valid but word in line is not.  Fill.
                let maf_idx <- mafTable.malloc();
                wordMissQ.enq(tuple4(req_base_out, req, way_meta.wordValid, maf_idx));
                // Mark all words valid in the line.  They will be after
                // the fill completes.
                meta_upd.ways[way] = tagged Valid metaData(tag, way_meta.dirty, replicate(True));
                metaStore.write(set, meta_upd);
                if (meta_upd.lru != meta.lru)
                begin
                    newMRUW.send();
                end
            end
        end
        else
        begin
            // Miss.
            //
            // Pick a fill victim:  either the first invalid or the LRU entry.
            // 
            t_CACHE_WAY_IDX fill_way = getLRU(meta.lru);
            if (findFirstInvalid(meta.ways) matches tagged Valid .inval_way)
            begin
                fill_way = inval_way;
            end
            let maf_idx <- mafTable.malloc();
            lineMissQ.enq(tuple3(meta, fill_way, maf_idx));
            dataLookupQ.enq(tuple4(req_base_out, req, ?, RL_SA_BRAM_CACHE_DATA_MISS));
            cacheLineDataReadReq(set, fill_way);
        end
    endrule

    //
    // handleWrite --
    //     First unique stage of cache WRITE path.
    //
    (* conservative_implicit_conditions *)
    rule handleWrite (tpl_2(metaLookupQ.first()) matches tagged HCOP_WRITE .wReq &&& tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_STD);

        match {.req_base_in, .req, .lookup_type} = metaLookupQ.first();
        metaLookupQ.deq();
        let meta <- metaStore.readRsp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        debugLog.record($format("  Process request: WRITE addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        let req_base_out = req_base_in;

        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            //
            // Line hit!
            //
            req_base_out.way = way;

            // Update LRU
            let meta_upd = meta;
            meta_upd.lru <- cacheLRUUpdate(set, way, meta.lru);

            writeHitW.send();

            // Mark line dirty and word valid
            let new_word_valid = way_meta.wordValid;
            new_word_valid[wReq.wordIdx] = True;

            meta_upd.ways[way] = tagged Valid metaData(tag, writeBackCache(), new_word_valid);
            metaStore.write(set, meta_upd);
            
            if (meta_upd.lru != meta.lru)
            begin
                newMRUW.send();
            end

            // Request write to cache
            writeDataQ.enq(tuple2(req_base_out, wReq));
            debugLog.record($format("  Write HIT: addr=0x%x, set=0x%x, way=%0d, mask=0x%x", debugAddrFromTag(tag, set), set, way, new_word_valid));

        end
        else
        begin
            // Miss.
            //
            // Pick a fill victim:  either the first invalid or the LRU entry.
            // 
            t_CACHE_WAY_IDX fill_way = getLRU(meta.lru);
            if (findFirstInvalid(meta.ways) matches tagged Valid .inval_way)
            begin
                fill_way = inval_way;
            end
            lineMissQ.enq(tuple3(meta, fill_way, ?));
            dataLookupQ.enq(tuple4(req_base_out, req, ?, RL_SA_BRAM_CACHE_DATA_MISS));
            cacheLineDataReadReq(set, fill_way);
        end
    endrule

    // ====================================================================
    //
    // Read or write hits end here.
    //
    // ====================================================================

    //
    // handleReadCacheHit --
    //   Forward data coming from cache BRAM from handleRead to back to the requester.
    //
    rule handleReadCacheHit (tpl_2(dataLookupQ.first()) matches tagged HCOP_READ .rReq &&& tpl_4(dataLookupQ.first()) == RL_SA_BRAM_CACHE_DATA_READ_HIT);

        match {.req_base, .req, .word_valid_mask, .req_type} = dataLookupQ.first();
        dataLookupQ.deq();
        
        t_CACHE_LINE v <- getCacheLineDataResp();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        readRespToClientQ_OOO.enq(tuple5(req_base, rReq, v, word_valid_mask, True));

        // Done with this read request
        doneQ.enq(set);

        debugLog.record($format("  Read HIT: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, way, word_valid_mask, v));
    endrule


    //
    // writeCacheData --
    //   All cache writes terminate here, including the line miss path.
    //
    rule writeCacheData (True);
        match {.req_base, .w_req} = writeDataQ.first();
        writeDataQ.deq();

        let w_data = reqInfo_writeData.sub(w_req.dataIdx);
        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        dataStore[w_req.wordIdx].write(getDataIdx(set, way), w_data.val);
        debugLog.record($format("  WRITE Word: addr=0x%x, set=0x%x, way=%0d, word=%0d, data=0x%x", debugAddrFromTag(tag, set), set, way, w_req.wordIdx, w_data.val));

        if (! writeBackCache())
        begin
            // Send all writes to backing storage if in write-through mode.
            Vector#(nWordsPerLine, Bool) mask = replicate(False);
            mask[w_req.wordIdx] = True;
            Vector#(nWordsPerLine, t_CACHE_WORD) val = replicate(w_data.val);
            sourceData.write(cacheAddr(tag, set), mask, unpack(pack(val)));
        end
        reqInfo_writeData.free(w_req.dataIdx);
        doneQ.enq(set);
    endrule


    // ====================================================================
    //
    // Miss handlers.
    //
    // ====================================================================

    //
    // handleWordMissForRead --
    //     Line is present in the cache but incomplete.  Request the full line
    //     from backing storage and merge it into the line.
    //
    rule handleWordMissForRead (tpl_2(wordMissQ.first()) matches tagged HCOP_READ .rReq);
        match {.req_base, .req, .word_valid_mask, .maf_idx} = wordMissQ.first();
        wordMissQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;

        //
        // Miss.  Pick a victim.
        //
        readMissW.send();

        let addr = cacheAddr(tag, set);
        
        mafTable.write(maf_idx, tuple4(rReq.readMeta, rReq.wordIdx, word_valid_mask, req_base.way));
        sourceData.readReq(addr, maf_idx, rReq.globalReadMeta);
        debugLog.record($format("  READ WORD MISS (FILL): addr=0x%x, set=0x%x, way=%0d, maf_idx=%0d", 
                        debugAddr(addr), set, req_base.way, maf_idx));
    endrule


    //
    // handleMissForRead --
    //     Pick a victim and prepare to fill a way from backing storage.
    //
    (* conservative_implicit_conditions *)
    rule handleMissForRead (tpl_2(dataLookupQ.first()) matches tagged HCOP_READ .rReq &&& tpl_4(dataLookupQ.first()) == RL_SA_BRAM_CACHE_DATA_MISS);

        match {.req_base_in, .req, .word_valid_mask, .req_type} = dataLookupQ.first();
        match {.meta, .fill_way, .maf_idx} = lineMissQ.first();
        dataLookupQ.deq();
        lineMissQ.deq();

        t_CACHE_LINE flush_data <- getCacheLineDataResp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        readMissW.send();

        let req_base_out = req_base_in;
        req_base_out.way = fill_way;

        // Update LRU
        let meta_upd = meta;
        meta_upd.lru <- cacheLRUUpdate(set, fill_way, meta.lru);

        //
        // Update metadata here for the filled line since we have the details.
        //
        meta_upd.ways[fill_way] = tagged Valid metaData(tag, False, replicate(True));
        metaStore.write(set, meta_upd);
        mafTable.write(maf_idx, tuple4(rReq.readMeta, rReq.wordIdx, replicate(False), fill_way));

        // Is victim dirty?
        Bool flushed_dirty = False;
        if (meta.ways[fill_way] matches tagged Valid .m)
        begin
            invalEntryW.send();
            if (m.dirty)
            begin
                // Victim is dirty.  Flush data.
                flushed_dirty = True;
                dirtyEntryFlushW.send();
                debugLog.record($format("  READ MISS (DIRTY WB): addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(m.tag, set), set, fill_way, m.wordValid, flush_data));
                sourceData.write(cacheAddr(m.tag, set), m.wordValid, flush_data);
                // READ: Pass the request on to the fill stage.
                fillLineRequestQ.enq(tuple3(req_base_out, maf_idx, rReq.globalReadMeta));
            end
        end

        if (! flushed_dirty)
        begin
            let addr = cacheAddr(tag, set);
            sourceData.readReq(addr, maf_idx, rReq.globalReadMeta);
            debugLog.record($format("  READ MISS (FILL): addr=0x%x, set=0x%x, way=%0d, maf_idx=%0d", 
                            debugAddr(addr), set, fill_way, maf_idx));
        end
    endrule


    //
    // handleMissForWrite --
    //     Pick a victim and write back the dirty data, if needed.
    //
    (* conservative_implicit_conditions *)
    rule handleMissForWrite (tpl_2(dataLookupQ.first()) matches tagged HCOP_WRITE .wReq &&& tpl_4(dataLookupQ.first()) == RL_SA_BRAM_CACHE_DATA_MISS);

        match {.req_base_in, .req, .mask, .req_type} = dataLookupQ.first();
        match {.meta, .fill_way, .maf_idx} = lineMissQ.first();
        dataLookupQ.deq();
        lineMissQ.deq();

        t_CACHE_LINE flush_data <- getCacheLineDataResp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        writeMissW.send();

        let req_base_out = req_base_in;
        req_base_out.way = fill_way;

        // Update LRU
        let meta_upd = meta;
        meta_upd.lru <- cacheLRUUpdate(set, fill_way, meta.lru);

        //
        // Update metadata here for the filled line since we have the details.
        //
        // The full line will not be filled from memory for a write.  Only
        // mark the word being written valid.
        t_CACHE_WORD_VALID_MASK word_valid_mask = replicate(False);
        word_valid_mask[wReq.wordIdx] = True;

        // Update tag and write metadata
        meta_upd.ways[fill_way] = tagged Valid metaData(tag, writeBackCache(), word_valid_mask);
        metaStore.write(set, meta_upd);

        // Is victim dirty?
        Bool flushed_dirty = False;
        if (meta.ways[fill_way] matches tagged Valid .m)
        begin
            invalEntryW.send();
            if (m.dirty)
            begin
                // Victim is dirty.  Flush data.
                flushed_dirty = True;
                dirtyEntryFlushW.send();
                debugLog.record($format("  WRITE MISS (DIRTY WB): addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(m.tag, set), set, fill_way, m.wordValid, flush_data));
                sourceData.write(cacheAddr(m.tag, set), m.wordValid, flush_data);
                // WRITE: Line is empty and ready to receive write data.
                writeDataQ.enq(tuple2(req_base_out, wReq));
            end
        end

        if (! flushed_dirty)
        begin
            // Writing does not require a fill.  Ready now.
            writeDataQ.enq(tuple2(req_base_out, wReq));
            debugLog.record($format("  Write to INVAL: addr=0x%x, set=0x%x, way=%0d", debugAddr(cacheAddr(tag, set)), set, fill_way));
        end
    endrule


    rule sendFillRequest (True);
        match {.req_base, .maf_idx, .global_read_meta} = fillLineRequestQ.first();
        fillLineRequestQ.deq();
        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;
        let addr = cacheAddr(tag, set);
        sourceData.readReq(addr, maf_idx, global_read_meta);
    endrule


    //
    // recvFillResp --
    //     receive fill response from next level memory
    //
    rule handleFillForRead (True);
        let rsp <- sourceData.readResp();
        match {.tag, .set} = cacheTagAndSet(rsp.addr);

        t_CACHE_REQ_BASE req_base;
        req_base.tag = tag;
        req_base.set = set;
        req_base.way = ?;
        
        mafTable.readReq(rsp.readMeta);
        mafLookupQ.enq(tuple5(req_base, rsp.val, rsp.globalReadMeta, rsp.readMeta, rsp.isCacheable));
    endrule

    //
    // handleFillForCacheableRead --
    //    Update the cache with requested data coming back from memory.
    //
    rule handleFillForCacheableRead (tpl_5(mafLookupQ.first()));
        //
        // Cache the new values.  Don't overwrite entries that are currently
        // valid, since they may be dirty.
        //
        // On return only claim that the newly filled words are valid.
        //
        let maf_data <- mafTable.readRsp();
        match {.client_meta, .word_idx, .cur_word_valid_mask, .cur_way} = maf_data;
        match {.req_base, .val, .global_read_meta, .maf_idx, .is_cacheable} = mafLookupQ.first();
        mafLookupQ.deq();
        mafTable.free(maf_idx);

        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));
        
        let tag = req_base.tag;
        let set = req_base.set;
        
        cacheLineDataWrite(set, cur_way, ret_valid_words, val);

        let r_req = RL_SA_BRAM_CACHE_READ_REQ { wordIdx: word_idx, 
                                                readMeta: client_meta, 
                                                globalReadMeta: global_read_meta };

        readRespToClientQ_OOO.enq(tuple5(req_base,
                                         r_req,
                                         val,
                                         ret_valid_words,
                                         is_cacheable));

        debugLog.record($format("  Read FILL: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x",
                                debugAddrFromTag(tag, set), set, cur_way, ret_valid_words, val));
        doneQ.enq(req_base.set);
    endrule

    //
    // handleFillForUncacheableRead --
    //
    rule handleFillForUncacheableRead (!tpl_5(mafLookupQ.first()));
        //
        // On return only claim that the newly filled words are valid.
        //
        let maf_data <- mafTable.readRsp();
        match {.client_meta, .word_idx, .cur_word_valid_mask, .cur_way} = maf_data;
        match {.req_base, .val, .global_read_meta, .maf_idx, .is_cacheable} = mafLookupQ.first();
        mafLookupQ.deq();
        mafTable.free(maf_idx);

        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));

        let r_req = RL_SA_BRAM_CACHE_READ_REQ { wordIdx: word_idx, 
                                                readMeta: client_meta, 
                                                globalReadMeta: global_read_meta };
        let tag = req_base.tag;
        let set = req_base.set;
       
        readRespToClientQ_OOO.enq(tuple5(req_base,
                                         r_req,
                                         val,
                                         ret_valid_words,
                                         is_cacheable));

        debugLog.record($format("  Read FILL [NOT CACHEABLE]: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x",
                                debugAddrFromTag(tag, set), set, cur_way, ret_valid_words, val));
        // Abnormal path.  Response is uncacheable.  The line has already
        // been marked valid in anticipation of the response, so the
        // metadata must now be fixed.
        let req_base_out = req_base;
        req_base_out.way = cur_way;
        metaStore.readReq(set);
        metaLookupReqW.wset(tuple3(req_base_out, tagged HCOP_READ r_req, RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE));
        fillLineUncacheableQ.enq(cur_word_valid_mask);
    endrule

    //
    // fixupUncacheableFillForRead --
    //     Fill response flaged the line uncacheable.  The way's metadata is
    //     speculatively set to valid when the fill is requested and must be
    //     marked invalid.
    //
    rule fixupUncacheableFillForRead (tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE);

        match {.req_base, .req, .lookup_type} = metaLookupQ.first();
        let old_word_valid_mask = fillLineUncacheableQ.first();
        fillLineUncacheableQ.deq();

        let meta <- metaStore.readRsp();
        metaLookupQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        // If no words were valid in the line before the fill then simply
        // mark the line invalid.  If words were valid then the line contained
        // partial write data.  In that case, restore the line to the state
        // before the fill request.
        let old_meta = validValue(meta.ways[way]);
        meta.ways[way] = (pack(old_word_valid_mask) == 0) ?
            tagged Invalid :
            tagged Valid metaData(old_meta.tag, old_meta.dirty, old_word_valid_mask);

        metaStore.write(set, meta);

        debugLog.record($format("  Read FILL uncacheable: restored addr=0x%x, set=0x%x, way=%0d, mask=%b",
                        debugAddrFromTag(tag, set), set, way, old_word_valid_mask));

        doneQ.enq(set);
    endrule


    // ====================================================================
    //
    //   End of reference.
    //
    // ====================================================================

    // BE CAREFUL HERE!  Poor choice of order can cause deadlocks.
    (* descending_urgency = "doneWithRef, writeCacheData, fixupUncacheableFillForRead, handleFillForRead, handleFillForCacheableRead, handleFillForUncacheableRead, pickReqQueue, handleReadCacheHit, fwdInvalOrFlush, flushDirtyLine, sendFillRequest, handleWordMissForRead, handleMissForRead, handleMissForWrite, handleRead, handleWrite, handleInvalOrFlush" *)

    //
    // doneWithRef --
    //     All access paths terminate here.
    //
    rule doneWithRef (True);
        let set = doneQ.first();
        doneQ.deq();

        setFilter.remove(set);
    endrule


    // ====================================================================
    //
    //   Debug scan state
    //
    // ====================================================================

    List#(Tuple2#(String, Bool)) ds_data = List::nil;

    ds_data = List::cons(tuple2("SA BRAM Cache newReqQ NotEmpty", newReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache metaLookupQ NotEmpty", metaLookupQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache dataLookupQ NotEmpty", dataLookupQ.notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA BRAM Cache writeDataQ NotEmpty", writeDataQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache writeDataQ NotFull", writeDataQ.notFull), ds_data);

    ds_data = List::cons(tuple2("SA BRAM Cache lineMissQ NotEmpty", lineMissQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache wordMissQ NotEmpty", wordMissQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache mafLookupQ NotEmpty", mafLookupQ.notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA BRAM Cache fillLineRequestQ NotEmpty", fillLineRequestQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache fillLineUncacheableQ NotEmpty", fillLineUncacheableQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache doneQ NotEmpty", doneQ.notEmpty), ds_data);

    let debugScanData = ds_data;
    
    // ====================================================================
    //
    //   Incoming cache requests (methods)
    //
    // ====================================================================

    //
    // genRequest --
    //     This function is used by most of the request methods to generate
    //     the internal data structure for managing a request.  It also starts
    //     the first step:  reading metadata from BRAM.
    //
    function ActionValue#(t_CACHE_SET_IDX) genRequest(t_CACHE_REQ req,
                                                      t_CACHE_ADDR addr);
        actionvalue
            match {.tag, .set} = cacheTagAndSet(addr);

            t_CACHE_REQ_BASE req_base;
            req_base.tag = tag;
            req_base.set = set;
            req_base.way = ?;  // Way won't be known until the set meta data is read
            newReqQ.enq(tuple2(req_base, req));
            
            return set;
        endactionvalue
    endfunction

    //
    // readReq -- Read up to a full line.  Fetch from backing store if not in the cache.
    //
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

        RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META) req;
        req.wordIdx = wordIdx;
        req.readMeta = readMeta;
        req.globalReadMeta = globalReadMeta;
        
        let set <- genRequest(tagged HCOP_READ req, addr);
        debugLog.record($format("  New request: READ addr=0x%x, set=0x%x, word=%0d", debugAddr(addr), set, wordIdx));
    endmethod

    method ActionValue#(t_CACHE_LOAD_RESP) readResp();
        match {.req_base, .r_req, .v, .valid_words, .is_cacheable} = readRespToClientQ_OOO.first();
        readRespToClientQ_OOO.deq();
        Vector#(nWordsPerLine, t_CACHE_WORD) value = unpack(pack(v));

        t_CACHE_LOAD_RESP rsp;
        for (Integer w = 0; w < valueOf(nWordsPerLine); w = w + 1)
            rsp.words[w] = valid_words[w] ? tagged Valid value[w] : tagged Invalid;
        rsp.addr = cacheAddr(req_base.tag, req_base.set);
        rsp.reqWordIdx = r_req.wordIdx;
        rsp.isCacheable = is_cacheable;
        rsp.readMeta = r_req.readMeta;
        rsp.globalReadMeta = r_req.globalReadMeta;

        return rsp;
    endmethod

    method t_CACHE_ADDR peekRespAddr();
        match {.req_base, .r_req, .v, .valid_words} = readRespToClientQ_OOO.first();
        return cacheAddr(req_base.tag, req_base.set);
    endmethod

    method Bool readRespReady();
        return readRespToClientQ_OOO.notEmpty();
    endmethod

    //
    // write -- Write a word to a line.
    //
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_WORD_IDX wordIdx);
        t_CACHE_WRITE_INFO w_info;
        w_info.val = val;

        let h <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(h, w_info);

        RL_SA_BRAM_CACHE_WRITE_REQ#(nWordsPerLine) w_req;
        w_req.wordIdx = wordIdx;    
        w_req.dataIdx = h;

        let set <- genRequest(tagged HCOP_WRITE w_req, addr);

        debugLog.record($format("  New request: WRITE addr=0x%x, set=0x%x, data=0x%x, word=%0d, wData heap=%0d", debugAddr(addr), set, val, wordIdx, h));
    endmethod


    //
    // invalReq -- Invalidate (remove) a line from the cache
    //
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
        let set <- genRequest(tagged HCOP_INVAL sendAck, addr);
        debugLog.record($format("  New request: INVAL addr=0x%x, set=0x%x, needAck=%s", 
                        debugAddr(addr), set, sendAck? "True" : "False"));
    endmethod
    

    //
    // flushReq --
    //     Flush (write back) a line from the cache but keep the line cached.
    //
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
        let set <- genRequest(tagged HCOP_FLUSH_DIRTY sendAck, addr);
        debugLog.record($format("  New request: FLUSH addr=0x%x, set=0x%x, needAck=%s", 
                        debugAddr(addr), set, sendAck? "True" : "False"));
    endmethod

    //
    // invalOrFlushWait -- Block until an inval or flush request completes.
    //
    method Action invalOrFlushWait();
        debugLog.record($format("    INVAL/FLUSH complete"));
        sourceData.invalOrFlushWait();
    endmethod

    //
    // setCacheMode -- Configure cache behavior.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
        if (cacheMode != mode)
        begin
            debugLog.record($format("Cache mode: %0d", mode));
        end
        cacheMode <= mode;    
    endmethod

    //
    // debugScanState -- Return cache state for DEBUG_SCAN.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
        return debugScanData;
    endmethod

    interface RL_CACHE_STATS stats;
        method Bool readHit() = readHitW;
        method Bool readMiss() = readMissW;
        method Bool readRecentLineHit() = False;
        method Bool writeHit() = writeHitW;
        method Bool writeMiss() = writeMissW;
        method Bool newMRU() = newMRUW;
        method Bool invalEntry() = invalEntryW;
        method Bool dirtyEntryFlush() = dirtyEntryFlushW;
        method Bool forceInvalLine() = forceInvalLineW;
    endinterface

endmodule

