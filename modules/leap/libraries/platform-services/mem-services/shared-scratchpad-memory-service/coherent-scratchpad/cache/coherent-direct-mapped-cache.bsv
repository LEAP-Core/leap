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
// Direct mapped cache with coherence support.  This cache is intended to be 
// relatively simple and light weight, with fast hit times.
//

// Library imports.

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import List::*;
import DefaultValue::*;

// Project foundation imports.

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/coherent_scratchpad_memory_service_params.bsh"

// ===================================================================
//
// PUBLIC DATA STRUCTURES
//
// ===================================================================

// Number of entries in the network request completion table 
typedef 16 COH_DM_CACHE_NW_COMPLETION_TABLE_ENTRIES;
// Number of entries in the miss status handling registers (MSHR)
typedef 64 COH_DM_CACHE_MSHR_ENTRIES;
// Size of the unactivated request buffer
typedef  8 COH_DM_CACHE_NW_REQ_BUF_SIZE;

typedef struct
{
    t_CACHE_WORD val;
    Bool isCacheable;
    t_CACHE_CLIENT_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
COH_DM_CACHE_LOAD_RESP#(type t_CACHE_WORD,
                        type t_CACHE_CLIENT_META)
    deriving (Eq, Bits);

//
// Cache mode can set the write policy.
// Only the write back mode is implemented in the current coherent cache.
//
// COH_DM_MODE_ALWAYS_WRITE_BACK: 
// always write back data and ownership
//
// COH_DM_MODE_CLEAN_WRITE_BACK:
// only write back ownership if the data is clean
//
typedef enum
{
    COH_DM_MODE_ALWAYS_WRITE_BACK = 0,
    COH_DM_MODE_CLEAN_WRITE_BACK = 1
}
COH_DM_CACHE_MODE
    deriving (Eq, Bits);

//
// Cache prefetch mode
//
typedef enum
{
    COH_DM_PREFETCH_DISABLE = 0,
    COH_DM_PREFETCH_ENABLE  = 1
}
COH_DM_CACHE_PREFETCH_MODE
    deriving (Eq, Bits);

//
// Cache fence type
//
typedef enum
{
    COH_DM_ALL_FENCE = 0,
    COH_DM_WRITE_FENCE = 1,
    COH_DM_READ_FENCE = 2
}
COH_DM_CACHE_FENCE_TYPE
    deriving (Eq, Bits);


//
// Coherent direct mapped cache interface.
//
// t_CACHE_CLIENT_META is metadata associated with a reference that will be
// returned along with a read response.  It is most often used by a clients
// as an index into a MAF (miss address file).
// 
interface COH_DM_CACHE#(type t_CACHE_ADDR,
                        type t_CACHE_WORD,
                        type t_CACHE_MASK,
                        type t_CACHE_CLIENT_META);

    // Read a word.  Read from backing store if not already cached.
    // *** Read responses are NOT guaranteed to be in the order of requests. ***
    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_CLIENT_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

    method ActionValue#(COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META)) readResp();
    // Read the head of the response queue
    method COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META) peekResp();
    
    //
    // Write up to an entire cache line (currently a cache line contains a single word).
    // Write only the bytes set in byteWriteMask.
    //
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_MASK byteWriteMask);
    
    // Invalidate & flush requests.  Both write dirty lines back.  Invalidate drops
    // the line from the cache.  Flush keeps the line in the cache.
    //
    // The request is propagated down to the full cache hierarchy (including other 
    // shared caches) and the caller must receive a confirmation that the operation 
    // is complete by waiting for invalOrFlushWait to fire.
    //
    // These two requests are used to maintain the memory coherence between the 
    // current cache hierarchy and other memory systems. (For example, these can be 
    // used to maintain the coherence between the FPGA cache hierarchy and the host 
    // memory.)
    //
    // To support hierarchical invalidate/flush, a locking mechanism is required. 
    // For simplicity, in the current version, these two requests are not implemented.
    // 
    method Action invalReq(t_CACHE_ADDR addr);
    method Action flushReq(t_CACHE_ADDR addr);
    method Action invalOrFlushWait();
    
`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Insert a memory fence.
    method Action fence(COH_DM_CACHE_FENCE_TYPE fenceType);
`endif

    // Return the number of read requests being processed now (0, 1, or 2)
    method Bit#(2) numReadProcessed();
    // Return the number of write requests being processed now (0, 1, or 2)
    method Bit#(2) numWriteProcessed();

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Test&set request and response
    method Action testAndSetReq(t_CACHE_ADDR addr, 
                                t_CACHE_WORD val, 
                                t_CACHE_MASK mask, 
                                t_CACHE_CLIENT_META readMeta, 
                                RL_CACHE_GLOBAL_READ_META globalReadMeta);
    method ActionValue#(COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META)) testAndSetResp();
    method COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META) peekTestAndSetResp();
