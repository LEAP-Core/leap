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
// Load response
//
typedef struct
{
    // Not all returned words are guaranteed, so they are protected by Maybe#().
    // The requested word is guaranteed valid.
    Vector#(nWordsPerLine, Maybe#(t_CACHE_WORD)) words;
    t_CACHE_ADDR addr;
    // Word index requested by read.
    Bit#(TLog#(nWordsPerLine)) reqWordIdx;
    Bool isCacheable;
    t_CACHE_READ_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_SA_CACHE_LOAD_RESP#(type t_CACHE_ADDR,
                       type t_CACHE_WORD,
                       numeric type nWordsPerLine,
                       type t_CACHE_READ_META)
    deriving (Eq, Bits);


//
// Cache mode can set the write policy or completely disable hits in the cache.
// This is mostly useful for debugging.
//
typedef enum
{
    RL_SA_MODE_WRITE_BACK,
    RL_SA_MODE_WRITE_THROUGH,
    RL_SA_MODE_DISABLED0,
    RL_SA_MODE_DISABLED1
}
RL_SA_CACHE_MODE
    deriving (Eq, Bits);


//
// Set associative cache interface.  nTagExtraLowBits is used just for
// debugging.  This specified number of low bits are prepanded to cache
// tags so addresses match those seen in other modules.
//
// t_CACHE_READ_META is metadata associated with a reference.  Metadata is
// passed to the backing store for fills.  The metadata is not stored in
// the cache.
//
interface RL_SA_CACHE#(type t_CACHE_ADDR,
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

endinterface: RL_SA_CACHE


//
// Source data fill response
//
typedef struct
{
    Bool isCacheable;
    t_CACHE_LINE val;
}
RL_SA_CACHE_FILL_RESP#(type t_CACHE_LINE)
    deriving (Eq, Bits);

//
// The caller must provide an instance of the RL_SA_CACHE_SOURCE_DATA interface
// so the cache can read and write data from the next level in the hierarchy.
//
// See RL_SA_CACHE interface for description of readUID.
//
interface RL_SA_CACHE_SOURCE_DATA#(type t_CACHE_ADDR,
                                   type t_CACHE_LINE,
                                   numeric type nWordsPerLine,
                                   type t_CACHE_READ_UID);

    // Read request and response with data
    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_READ_UID readUID,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

    method ActionValue#(RL_SA_CACHE_FILL_RESP#(t_CACHE_LINE)) readResp();
    
    // Asynchronous write (no response)
    method Action write(t_CACHE_ADDR addr,
                        Vector#(nWordsPerLine, Bool) wordValidMask,
                        t_CACHE_LINE val);
    
    // Synchronous write.  writeSyncWait() blocks until the response arrives.
    method Action writeSyncReq(t_CACHE_ADDR addr,
                               Vector#(nWordsPerLine, Bool) wordValidMask,
                               t_CACHE_LINE val);
    method Action writeSyncWait();

endinterface: RL_SA_CACHE_SOURCE_DATA

//
// Number of read ports required by the cache code.
typedef 4 RL_SA_CACHE_DATA_READ_PORTS;

//
// The caller must also provide storage for the cache's local data.  Local
// data includes both cache metadata and the cached values.
//
// A standard BRAM-based implementation of local data is provided in this
// module (mkBRAMCacheLocalData).
//
interface RL_SA_CACHE_LOCAL_DATA#(numeric type t_CACHE_ADDR_SZ,
                                  type t_CACHE_WORD,
                                  numeric type nWordsPerLine,
                                  numeric type nSets,
                                  numeric type nWays,
                                  numeric type nReaders);
    //
    // Fetch an entire set.  Requesting the set instead of just the metadata
    // gives high-latency storage a chance to prefetch the data.  The response
    // arrives first as readMetaRsp().  If prefetchSet is True, the caller
    // is also obligated to invoke the readDataReq() / readDataRsp() pair
    // exactly once.
    //
    method Action setReadReq(RL_SA_CACHE_SET_IDX#(nSets) set, Bool prefetchSet);

    // Set's metadata, returned as a response to setReadReq().
    method ActionValue#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays)) metaReadRsp();
    method Bool metaReadNotEmpty();

    // Read one way from the set fetched by setReadReq() with prefetchSet True.
    // This pair must be called when prefetchSet was True and may not be called
    // when it was False.
    interface Vector#(nReaders,
                      MEMORY_READER_IFC#(RL_SA_CACHE_WAY_IDX#(nWays),
                                         Vector#(nWordsPerLine, t_CACHE_WORD))) dataRead;

    // Write metadata for a set
    method Action metaWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays) meta);

    // Write up to an entire line, writing only the words with bits set in
    // wordMask.
    method Action dataWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_WAY_IDX#(nWays) way,
                            Vector#(nWordsPerLine, Bool) wordMask,
                            Vector#(nWordsPerLine, t_CACHE_WORD) val);

    // Write only a single word in a line.
    method Action dataWriteWord(RL_SA_CACHE_SET_IDX#(nSets) set,
                                RL_SA_CACHE_WAY_IDX#(nWays) way,
                                Bit#(TLog#(nWordsPerLine)) wordIdx,
                                t_CACHE_WORD val);
endinterface: RL_SA_CACHE_LOCAL_DATA


// ===================================================================
//
// PRIVATE DATA STRUCTURES
//
// ===================================================================

//
// Size of the conflicting reference holding queue.  Results may be returned
// out of order.  Only one request to a given line may be in flight.  Shunt
// conflicting requests to a side queue in order to allow other non-conflicting
// requests to proceed.
//
typedef 16 RL_SA_CONFLICTQ_ENTRIES;

//
// Data to be written to the cache.
//
typedef struct
{
    t_CACHE_WORD val;
}
RL_SA_CACHE_WRITE_INFO#(type t_CACHE_WORD, type t_CACHE_WRITE_WORD_IDX)
    deriving (Eq, Bits);