`endif

    //
    // Set cache and prefetch mode.  Mostly useful for debugging.  This may not be changed
    // in the middle of a run!
    //
    method Action setCacheMode(COH_DM_CACHE_MODE mode, COH_DM_CACHE_PREFETCH_MODE en);
    
    // Debug scan state.
    method List#(Tuple2#(String, Bool)) debugScanState();
    
    interface COH_CACHE_STATS stats;

endinterface: COH_DM_CACHE

//
// Source data fill response
//
typedef struct
{
    t_CACHE_WORD              val;
    t_CACHE_META              meta;
    Bool                      ownership;
    Bool                      isExclusive;
    Bool                      isCacheable;
    Bool                      retry;
    Bool                      getsFwd;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
COH_DM_CACHE_FILL_RESP#(type t_CACHE_WORD,
                        type t_CACHE_META)
    deriving (Eq, Bits);

//
// Coherence request type 
//
typedef enum
{
    COH_CACHE_GETS  = 0,
    COH_CACHE_GETX  = 1,
    COH_CACHE_PUTX  = 2  
    //COH_CACHE_FLUSH = 3, 
    //COH_CACHE_INV   = 4
}
COH_CACHE_REQ_TYPE
    deriving (Eq, Bits);

//
// Index of the network request completion table 
//
typedef UInt#(TLog#(n_ENTRIES)) COH_DM_CACHE_NETWORK_REQ_IDX#(numeric type n_ENTRIES);

//
// Index of the miss status handling registers (MSHR)
//
typedef UInt#(TLog#(n_ENTRIES)) COH_DM_CACHE_MSHR_IDX#(numeric type n_ENTRIES);

//
// Request from network
//
typedef struct
{
    t_CACHE_ADDR           addr;
    Bool                   ownReq; // whether the request is sent by itself or not
    t_NW_REQ_IDX           reqIdx;
    COH_CACHE_REQ_TYPE     reqType;
}
COH_DM_CACHE_NETWORK_REQ#(type t_CACHE_ADDR,
                          type t_NW_REQ_IDX)
    deriving(Bits, Eq);

//
// The caller must provide an instance of the COH_DM_CACHE_SOURCE_DATA interface
// so the cache can read and write data from the next level in the hierarchy.
//
// Clients' metadata is stored in the cache's MSHR (miss status handling registers).
//
// t_CACHE_META is a metadata used to index into the MSHR, and it is sent to
// the next level in the hierarchy when misses happen. 
//
interface COH_DM_CACHE_SOURCE_DATA#(type t_CACHE_ADDR,
                                    type t_CACHE_WORD,
                                    type t_CACHE_META,
                                    type t_REQ_IDX);

    // Request for share data
    method Action getShare(t_CACHE_ADDR addr,
                           t_CACHE_META meta,
                           RL_CACHE_GLOBAL_READ_META globalReadMeta);
    // Request for data and exlusive ownership
    method Action getExclusive(t_CACHE_ADDR addr,
                               t_CACHE_META meta,
                               RL_CACHE_GLOBAL_READ_META globalReadMeta);

    method ActionValue#(COH_DM_CACHE_FILL_RESP#(t_CACHE_WORD,
                                                t_CACHE_META)) getResp();
    method COH_DM_CACHE_FILL_RESP#(t_CACHE_WORD,
                                   t_CACHE_META) peekResp();
    
    // Write back and give up ownership
    method Action putExclusive(t_CACHE_ADDR addr, Bool isCleanWB, Bool isExclusive);
  
    // Signal indicating an unactivated request is sent to the network
    // (One slot in the request buffer is released)
    method Bool unactivatedReqSent();

    // Data owner sends responses to serve other caches
    // If it is not the owner, null response is sent to clear the entry in the 
    // completion table 
    method Action sendResp(COH_DM_CACHE_MSHR_ROUTER_RESP#(t_REQ_IDX,
                                                          t_CACHE_WORD,
                                                          t_CACHE_META,
                                                          t_CACHE_ADDR) resp);
    // Return the released forwarding entry index
    // Cache will pass the information to MSHR in order to release the MSHR entry
    method ActionValue#(t_CACHE_META) getReleasedFwdEntryIdx();

    // Return the pending forwarding entry
    // Cache will pass the information to MSHR and ask MSHR to re-send the
    // forwarding response 
    method ActionValue#(t_CACHE_META) getPendingFwdEntryIdx();

    // Resend forward response value 
    method Action resendFwdRespVal(t_CACHE_META fwdIdx, t_CACHE_WORD val);

    //
    // Activated requests from the network
    // In a snoopy-based protocol, the requests may be the cache's own requests or
    // from other caches or next level in the hierarchy
    //
    method ActionValue#(COH_DM_CACHE_NETWORK_REQ#(t_CACHE_ADDR,
                                                  t_REQ_IDX)) activatedReq();
    method COH_DM_CACHE_NETWORK_REQ#(t_CACHE_ADDR,
                                     t_REQ_IDX) peekActivatedReq();

    // Pass invalidate and flush requests down the hierarchy.
    // invalOrFlushWait must block until the operation is complete.
    //
    // In the current version, these two requests are not implemented.
    //
    method Action invalReq(t_CACHE_ADDR addr);
    method Action flushReq(t_CACHE_ADDR addr);
    method Action invalOrFlushWait();
   
    // Debug scan state
    method List#(Tuple2#(String, Bool)) debugScanState();

endinterface: COH_DM_CACHE_SOURCE_DATA


// ===================================================================
//
// Internal types
//
// ===================================================================

typedef enum
{
    COH_DM_CACHE_READ,
    COH_DM_CACHE_WRITE,
    COH_DM_CACHE_FLUSH,
    COH_DM_CACHE_INVAL,
    COH_DM_CACHE_FENCE
}
COH_DM_CACHE_ACTION
    deriving (Eq, Bits);

typedef enum
{
    COH_DM_CACHE_LOCAL_REQ,
    COH_DM_CACHE_LOCAL_RETRY_REQ,
    COH_DM_CACHE_PREFETCH_REQ,
    COH_DM_CACHE_REMOTE_REQ,
    COH_DM_CACHE_MSHR_RETRY_REQ
}
COH_DM_CACHE_REQ_TYPE
    deriving (Eq, Bits);

// Cache steady states for coherent caches (MOSI)
typedef enum
{
    COH_DM_CACHE_STATE_I,     // Invalid
    COH_DM_CACHE_STATE_S,     // Shared
    COH_DM_CACHE_STATE_M,     // Modified
    COH_DM_CACHE_STATE_O,     // Owned
    COH_DM_CACHE_STATE_TRANS  // Transient: handled by MSHR
}
COH_DM_CACHE_COH_STATE
    deriving (Eq, Bits);
   
//
// Index of the write data heap index.  To save space, write data is passed
// through the cache pipelines as a pointer.  The heap size limits the number
// of writes in flight.  Writes never wait for a fill, so the heap doesn't
// have to be especially large.
//
typedef Bit#(2) COH_DM_WRITE_DATA_HEAP_IDX;


// Cache request info passed through the pipeline  
//
// Request info for local request
//
typedef struct
{
   COH_DM_CACHE_ACTION act;
   COH_DM_CACHE_READ_META#(t_CACHE_CLIENT_META) readMeta;
   RL_CACHE_GLOBAL_READ_META globalReadMeta;
 
   // Write data index
   COH_DM_WRITE_DATA_HEAP_IDX writeDataIdx;
   // Test and set request flag
   Bool isTestSet; 
}
COH_DM_CACHE_LOCAL_REQ_INFO#(type t_CACHE_CLIENT_META)
    deriving (Eq, Bits);

//
// Request info for remote request
//
typedef struct
{
   t_REQ_IDX           reqIdx;
   Bool                ownReq;
   COH_CACHE_REQ_TYPE  reqType;
}
COH_DM_CACHE_REMOTE_REQ_INFO#(type t_REQ_IDX)
    deriving (Eq, Bits);

typedef union tagged
{
    COH_DM_CACHE_LOCAL_REQ_INFO#(t_CACHE_CLIENT_META) LocalReqInfo;
    COH_DM_CACHE_REMOTE_REQ_INFO#(t_REQ_IDX) RemoteReqInfo;
}
COH_DM_CACHE_REQ_INFO#(type t_CACHE_CLIENT_META,
                       type t_REQ_IDX)
    deriving(Bits, Eq);


//
// Cache request passed through the pipeline
//
typedef struct
{
   COH_DM_CACHE_REQ_INFO#(t_CACHE_CLIENT_META, t_REQ_IDX) reqInfo;
   t_CACHE_ADDR addr;
   // Hashed address and tag, passed through the pipeline instead of recomputed.
   t_CACHE_TAG tag;
   t_CACHE_IDX idx;
}
COH_DM_CACHE_REQ#(type t_CACHE_CLIENT_META, 
                  type t_REQ_IDX, 
                  type t_CACHE_ADDR, 
                  type t_CACHE_TAG,  
                  type t_CACHE_IDX)
    deriving (Eq, Bits);


// Cache index
typedef UInt#(n_ENTRY_IDX_BITS) COH_DM_CACHE_IDX#(numeric type n_ENTRY_IDX_BITS);

// Cache entry
typedef struct
{
    t_CACHE_TAG    tag;
    t_CACHE_WORD   val;
    t_CACHE_STATE  state;
    Bool           dirty;
}
COH_DM_CACHE_ENTRY#(type t_CACHE_WORD, 
                    type t_CACHE_TAG,
                    type t_CACHE_STATE)
    deriving (Eq, Bits);

//
// Read metadata grows inside the cache because prefetches are added to the mix.
//
typedef struct
{
    Bool isLocalPrefetch;
    t_CACHE_CLIENT_META clientReadMeta;
}
COH_DM_CACHE_READ_META#(type t_CACHE_CLIENT_META)
    deriving (Eq, Bits);

// ===================================================================
//
// Cache implementation
//
// ===================================================================

//
// mkCoherentCacheDirectMapped --
//   n_ENTRIES parameter defines the number of entries in the cache.  The true
//   number of entries will be rounded up to a power of 2.
//
module [m] mkCoherentCacheDirectMapped#(COH_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, t_CACHE_WORD, t_MSHR_IDX, t_NW_REQ_IDX) sourceData,
                                        CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_CLIENT_META) prefetcher,
                                        NumTypeParam#(n_ENTRIES) dummy,
                                        Bool hashAddresses,
                                        DEBUG_FILE debugLog)
    // interface:
    (COH_DM_CACHE#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_CLIENT_META))
    provisos (IsModule#(m, m__),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Bits#(t_CACHE_MASK, t_CACHE_MASK_SZ),
              Bits#(t_CACHE_CLIENT_META, t_CACHE_CLIENT_META_SZ),
              Div#(t_CACHE_WORD_SZ, 8, t_CACHE_MASK_SZ),

              // Entry index.  Round n_ENTRIES request up to a power of 2.
              Log#(n_ENTRIES, t_ENTRY_IDX_SZ),
              // Cache index size needs to be no larger than the memory address
              NumAlias#(TMin#(t_ENTRY_IDX_SZ, t_CACHE_ADDR_SZ), t_CACHE_IDX_SZ),
              Alias#(COH_DM_CACHE_IDX#(t_CACHE_IDX_SZ), t_CACHE_IDX),

              // Tag is the address bits other than the entry index
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, t_CACHE_IDX_SZ)), t_CACHE_TAG),
              Alias#(COH_DM_CACHE_ENTRY#(t_CACHE_WORD, t_CACHE_TAG, COH_DM_CACHE_COH_STATE), t_CACHE_ENTRY),

              // MSHR index
              Alias#(UInt#(TMin#(TLog#(TDiv#(COH_DM_CACHE_MSHR_ENTRIES,2)), t_CACHE_IDX_SZ)), t_MSHR_IDX),
              // Network request index
              Alias#(COH_DM_CACHE_NETWORK_REQ_IDX#(COH_DM_CACHE_NW_COMPLETION_TABLE_ENTRIES), t_NW_REQ_IDX),

              // Coherence messages
              Alias#(COH_DM_CACHE_LOCAL_REQ_INFO#(t_CACHE_CLIENT_META), t_LOCAL_REQ_INFO),
              Alias#(COH_DM_CACHE_REQ#(t_CACHE_CLIENT_META, t_NW_REQ_IDX, t_CACHE_ADDR, t_CACHE_TAG, t_CACHE_IDX), t_CACHE_REQ),
              Alias#(COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META), t_CACHE_LOAD_RESP),
              Alias#(COH_DM_CACHE_READ_META#(t_CACHE_CLIENT_META), t_CACHE_READ_META),
              Alias#(COH_DM_CACHE_MSHR_ROUTER_RESP#(t_NW_REQ_IDX, t_CACHE_WORD, t_MSHR_IDX, t_CACHE_ADDR), t_ROUTER_RESP),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),

              // Unactivated request counter bit size
              NumAlias#(TLog#(TAdd#(COH_DM_CACHE_NW_REQ_BUF_SIZE,1)), t_REQ_COUNTER_SZ),

              // Required by the compiler:
              Bits#(t_CACHE_LOAD_RESP, t_CACHE_LOAD_RESP_SZ),
              Bits#(t_CACHE_TAG, t_CACHE_TAG_SZ));
    
    Reg#(COH_DM_CACHE_MODE) cacheMode <- mkReg(COH_DM_MODE_CLEAN_WRITE_BACK);
    Reg#(COH_DM_CACHE_PREFETCH_MODE) prefetchMode <- mkReg(COH_DM_PREFETCH_DISABLE);
    
    // Cache data and tag
    let cache_init_val = COH_DM_CACHE_ENTRY{ tag: ?,
                                             val: ?,
                                             state: COH_DM_CACHE_STATE_I,
                                             dirty: False };

    BRAM#(t_CACHE_IDX, t_CACHE_ENTRY) cache;
    if (`RL_DM_CACHE_BRAM_TYPE == 0)
    begin
        // Cache implemented as a single BRAM
        cache <- mkBRAMInitialized(cache_init_val);
    end
    else
    begin
        // Cache implemented as 4 BRAM banks with I/O buffering to allow
        // more time to reach memory.
        NumTypeParam#(4) p_banks = ?;
        cache <- mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW,
                                 mkBRAMInitializedBuffered(cache_init_val));
    end

    // Cache MSHR
    COH_DM_CACHE_MSHR#(t_CACHE_ADDR, 
                       t_CACHE_WORD, 
                       t_CACHE_MASK,
                       Bit#(t_CACHE_READ_META_SZ),
                       t_MSHR_IDX, 
                       t_NW_REQ_IDX) mshr <- mkMSHRForDirectMappedCache(debugLog);

    // Cache writeback status bits
    // True: the current cache line has an inflight PUTX in mshr
    LUTRAM#(t_CACHE_IDX, Bool) writebackStatusBits <- mkLUTRAM(False);

    // Track busy entries
    COUNTING_FILTER#(t_CACHE_IDX, 1) entryFilter <- mkCountingFilter(debugLog);

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(COH_DM_WRITE_DATA_HEAP_IDX, Tuple2#(t_CACHE_WORD,t_CACHE_MASK)) reqInfo_writeData <- mkMemoryHeapUnionLUTRAM();

    //
    // Queues to access the cache
    //
    // Incoming requests from the local client.
    FIFOF#(t_CACHE_REQ) localReqQ <- mkFIFOF();
    // Incoming activated requests from the network.
    FIFOF#(t_CACHE_REQ) remoteReqQ <- mkFIFOF();

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Incoming fence request info
    FIFOF#(Tuple2#(Bool, Bool)) localFenceInfoQ <- mkFIFOF();
`endif

    // Pipelines
    FIFO#(Tuple2#(t_CACHE_REQ, Bool)) fillReqQ <- mkFIFO();
    FIFO#(t_CACHE_LOAD_RESP) readRespQ <- mkBypassFIFO();

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    FIFO#(t_CACHE_LOAD_RESP) testSetRespQ <- mkBypassFIFO();
`endif

    // Use peekable fifo to enable accessing an arbitrary opject in the fifo
    PEEKABLE_FIFOF#(t_CACHE_REQ, 2) cacheLookupQ <- mkPeekableFIFOF();
    RWire#(t_CACHE_REQ) cacheLookupReq           <- mkRWire();
   
    //FIFO#(t_CACHE_REQ) invalQ       <- mkFIFO();
   
    // Track the number of available slots (in the request buffer in sourceData) 
    // for inflight unacitaved requests
    COUNTER#(t_REQ_COUNTER_SZ) numFreeReqBufSlots <- mkLCounter(fromInteger(valueOf(COH_DM_CACHE_NW_REQ_BUF_SIZE)));
    RWire#(Bit#(t_REQ_COUNTER_SZ)) numFreedSlots  <- mkRWire();
    PulseWire startLocalReqW                      <- mkPulseWire();
    PulseWire resendGetXFromMSHRW                 <- mkPulseWire();

    // Wires for communicating stats
    PulseWire readHitW              <- mkPulseWire();
    PulseWire readMissW             <- mkPulseWire();
    PulseWire writeHitW             <- mkPulseWire();
    PulseWire writeCacheMissW       <- mkPulseWire();
    PulseWire writePermissionMissSW <- mkPulseWire();
    PulseWire writePermissionMissOW <- mkPulseWire();
    // PulseWire selfInvalW           <- mkPulseWire();
    PulseWire selfDirtyFlushW       <- mkPulseWire();
    PulseWire selfCleanFlushW       <- mkPulseWire();
    PulseWire coherenceInvalW       <- mkPulseWire();
    PulseWire coherenceFlushW       <- mkPulseWire();
    // PulseWire forceInvalLineW      <- mkPulseWire();
    // PulseWire forceFlushLineW      <- mkPulseWire();
    PulseWire getsUncacheableW      <- mkPulseWire();
    PulseWire imUpgradeW            <- mkPulseWire();
    PulseWire ioUpgradeW            <- mkPulseWire();

    //
    // Convert address to cache index and tag
    //
    function Tuple2#(t_CACHE_TAG, t_CACHE_IDX) cacheEntryFromAddr(t_CACHE_ADDR addr);
        let a = hashAddresses ? hashBits(pack(addr)) : pack(addr);

        // The truncateNP avoids having to assert a tautology about the relative
        // sizes.  All objects are actually the same size.
        return unpack(truncateNP(a));
    endfunction

    function t_CACHE_ADDR cacheAddrFromEntry(t_CACHE_TAG tag, t_CACHE_IDX idx);
        t_CACHE_ADDR a = unpack(zeroExtendNP({tag, pack(idx)}));

        // Are addresses hashed or direct?  The original hash is reversible.
        if (hashAddresses)
            a = unpack(hashBits_inv(pack(a)));

        return a;
    endfunction

    // When addresses are hashed, the hash is computed once and stored in
    // the request.  When not hashed, the bits come directly from the address.
    // We do this, hoping that an optimizer will get rid of the .tag
    // and .idx fields in the t_CACHE_REQ stored in the FIFOs when they
    // are unhashed duplicates of the address.
    function t_CACHE_IDX cacheIdx(t_CACHE_REQ r);
        return hashAddresses ? r.idx : tpl_2(cacheEntryFromAddr(r.addr));
    endfunction

    function t_CACHE_TAG cacheTag(t_CACHE_REQ r);
        return hashAddresses ? r.tag : tpl_1(cacheEntryFromAddr(r.addr));
    endfunction

    //
    // Collecting activated requests from network (sourceData)
    //
    (*fire_when_enabled*)
    rule collectRemoteReq (True);
        let remote_req <- sourceData.activatedReq();
        t_CACHE_REQ r = ?;
        r.addr = remote_req.addr;
        r.tag  = ?;
        r.idx  = ?;
        r.reqInfo = tagged RemoteReqInfo COH_DM_CACHE_REMOTE_REQ_INFO { reqIdx: remote_req.reqIdx, 
                                                                        ownReq: remote_req.ownReq,
                                                                        reqType: remote_req.reqType };

        debugLog.record($format("    Cache: remote request (%s): reqType=0x%x, addr=0x%x, reqIdx=0x%x", 
                                remote_req.ownReq? "own" : "other", remote_req.reqType, 
                                remote_req.addr, remote_req.reqIdx));
        remoteReqQ.enq(r);
    endrule

    //
    // Managing the number of freed slots in the unactiaved request buffer (in sourceData)
    //
    (*fire_when_enabled*)
    rule updFreedReqSlot (True);
        let free_num = 0;
        if (numFreedSlots.wget() matches tagged Valid .n)
        begin
            free_num = free_num + n;
        end
        if (sourceData.unactivatedReqSent())
        begin
            free_num = free_num + 1;
        end
        if (free_num != 0)
        begin
            numFreeReqBufSlots.upBy(free_num);
            debugLog.record($format("    Cache: updFreedReqSlot: number of freed slots=%x, numFreeReqBufSlots=%x", free_num, numFreeReqBufSlots.value()));
        end
    endrule

    //
    // Managing the number of reserved slots in the unactiaved request buffer (in sourceData)
    //
    (*fire_when_enabled*)
    rule updReservedReqSlot (True);
        let num = 0;
        if (startLocalReqW)
        begin
            num = num + 2;
        end
        if (resendGetXFromMSHRW)
        begin
            num = num + 1;
        end
        if (num != 0)
        begin
            numFreeReqBufSlots.downBy(num);
            debugLog.record($format("    Cache: updReservedReqSlot: number of reserved slots=%x, numFreeReqBufSlots=%x", num, numFreeReqBufSlots.value()));
        end
    endrule


    // ===========================================================================
    //
    // All incoming requests start here.
    //
    //     There are five kinds of requests trying to access the cache. 
    //     (1) new incoming local request (from client)
    //     (2) local retry request
    //     (3) local prefetch request (if cache prefetcher is enabled)
    //     (4) remote request (from network)
    //     (5) MSHR retry request
    //
    //     (1), (2), and (3) belong to local reqeusts, which are from the local 
    //     client or created locally. (4) is a remote request. (5) is a local 
    //     request that has already accessed the cache but is not be able to 
    //     processed because the MSHR entry is not avaiable. The type of request 
    //     need to be handle differently than other local requests. To avoid 
    //     confusion, when mentioning local requests, (5) is not included. 
    //
    //     At most one local request per line may be active.  When a new incoming
    //     local request arrives for an active line, the request is shunted to 
    //     the localRetryQ in order to allow other requests to flow past it.
    //     
    //     When a local prefetch request tries to access an active line, it is 
    //     dropped becuase it is likely that the prefetch request is untimely.
    // 
    //     A remote request accesses the MSHR when the cache line is active, and
    //     it accesses the cache when the line is inactive. 
    //     Because the line filter can output false positive result, the remote 
    //     request needs to access the cache no matter whether the cache line 
    //     is reported as active or not. If the cache line is reported as active, 
    //     the request needs to access both the MSHR and cache; if the cache line 
    //     is reported as negative, the request only needs to access the cache.
    //     
    //     Because the line filter is expensive, all requests share a single 
    //     filter. A fair round robin arbiter is used to select which request to 
    //     process.
    //
    // ===========================================================================

    //
    // A cache miss (caused by local requests) requires to allocate an entry in 
    // MSHR. If the MSHR entry is not available, the request needs to be stalled 
    // and it needs to re-access the cache once the MSHR entry is available. 
    // 
    // To avoid dependency issues, the requests that enter the cacheLookupQ need 
    // to be served before other local requests that are not yet picked to enter 
    // the cacheLookupQ.
    //
    // To achieve this, we keep a small mshrRetryQ to buffer the requests that 
    // have already accessed the cache but cannot find a free MSHR entry and
    // stall all other local requests until the mshrRetryQ is empty.
    //
    FIFOF#(t_CACHE_REQ) mshrRetryQ  <- mkFIFOF();
    // To reduce the number of retry times, process mshrRetryQ only when there
    // is a MSHR entry released
    Reg#(Bool) mshrReleased <- mkReg(False);
    PulseWire  mshrRetryW   <- mkPulseWire();
    //
    // A fair round robin arbiter with changing priorities
    //
    LOCAL_ARBITER#(5) processReqArb <- mkLocalArbiter();
    PulseWire updateReqArbW         <- mkPulseWire();
    Wire#(LOCAL_ARBITER_OPAQUE#(5)) arbNewState <- mkWire();
    
    //
    // Local retry buffer and its filter preserve read/write, write/write order
    //
    FIFOF#(t_CACHE_REQ) localRetryQ <- mkSizedFIFOF(8);
    LUTRAM#(Bit#(5), Bit#(2)) localRetryReqFilter <- mkLUTRAM(0);

    Wire#(Tuple3#(COH_DM_CACHE_REQ_TYPE, t_CACHE_REQ, Bool)) pickReq <- mkWire();
    Wire#(Tuple4#(COH_DM_CACHE_REQ_TYPE, 
                  t_CACHE_REQ, 
                  Maybe#(CF_OPAQUE#(t_CACHE_IDX, 1)),
                  Bool)) curReq <- mkWire();


`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    
    PulseWire readPendingW <- mkPulseWire();
    PulseWire writePendingW <- mkPulseWire();

    // 
    // Check local pending requests
    //
    rule checkPendingReq (True);
        // Check if there is a pending local write request
        let has_local_write = mshr.getExclusivePending();
        if (cacheLookupQ.peekElem(0) matches tagged Valid .req0 &&& req0.reqInfo matches tagged LocalReqInfo .f0 &&& f0.act == COH_DM_CACHE_WRITE)
        begin
            has_local_write = True;
        end
        if (cacheLookupQ.peekElem(1) matches tagged Valid .req1 &&& req1.reqInfo matches tagged LocalReqInfo .f1 &&& f1.act == COH_DM_CACHE_WRITE)
        begin
            has_local_write = True;
        end
        // Check if there is a pending local read request
        let has_local_read = mshr.getSharePending();
        if (cacheLookupQ.peekElem(0) matches tagged Valid .req0 &&& req0.reqInfo matches tagged LocalReqInfo .f0 &&& f0.act == COH_DM_CACHE_READ)
        begin
            has_local_read = True;
        end
        if (cacheLookupQ.peekElem(1) matches tagged Valid .req1 &&& req1.reqInfo matches tagged LocalReqInfo .f1 &&& f1.act == COH_DM_CACHE_READ)
        begin
            has_local_read = True;
        end
        // Raise signals to inform rule pickReqQueue0
        if (has_local_write)
        begin
            writePendingW.send();
        end
        if (has_local_read)
        begin
            readPendingW.send();
        end
    endrule

`endif

    //
    // updateReqArb --
    //     Update the state of the round robin arbiter (processReqArb) if the 
    //     picked request is processed (updateReqArbW signal is raised)
    // 
    rule updateReqArb (updateReqArbW);
        processReqArb.update(arbNewState);
    endrule

    //
    // pickReqQueue0 --
    //     Decide whether to consider the MSHR retry request, remote request, 
    //     new local request, or local retry request this cycle.   
    //     
    //     If the cache prefecher is enabled, choose among MSHR retry request, 
    //     remote request, local request, local retry request, and prefetch 
    //     request queues.
    // 
    //     Never pick from the three local request queues (localReqQ, localReqQ, 
    //     prefetchQ) if mshrRetryQ is not empty or if there are no enough
    //     slots in the unacitaved request buffer (in sourceData). 
    //
    //     Pick from mshrRetryQ only if there is an MSHR entry released. 
    //
    rule pickReqQueue0 (True);

        // Note which request queue has request available to process
        LOCAL_ARBITER_CLIENT_MASK#(5) reqs = newVector();
        
        let req_buf_free = (numFreeReqBufSlots.value() > 2);
        let is_fence_req = False;
        