//
// Bit size of the write data heap index.  To save space, write data is passed
// through the cache pipelines as a pointer.  The heap size limits the number
// of writes in flight.  Writes never wait for a fill, so the heap doesn't
// have to be especially large.
//
typedef 3 WRITE_DATA_HEAP_IDX_SZ;

//
// Meta-data associated with a write request.
//
typedef struct
{
    Bit#(WRITE_DATA_HEAP_IDX_SZ) dataIdx;
    Bit#(TLog#(nWordsPerLine)) wordIdx;
}
RL_SA_CACHE_WRITE_REQ#(numeric type nWordsPerLine)
    deriving (Eq, Bits);


typedef UInt#(TLog#(nSets)) RL_SA_CACHE_SET_IDX#(numeric type nSets);
typedef UInt#(TLog#(nWays)) RL_SA_CACHE_WAY_IDX#(numeric type nWays);


//
// Cache way metadata (tag and a dirty bit). It is the responsibility of the
// package using this cache to drop insignificant low bits from the address
// size before addresses reach here.
//

typedef Bit#(TSub#(t_CACHE_ADDR_SZ, TLog#(nSets))) RL_SA_CACHE_TAG#(numeric type t_CACHE_ADDR_SZ, numeric type nSets);

typedef struct
{
    RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets) tag;
    Bool dirty;
    Vector#(nWordsPerLine, Bool) wordValid;
}
RL_SA_CACHE_WAY_METADATA#(numeric type t_CACHE_ADDR_SZ, numeric type nWordsPerLine, numeric type nSets)
    deriving(Bits, Eq);

//
// Cache set metadata includes LRU chain and the metadata for each way.  The
// way metadata is wrapped in a Maybe#() to permit invalid (unallocated) ways.
//
typedef struct
{
    Vector#(nWays, RL_SA_CACHE_WAY_IDX#(nWays)) lru;
    Vector#(nWays, Maybe#(RL_SA_CACHE_WAY_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets))) ways;
}
RL_SA_CACHE_SET_METADATA#(numeric type t_CACHE_ADDR_SZ, numeric type nWordsPerLine, numeric type nSets, numeric type nWays)
    deriving(Bits, Eq);

instance DefaultValue#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays));
    defaultValue = RL_SA_CACHE_SET_METADATA { lru: Vector::genWith(fromInteger),
                                              ways: Vector::replicate(tagged Invalid) };
endinstance


//
// The cache data is indexed by the set and the way within the set.
// Declaring the cache data as multiply indexed vectors results in a large
// amount of extra LUT usage to control the BRAMs.  Instead, we allocate a
// single large cache data BRAM and index it with a packed version of this
// structure:
//
typedef struct
{
    t_CACHE_SET_IDX set;
    RL_SA_CACHE_WAY_IDX#(nWays) way;
}
RL_SA_CACHE_DATA_IDX#(numeric type nWays, type t_CACHE_SET_IDX)
    deriving(Bits, Eq);


//
// Responses to flush and invalidate requests are returned in order to
// guarantee consistent state.  The number of entries in the scoreboard
// limits the number of requests in flight.
//
typedef 16 RL_SA_CACHE_MAX_INVAL;
typedef Bit#(TLog#(RL_SA_CACHE_MAX_INVAL)) RL_SA_CACHE_INVAL_IDX;


//
// Specify read client for localData reads.
//
typedef enum
{
    RL_SA_CACHE_META_CLIENT_STD,
    RL_SA_CACHE_META_CLIENT_UNCACHEABLE
}
RL_SA_CACHE_META_CLIENT
    deriving (Eq, Bits);


//
// Meta-data associated with a read request.
//
typedef struct
{
    Bit#(TLog#(nWordsPerLine)) wordIdx;
}
RL_SA_CACHE_READ_REQ#(numeric type nWordsPerLine)
    deriving (Eq, Bits);


//
// Basic request information constructed when a new request arrives.
//
// This declaration would be much cleaner if typedef could be inside a module
// after the types are known.
//
typedef struct
{
    t_CACHE_TAG     tag;
    t_CACHE_SET_IDX set;
    t_CACHE_WAY_IDX way;

    // Meta-data associated with the reference.  Meta-data has meaning only to the
    // caller.
    t_CACHE_READ_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_SA_CACHE_REQ_BASE#(type t_CACHE_TAG,
                      type t_CACHE_SET_IDX,
                      type t_CACHE_WAY_IDX,
                      type t_CACHE_READ_META)
    deriving(Bits, Eq);

typedef union tagged
{
    // Reads have no extra data (beyond RL_SA_CACHE_REQ_BASE above)
    RL_SA_CACHE_READ_REQ#(nWordsPerLine) HCOP_READ;

    // Writes have pointer to data to be written
    RL_SA_CACHE_WRITE_REQ#(nWordsPerLine) HCOP_WRITE;

    // Inval and flush have a bool indicating whether an ACK is needed
    Maybe#(RL_SA_CACHE_INVAL_IDX) HCOP_INVAL;
    Maybe#(RL_SA_CACHE_INVAL_IDX) HCOP_FLUSH_DIRTY;
}
RL_SA_CACHE_REQ#(numeric type nWordsPerLine)
    deriving(Bits, Eq);


// ========================================================================
//
// mkCacheSetAssoc --
//     Set associative cache.
//
//    NOTE: mkCacheSetAssoc may return read responses out of order relative
//          to the request order!  For in-order responses the caller
//          must add a tag to the t_CACHE_READ_META type and use the
//          tag to sort the responses.  A SCOREBOARD_FIFO would do the job.
//
// ========================================================================

module mkCacheSetAssoc#(RL_SA_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_CACHE_READ_META) sourceData,
                        RL_SA_CACHE_LOCAL_DATA#(t_CACHE_ADDR_SZ, t_CACHE_WORD, nWordsPerLine, nSets, nWays, nReaders) localData,
                        NumTypeParam#(t_RECENT_READ_CACHE_IDX_SZ) param0,
                        NumTypeParam#(nTagExtraLowBits) param1,
                        DEBUG_FILE debugLog)
    // interface:
        (RL_SA_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META))
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
              Alias#(RL_SA_CACHE_REQ_BASE#(t_CACHE_TAG, t_CACHE_SET_IDX, t_CACHE_WAY_IDX, t_CACHE_READ_META), t_CACHE_REQ_BASE),
              Alias#(RL_SA_CACHE_REQ#(nWordsPerLine), t_CACHE_REQ),
              Alias#(Bit#(TLog#(nWordsPerLine)), t_CACHE_WRITE_WORD_IDX),
              Alias#(RL_SA_CACHE_WRITE_INFO#(t_CACHE_WORD, t_CACHE_WRITE_WORD_IDX), t_CACHE_WRITE_INFO),
              Alias#(Vector#(nWordsPerLine, Bool), t_CACHE_WORD_VALID_MASK),
       
              Bits#(t_CACHE_REQ, t_CACHE_REQ_SZ),

              // Index and tag of local, recently read, line cache.
              Alias#(Bit#(t_RECENT_READ_CACHE_IDX_SZ), t_RECENT_READ_CACHE_IDX),
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, t_RECENT_READ_CACHE_IDX_SZ)), t_RECENT_READ_CACHE_TAG),
              Alias#(Maybe#(Tuple3#(t_RECENT_READ_CACHE_TAG,
                                    t_CACHE_LINE,
                                    t_CACHE_WORD_VALID_MASK)), t_RECENT_READ_CACHE_ENTRY),

              // Unbelievably ugly tautologies required by the compiler:
              Add#(TSub#(t_CACHE_ADDR_SZ, t_RECENT_READ_CACHE_IDX_SZ), t_RECENT_READ_CACHE_IDX_SZ, t_CACHE_ADDR_SZ),
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
 


    // ***** Internal state *****

    Reg#(Bool) cacheIsEmpty <- mkReg(True);

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(Bit#(WRITE_DATA_HEAP_IDX_SZ), t_CACHE_WRITE_INFO) reqInfo_writeData <- mkMemoryHeapLUTRAM();

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

    // First stage coming out of handleIncomingReq
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) processReqQ0 <- mkSizedFIFOF(4);
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, Bool)) processReqQ1 <- mkSizedFIFOF(8);
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE,
                   t_CACHE_REQ,
                   Bool,
                   t_SET_METADATA,
                   Maybe#(Tuple2#(t_CACHE_WAY_IDX, t_METADATA))))
        processReqQ2 <- mkFIFOF();

    // Hit path for operations that read the cache (read and flush)
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK)) readHitQ <- mkSizedFIFOF(8);

    // Queues on miss path
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_SET_METADATA, t_CACHE_WAY_IDX)) lineMissQ <- mkFIFOF();
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK)) wordMissQ <- mkFIFOF();

    // Fill for read path
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) fillLineRequestQ <- mkFIFOF();
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK)) fillLineQ <- mkSizedFIFOF(16);
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_WORD_VALID_MASK)) fillLineUncacheableQ <- mkSizedFIFOF(8);

    // Write data to an allocated queue entry
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, RL_SA_CACHE_WRITE_REQ#(nWordsPerLine))) writeDataQ <- mkFIFOF();

    // Wait for ACK from backing store that flush was received
    FIFO#(Tuple2#(t_CACHE_SET_IDX, Maybe#(RL_SA_CACHE_INVAL_IDX))) flushAckQ <- mkFIFO();

    // Exit from all paths
    FIFOF#(t_CACHE_SET_IDX) doneQ <- mkFIFOF();

    // Read responses may be returned out of order relative to request order!
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, RL_SA_CACHE_READ_REQ#(nWordsPerLine), t_CACHE_LINE, t_CACHE_WORD_VALID_MASK, Bool)) readRespToClientQ_OOO <- mkFIFOF();

    // Who asked for localData read?
    FIFOF#(RL_SA_CACHE_META_CLIENT) metaClientQ <- mkSizedFIFOF(8);

    // Invalidate and flush requests are always returned in the order they
    // were requested.
    SCOREBOARD_FIFOF#(RL_SA_CACHE_MAX_INVAL, Bool) invalReqDoneQ <- mkScoreboardFIFOF();

    PulseWire readMissW          <- mkPulseWire();
    PulseWire writeMissW         <- mkPulseWire();
    PulseWire readHitW           <- mkPulseWire();
    PulseWire writeHitW          <- mkPulseWire();
    PulseWire newMRUW            <- mkPulseWire();
    PulseWire invalEntryW        <- mkPulseWire();
    PulseWire forceInvalLineW    <- mkPulseWire();
    PulseWire dirtyEntryFlushW   <- mkPulseWire();
    PulseWire readRecentLineHitW <- mkPulseWire();


    // ***** localData read port assignment ***** //

    // Writeback of explicit inval/flush request
    let lpFLUSH = 0;
    // Read hit
    let lpREAD  = 1;
    // Writeback for line evicted due to capacity
    let lpWB    = 2;
    // Drain prefetched set (not needed)
    let lpDRAIN = 3;


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


    // ====================================================================
    //
    // Recent read line cache
    //
    // ====================================================================

    //
    // The recent line cache optimizes repeated reads to the same line
    // using a small BRAM cache.  This avoids the latency of reading meta data
    // and then the actual data.  Repeated references to the same line
    // occur because the L1 caches are word sized, not line sized.
    //

    // Recent line cache enabled?
    Reg#(Bool) enableRecentLineCache <- mkReg(True);

    MEMORY_IFC#(t_RECENT_READ_CACHE_IDX, t_RECENT_READ_CACHE_ENTRY)
        recentLineCache <- mkSlowMemoryM(mkBRAMInitialized(tagged Invalid), True);

    // Lock out potential reads and writes of the same entry in a cycle
    RWire#(t_RECENT_READ_CACHE_IDX) recentLineWriteLock <- mkRWire();

    //
    // recentLineTagAndIdx --
    //   Indexing function for recent read cache.
    //
    function Tuple2#(t_RECENT_READ_CACHE_TAG,
                     t_RECENT_READ_CACHE_IDX) recentLineTagAndIdx(t_CACHE_TAG tag,
                                                                  t_CACHE_SET_IDX set);
        // Break cache address into recent read index and tag.
        return unpack({tag, pack(set)});
    endfunction

    function t_RECENT_READ_CACHE_TAG recentLineTag(t_CACHE_TAG tag,
                                                   t_CACHE_SET_IDX set) =
        tpl_1(recentLineTagAndIdx(tag, set));

    function t_RECENT_READ_CACHE_IDX recentLineIdx(t_CACHE_TAG tag,
                                                   t_CACHE_SET_IDX set) =
        tpl_2(recentLineTagAndIdx(tag, set));

    //
    // updateRecentReadLine --
    //   Write a new read value to the recent line cache.  Also sets the BRAM's
    //   write lock to avoid read and write of the same entry in an FPGA cycle.
    //
    function Action updateRecentReadLine(t_CACHE_TAG tag,
                                         t_CACHE_SET_IDX set,
                                         t_RECENT_READ_CACHE_ENTRY entry);
    action
        let idx = recentLineIdx(tag, set);
        recentLineCache.write(idx, entry);
        recentLineWriteLock.wset(idx);
    endaction
    endfunction

    //
    // Test whether a recent line is read-locked due to a write this cycle.
    // In some BRAM implementations, read and write of the same entry
    // produces unpredictable read results.
    //
    function Bool recentReadLineLocked(t_CACHE_TAG tag,
                                       t_CACHE_SET_IDX set);
        let recent_idx = recentLineIdx(tag, set);
        let recent_lock = recentLineWriteLock.wget();
        return (isValid(recent_lock) &&
                (recent_idx == validValue(recent_lock)));
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

        if (! recentReadLineLocked(tag, set))
        begin
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

        debugLog.record($format("  FWD %s to ReqQ: addr=0x%x, set=0x%x",
                                pick_new_req ? "new" : "side",
                                debugAddrFromTag(tag, set), set));

        // Read the current state of the recent line cache for the set.
        recentLineCache.readReq(recentLineIdx(tag, set));
        processReqQ0.enq(tuple2(req_base, req));

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

    (* fire_when_enabled *)
    rule shuntNewReq (tpl_1(curReq) &&
                      ! tpl_1(tpl_2(curReq)).globalReadMeta.orderedSourceDataReqs &&
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
    // handleIncomingReq1 --
    //     Second stage combines the request and the state of the recent
    //     line cache.  Now it can be known whether a meta data read is
    //     required.
    //
    rule handleIncomingReq1 (True);
        match {.req_base, .req} = processReqQ0.first();
        processReqQ0.deq();

        let recent_lc <- recentLineCache.readRsp();
        Bool recent_is_valid = isValid(recent_lc) && enableRecentLineCache;
        match {.recent_tag, .recent_line, .recent_word_valid_mask} = validValue(recent_lc);

        let tag = req_base.tag;
        let set = req_base.set;

        Bool recent_matches = recent_is_valid &&
                              (recent_tag == recentLineTag(tag, set));

        if (req matches tagged HCOP_READ .rReq &&&
            recent_matches && recent_word_valid_mask[rReq.wordIdx])
        begin
            // Recent line read hit!
            debugLog.record($format("  Read RECENT HIT: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, recent_word_valid_mask, recent_line));
            readRecentLineHitW.send();

            readRespToClientQ_OOO.enq(tuple5(req_base,
                                             rReq,
                                             recent_line,
                                             recent_word_valid_mask,
                                             True));

            doneQ.enq(set);
        end
        else
        begin
            //
            // Normal path -- no recent read line hit.
            //

            // Read meta data and LRU hints
            localData.setReadReq(req_base.set, True);
            metaClientQ.enq(RL_SA_CACHE_META_CLIENT_STD);

            processReqQ1.enq(tuple3(req_base, req, recent_matches));
        end
    endrule


    //
    // handleIncomingReq2 --
    //     Receive a set's current metadata and see whether the line hit
    //     in the cache.
    //
    rule handleIncomingReq2 (metaClientQ.first() == RL_SA_CACHE_META_CLIENT_STD);
        match {.req_base_in, .req, .recent_matches} = processReqQ1.first();
        processReqQ1.deq();

        let meta <- localData.metaReadRsp();
        metaClientQ.deq();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        processReqQ2.enq(tuple5(req_base_in, req, recent_matches, meta,
                                findWayMatch(tag, meta)));
    endrule


    // ====================================================================
    //
    // Three stage path for invalidate or flush requests.  First stage
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
    rule handleInvalOrFlush (reqIsInvalOrFlush(tpl_2(processReqQ2.first())));
        match {.req_base_in, .req, .recent_matches, .meta, .m_match} = processReqQ2.first();
        processReqQ2.deq();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        Maybe#(RL_SA_CACHE_INVAL_IDX) need_ack = ?;
        Bool is_inval = ?;

        if (recent_matches)
        begin
            // Invalidate an entry currently stored in the recent line cache.
            debugLog.record($format("  RECENT Inval: addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
            updateRecentReadLine(tag, set, tagged Invalid);
        end

        case (req) matches
        tagged HCOP_INVAL .needACK:
        begin
            need_ack = needACK;
            is_inval = True;
            debugLog.record($format("  Process request: INVAL addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
        end
        tagged HCOP_FLUSH_DIRTY .needACK:
        begin
            need_ack = needACK;
            is_inval = False;
            debugLog.record($format("  Process request: FLUSH addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
        end
        endcase

        Bool found_dirty_line = False;
        let req_base_out = req_base_in;

        if (m_match matches tagged Valid {.way, .way_meta})
        begin
            let meta_upd = meta;

            if (way_meta.dirty)
            begin
                // Found dirty line.  Prepare for write back.
                req_base_out.way = way;
                localData.dataRead[lpFLUSH].readReq(way);
                readHitQ.enq(tuple3(req_base_out, req, way_meta.wordValid));
                found_dirty_line = True;

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

            localData.metaWrite(set, meta_upd);

            debugLog.record($format("  FLUSH/INVAL HIT %s: addr=0x%x, set=0x%x, way=%0d", (found_dirty_line ? "dirty" : "clean"), debugAddrFromTag(tag, set), set, way));
        end
        
        if (! found_dirty_line)
        begin
            // Line is not dirty.  Done with this request.
            doneQ.enq(set);

            // Must consume prefetched set
            localData.dataRead[lpDRAIN].readReq(?);

            if (need_ack matches tagged Valid .inval_idx)
                invalReqDoneQ.setValue(inval_idx, ?);
        end
    endrule


    //
    // flushDirtyLine --
    //   Flush a dirty line and continue on to fill, if appropriate.
    //
    rule flushDirtyLine (reqIsInvalOrFlush(tpl_2(readHitQ.first())));

        match {.req_base, .req, .word_valid_mask} = readHitQ.first();
        readHitQ.deq();

        let v <- localData.dataRead[lpFLUSH].readRsp();
        t_CACHE_LINE flush_data = unpack(pack(v));

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        Maybe#(RL_SA_CACHE_INVAL_IDX) need_ack =
            case (req) matches
                tagged HCOP_INVAL .needAck: needAck;
                tagged HCOP_FLUSH_DIRTY .needAck: needAck;
            endcase;

        dirtyEntryFlushW.send();
        debugLog.record($format("  Write back DIRTY: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, word_valid_mask, flush_data));

        // Flush for invalidate request.  Use sync method to know the
        // data arrived.
        sourceData.writeSyncReq(cacheAddr(tag, set), word_valid_mask, flush_data);
        flushAckQ.enq(tuple2(set, need_ack));
    endrule


    //
    // handleFlushACK --
    //   Wait for the response to a flush from back storage for synchronous
    //   flushes.
    //
    rule handleFlushACK (True);
        sourceData.writeSyncWait();

        match { .set, .need_ack } = flushAckQ.first();
        flushAckQ.deq();

        // Done with this flush request.
        doneQ.enq(set);

        if (need_ack matches tagged Valid .inval_idx)
        begin
            invalReqDoneQ.setValue(inval_idx, ?);
            debugLog.record($format("  FLUSH or INVAL done, set=0x%x, invalIdx=%0d", set, inval_idx));
        end
        else
        begin
            debugLog.record($format("  FLUSH or INVAL done, set=0x%x", set));
        end
    endrule


    //
    // drainPrefetch --
    //   Consume set prefetch when not needed.    
    //
    rule drainPrefetch (True);
        let d <- localData.dataRead[lpDRAIN].readRsp();
    endrule


    // ====================================================================
    //
    // Read and Write data path.
    //
    // ====================================================================

    //
    // handleRead --
    //     First unique stage of cache READ path.
    //
    (* conservative_implicit_conditions *)
    rule handleRead (tpl_2(processReqQ2.first()) matches tagged HCOP_READ .rReq);
        match {.req_base_in, .req, .recent_matches, .meta, .m_match} = processReqQ2.first();
        processReqQ2.deq();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        debugLog.record($format("  Process request: READ addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        Bool need_set_data = False;
        let req_base_out = req_base_in;

        if (m_match matches tagged Valid {.way, .way_meta})
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
                localData.dataRead[lpREAD].readReq(way);
                need_set_data = True;
                readHitQ.enq(tuple3(req_base_out, req, way_meta.wordValid));

                if (meta_upd.lru != meta.lru)
                begin
                    // LRU changed.  Update metadata.
                    localData.metaWrite(set, meta_upd);
                    newMRUW.send();
                end
            end
            else
            begin
                // Line valid but word in line is not.  Fill.
                wordMissQ.enq(tuple3(req_base_out, req, way_meta.wordValid));

                // Must consume prefetched set data
                localData.dataRead[lpDRAIN].readReq(?);

                // Mark all words valid in the line.  They will be after
                // the fill completes.
                meta_upd.ways[way] = tagged Valid metaData(tag, way_meta.dirty, replicate(True));

                localData.metaWrite(set, meta_upd);
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

            lineMissQ.enq(tuple4(req_base_out, req, meta, fill_way));
            localData.dataRead[lpWB].readReq(fill_way);
        end
    endrule


    //
    // handleWrite --
    //     First unique stage of cache WRITE path.
    //
    (* conservative_implicit_conditions *)
    rule handleWrite (tpl_2(processReqQ2.first()) matches tagged HCOP_WRITE .wReq);
        match {.req_base_in, .req, .recent_matches, .meta, .m_match} = processReqQ2.first();
        processReqQ2.deq();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        debugLog.record($format("  Process request: WRITE addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        if (recent_matches)
        begin
            // Write to an entry stored in the recent line cache.  Simply invalidate
            // it instead of being clever.  Even if we were trying to be clever,
            // all we have is one word.
            debugLog.record($format("  RECENT Inval: addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
            updateRecentReadLine(tag, set, tagged Invalid);
        end

        cacheIsEmpty <= False;
        let req_base_out = req_base_in;

        if (m_match matches tagged Valid {.way, .way_meta})
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

            // Update metadata if it is changed.  Skip the write otherwise, since
            // DDR writes are costly.
            if ((meta_upd.lru != meta.lru) ||
                (new_word_valid != way_meta.wordValid) ||
                ! way_meta.dirty)
            begin
                localData.metaWrite(set, meta_upd);
                if (meta_upd.lru != meta.lru)
                begin
                    newMRUW.send();
                end
            end

            // Request write to cache
            writeDataQ.enq(tuple2(req_base_out, wReq));
            debugLog.record($format("  Write HIT: addr=0x%x, set=0x%x, way=%0d, mask=0x%x", debugAddrFromTag(tag, set), set, way, new_word_valid));

            // Must consume prefetched set
            localData.dataRead[lpDRAIN].readReq(?);
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

            lineMissQ.enq(tuple4(req_base_out, req, meta, fill_way));
            localData.dataRead[lpWB].readReq(fill_way);
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
    rule handleReadCacheHit (tpl_2(readHitQ.first()) matches tagged HCOP_READ .rReq);

        match {.req_base, .req, .word_valid_mask} = readHitQ.first();
        readHitQ.deq();

        let d <- localData.dataRead[lpREAD].readRsp();
        t_CACHE_LINE v = unpack(pack(d));

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        // Update the recent line cache
        updateRecentReadLine(tag, set,
                             tagged Valid tuple3(recentLineTag(tag, set),
                                                 v,
                                                 word_valid_mask));

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

        localData.dataWriteWord(set, way, w_req.wordIdx, w_data.val);

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

        match {.req_base, .req, .word_valid_mask} = wordMissQ.first();
        wordMissQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;

        //
        // Miss.  Pick a victim.
        //

        readMissW.send();

        let addr = cacheAddr(tag, set);
        sourceData.readReq(addr, req_base.readMeta, req_base.globalReadMeta);
        fillLineQ.enq(tuple3(req_base, req, word_valid_mask));

        debugLog.record($format("  READ WORD MISS (FILL): addr=0x%x, set=0x%x, way=%0d", debugAddr(addr), set, req_base.way));
    endrule


    //
    // handleMissForRead --
    //     Pick a victim and prepare to fill a way from backing storage.
    //
    (* conservative_implicit_conditions *)
    rule handleMissForRead (tpl_2(lineMissQ.first()) matches tagged HCOP_READ .rReq);

        match {.req_base_in, .req, .meta, .fill_way} = lineMissQ.first();
        lineMissQ.deq();

        let v <- localData.dataRead[lpWB].readRsp();
        t_CACHE_LINE flush_data = unpack(pack(v));

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
        localData.metaWrite(set, meta_upd);

        //
        // Now must figure out the next state...
        //

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
                fillLineRequestQ.enq(tuple2(req_base_out, req));
            end
        end

        if (! flushed_dirty)
        begin
            let addr = cacheAddr(tag, set);
            sourceData.readReq(addr, req_base_out.readMeta, req_base_out.globalReadMeta);
            fillLineQ.enq(tuple3(req_base_out, req, replicate(False)));

            debugLog.record($format("  READ MISS (FILL): addr=0x%x, set=0x%x, way=%0d", debugAddr(addr), set, req_base_out.way));
        end
    endrule


    //
    // handleMissForWrite --
    //     Pick a victim and write back the dirty data, if needed.
    //
    (* conservative_implicit_conditions *)
    rule handleMissForWrite (tpl_2(lineMissQ.first()) matches tagged HCOP_WRITE .wReq);

        match {.req_base_in, .req, .meta, .fill_way} = lineMissQ.first();
        lineMissQ.deq();

        let v <- localData.dataRead[lpWB].readRsp();
        t_CACHE_LINE flush_data = unpack(pack(v));

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
        localData.metaWrite(set, meta_upd);

        //
        // Now must figure out the next state...
        //

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
        match {.req_base, .req} = fillLineRequestQ.first();
        fillLineRequestQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        let addr = cacheAddr(tag, set);
        sourceData.readReq(addr, req_base.readMeta, req_base.globalReadMeta);
        fillLineQ.enq(tuple3(req_base, req, replicate(False)));
    endrule


    //
    // handleFillForRead --
    //    Update the cache with requested data coming back from memory.
    //
    rule handleFillForRead (tpl_2(fillLineQ.first()) matches tagged HCOP_READ .rReq);

        match {.req_base, .req, .cur_word_valid_mask} = fillLineQ.first();
        fillLineQ.deq();

        let rsp <- sourceData.readResp();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        //
        // Cache the new values.  Don't overwrite entries that are currently
        // valid, since they may be dirty.
        //
        // On return only claim that the newly filled words are valid.
        // We could retrieve the entire line but that would take another
        // stage and more wires to read the dirty data from the cache.
        //
        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));
        localData.dataWrite(set, way, ret_valid_words, unpack(pack(rsp.val)));

        // Update the recent line cache
        if (rsp.isCacheable)
        begin
            updateRecentReadLine(tag, set,
                                 tagged Valid tuple3(recentLineTag(tag, set),
                                                     rsp.val,
                                                     ret_valid_words));
        end

        readRespToClientQ_OOO.enq(tuple5(req_base,
                                         rReq,
                                         rsp.val,
                                         ret_valid_words,
                                         rsp.isCacheable));

        debugLog.record($format("  Read FILL%s: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x",
                                (rsp.isCacheable ? "" : " [NOT CACHEABLE]"),
                                debugAddrFromTag(tag, set), set, way, ret_valid_words, rsp.val));

        if (rsp.isCacheable)
        begin
            // Normal path.  Fill is complete and line is marked valid in the
            // cache.
            doneQ.enq(set);
        end
        else
        begin
            // Abnormal path.  Response is uncacheable.  The line has already
            // been marked valid in anticipation of the response, so the
            // metadata must now be fixed.
            localData.setReadReq(set, False);
            metaClientQ.enq(RL_SA_CACHE_META_CLIENT_UNCACHEABLE);
            fillLineUncacheableQ.enq(tuple2(req_base, cur_word_valid_mask));
        end

    endrule

    //
    // fixupUncacheableFillForRead --
    //     Fill response flaged the line uncacheable.  The way's metadata is
    //     speculatively set to valid when the fill is requested and must be
    //     marked invalid.
    //
    rule fixupUncacheableFillForRead (metaClientQ.first() == RL_SA_CACHE_META_CLIENT_UNCACHEABLE);
        match {.req_base, .old_word_valid_mask} = fillLineUncacheableQ.first();
        fillLineUncacheableQ.deq();

        let meta <- localData.metaReadRsp();
        metaClientQ.deq();

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

        localData.metaWrite(set, meta);

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
    (* descending_urgency = "writeCacheData, handleFlushACK, fixupUncacheableFillForRead, handleFillForRead, handleReadCacheHit, flushDirtyLine, sendFillRequest, handleWordMissForRead, handleMissForRead, handleMissForWrite, handleRead, handleWrite, handleInvalOrFlush, handleIncomingReq1" *)

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

    ds_data = List::cons(tuple2("SA Cache metaClientQNotEmpty", metaClientQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache localData_MetaNotEmpty", localData.metaReadNotEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache localData_Data FLUSH NotEmpty", localData.dataRead[lpFLUSH].notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache localData_Data READ NotEmpty", localData.dataRead[lpREAD].notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache localData_Data WB NotEmpty", localData.dataRead[lpWB].notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA Cache writeDataQNotEmpty", writeDataQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache writeDataQNotFull", writeDataQ.notFull), ds_data);
    ds_data = List::cons(tuple2("SA Cache processReqQ0NotEmpty", processReqQ0.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache processReqQ1NotEmpty", processReqQ1.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache processReqQ2NotEmpty", processReqQ2.notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA Cache readHitQNotEmpty", readHitQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache lineMissQNotEmpty", lineMissQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache wordMissQNotEmpty", wordMissQ.notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA Cache fillLineRequestQNotEmpty", fillLineRequestQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache newReqNotEmpty", newReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache fillLineQNotEmpty", fillLineQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache fillLineUncacheableQNotEmpty", fillLineUncacheableQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache doneQNotEmpty", doneQ.notEmpty), ds_data);

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
                                                      t_CACHE_ADDR addr,
                                                      t_CACHE_READ_META readMeta,
                                                      RL_CACHE_GLOBAL_READ_META globalReadMeta);
    actionvalue
        match {.tag, .set} = cacheTagAndSet(addr);

        t_CACHE_REQ_BASE req_base;
        req_base.tag = tag;
        req_base.set = set;
        req_base.way = ?;  // Way won't be known until the set meta data is read
        req_base.readMeta = readMeta;
        req_base.globalReadMeta = globalReadMeta;
        
        newReqQ.enq(tuple2(req_base, req));

        return set;
    endactionvalue
    endfunction


    //
    // readReq -- Read a full line.  Fetch from backing store if not in the cache.
    //
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

        RL_SA_CACHE_READ_REQ#(nWordsPerLine) req;
        req.wordIdx = wordIdx;
    
        let set <- genRequest(tagged HCOP_READ req, addr, readMeta, globalReadMeta);
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
        rsp.readMeta = req_base.readMeta;
        rsp.globalReadMeta = req_base.globalReadMeta;

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
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_WRITE_WORD_IDX wordIdx);
        t_CACHE_WRITE_INFO w_info;
        w_info.val = val;

        let h <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(h, w_info);

        RL_SA_CACHE_WRITE_REQ#(nWordsPerLine) w_req;
        w_req.wordIdx = wordIdx;    
        w_req.dataIdx = h;

        let set <- genRequest(tagged HCOP_WRITE w_req, addr, ?, ?);

        debugLog.record($format("  New request: WRITE addr=0x%x, set=0x%x, data=0x%x, word=%0d, wData heap=%0d", debugAddr(addr), set, val, wordIdx, h));
    endmethod


    //
    // invalReq -- Invalidate (remove) a line from the cache
    //
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
        if (sendAck)
        begin
            let idx <- invalReqDoneQ.enq();
            let set <- genRequest(tagged HCOP_INVAL tagged Valid idx, addr, ?, ?);

            debugLog.record($format("  New request: INVAL addr=0x%x, set=0x%x, invalIdx=%d", debugAddr(addr), set, idx));
        end
        else
        begin
            let set <- genRequest(tagged HCOP_INVAL tagged Invalid, addr, ?, ?);

            debugLog.record($format("  New request: INVAL addr=0x%x, set=0x%x", debugAddr(addr), set));
        end
    endmethod
    

    //
    // flushReq --
    //     Flush (write back) a line from the cache but keep the line cached.
    //
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
        if (sendAck)
        begin
            let idx <- invalReqDoneQ.enq();
            let set <- genRequest(tagged HCOP_FLUSH_DIRTY tagged Valid idx, addr, ?, ?);

            debugLog.record($format("  New request: FLUSH addr=0x%x, set=0x%x, invalIdx=%d", debugAddr(addr), set, idx));
        end
        else
        begin
            let set <- genRequest(tagged HCOP_FLUSH_DIRTY tagged Invalid, addr, ?, ?);

            debugLog.record($format("  New request: FLUSH addr=0x%x, set=0x%x", debugAddr(addr), set));
        end
    endmethod


    //
    // invalOrFlushWait -- Block until an inval or flush request completes.
    //
    method Action invalOrFlushWait();
        invalReqDoneQ.deq();
    endmethod


    //
    // setCacheMode -- Configure cache behavior.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
        if (cacheMode != mode)
            debugLog.record($format("Cache mode: %0d", mode));

        cacheMode <= mode;    
    endmethod


    //
    // setRecentLineCacheMode --
    //     Enable / disable recent line cache.
    //
    method Action setRecentLineCacheMode(Bool enabled);
        debugLog.record($format("Recent line cache: %s",
                                enabled ? "Enabled" : "Disabled"));

        enableRecentLineCache <= enabled;    
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
        method Bool readRecentLineHit() = readRecentLineHitW;
        method Bool writeHit() = writeHitW;
        method Bool writeMiss() = writeMissW;
        method Bool newMRU() = newMRUW;
        method Bool invalEntry() = invalEntryW;
        method Bool dirtyEntryFlush() = dirtyEntryFlushW;
        method Bool forceInvalLine() = forceInvalLineW;
    endinterface

endmodule



// ===================================================================
//
// BRAM-based local data implementation.
//
// ===================================================================

module mkBRAMCacheLocalData
    // interface:
    (RL_SA_CACHE_LOCAL_DATA#(t_CACHE_ADDR_SZ, t_CACHE_WORD, nWordsPerLine, nSets, nWays, nReaders))
    provisos (Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Alias#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays), t_SET_METADATA),
              Bits#(t_SET_METADATA, t_SET_METADATA_SZ),
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Alias#(RL_SA_CACHE_WAY_IDX#(nWays), t_CACHE_WAY_IDX),
              Alias#(Tuple2#(t_CACHE_SET_IDX, t_CACHE_WAY_IDX), t_CACHE_DATA_IDX));
    
    // Metadata
    BRAM#(RL_SA_CACHE_SET_IDX#(nSets), t_SET_METADATA) meta <- mkBRAMInitialized(defaultValue);

    // Values
    Vector#(nWordsPerLine, BRAM_MULTI_READ#(RL_SA_CACHE_DATA_READ_PORTS, t_CACHE_DATA_IDX, t_CACHE_WORD)) data <- replicateM(mkBRAMPseudoMultiRead());

    // Data read ports
    Vector#(nReaders,
            MEMORY_READER_IFC#(RL_SA_CACHE_WAY_IDX#(nWays),
                               Vector#(nWordsPerLine, t_CACHE_WORD))) dataReadPorts = newVector();

    //
    // getDataIdx --
    //     Convert set and way into a linear address.
    //
    function t_CACHE_DATA_IDX getDataIdx (t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        return tuple2(set, way);
    endfunction


    // ====================================================================
    //
    // Read request FIFOs.  Read requests are buffered through FIFOs in
    // order to break scheduling dependence between reads and writes.
    // They also introduce delay that is needed to meet timing between
    // metadata lookups and data reads.
    //
    // ====================================================================

    FIFO#(t_CACHE_SET_IDX) setQ <- mkSizedFIFO(8);
    FIFO#(Tuple3#(Bit#(TLog#(RL_SA_CACHE_DATA_READ_PORTS)), t_CACHE_SET_IDX, t_CACHE_WAY_IDX)) readDataReqQ <- mkFIFO();

    rule forwardDataReq (True);
        match {.port, .set, .way} = readDataReqQ.first();
        readDataReqQ.deq();

        for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
        begin
            data[b].readPorts[port].readReq(getDataIdx(set, way));
        end
    endrule


    //
    // Data access methods
    //

    for (Integer p = 0; p < valueOf(nReaders); p = p + 1)
    begin
        dataReadPorts[p] =
           (interface MEMORY_READER_IFC#(RL_SA_CACHE_WAY_IDX#(nWays),
                                         Vector#(nWordsPerLine, t_CACHE_WORD));
                method Action readReq(RL_SA_CACHE_WAY_IDX#(nWays) way);
                    let set = setQ.first();
                    setQ.deq();

                    readDataReqQ.enq(tuple3(fromInteger(p), set, way));
                endmethod

                method ActionValue#(Vector#(nWordsPerLine, t_CACHE_WORD)) readRsp();
                    Vector#(nWordsPerLine, t_CACHE_WORD) lineVal;
                    for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
                    begin
                        let v <- data[b].readPorts[p].readRsp();
                        lineVal[b] = v;
                    end

                    return lineVal;
                endmethod

                method peek() = error("peek() not implemented");

                method Bool notEmpty();
                    Bool ne = True;
                    for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
                    begin
                        ne = ne && data[b].readPorts[p].notEmpty();
                    end

                    return ne;
                endmethod

                method Bool notFull();
                    Bool nf = True;
                    for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
                    begin
                        nf = nf && data[b].readPorts[p].notFull();
                    end

                    return nf;
                endmethod
            endinterface);
    end

    interface dataRead = dataReadPorts;


    //
    // Metadata access methods
    //
    method Action setReadReq(RL_SA_CACHE_SET_IDX#(nSets) set,
                             Bool prefetchSet);
        meta.readReq(set);
        setQ.enq(set);
    endmethod

    // Set's metadata, returned as a response to setReadReq().
    method ActionValue#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ,
                                                  nWordsPerLine,
                                                  nSets,
                                                  nWays)) metaReadRsp() = meta.readRsp();

    method Bool metaReadNotEmpty() = meta.notEmpty();


    method Action metaWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays) metaUpd);
        meta.write(set, metaUpd);
    endmethod    

    method Action dataWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_WAY_IDX#(nWays) way,
                            Vector#(nWordsPerLine, Bool) wordMask,
                            Vector#(nWordsPerLine, t_CACHE_WORD) val);
        for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
        begin
            // Only write the word if the mask bit is set
            if (wordMask[b])
            begin
                data[b].write(getDataIdx(set, way), val[b]);
            end
        end
    endmethod

    method Action dataWriteWord(RL_SA_CACHE_SET_IDX#(nSets) set,
                                RL_SA_CACHE_WAY_IDX#(nWays) way,
                                Bit#(TLog#(nWordsPerLine)) wordIdx,
                                t_CACHE_WORD val);
        data[wordIdx].write(getDataIdx(set, way), val);
    endmethod

endmodule