`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
        //
        // Fence request process condition:
        // All retry queues are empty and cache lookup pipeline (cacheLookupQ) 
        // does not have local requests
        //
        // Check if the first local request is a fence request
        let has_local = False;
        if (localReqQ.notEmpty)
        begin
            let first_local_req = localReqQ.first();
            if (first_local_req.reqInfo matches tagged LocalReqInfo .f &&& f.act == COH_DM_CACHE_FENCE)
            begin
                is_fence_req = True;
                match {.check_read, .check_write} = localFenceInfoQ.first();
                has_local = (check_read && readPendingW) || (check_write && writePendingW);
            end
        end
        reqs[pack(COH_DM_CACHE_LOCAL_REQ)]       = localReqQ.notEmpty && !mshrRetryQ.notEmpty &&
                                                   ((is_fence_req && !localRetryQ.notEmpty && !has_local) || 
                                                   (!is_fence_req && req_buf_free));
`else
        reqs[pack(COH_DM_CACHE_LOCAL_REQ)]       = localReqQ.notEmpty && !mshrRetryQ.notEmpty && req_buf_free;
`endif

        reqs[pack(COH_DM_CACHE_LOCAL_RETRY_REQ)] = localRetryQ.notEmpty && !mshrRetryQ.notEmpty && req_buf_free;
        reqs[pack(COH_DM_CACHE_PREFETCH_REQ)]    = prefetchMode == COH_DM_PREFETCH_ENABLE && 
                                                   prefetcher.hasReq() && !mshrRetryQ.notEmpty && req_buf_free;
        reqs[pack(COH_DM_CACHE_REMOTE_REQ)]      = remoteReqQ.notEmpty && !mshr.dataRespQAlmostFull();
        reqs[pack(COH_DM_CACHE_MSHR_RETRY_REQ)]  = mshrRetryQ.notEmpty && mshrReleased;

        match {.winner_idx, .state_upd} <- processReqArb.arbitrateNoUpd(reqs, False); 
        
        // There is a request available and is picked to process
        if (winner_idx matches tagged Valid .req_idx)
        begin        
            COH_DM_CACHE_REQ_TYPE req_type = unpack(pack(req_idx)); 
            // debugLog.record($format("    Cache: pick req: type=%d", req_idx));
            
            t_CACHE_REQ r = ?;
            case (req_type)
                COH_DM_CACHE_LOCAL_REQ: r = localReqQ.first();
                COH_DM_CACHE_LOCAL_RETRY_REQ: r = localRetryQ.first();
                COH_DM_CACHE_PREFETCH_REQ: 
                begin
                    let pref_req  = prefetcher.peekReq();
                    t_LOCAL_REQ_INFO pref_info = ?;
                    pref_info.act = COH_DM_CACHE_READ;
                    pref_info.readMeta = COH_DM_CACHE_READ_META { isLocalPrefetch: True,
                                                                  clientReadMeta: pref_req.readMeta };
                    pref_info.globalReadMeta = defaultValue();
                    pref_info.globalReadMeta.isPrefetch = True;
                    r.addr    = pref_req.addr;
                    r.reqInfo = tagged LocalReqInfo pref_info;
                end
                COH_DM_CACHE_REMOTE_REQ: r = remoteReqQ.first();
                COH_DM_CACHE_MSHR_RETRY_REQ: r = mshrRetryQ.first();
            endcase
            match {.tag, .idx} = cacheEntryFromAddr(r.addr);
            r.tag = tag;
            r.idx = idx;
            pickReq <= tuple3(req_type, r, (req_type == COH_DM_CACHE_LOCAL_REQ && is_fence_req));
            arbNewState <= state_upd;
        end
    endrule

    //
    // pickReqQueue1 --
    //     Second half of picking a request.  Apply the entry filter to the
    //     chosen request.
    //
    //     Written as a separate rule connected by a wire so that only one
    //     request is tested by the expensive entryFilter.
    // 
    (* fire_when_enabled *)
    rule pickReqQueue1 (True);
        match {.req_type, .r, .is_local_fence} = pickReq;
        //
        // In order to preserve read/write and write/write order of local 
        // requests, a local request must either come from the local retry 
        // buffer or be a new local request (or a prefetch request) 
        // referencing a line not already in the local retry buffer.
        //
        // The array localRetryReqFilter tracks lines active in the local
        // retry queue.
        //
        // Remote requests do not need to check the local retry buffer
        //
        if ((req_type == COH_DM_CACHE_LOCAL_RETRY_REQ) ||
            (req_type == COH_DM_CACHE_REMOTE_REQ) ||
            (req_type == COH_DM_CACHE_MSHR_RETRY_REQ) ||
            (localRetryReqFilter.sub(resize(cacheIdx(r))) == 0))
        begin
            curReq <= tuple4(req_type, r, entryFilter.test(cacheIdx(r)), is_local_fence); 
        end
        else
        begin
            curReq <= tuple4(req_type, r, tagged Invalid, is_local_fence);
        end
    endrule

    //
    // startRemoteReq --
    //     Start remote request no matter whether the line is busy or not
    //
    (* fire_when_enabled *)
    rule startRemoteReq (tpl_2(curReq).reqInfo matches tagged RemoteReqInfo .f);
        match {.req_type, .r, .cf_opaque} = curReq;
        let idx = cacheIdx(r);
        debugLog.record($format("    Cache: startRemoteReq: addr=0x%x, entry=0x%x", r.addr, idx));
        cache.readReq(idx);
        cacheLookupQ.enq(r);
        cacheLookupReq.wset(r);
        remoteReqQ.deq();
        // update arbiter processReqArb
        updateReqArbW.send();
    endrule
    
    //
    // startMSHRRetryReq --
    //     Start MSHRRetry request no matter whether the line is busy or not.
    // Actually, the cache line is always busy, because the filter is already 
    // marked in the first run. 
    //
    (* mutually_exclusive = "startRemoteReq, startMSHRRetryReq" *)
    (* fire_when_enabled *)
    rule startMSHRRetryReq (tpl_2(curReq).reqInfo matches tagged LocalReqInfo .f &&& 
                            tpl_1(curReq) == COH_DM_CACHE_MSHR_RETRY_REQ);
        match {.req_type, .r, .cf_opaque, .is_fence} = curReq;
        let idx = cacheIdx(r);
        debugLog.record($format("    Cache: startMSHRRetryReq: addr=0x%x, entry=0x%x", r.addr, idx));
        cache.readReq(idx);
        cacheLookupQ.enq(r);
        cacheLookupReq.wset(r);
        mshrRetryQ.deq();
        // update arbiter processReqArb
        updateReqArbW.send();
    endrule

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    //
    // startFenceReq --
    //     All local writes are cleared. Dequeue the fence request from local 
    // request queue.
    //
    (* mutually_exclusive = "startFenceReq, startRemoteReq, startMSHRRetryReq" *)
    (* fire_when_enabled *)
    rule startFenceReq (tpl_4(curReq));
        debugLog.record($format("    Cache: done with fence request..."));
        localReqQ.deq();
        localFenceInfoQ.deq();
        // update arbiter processReqArb
        updateReqArbW.send();
    endrule
`endif

    //
    // startLocalReq --
    //     Start the current local request if the line is not busy
    //
    (* fire_when_enabled *)
    rule startLocalReq (tpl_2(curReq).reqInfo matches tagged LocalReqInfo .f  &&& 
                        (tpl_1(curReq) != COH_DM_CACHE_MSHR_RETRY_REQ) &&& 
                        tpl_3(curReq) matches tagged Valid .filter_state &&& !tpl_4(curReq));
        
        match {.req_type, .r, .cf_opaque, .is_fence} = curReq;

        entryFilter.set(filter_state);
        let idx = cacheIdx(r);

        debugLog.record($format("    Cache: %s: addr=0x%x, entry=0x%x",
                                req_type == COH_DM_CACHE_LOCAL_REQ ? "startLocalReq" : 
                                ( req_type == COH_DM_CACHE_LOCAL_RETRY_REQ ? "startLocalRetryReq" :
                                  "startPrefetchReq" ), r.addr, idx));

        // Read the entry either to return the value (READ) or to see whether
        // the entry is dirty and flush it.
        cache.readReq(idx);
        cacheLookupQ.enq(r);
        cacheLookupReq.wset(r);
        startLocalReqW.send();
        debugLog.record($format("    Cache: start local req: numFreeReqBufSlots=%x", numFreeReqBufSlots.value()));

        if (req_type == COH_DM_CACHE_LOCAL_REQ)
        begin
            localReqQ.deq();
        end
        else if (req_type == COH_DM_CACHE_LOCAL_RETRY_REQ)
        begin
            localRetryQ.deq();
            localRetryReqFilter.upd(resize(idx), localRetryReqFilter.sub(resize(idx)) - 1);
        end
        else
        begin
            let pf_req <- prefetcher.getReq();
        end
        
        // update arbiter processReqArb
        updateReqArbW.send();
    endrule

    //
    // blockedLocalReq --
    //     update arbiter processReqArb when local requests are blocked by busy 
    //     cache lines
    //
    (* fire_when_enabled *)
    rule blockedLocalReq (tpl_2(curReq).reqInfo matches tagged LocalReqInfo .f &&& 
                          (tpl_1(curReq) != COH_DM_CACHE_MSHR_RETRY_REQ) &&& 
                          ! isValid(tpl_3(curReq)) &&& !tpl_4(curReq));
        updateReqArbW.send();
    endrule
    
    //
    // shuntNewReq --
    //     If the current local request is new (not a shunted request) and the
    //     line is busy, shunt the new request to a retry queue in order to
    //     attempt to process a later request that may be ready to go.
    //
    //     This rule will not fire if startLocalReq fires.
    //
    (* fire_when_enabled *)
    rule shuntNewReq (tpl_1(curReq) == COH_DM_CACHE_LOCAL_REQ &&
                      (localRetryReqFilter.sub(resize(cacheIdx(tpl_2(curReq)))) != maxBound) &&
                      ! isValid(tpl_3(curReq)) && !tpl_4(curReq));
        match {.req_type, .r, .cf_opaque, .is_fence} = curReq;
        let idx = cacheIdx(r);

        debugLog.record($format("    Cache: shunt busy line req: addr=0x%x, entry=0x%x", r.addr, idx));

        localRetryQ.enq(r);
        localReqQ.deq();

        // Note line present in localRetryQ
        localRetryReqFilter.upd(resize(idx), localRetryReqFilter.sub(resize(idx)) + 1);
        
        if (prefetchMode == COH_DM_PREFETCH_ENABLE)
        begin
            prefetcher.shuntNewCacheReq(idx, r.addr);
        end
    endrule
    
    //
    // For collecting prefetch stats
    //
    (* fire_when_enabled *)
    rule dropPrefetchReqByBusy ( tpl_1(curReq) == COH_DM_CACHE_PREFETCH_REQ && 
                                 !isValid(tpl_3(curReq)) );
        let pf_req <- prefetcher.getReq();
        debugLog.record($format("    Cache: prefetch req dropped by busy: addr=0x%x", tpl_2(curReq).addr));
        prefetcher.prefetchDroppedByBusy(tpl_2(curReq).addr);
    endrule

    
    // ========================================================================
    //
    // Cache access paths
    //
    // ========================================================================

    //
    // To avoid deadlocks, remote requests need to access the cache no matter 
    // whether the cache line is active or not. As a result, requests in the 
    // cache lookup pipeline may have the same target cache line and may cause 
    // read-after-write hazards. To deal with read-after-write hazards, we add
    // two bypass paths to allow cache reads to get the latest update.
    //
    // The reason why we need two bypass paths is because there are two paths
    // updating the cache: (1) fill responses from MSHR (2) normal cache 
    // operations (read misses/cache writes)
    //
    // Each time when MSHR writes back to cache, it checks the cache's two 
    // inflight read requests (cacheReadInflight0, cacheReadInflight1) and updates 
    // the bypass entries if necessary (bypassCacheEntry0, bypassCacheEntry1).
    //
    Reg#(t_CACHE_ENTRY) bypassCacheEntry0 <- mkReg(COH_DM_CACHE_ENTRY{ tag: ?,
                                                                       val: ?,
                                                                       state: COH_DM_CACHE_STATE_I,
                                                                       dirty: False });
    Reg#(t_CACHE_ENTRY) bypassCacheEntry1 <- mkReg(COH_DM_CACHE_ENTRY{ tag: ?,
                                                                       val: ?,
                                                                       state: COH_DM_CACHE_STATE_I,
                                                                       dirty: False });
    Reg#(Bool) needBypass0 <- mkReg(False);
    Reg#(Bool) needBypass1 <- mkReg(False);

    // 
    // updateBypassEntry -- 
    // 
    // The two bypass entries are shifted each time when a cache read response
    // is dequeued (which happens during each cache operation).
    //
    // If the current cache operation's update needs to be bypassed, the new
    // updates is stored into bypassCacheEntry0; otherwise, the value of 
    // bypassCacheEntry1 is shifted to bypassCacheEntry0.
    // 
    function Action updateBypassEntry(Bool needBypass, t_CACHE_ENTRY bypassEntry);
        return 
            action
                bypassCacheEntry0 <= (needBypass)? bypassEntry : bypassCacheEntry1;
                needBypass0 <= needBypass || needBypass1;
                needBypass1 <= False;
            endaction;
    endfunction

    //
    // Return bypassCacheEntry0 if needBypass0 is true; otherwise, return 
    // cache.readRsp()
    //
    function ActionValue#(t_CACHE_ENTRY) cacheReadRespBypass();
        actionvalue
            let resp <- cache.readRsp();
            if (needBypass0)
            begin
                resp = bypassCacheEntry0;
                debugLog.record($format("    Cache: read from bypass entry..."));
            end
            return resp;
        endactionvalue
    endfunction
   
    //
    // Apply write mask and return the updated data
    //
    function t_CACHE_WORD applyWriteMask(t_CACHE_WORD oldVal, t_CACHE_WORD wData, t_CACHE_MASK mask);
        Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_out = newVector();
        Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_old = unpack(resize(pack(oldVal)));
        Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_new = unpack(resize(pack(wData)));
        Vector#(t_CACHE_MASK_SZ, Bool) mask_v       = unpack(pack(mask));
        for (Integer b = 0; b < valueOf(t_CACHE_MASK_SZ); b = b + 1)
        begin
            bytes_out[b] = mask_v[b] ? bytes_new[b] : bytes_old[b];
        end
        return unpack(resize(pack(bytes_out))); 
    endfunction
    
    // ========================================================================
    //
    // Remote request path
    //
    // ========================================================================
    
    FIFOF#(t_ROUTER_RESP) respToRouterQ <- mkFIFOF();
    
    (* conservative_implicit_conditions *)
    rule remoteCacheLookup (cacheLookupQ.first().reqInfo matches tagged RemoteReqInfo .f);
        let r = cacheLookupQ.first();
        cacheLookupQ.deq();

        Bool resp_sent   = False;
        Bool need_bypass = False;
        
        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cacheReadRespBypass();
        let upd_entry = cur_entry;

        if (cur_entry.state != COH_DM_CACHE_STATE_TRANS && cur_entry.tag == tag) // Hit!
        begin
            debugLog.record($format("    Cache: remoteLookup: HIT addr=0x%x, entry=0x%x, state=%d, val=0x%x", r.addr, idx, cur_entry.state, cur_entry.val));
            
            if ((f.reqType == COH_CACHE_GETS) && ((cur_entry.state == COH_DM_CACHE_STATE_M) || (cur_entry.state == COH_DM_CACHE_STATE_O)))
            begin
                upd_entry.state = COH_DM_CACHE_STATE_O;
                coherenceFlushW.send();
                respToRouterQ.enq(tagged MSHR_REMOTE_RESP COH_DM_CACHE_MSHR_REMOTE_RESP{ reqIdx: f.reqIdx, 
                                                                                         val: cur_entry.val,
                                                                                         retry: False,
                                                                                         isCacheable: True,
                                                                                         isExclusive: False });
                resp_sent = True;
                debugLog.record($format("    Cache: remoteLookup: REMOTE RESP: addr=0x%x, reqIdx=0x%x, val=0x%x, retry=False", 
                                r.addr, f.reqIdx, cur_entry.val));
            end
            else if (f.reqType == COH_CACHE_GETX) 
            begin
                upd_entry.state = COH_DM_CACHE_STATE_I;
                if (cur_entry.state != COH_DM_CACHE_STATE_I)
                begin
                    coherenceInvalW.send();
                end
                if ((cur_entry.state == COH_DM_CACHE_STATE_M) || (cur_entry.state == COH_DM_CACHE_STATE_O))
                begin
                    respToRouterQ.enq(tagged MSHR_REMOTE_RESP COH_DM_CACHE_MSHR_REMOTE_RESP{ reqIdx: f.reqIdx, 
                                                                                             val: cur_entry.val,
                                                                                             retry: False,
                                                                                             isCacheable: True,
                                                                                             isExclusive: False });
                    resp_sent = True;
                    debugLog.record($format("    Cache: remoteLookup: REMOTE RESP: addr=0x%x, reqIdx=0x%x, val=0x%x, retry=False", 
                                    r.addr, f.reqIdx, cur_entry.val));
                end
            end
            if (cacheLookupQ.peekElem(1) matches tagged Valid .req1 &&& req1.idx == idx)
            begin
                need_bypass = True;
            end
            else if (cacheLookupReq.wget() matches tagged Valid .req0 &&& req0.idx == idx)
            begin
                need_bypass = True;
            end
            cache.write(idx, upd_entry);
            debugLog.record($format("    Cache: remoteLookup: update cache state=%d", upd_entry.state));
        end
        else if (cur_entry.state == COH_DM_CACHE_STATE_TRANS || writebackStatusBits.sub(idx))
        begin
            // if the cache state is in transient state or mshr is still waiting 
            // for the PUTX completion, it is MSHR's responsibility to send responses
            debugLog.record($format("    Cache: remoteLookup: TRANS state: addr=0x%x, entry=0x%x", r.addr, idx));
            mshr.activatedReq(truncateNP(idx), r.addr, f.ownReq, f.reqIdx, f.reqType);
            resp_sent = True;
        end
            
        // Send null response to remove the entry from the completion table
        if (!resp_sent)
        begin
            let gets_fwd = (cur_entry.state == COH_DM_CACHE_STATE_S) && (cur_entry.tag == tag);
            let null_resp = COH_DM_CACHE_MSHR_NULL_RESP { reqIdx: f.reqIdx, 
                                                          fwdEntryIdx: gets_fwd? tagged Valid truncateNP(idx) : tagged Invalid,
                                                          reqAddr: r.addr };
            respToRouterQ.enq(tagged MSHR_NULL_RESP null_resp);
            debugLog.record($format("    Cache: remoteLookup: NULL RESP: addr=0x%x, reqIdx=0x%x", 
                            r.addr, f.reqIdx));
        end

        updateBypassEntry(need_bypass, upd_entry);
    
    endrule

    // ========================================================================
    //
    // Read path
    //
    // ========================================================================
    
    (* conservative_implicit_conditions *)
    rule localLookupRead (cacheLookupQ.first().reqInfo matches tagged LocalReqInfo .f &&& f.act == COH_DM_CACHE_READ);
        let r = cacheLookupQ.first();
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cacheReadRespBypass(); 
        let upd_entry = ?;

        Bool need_fill       = True;
        Bool need_bypass     = False;
        Bool need_writeback  = False;
        t_MSHR_IDX mshr_idx  = truncateNP(idx);

        if (cur_entry.state != COH_DM_CACHE_STATE_I)
        begin
            if (cur_entry.tag == tag) // Hit!
            begin
                debugLog.record($format("    Cache: localLookupRead: HIT addr=0x%x, entry=0x%x, state=%d, val=0x%x", r.addr, idx, cur_entry.state, cur_entry.val));
                // Ignore prefetch hit response and prefetch hit status
                if (! f.readMeta.isLocalPrefetch)
                begin
                    readHitW.send();
                    if (prefetchMode == COH_DM_PREFETCH_ENABLE)
                    begin
                        prefetcher.readHit(idx, r.addr);
                    end
                    t_CACHE_LOAD_RESP resp;
                    resp.val = cur_entry.val;
                    resp.isCacheable = True;
                    resp.readMeta = f.readMeta.clientReadMeta;
                    resp.globalReadMeta = f.globalReadMeta;
                    readRespQ.enq(resp);
                end
                else
                begin
                    prefetcher.prefetchDroppedByHit();
                end
                entryFilter.remove(idx);
                need_fill = False;
                numFreedSlots.wset(2);
            end
            else if ((cur_entry.state == COH_DM_CACHE_STATE_O) || (cur_entry.state == COH_DM_CACHE_STATE_M))
            begin
                // Miss.  Need to flush old data
                // Check if MSHR has available spots
                if (mshr.entryAvailable(mshr_idx))
                begin
                    let old_addr = cacheAddrFromEntry(cur_entry.tag, idx);
                    debugLog.record($format("    Cache: localLookupRead: FLUSH addr=0x%x, entry=0x%x, val=0x%x, dirty=%s", 
                                    old_addr, idx, cur_entry.val, cur_entry.dirty? "True" : "False"));
                    // Write back old data
                    let clean_write_back = (cacheMode == COH_DM_MODE_CLEAN_WRITE_BACK) && !cur_entry.dirty; 
                    let is_exclusive = (cur_entry.state == COH_DM_CACHE_STATE_M);
                    sourceData.putExclusive(old_addr, clean_write_back, is_exclusive);
                    mshr.putExclusive(mshr_idx, old_addr, cur_entry.val, False, clean_write_back, is_exclusive);
                    need_writeback = True;
                    writebackStatusBits.upd(idx, True);
                    if (clean_write_back)
                    begin
                        selfCleanFlushW.send();
                    end
                    else
                    begin
                        selfDirtyFlushW.send();
                    end
                end
            end
        end

        // Request fill of new value
        if (need_fill)
        begin
            if (mshr.entryAvailable(mshr_idx))
            begin
                mshr.getShare(mshr_idx, r.addr, pack(f.readMeta));
                fillReqQ.enq(tuple2(r, True));
                if (prefetchMode == COH_DM_PREFETCH_ENABLE)
                begin
                    prefetcher.readMiss(idx, r.addr,
                                        f.readMeta.isLocalPrefetch,
                                        f.readMeta.clientReadMeta);
                end
                upd_entry = COH_DM_CACHE_ENTRY { tag: tag,
                                                 val: ?,
                                                 state: COH_DM_CACHE_STATE_TRANS,
                                                 dirty: False };
                if (cacheLookupQ.peekElem(1) matches tagged Valid .req1 &&& req1.idx == idx)
                begin
                    need_bypass = True;
                end
                else if (cacheLookupReq.wget() matches tagged Valid .req0 &&& req0.idx == idx)
                begin
                    need_bypass = True;
                end
                debugLog.record($format("    Cache: localLookupRead: MISS addr=0x%x, entry=0x%x, meta=0x%x", r.addr, idx, f.readMeta));
                cache.write(idx, upd_entry);
                if (!need_writeback)
                begin
                    numFreedSlots.wset(1);
                end
            end
            else // Request goes to mshrRetryQ and re-accesses the cache later
            begin
                mshrRetryQ.enq(r);
                mshrRetryW.send();
                debugLog.record($format("    Cache: localLookupRead: Retry addr=0x%x, entry=0x%x, MSHR entry (idx=0x%x) not available", r.addr, idx, mshr_idx));
            end
        end
        
        updateBypassEntry(need_bypass, upd_entry);
        
    endrule

    // ====================================================================
    //
    // Write path
    //
    // ====================================================================

    (* mutually_exclusive = "remoteCacheLookup, localLookupRead, doLocalWrite" *)
    (* conservative_implicit_conditions *)
    rule doLocalWrite (cacheLookupQ.first().reqInfo matches tagged LocalReqInfo .f &&& f.act == COH_DM_CACHE_WRITE);
        let r = cacheLookupQ.first();
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cacheReadRespBypass();
        let upd_entry = ?;
       
        Bool need_retry      = False;
        Bool need_bypass     = False;
        Bool need_writeback  = False;
        t_MSHR_IDX mshr_idx  = truncateNP(idx);

        // New data to write
        match {.w_data, .w_mask} = reqInfo_writeData.sub(f.writeDataIdx);

        if (cur_entry.tag != tag && ((cur_entry.state == COH_DM_CACHE_STATE_M) || (cur_entry.state == COH_DM_CACHE_STATE_O)))
        begin
            // Check if MSHR has available spots
            if (mshr.entryAvailable(mshr_idx))
            begin
                // Dirty data must be flushed
                let old_addr = cacheAddrFromEntry(cur_entry.tag, idx);
                debugLog.record($format("    Cache: doLocalWrite: FLUSH addr=0x%x, entry=0x%x, val=0x%x, dirty=%s", 
                                old_addr, idx, cur_entry.val, cur_entry.dirty? "True" : "False"));
                let clean_write_back = (cacheMode == COH_DM_MODE_CLEAN_WRITE_BACK) && !cur_entry.dirty;
                let is_exclusive = (cur_entry.state == COH_DM_CACHE_STATE_M);
                sourceData.putExclusive(old_addr, clean_write_back, is_exclusive);
                mshr.putExclusive(mshr_idx, old_addr, cur_entry.val, False, clean_write_back, is_exclusive);
                need_writeback = True;
                writebackStatusBits.upd(idx, True);
                if (clean_write_back)
                begin
                    selfCleanFlushW.send();
                end
                else
                begin
                    selfDirtyFlushW.send();
                end
            end
        end

        // Now do the write.
        if (cur_entry.tag == tag && cur_entry.state == COH_DM_CACHE_STATE_M) //Write Hit!
        begin
            debugLog.record($format("    Cache: doLocalWrite: WRITE addr=0x%x, entry=0x%x, val=0x%x", r.addr, idx, w_data));
            writeHitW.send();
            // apply write mask
            let new_data = applyWriteMask(cur_entry.val, w_data, w_mask);
            upd_entry = COH_DM_CACHE_ENTRY { tag: tag, val: new_data, state: COH_DM_CACHE_STATE_M, dirty: True };
            entryFilter.remove(idx);
            reqInfo_writeData.free(f.writeDataIdx);
            numFreedSlots.wset(2);
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
            if (f.isTestSet)
            begin
                t_CACHE_LOAD_RESP resp;
                resp.val = cur_entry.val;
                resp.isCacheable = True;
                resp.readMeta = f.readMeta.clientReadMeta;
                resp.globalReadMeta = f.globalReadMeta;
                testSetRespQ.enq(resp);
            end
`endif
        end
        else // Request fill for write permission (and data)
        begin
            if (mshr.entryAvailable(mshr_idx))
            begin
                let old_state = (cur_entry.tag == tag)? cur_entry.state : COH_DM_CACHE_STATE_I;
                fillReqQ.enq(tuple2(r, False));
                mshr.getExclusive(mshr_idx, r.addr, cur_entry.val, w_data, w_mask, old_state, pack(f.readMeta), f.isTestSet);
                reqInfo_writeData.free(f.writeDataIdx);
                upd_entry = COH_DM_CACHE_ENTRY { tag: tag,
                                                 val: cur_entry.val,
                                                 state: COH_DM_CACHE_STATE_TRANS,
                                                 dirty: False };
                if (cur_entry.tag == tag && cur_entry.state != COH_DM_CACHE_STATE_I)
                begin
                    debugLog.record($format("    Cache: doLocalWrite: Permission MISS addr=0x%x, entry=0x%x, state=0x%x", r.addr, idx, cur_entry.state));
                    if (cur_entry.state == COH_DM_CACHE_STATE_O)
                    begin
                        writePermissionMissOW.send();
                    end
                    else
                    begin
                        writePermissionMissSW.send();
                    end
                end
                else
                begin
                    debugLog.record($format("    Cache: doLocalWrite: Cacheline MISS addr=0x%x, entry=0x%x", r.addr, idx));
                    writeCacheMissW.send();
                end
                if (!need_writeback)
                begin
                    numFreedSlots.wset(1);
                end
            end
            else // need to retry and re-access the cache
            begin
                need_retry = True;
                mshrRetryQ.enq(r);
                mshrRetryW.send(); 
                debugLog.record($format("    Cache: doLocalWrite: Retry addr=0x%x, entry=0x%x, MSHR entry (idx=0x%x) not available", r.addr, idx, mshr_idx));
            end
        end

        if (!need_retry && prefetchMode == COH_DM_PREFETCH_ENABLE)
        begin
            prefetcher.prefetchInval(idx);
        end
        
        if (!need_retry)
        begin
            if (cacheLookupQ.peekElem(1) matches tagged Valid .req1 &&& req1.idx == idx)
            begin
                need_bypass = True;
            end
            else if (cacheLookupReq.wget() matches tagged Valid .req0 &&& req0.idx == idx)
            begin
                need_bypass = True;
            end
            cache.write(idx, upd_entry);
        end

        updateBypassEntry(need_bypass, upd_entry);

    endrule

    // ====================================================================
    //
    // Fill requests and responses
    //
    // ====================================================================
    
    //
    // fillReq --
    //     Request fill from backing storage.
    //     Allocate new entry in MSHR.
    //
    rule fillReq (True);
        match {.r, .is_read} = fillReqQ.first();
        fillReqQ.deq();
        t_MSHR_IDX mshr_idx = truncateNP(cacheIdx(r));
        let req_info = r.reqInfo.LocalReqInfo;
        if (is_read) // read miss fill
        begin
            if (! req_info.readMeta.isLocalPrefetch)
            begin
                readMissW.send();
            end
            sourceData.getShare(r.addr, mshr_idx, req_info.globalReadMeta);
            debugLog.record($format("    Cache: fillReq (read miss): addr=0x%x", r.addr));
        end
        else // write miss fill
        begin
            sourceData.getExclusive(r.addr, mshr_idx, defaultValue());
            debugLog.record($format("    Cache: fillReq (write miss): addr=0x%x", r.addr));
        end
    endrule

    //
    // fillResp --
    //     Fill response from MSHR.  Fill responses may return out of order 
    // relative to requests. When writing back to the cache, check the inflight
    // read requests in the cacheLookupQ and update bypass entries if necessary.
    //
    (* descending_urgency = "fillResp, fillReq, resendGetXFromMSHR, sendRemoteRespFromMSHR, remoteCacheLookup, localLookupRead, doLocalWrite" *)
    (* preempts = "fillResp, (doLocalWrite, remoteCacheLookup, localLookupRead)" *)
    rule fillResp (True);
        let f <- mshr.localResp();
        
        match {.tag, .idx} = cacheEntryFromAddr(f.addr);
        
        debugLog.record($format("    Cache: fillResp: FILL addr=0x%x, entry=0x%x, msgType=%x, cacheable=%b, state=%d, val=0x%x", 
                        f.addr, idx, f.msgType, f.isCacheable, f.newState, f.val));
        
        t_CACHE_READ_META read_meta = unpack(f.clientMeta);
        t_CACHE_LOAD_RESP resp = ?;
        
        if (f.msgType == COH_CACHE_GETS && !read_meta.isLocalPrefetch)
        begin
            resp.val = f.val;
            resp.isCacheable = f.isCacheable;
            resp.readMeta = read_meta.clientReadMeta;
            resp.globalReadMeta = f.globalReadMeta;
            readRespQ.enq(resp);
            debugLog.record($format("    Cache: fillResp: send read response to client: addr=0x%x, val=0x%x", f.addr, f.val));
            
            // update stats
            if (f.newState == COH_DM_CACHE_STATE_M)
            begin
                imUpgradeW.send();
            end
            else if (f.newState == COH_DM_CACHE_STATE_O)
            begin
                ioUpgradeW.send();
            end
            if (!f.isCacheable)
            begin
                getsUncacheableW.send();
            end
        end
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
        else if (f.oldVal matches tagged Valid .old_val) // test and set response
        begin
            resp.val = old_val;
            resp.isCacheable = False;
            resp.readMeta = read_meta.clientReadMeta;
            resp.globalReadMeta = f.globalReadMeta;
            testSetRespQ.enq(resp);
            debugLog.record($format("    Cache: fillResp: send test&set response to client: addr=0x%x, val=0x%x", f.addr, old_val));
        end
`endif

        if (f.msgType == COH_CACHE_PUTX && !f.isCacheable) // write backs due to cache conflicts
        begin
            writebackStatusBits.upd(idx, False);
        end
        else
        begin
            // Save value in cache
            let new_state = (f.isCacheable)? f.newState : COH_DM_CACHE_STATE_I;
            let new_entry = COH_DM_CACHE_ENTRY {tag: tag, val: f.val, state: new_state, dirty: (f.msgType == COH_CACHE_GETX) }; 
            
            debugLog.record($format("    Cache: fillResp: update cache: addr=0x%x, entry=0x%x, state=%d, val=0x%x, dirty=%s", 
                            f.addr, idx, new_state, f.val, (f.msgType == COH_CACHE_GETX)? "True" : "False"));

            // update stats 
            if (!f.isCacheable && (f.msgType == COH_CACHE_GETS) && read_meta.isLocalPrefetch)
            begin
                prefetcher.prefetchIllegalReq();
            end
            if (f.isCacheable && (f.msgType != COH_CACHE_PUTX) && (f.newState == COH_DM_CACHE_STATE_I))
            begin
                coherenceInvalW.send();
            end
            if (f.msgType == COH_CACHE_GETX && f.newState == COH_DM_CACHE_STATE_O)
            begin
                coherenceFlushW.send();
            end

            // update cache and bypass entries
            cache.write(idx, new_entry);
            
            Maybe#(t_CACHE_REQ) req0 = tagged Invalid;
            Maybe#(t_CACHE_REQ) req1 = tagged Invalid;
            
            // cacheLookupQ is empty 
            if (!cacheLookupQ.notEmpty())
            begin
                req0 = cacheLookupReq.wget();
            end
            else // cacheLookupQ is not empty
            begin
                req0 = cacheLookupQ.peekElem(0);
                req1 = (cacheLookupQ.notFull())? cacheLookupReq.wget() : cacheLookupQ.peekElem(1);
            end

            if (req0 matches tagged Valid .r0 &&& r0.idx == idx)
            begin
                needBypass0 <= True;
                bypassCacheEntry0 <= new_entry;
                debugLog.record($format("    Cache: fillResp: bypass updated entry: entry=0x%x", idx));
            end
            if (req1 matches tagged Valid .r1 &&& r1.idx == idx)
            begin
                needBypass1 <= True;
                bypassCacheEntry1 <= new_entry;
                debugLog.record($format("    Cache: fillResp: bypass updated entry: entry=0x%x", idx));
            end

            entryFilter.remove(idx);
        end
    endrule

    (*fire_when_enabled*)
    rule mshrRelease(True);
        if (mshr.entryReleased())
        begin
            mshrReleased <= True;
        end
        else if (mshrRetryW)
        begin
            mshrReleased <= False;
        end
    endrule

    (*fire_when_enabled*)
    rule sendRemoteRespFromCache (True);
        let resp = respToRouterQ.first();
        respToRouterQ.deq();
        sourceData.sendResp(resp);
    endrule


    // ====================================================================
    //
    // Connections between MSHR and sourceData
    //
    // ====================================================================
    
    //
    // recvNwResp --
    //     Receive responses from network and feed them into MSHR.
    //
    (*fire_when_enabled*)
    rule recvNwResp (True);
        let f <- sourceData.getResp();
        mshr.recvResp(f);
    endrule

    //
    // sendRemoteRespFromMSHR --
    //     Forward MSHR responses to the network
    //
    (* descending_urgency = "sendRemoteRespFromCache, sendRemoteRespFromMSHR" *)
    rule sendRemoteRespFromMSHR (True);
        let f <- mshr.remoteResp();
        sourceData.sendResp(f);
    endrule

    //
    // mshr resend getX request if receiving retry response
    //
    rule resendGetXFromMSHR (numFreeReqBufSlots.value() > 0);
        match {.addr, .idx} <- mshr.retryReq();
        sourceData.getExclusive(addr, idx, defaultValue());
        resendGetXFromMSHRW.send();
        debugLog.record($format("    Cache: resendGetXFromMSHR: resend GETX req: addr=0x%x, mshr_idx=0x%x", addr, idx));
    endrule

    //
    // releaseMSHRGetEntry --
    //     Receive response from router saying that the forwarding entry is released
    // Inform MSHR to release the associated GET entry
    //
    (*fire_when_enabled*)
    rule releaseMSHRGetEntry (True);
        let idx <- sourceData.getReleasedFwdEntryIdx();
        mshr.releaseGetEntry(idx);
        debugLog.record($format("    Cache: releaseMSHRGetEntry: release MSHR entry=0x%x", idx));
    endrule

    //
    // resendFwdRespFromMSHR --
    //     Receive request from router saying that the forwarding entry is pending for the 
    // response value. Ask MSHR to return the forwarding value
    //
    (*fire_when_enabled*)
    rule resendFwdRespFromMSHR (True);
        let idx <- sourceData.getPendingFwdEntryIdx();
        let val <- mshr.getFwdRespVal(idx);
        sourceData.resendFwdRespVal(idx, val);
    endrule
    
    // ====================================================================
    //
    //   Debug scan state
    //
    // ====================================================================

    List#(Tuple2#(String, Bool)) ds_data = List::nil;

    // Cache lookup request sources
    ds_data = List::cons(tuple2("Coherent Cache localReqQ notEmpty", localReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache localReqQ notFull", localReqQ.notFull), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache remoteReqQ notEmpty", remoteReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache remoteReqQ notFull", remoteReqQ.notFull), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache localRetryQ notEmpty", localRetryQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache localRetryQ notFull", localRetryQ.notFull), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache mshrRetryQ notEmpty", mshrRetryQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache mshrRetryQ notFull", mshrRetryQ.notFull), ds_data);
    // Cache lookup queues
    ds_data = List::cons(tuple2("Coherent Cache cacheLookupQ notEmpty", cacheLookupQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache cacheLookupQ notFull", cacheLookupQ.notFull), ds_data);
    // Request reserved slots
    ds_data = List::cons(tuple2("Coherent Cache numFreeReqBufSlots notEmpty", (numFreeReqBufSlots.value()>0)), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache numFreeReqBufSlots notFull", (numFreeReqBufSlots.value()<fromInteger(valueOf(COH_DM_CACHE_NW_REQ_BUF_SIZE)))), ds_data);

    let debugScanData = ds_data;

    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_CLIENT_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
        debugLog.record($format("    Cache: New request: READ addr=0x%x", addr));

        t_CACHE_REQ r = ?;
        r.addr = addr;
        
        t_LOCAL_REQ_INFO f = ?;
        f.act = COH_DM_CACHE_READ;
        f.readMeta = COH_DM_CACHE_READ_META { isLocalPrefetch: False,
                                              clientReadMeta: readMeta };
        f.globalReadMeta = globalReadMeta;
        
        r.reqInfo = tagged LocalReqInfo f;
        
        localReqQ.enq(r);
    endmethod

    method ActionValue#(COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META)) readResp();
        let r = readRespQ.first();
        readRespQ.deq();
        debugLog.record($format("    Cache: send read response: val=0x%x, meta=0x%x", r.val, r.readMeta));
        return r;
    endmethod
    
    method COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META) peekResp();
        return readRespQ.first();
    endmethod


    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_MASK byteWriteMask);
        // Store the write data on a heap
        let data_idx <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(data_idx, tuple2(val, byteWriteMask));

        t_CACHE_REQ r = ?;
        r.addr = addr;
        r.reqInfo = tagged LocalReqInfo COH_DM_CACHE_LOCAL_REQ_INFO { act: COH_DM_CACHE_WRITE,
                                                                      readMeta: ?,
                                                                      globalReadMeta: ?,
                                                                      writeDataIdx: data_idx,
                                                                      isTestSet: False };
        localReqQ.enq(r);
        debugLog.record($format("    Cache: New request: WRITE addr=0x%x, wData heap=%0d, val=0x%x, mask=0x%x", addr, data_idx, val, byteWriteMask));
    endmethod
    
    //
    // Invalidate / flush currently are not implemented.
    //
    method Action invalReq(t_CACHE_ADDR addr);
        noAction;
    endmethod

    method Action flushReq(t_CACHE_ADDR addr);
        noAction;
    endmethod

    method Action invalOrFlushWait();
        noAction;
    endmethod

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence(COH_DM_CACHE_FENCE_TYPE fenceType);
        Bool check_read  = False;
        Bool check_write = False;
        case (fenceType)
            COH_DM_ALL_FENCE:
            begin
                check_read  = True;
                check_write = True;
                debugLog.record($format("    Cache: New request: ALL FENCE request"));
            end
            COH_DM_WRITE_FENCE:
            begin
                check_write = True;
                debugLog.record($format("    Cache: New request: WRITE FENCE request"));
            end
            COH_DM_READ_FENCE:
            begin
                check_read  = True;
                debugLog.record($format("    Cache: New request: READ FENCE request"));
            end
        endcase

        t_CACHE_REQ r = ?;
        t_LOCAL_REQ_INFO f = ?;
        f.act = COH_DM_CACHE_FENCE;
        r.reqInfo = tagged LocalReqInfo f;
        localReqQ.enq(r);
        localFenceInfoQ.enq(tuple2(check_read, check_write));
    endmethod
`endif

    method Bit#(2) numReadProcessed();
         let n = (readHitW) ? 1 : 0;
         if (mshr.getShareProcessed())
         begin
             n = n + 1;
         end
         return n;
    endmethod

    method Bit#(2) numWriteProcessed();
         let n = (writeHitW) ? 1 : 0;
         if (mshr.getExclusiveProcessed())
         begin
             n = n + 1;
         end
         return n;
    endmethod
    
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_CACHE_ADDR addr, 
                                t_CACHE_WORD val, 
                                t_CACHE_MASK byteWriteMask, 
                                t_CACHE_CLIENT_META readMeta, 
                                RL_CACHE_GLOBAL_READ_META globalReadMeta);
        // Store the write data on a heap
        let data_idx <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(data_idx, tuple2(val, byteWriteMask));

        let read_meta = COH_DM_CACHE_READ_META { isLocalPrefetch: False,
                                                 clientReadMeta: readMeta };
        t_CACHE_REQ r = ?;
        r.addr = addr;
        r.reqInfo = tagged LocalReqInfo COH_DM_CACHE_LOCAL_REQ_INFO { act: COH_DM_CACHE_WRITE,
                                                                      readMeta: read_meta,
                                                                      globalReadMeta: globalReadMeta,
                                                                      writeDataIdx: data_idx,
                                                                      isTestSet: True };

        localReqQ.enq(r);
        debugLog.record($format("    Cache: New request: TEST & SET addr=0x%x, wData heap=%0d, val=0x%x, mask=0x%x", addr, data_idx, val, byteWriteMask));
    endmethod
    
    method ActionValue#(COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META)) testAndSetResp();
        let r = testSetRespQ.first();
        testSetRespQ.deq();
        debugLog.record($format("    Cache: send test&set response: val=0x%x, meta=0x%x", r.val, r.readMeta));
        return r;
    endmethod
    method COH_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_CLIENT_META) peekTestAndSetResp();
        return testSetRespQ.first();
    endmethod
`endif

    method Action setCacheMode(COH_DM_CACHE_MODE mode, COH_DM_CACHE_PREFETCH_MODE en);
        cacheMode    <= mode;
        prefetchMode <= en;
    endmethod
    
    //
    // debugScanState -- Return cache state for DEBUG_SCAN.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
        return List::append(debugScanData, mshr.debugScanState());
    endmethod

    interface COH_CACHE_STATS stats;
        method Bool readHit() = readHitW;
        method Bool readMiss() = readMissW;
        method Bool writeHit() = writeHitW;
        method Bool writeCacheMiss() = writeCacheMissW;
        method Bool writePermissionMissS () = writePermissionMissSW;
        method Bool writePermissionMissO () = writePermissionMissOW;
        method Bool invalEntry() = False;
        method Bool dirtyEntryFlush() = selfDirtyFlushW;
        method Bool cleanEntryFlush() = selfCleanFlushW;
        method Bool coherenceInval() = coherenceInvalW;
        method Bool coherenceFlush() = coherenceFlushW;
        method Bool forceInvalLine() = False;
        method Bool forceFlushlLine() = False;
        method Bool mshrRetry() = mshrRetryW;
        method Bool getxRetry() = resendGetXFromMSHRW;
        method Bool getsUncacheable() = getsUncacheableW;
        method Bool imUpgrade() = imUpgradeW;
        method Bool ioUpgrade() = ioUpgradeW;
    endinterface

endmodule


