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
// Direct mapped cache.  This cache is intended to be relatively simple and
// light weight, with fast hit times.
//

// Library imports.

import FIFO::*;
import SpecialFIFOs::*;

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
    t_CACHE_WORD val;
    Bool isCacheable;
    t_CACHE_READ_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_DM_CACHE_LOAD_RESP#(type t_CACHE_WORD,
                       type t_CACHE_READ_META)
    deriving (Eq, Bits);

//
// Store Request
//
typedef struct
{
    t_CACHE_ADDRESS addr;
    t_CACHE_WORD val;
}
RL_DM_CACHE_STORE_REQ#(type t_CACHE_WORD,
                       type t_CACHE_ADDRESS)
    deriving (Eq, Bits);

//
// Cache mode can set the write policy or completely disable hits in the cache.
// This is mostly useful for debugging.
//
typedef enum
{
    RL_DM_MODE_WRITE_BACK = 0,
    RL_DM_MODE_WRITE_THROUGH = 1,
    RL_DM_MODE_WRITE_NO_ALLOC = 2,
    RL_DM_MODE_DISABLED = 3
}
RL_DM_CACHE_MODE
    deriving (Eq, Bits);

//
// Cache prefetch mode
//
typedef enum
{
    RL_DM_PREFETCH_DISABLE = 0,
    RL_DM_PREFETCH_ENABLE  = 1
}
RL_DM_CACHE_PREFETCH_MODE
    deriving (Eq, Bits);
   
//
// Direct mapped cache interface.
//
// t_CACHE_READ_META is metadata associated with a reference that will be
// returned along with a read response.  It is most often used by a clients
// as an index into a MAF (miss address file).
//
interface RL_DM_CACHE#(type t_CACHE_ADDR,
                       type t_CACHE_WORD,
                       type t_CACHE_MASK,
                       type t_CACHE_READ_META);

    // Read a word.  Read from backing store if not already cached.
    // *** Read responses are NOT guaranteed to be in the order of requests. ***
    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

    method ActionValue#(RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META)) readResp();
    // Read the head of the response queue
    method RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META) peekResp();
    

    // Write a word to a cache line.  Word index 0 corresponds to the
    // low bits of a cache line.
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val);
    method Action writeMasked(t_CACHE_ADDR addr, t_CACHE_WORD val,
                              t_CACHE_MASK byteWriteMask);
    
    // Invalidate & flush requests.  Both write dirty lines back.  Invalidate drops
    // the line from the cache.  Flush keeps the line in the cache.
    //
    // If fullHierarchy is True then the request is propagated down the full
    // cache hierarchy and the caller must receive a confirmation that the
    // operation is complete by waiting for invalOrFlushWait to fire.
    //
    // If fullHierarchy is False the request is local to this cache and
    // invalOrFlushWait should NOT be checked.
    method Action invalReq(t_CACHE_ADDR addr, Bool fullHierarchy);
    method Action flushReq(t_CACHE_ADDR addr, Bool fullHierarchy);
    method Action invalOrFlushWait();
    
    //
    // Set cache and prefetch mode.  Mostly useful for debugging.  This may not be changed
    // in the middle of a run!
    //
    method Action setCacheMode(RL_DM_CACHE_MODE mode, RL_DM_CACHE_PREFETCH_MODE en);
    
    interface RL_CACHE_STATS#(t_CACHE_READ_META) stats;

endinterface: RL_DM_CACHE


//
// Source data fill response
//
typedef struct
{
    t_CACHE_ADDR addr;
    t_CACHE_WORD val;
    Bool isCacheable;
    t_CACHE_READ_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_DM_CACHE_FILL_RESP#(type t_CACHE_ADDR,
                       type t_CACHE_WORD,
                       type t_CACHE_READ_META)
    deriving (Eq, Bits);

//
// The caller must provide an instance of the RL_DM_CACHE_SOURCE_DATA interface
// so the cache can read and write data from the next level in the hierarchy.
//
// See RL_DM_CACHE interface for description of readMeta.
//
interface RL_DM_CACHE_SOURCE_DATA#(type t_CACHE_ADDR,
                                   type t_CACHE_WORD,
                                   type t_CACHE_READ_META);

    // Fill request and response with data.  Since the response is tagged with
    // the details of the request, responses may be returned in any order.
    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

    method ActionValue#(RL_DM_CACHE_FILL_RESP#(t_CACHE_ADDR,
                                               t_CACHE_WORD,
                                               t_CACHE_READ_META)) readResp();
    method RL_DM_CACHE_FILL_RESP#(t_CACHE_ADDR,
                                  t_CACHE_WORD,
                                  t_CACHE_READ_META) peekResp();
    
    // Asynchronous write (no response)
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val);
    
    // Pass invalidate and flush requests down the hierarchy.  If sendAck is
    // true then invalOrFlushWait must block until the operation is complete.
    // If sendAck is false invalOrflushWait will not be called.
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action invalOrFlushWait();

endinterface: RL_DM_CACHE_SOURCE_DATA



// ===================================================================
//
// Internal types
//
// ===================================================================

typedef enum
{
    DM_CACHE_READ,
    DM_CACHE_WRITE,
    DM_CACHE_FLUSH,
    DM_CACHE_INVAL
}
RL_DM_CACHE_ACTION
    deriving (Eq, Bits);

typedef enum
{
    DM_CACHE_NEW_REQ,
    DM_CACHE_SIDE_REQ,
    DM_CACHE_PREFETCH_REQ
}
RL_DM_CACHE_REQ_TYPE
    deriving (Eq, Bits);

typedef enum
{
    DM_CACHE_FILL_START,
    DM_CACHE_FILL_ONGOING
}
RL_DM_CACHE_FILL_STATE
    deriving (Eq, Bits);


//
// Index of the write data heap index.  To save space, write data is passed
// through the cache pipelines as a pointer.  The heap size limits the number
// of writes in flight.
//
typedef 4 RL_DM_WRITE_DATA_HEAP_IDX_SZ;


//
// Basic cache request.  A tagged union would be a good idea here but the
// compiler gets funny about Bits#() of a tagged union and seems to force
// ugly provisos up the call chain.
//
typedef struct
{
   RL_DM_CACHE_ACTION act;
   t_CACHE_ADDR addr;
   RL_DM_CACHE_READ_META#(t_CACHE_READ_META) readMeta;
   RL_CACHE_GLOBAL_READ_META globalReadMeta;
 
   // Write data index
   t_WRITE_HEAP_IDX writeDataIdx;
 
   // Flush / inval info
   Bool fullHierarchy;

   // Hashed address and tag, passed through the pipeline instead of recomputed.
   t_CACHE_TAG tag;
   t_CACHE_IDX idx;
}
RL_DM_CACHE_REQ#(type t_CACHE_ADDR, 
                 type t_CACHE_READ_META,
                 type t_WRITE_HEAP_IDX,
                 type t_CACHE_TAG, 
                 type t_CACHE_IDX)
    deriving (Eq, Bits);


// Cache index
typedef UInt#(n_ENTRY_IDX_BITS) RL_DM_CACHE_IDX#(numeric type n_ENTRY_IDX_BITS);


typedef struct
{
    Bool dirty;
    t_CACHE_TAG tag;
    t_CACHE_WORD val;
}
RL_DM_CACHE_ENTRY#(type t_CACHE_WORD, type t_CACHE_TAG)
    deriving (Eq, Bits);

//
// Read metadata grows inside the cache because prefetches are added to the mix.
// We can't simply use the existing read metadata space because prefetches are new
// read requests sent to lower level caches and these new read requests must
// have unique IDs.
//
typedef struct
{
    Bool isLocalPrefetch;
    Bool isWriteMiss;
    t_CACHE_READ_META clientReadMeta;
}
RL_DM_CACHE_READ_META#(type t_CACHE_READ_META)
    deriving (Eq, Bits);



// 
// Request during the first stage of the request selection process. This is a provisional 
// request which exists before issuing requests to the cache and the data filter. 
//
typedef  struct {
   RL_DM_CACHE_REQ_TYPE reqType;
   t_CACHE_REQ          request;
} 
RL_DM_EARLY_REQUEST_SELECTION#(type t_CACHE_REQ)
    deriving (Eq, Bits);

// 
// Request during the second(final) stage of the request selection process. This request has 
// issued to the cache and filter, and has the metadata for these structures.
//
typedef  struct {
   RL_DM_CACHE_REQ_TYPE                reqType;
   t_CACHE_REQ                         request;
   Maybe#(CF_OPAQUE#(t_CACHE_IDX, 1))  requestMetadata;
} 
RL_DM_FINAL_REQUEST_SELECTION#(type t_CACHE_REQ, type t_CACHE_IDX)
    deriving (Eq, Bits);


//
// Basic cache request.  A tagged union would be a good idea here but the
// compiler gets funny about Bits#() of a tagged union and seems to force
// ugly provisos up the call chain.
//
typedef struct
{
   RL_DM_CACHE_ACTION act;
   t_CACHE_ADDR addr;
   RL_DM_CACHE_READ_META#(t_CACHE_READ_META) readMeta;
   RL_CACHE_GLOBAL_READ_META globalReadMeta;
 
   // Write data index
   t_WRITE_HEAP_IDX writeDataIdx;
 
   // Flush / inval info
   Bool fullHierarchy;

   // Hashed address and tag, passed through the pipeline instead of recomputed.
   t_CACHE_TAG tag;
   t_CACHE_IDX idx;
}
RL_DM_CACHE_WRITE_REQ#(type t_CACHE_ADDR, 
                       type t_CACHE_READ_META,
                       type t_WRITE_HEAP_IDX,
                       type t_CACHE_TAG, 
                       type t_CACHE_IDX)
    deriving (Eq, Bits);

// Definitions for cache side buffer
typedef Bit#(2) RL_DM_CACHE_SIDE_REQS_OUTSTANDING;
typedef Bit#(5) RL_DM_CACHE_SIDE_REQ_BINS;

typedef Bit#(3) RL_DM_CACHE_MSHR_IDX;
typedef 4       RL_DM_CACHE_MSHR_ENTRIES;

// ===================================================================
//
// Cache implementation
//
// ===================================================================

//
// mkCacheDirectMapped --
//    A thin wrapper allowing us to make parameterization decisions about the actual cache (implemented below).  Here,
//    we examine the requested cache size, and parameterize an implementation on behalf of the programmer.
//    n_ENTRIES parameter defines the number of entries in the cache.  The true number of entries will be rounded
//    up to a supported cache size.
//
module [m] mkCacheDirectMapped#(RL_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, t_CACHE_WORD, RL_DM_CACHE_READ_META#(t_CACHE_READ_META)) sourceData,
                                CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_READ_META) prefetcher,
                                NumTypeParam#(n_ENTRIES) entries,
                                Maybe#(RL_CACHE_STORE_TYPE) cacheImplementation,
                                Bool hashAddresses,
                                Bool enMaskedWrite, // enable masked write support
                                DEBUG_FILE debugLog)
    // interface:
    (RL_DM_CACHE#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_READ_META))
    provisos (IsModule#(m, m__),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Bits#(t_CACHE_MASK, t_CACHE_MASK_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),

              // Entry index.  Round n_ENTRIES request up to a power of 2.
              Log#(n_ENTRIES, t_CACHE_IDX_SZ),
              NumAlias#(TExp#(t_CACHE_IDX_SZ), n_MAX_ENTRIES),
              Alias#(RL_DM_CACHE_IDX#(t_CACHE_IDX_SZ), t_CACHE_IDX),

              Alias#(Bit#(TSub#(t_CACHE_IDX_SZ, n_LOAD_BALANCE_BASE_BITS)), t_LOAD_BALANCE_RANGE_BITS),
              Alias#(Bit#(TAdd#(n_LOAD_BALANCE_EXTRA_BITS, SizeOf#(t_LOAD_BALANCE_RANGE_BITS))), t_LOAD_BALANCE_DOMAIN_BITS),

              Alias#(Bit#(n_LOAD_BALANCE_BASE_BITS), t_LOAD_BALANCE_BASE_BITS),

              // Tag is the address bits other than the entry index
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, n_LOAD_BALANCE_BASE_BITS)), t_CACHE_TAG),
              Alias#(Maybe#(RL_DM_CACHE_ENTRY#(t_CACHE_WORD, t_CACHE_TAG)), t_CACHE_ENTRY),

              Bits#(t_CACHE_TAG, t_CACHE_TAG_SZ));

    RL_DM_CACHE#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_READ_META) cache = ?;

    // Disable/Enable MSHRs
    Bool enableMSHRs = False; 

    // Here, we examine n_ENTRIES, and develop different cache implementations
    // based on how close this value is to the next power of two.  
    if(valueof(n_ENTRIES) > 15 * valueof(n_MAX_ENTRIES) / 16)
    begin
        // Build power of two cache
        NumTypeParam#(0) loadBalanceExtraBits = ?;
        NumTypeParam#(t_CACHE_IDX_SZ) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 1;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits, 
                                             maxLoadBalanceIndex, 
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);

    end
    else if(valueof(n_ENTRIES) > 7 * valueof(n_MAX_ENTRIES) / 8)
    begin
        // Build 15/16 power of two cache

        // Normally, we choose the N bits above the base for balancing. However, in some cases
        // we may have fewer than this.
        NumTypeParam#(TMin#(4,TSub#(t_CACHE_ADDR_SZ,t_CACHE_IDX_SZ))) loadBalanceExtraBits = ?;
        NumTypeParam#(TSub#(t_CACHE_IDX_SZ,4)) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 14;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits, 
                                             maxLoadBalanceIndex, 
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);
    end
    else if(valueof(n_ENTRIES) > 13 * valueof(n_MAX_ENTRIES) / 16)
    begin
        // Build 7/8 power of two cache

        // Normally, we choose the N bits above the base for balancing. However, in some cases
        // we may have fewer than this.
        NumTypeParam#(TMin#(4,TSub#(t_CACHE_ADDR_SZ,t_CACHE_IDX_SZ))) loadBalanceExtraBits = ?;
        NumTypeParam#(TSub#(t_CACHE_IDX_SZ,3)) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 6;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits, 
                                             maxLoadBalanceIndex, 
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);
    end
    else if(valueof(n_ENTRIES) > 3 * valueof(n_MAX_ENTRIES) / 4)
    begin
        // Build 13/16 power of two cache

        // Normally, we choose the N bits above the base for balancing. However, in some cases
        // we may have fewer than this.
        NumTypeParam#(TMin#(4,TSub#(t_CACHE_ADDR_SZ,t_CACHE_IDX_SZ))) loadBalanceExtraBits = ?;
        NumTypeParam#(TSub#(t_CACHE_IDX_SZ,4)) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 12;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits, 
                                             maxLoadBalanceIndex, 
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);
    end
    else if(valueof(n_ENTRIES) > 11 * valueof(n_MAX_ENTRIES) / 16)
    begin
        // Build 3/4 power of two cache

        // Normally, we choose the N bits above the base for balancing. However, in some cases
        // we may have fewer than this.
        NumTypeParam#(TMin#(4,TSub#(t_CACHE_ADDR_SZ,t_CACHE_IDX_SZ))) loadBalanceExtraBits = ?;
        NumTypeParam#(TSub#(t_CACHE_IDX_SZ,2)) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 2;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits, 
                                             maxLoadBalanceIndex, 
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);
    end
    else if(valueof(n_ENTRIES) > 5 * valueof(n_MAX_ENTRIES) / 8)
    begin
        // Build 11/16 power of two cache

        // Normally, we choose the N bits above the base for balancing. However, in some cases
        // we may have fewer than this.
        NumTypeParam#(TMin#(4,TSub#(t_CACHE_ADDR_SZ,t_CACHE_IDX_SZ))) loadBalanceExtraBits = ?;
        NumTypeParam#(TSub#(t_CACHE_IDX_SZ,4)) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 10;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits, 
                                             maxLoadBalanceIndex, 
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);
    end
    else if(valueof(n_ENTRIES) > 9 * valueof(n_MAX_ENTRIES) / 16)
    begin
        // Build 5/8 power of two cache
 
        // Normally, we choose the N bits above the base for balancing. However, in some cases
        // we may have fewer than this.
        NumTypeParam#(TMin#(4,TSub#(t_CACHE_ADDR_SZ,t_CACHE_IDX_SZ))) loadBalanceExtraBits = ?;
        NumTypeParam#(TSub#(t_CACHE_IDX_SZ,3)) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 4;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits,  
                                             maxLoadBalanceIndex,
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);
    end
    else
    begin
        // Build 9/16 power of two cache
 
        // Normally, we choose the N bits above the base for balancing. However, in some cases
        // we may have fewer than this.
        NumTypeParam#(TMin#(4,TSub#(t_CACHE_ADDR_SZ,t_CACHE_IDX_SZ))) loadBalanceExtraBits = ?;
        NumTypeParam#(TSub#(t_CACHE_IDX_SZ,4)) loadBalanceBaseBits = ?;
        Integer maxLoadBalanceIndex = 8;

        cache <- mkCacheDirectMappedBalanced(sourceData, 
                                             prefetcher, 
                                             entries, 
                                             cacheImplementation,
                                             loadBalanceExtraBits, 
                                             loadBalanceBaseBits,  
                                             maxLoadBalanceIndex,
                                             enableMSHRs, 
                                             hashAddresses, 
                                             enMaskedWrite, 
                                             debugLog);
    end


    return cache;
endmodule


// ===================================================================
//
// Cache implementation
//
// ===================================================================

//
// mkCacheDirectMappedBalanced --
//   A cache implementing an optional load-balancer functionality for non-power of two caches.
//
module [m] mkCacheDirectMappedBalanced#(RL_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, t_CACHE_WORD, RL_DM_CACHE_READ_META#(t_CACHE_READ_META)) sourceData,
                                CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_READ_META) prefetcher,
                                NumTypeParam#(n_ENTRIES) entries,
                                Maybe#(RL_CACHE_STORE_TYPE) cacheImplementation,
                                // These parameters allow us to support non-power of two caches
                                // via a load balancing technique.
                                NumTypeParam#(n_LOAD_BALANCE_EXTRA_BITS) loadBalanceExtraBits,
                                NumTypeParam#(n_LOAD_BALANCE_BASE_BITS) loadBalanceBaseBits,
                                Integer maxLoadBalanceIndex,
                                Bool enableMSHRs,   // should we make use of MSHRs?                                 
                                Bool hashAddresses, // should we hash cache addresses?
                                Bool enMaskedWrite, // enable masked write support
                                DEBUG_FILE debugLog)
    // interface:
    (RL_DM_CACHE#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_READ_META))
    provisos (IsModule#(m, m__),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Bits#(t_CACHE_MASK, t_CACHE_MASK_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),

              // Entry index.  Round n_ENTRIES request up to a power of 2.
              Log#(n_ENTRIES, t_CACHE_IDX_SZ),
              Alias#(RL_DM_CACHE_IDX#(t_CACHE_IDX_SZ), t_CACHE_IDX),

              Alias#(Bit#(TSub#(t_CACHE_IDX_SZ, n_LOAD_BALANCE_BASE_BITS)), t_LOAD_BALANCE_RANGE_BITS),
              Alias#(Bit#(TAdd#(n_LOAD_BALANCE_EXTRA_BITS, SizeOf#(t_LOAD_BALANCE_RANGE_BITS))), t_LOAD_BALANCE_DOMAIN_BITS),

              Alias#(Bit#(n_LOAD_BALANCE_BASE_BITS), t_LOAD_BALANCE_BASE_BITS),

              // Tag is the address bits other than the entry index
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, n_LOAD_BALANCE_BASE_BITS)), t_CACHE_TAG),
              Alias#(Maybe#(RL_DM_CACHE_ENTRY#(t_CACHE_WORD, t_CACHE_TAG)), t_CACHE_ENTRY),

              // Write Heap Index
              NumAlias#(TMin#(RL_DM_WRITE_DATA_HEAP_IDX_SZ, t_CACHE_READ_META_SZ), t_WRITE_HEAP_IDX_SZ),
              Alias#(Bit#(t_WRITE_HEAP_IDX_SZ), t_WRITE_HEAP_IDX),
       
              Alias#(RL_DM_CACHE_WRITE_REQ#(t_CACHE_ADDR, t_CACHE_READ_META, t_WRITE_HEAP_IDX, t_CACHE_TAG, t_CACHE_IDX), t_CACHE_REQ),
              Alias#(RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META), t_CACHE_LOAD_RESP),


              // Required by the compiler:
              Bits#(t_CACHE_LOAD_RESP, t_CACHE_LOAD_RESP_SZ),
              Bits#(t_CACHE_TAG, t_CACHE_TAG_SZ));

    function Integer doMod(Integer modEnd);
        return modEnd % (maxLoadBalanceIndex + 1);
    endfunction

    function t_LOAD_BALANCE_RANGE_BITS calculateLoadBalanceIndex(t_LOAD_BALANCE_DOMAIN_BITS index);
        Vector#(TExp#(SizeOf#(t_LOAD_BALANCE_DOMAIN_BITS)), Integer) loadBalancer = map(doMod, genVector());
        return fromInteger(loadBalancer[index]);
    endfunction
   
    if (valueOf(t_CACHE_READ_META_SZ) < valueOf(RL_DM_WRITE_DATA_HEAP_IDX_SZ))
    begin
        error("Read meta-data size is too small to support requested write heap size");
    end

    // Only the write back mode is supported
    Reg#(RL_DM_CACHE_MODE) cacheMode <- mkReg(RL_DM_MODE_WRITE_BACK);
    Reg#(RL_DM_CACHE_PREFETCH_MODE) prefetchMode <- mkReg(RL_DM_PREFETCH_DISABLE);
    
    // Cache data and tag
    MEMORY_IFC#(t_CACHE_IDX, t_CACHE_ENTRY) cache = ?;
    
    // Decide the sort of cache that we will implement. 
    RL_CACHE_STORE_TYPE storeType = unpack(`RL_DM_CACHE_BRAM_TYPE);
    if(cacheImplementation matches tagged Valid .overrideStoreType)
    begin 
        storeType = overrideStoreType;
    end

    if (storeType == RL_CACHE_STORE_FLAT_BRAM)
    begin
        // Cache implemented as a single BRAM
        cache <- mkBRAMInitializedSized(tagged Invalid, valueof(n_ENTRIES));
    end
    else if(storeType == RL_CACHE_STORE_BANKED_BRAM)
    begin
        // Cache implemented as 4 BRAM banks with I/O buffering to allow
        // more time to reach memory.
        NumTypeParam#(4) p_banks = ?;
        
        // Notice that we must choose MEM_BANK_SELECTOR_BITS_LOW
        // here. Choosing the high bits will not work if we have a
        // non-power-of-2 cache.

        cache <- mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW,
                                 mkBRAMInitializedSizedBuffered(tagged Invalid, valueof(n_ENTRIES)/4));
    end
    else if(storeType == RL_CACHE_STORE_CLOCK_DIVIDED_BRAM)
    begin
        // Cache implemented as 8 half-speed BRAM banks.  We assume that
        // the cache is quite large in order to justify half-speed BRAM.
        // 8 banks does a reasonable job of hiding the latency.
        NumTypeParam#(8) p_banks = ?;

        // Add buffering.  This accomplishes two things:
        //   1. It adds a fully scheduled stage (without conservative conditions)
        //      that allows requests to go to banks that aren't busy.
        //   2. Buffering supports long wires.
        let cache_slow = mkSlowMemoryM(mkBRAMInitializedSizedClockDivider(tagged Invalid, valueof(n_ENTRIES)/8), True);

        // Notice that we must choose MEM_BANK_SELECTOR_BITS_LOW
        // here. Choosing the high bits will not work if we have a
        // non-power-of-2 cache.
        cache <- mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW, cache_slow);
    end
    else 
    begin
        error("rl-direct-mapped-cache: undefined storage type");
    end
    
    // Track busy entries
    RL_MSHR#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_REQ, RL_DM_CACHE_MSHR_IDX, RL_DM_CACHE_MSHR_ENTRIES) mshr = ?;
    RWire#(RL_DM_CACHE_MSHR_IDX) newMSHRRequest = ?; 

    if (enableMSHRs)
    begin
        mshr <- mkMSHR(debugLog);
        newMSHRRequest <- mkRWire();
    end

    COUNTING_FILTER#(t_CACHE_IDX, 1) entryFilter <- mkCountingFilter(debugLog);
    FIFO#(t_CACHE_IDX) entryFilterUpdateQ <- mkFIFO();

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(t_WRITE_HEAP_IDX, Tuple2#(t_CACHE_WORD, t_CACHE_MASK)) reqInfo_writeDataMask = ?;
    MEMORY_HEAP_IMM#(t_WRITE_HEAP_IDX, t_CACHE_WORD) reqInfo_writeData = ?;
    

    Reg#(RL_DM_CACHE_FILL_STATE) fillState       <- mkReg(DM_CACHE_FILL_START);
    Reg#(t_CACHE_WORD)           fillBuffer      <- mkRegU(); 
    Reg#(Bool)                   fillBufferDirty <- mkReg(False);

    if (enMaskedWrite)
    begin
        reqInfo_writeDataMask <- mkMemoryHeapLUTRAM();
    end
    else
    begin
        reqInfo_writeData <- mkMemoryHeapLUTRAM();
    end

    // Incoming data.  One method may fire at a time.
    FIFOF#(t_CACHE_REQ) newReqQ <- mkFIFOF();

    // Pipelines
    FIFOF#(Maybe#(t_CACHE_REQ)) cacheLookupQ = ?;
    if (`RL_DM_CACHE_BRAM_TYPE == 0)
    begin
        cacheLookupQ <- mkFIFOF();
    end
    else
    begin
        cacheLookupQ <- mkSizedFIFOF(16);
    end
    
    // Wires for managing cacheLookupQ
    RWire#(t_CACHE_REQ) newCacheLookupW <- mkRWire();
    PulseWire newCacheLookupValidW <- mkPulseWire();

    FIFO#(t_CACHE_REQ) fillReqQ <- mkFIFO();
    FIFO#(t_CACHE_REQ) invalQ <- mkFIFO();

    FIFO#(t_CACHE_LOAD_RESP) readRespQ <- mkBypassFIFO();
    
    // Wires for communicating stats
    RWire#(t_CACHE_READ_META) readHitW          <- mkRWire();
    PulseWire                 dirtyEntryFlushW  <- mkPulseWire();
    RWire#(t_CACHE_READ_META) readMissW         <- mkRWire();
    RWire#(t_CACHE_READ_META) writeHitW         <- mkRWire();
    RWire#(t_CACHE_READ_META) writeMissW        <- mkRWire();
    PulseWire                 forceInvalLineW   <- mkPulseWire();

    //
    // Convert address to cache index and tag
    //
    function Tuple2#(t_CACHE_TAG, t_CACHE_IDX) cacheEntryFromAddr(t_CACHE_ADDR addr);
        let a = hashAddresses ? hashBits(pack(addr)) : pack(addr);

        Tuple2#(t_CACHE_TAG, t_LOAD_BALANCE_BASE_BITS) addrSplit = unpack(truncateNP(a));
        match {.tag, .baseBits} = addrSplit;

        // Calculate the load balancer index bits
        t_LOAD_BALANCE_DOMAIN_BITS balancerBits = truncateNP(tag);
        let balancedIndex = calculateLoadBalanceIndex(balancerBits);

        return tuple2(tag, unpack({balancedIndex, baseBits}));
    endfunction

    function t_CACHE_ADDR cacheAddrFromEntry(t_CACHE_TAG tag, t_CACHE_IDX idx);

        t_LOAD_BALANCE_BASE_BITS indexBaseBits = truncateNP(pack(idx));
        t_CACHE_ADDR a = unpack(zeroExtendNP({tag, indexBaseBits}));

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
    // Apply write mask and return the updated data
    //
    function t_CACHE_WORD applyWriteMask(t_CACHE_WORD oldVal, t_CACHE_WORD wData, t_CACHE_MASK mask);
        t_CACHE_WORD r = wData;

        if (enMaskedWrite)
        begin
            Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_out = newVector();
            Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_old = unpack(resize(pack(oldVal)));
            Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_new = unpack(resize(pack(wData)));
            Vector#(t_CACHE_MASK_SZ, Bool) mask_v       = unpack(pack(mask));
            for (Integer b = 0; b < valueOf(t_CACHE_MASK_SZ); b = b + 1)
            begin
                bytes_out[b] = mask_v[b] ? bytes_new[b] : bytes_old[b];
            end

            r = unpack(resize(pack(bytes_out)));
        end

        return r;
    endfunction

    // ====================================================================
    //
    // All incoming requests start here.
    //
    //     At most one request per line may be active.  When a new request
    //     arrives for an active line, the request is shunted to the
    //     sideReqQ in order to allow other requests to flow past it.
    //     Because the line filter is expensive, the side queue and the
    //     new request queues share a single filter.  Priority for new
    //     requests and side requests is updated each cycle.
    //
    // ====================================================================

    FIFOF#(t_CACHE_REQ) sideReqQ <- mkSizedFIFOF(8);
    LUTRAM#(RL_DM_CACHE_SIDE_REQ_BINS, RL_DM_CACHE_SIDE_REQS_OUTSTANDING) sideReqFilter <- mkLUTRAM(0);
    Reg#(Bit#(2)) newReqArb <- mkReg(0);

    // Track whether the heads of the new and side request queues are
    // blocked.  Once blocked, a queue stays blocked until either the head
    // is removed or a cache index is unlocked when an in-flight request
    // is completed.
    Reg#(Bool) newReqNotBlocked[3] <- mkCReg(3, True);
    Reg#(Bool) sideReqNotBlocked[2] <- mkCReg(2, True);

    // Wires controlling the request pipeline. 
    Wire#(RL_DM_EARLY_REQUEST_SELECTION#(t_CACHE_REQ))              pickReq <- mkWire();
    Wire#(RL_DM_FINAL_REQUEST_SELECTION#(t_CACHE_REQ, t_CACHE_IDX)) curReq <- mkWire();
    PulseWire                                                       mshrReq <- mkPulseWire();

    //
    // pickReqQueue0 --
    //     Decide whether to consider the new request or side request queue
    //     this cycle.  Filtering both is too expensive.
    //
    //     If the cache prefecher is enabled, choose among new request, side 
    //     request, and prefetch request queues.
    // 
    rule pickReqQueue0 (True);
        // New requests win over side requests if there is a new request
        // and the arbiter is non-zero.  If the arbitration counter newReqArb
        // is larger than 1 bit this favors new requests over side-buffer
        // requests in an effort to have as many requests in flight as possible.
        //
        // Choose from prefech request queue is the prefetcher is enabled and 
        // the arbitration counter newReqArb is larger than a certain threshold
        
        Bool new_req_avail = newReqQ.notEmpty && newReqNotBlocked[0];
        Bool side_req_avail = sideReqQ.notEmpty && sideReqNotBlocked[0];

        Bool pick_new_req = new_req_avail && ((newReqArb != 0) || ! side_req_avail);

        // If we have a high priority prefetch, we can issue it over other requests. 
        // we examine bit 0 of new request to balance the prefetches better against
        // against the baseline reqeusts.  If we have a low priority prefetch, we will 
        // only issue it if we don't have something else to do. 
        if ( prefetchMode == RL_DM_PREFETCH_ENABLE && prefetcher.hasReq() && 
           ((!newReqQ.notEmpty && !sideReqQ.notEmpty) || 
           ((newReqArb[0] == 0) && (prefetcher.peekReq().prio == PREFETCH_PRIO_HIGH))))
        begin
            let req_type  = DM_CACHE_PREFETCH_REQ;
            let pref_req  = prefetcher.peekReq();
            t_CACHE_REQ r = ?;
            r.act         = DM_CACHE_READ;
            r.addr        = pref_req.addr;
            r.readMeta    = RL_DM_CACHE_READ_META { isLocalPrefetch: True,
                                                    isWriteMiss: False, 
                                                    clientReadMeta: pref_req.readMeta };
            r.globalReadMeta  = defaultValue();
            r.globalReadMeta.isPrefetch = True;
            match {.tag, .idx} = cacheEntryFromAddr(pref_req.addr);
            r.tag = tag;
            r.idx = idx;

            pickReq <= RL_DM_EARLY_REQUEST_SELECTION{reqType: req_type, request: r};
            debugLog.record($format("    pick prefetch req: addr=0x%x, entry=0x%x", r.addr, idx));
        end
        else if (pick_new_req)
        begin
            let r = newReqQ.first();
            pickReq <= RL_DM_EARLY_REQUEST_SELECTION{reqType:DM_CACHE_NEW_REQ, request: r};
            debugLog.record($format("    pick new req: addr=0x%x, entry=0x%x", r.addr, cacheIdx(r)));
        end
        else if (side_req_avail)
        begin
            let r = sideReqQ.first();
            pickReq <= RL_DM_EARLY_REQUEST_SELECTION{reqType: DM_CACHE_SIDE_REQ, request: r};
            debugLog.record($format("    pick side req: addr=0x%x, entry=0x%x", r.addr, cacheIdx(r)));
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
    rule pickReqQueue1 (cacheLookupQ.notFull);
        let req_type = pickReq.reqType;
        let r = pickReq.request;
        let idx = cacheIdx(r);
        
        // At this point the cache index is known but it is not yet known
        // whether it is legal to read the index this cycle.  Delaying the
        // cache read any longer is an FPGA timing bottleneck.  We request
        // the read speculatively now and will indicate in cacheLookupQ
        // whether the speculative read must be drained.  Nothing else
        // would have been done this cycle, so we lose no performance.
        cache.readReq(idx);
        newCacheLookupW.wset(r);

        // Update arbiter now that a request has been posted.  Arbiter update
        // is tied to cache requests in order to support storage that
        // doesn't accept a request every cycle, such as BRAM running
        // with a divided block.  Updating the arbiter without this connection
        // can trigger harmonics that result in live locks.
        newReqArb <= newReqArb + 1;

        // In order to preserve read/write and write/write order, the
        // request must either come from the side buffer or be a new request
        // referencing a line not already in the side buffer.
        //
        // The array sideReqFilter tracks lines active in the side request
        // queue.
        if ((req_type == DM_CACHE_SIDE_REQ) ||        // Was in side req queue -- it's the oldest request, so there is no order hazard
            (sideReqFilter.sub(resize(idx)) == 0))    // No conflicting instruction in sideReqQ. 
        begin
            curReq <= RL_DM_FINAL_REQUEST_SELECTION{reqType: req_type, request: r, requestMetadata: entryFilter.test(idx)};
        end
        else
        begin
            curReq <= RL_DM_FINAL_REQUEST_SELECTION{reqType: req_type, request: r, requestMetadata: tagged Invalid};
        end
    endrule

    (* fire_when_enabled *)
    rule startNewReq (curReq.requestMetadata matches tagged Valid .filter_state &&&
                      curReq.reqType  == DM_CACHE_NEW_REQ);

        let req_type = curReq.reqType;
        let r = curReq.request;
        let cf_opaque = curReq.requestMetadata;

        let idx = cacheIdx(r);

        // The new request is permitted.  Do it.
        newCacheLookupValidW.send();
        entryFilter.set(filter_state);

        debugLog.record($format("    %s: addr=0x%x, entry=0x%x",
                                req_type == DM_CACHE_NEW_REQ ? "startNewReq" : 
                                ( req_type == DM_CACHE_SIDE_REQ ? "startSideReq" :
                                  "startPrefetchReq" ), r.addr, idx));
        newReqQ.deq();
        
    endrule


    (* fire_when_enabled *)
    rule startSideReq (curReq.requestMetadata matches tagged Valid .filter_state &&&
                       curReq.reqType == DM_CACHE_SIDE_REQ);

        let req_type = curReq.reqType;
        let r = curReq.request;
        let cf_opaque = curReq.requestMetadata;

        let idx = cacheIdx(r);

        // The new request is permitted.  Do it.
        newCacheLookupValidW.send();
        entryFilter.set(filter_state);

        debugLog.record($format("    %s: addr=0x%x, entry=0x%x",
                                req_type == DM_CACHE_NEW_REQ ? "startNewReq" : 
                                ( req_type == DM_CACHE_SIDE_REQ ? "startSideReq" :
                                  "startPrefetchReq" ), r.addr, idx));

        sideReqQ.deq();
        sideReqFilter.upd(resize(idx), sideReqFilter.sub(resize(idx)) - 1);
        // Removing from the side buffer may free the new request.
        newReqNotBlocked[2] <= True;
        
    endrule

    (* fire_when_enabled *)
    rule startPrefetchReq (curReq.requestMetadata matches tagged Valid .filter_state &&&
                           (curReq.reqType == DM_CACHE_PREFETCH_REQ));

        let req_type = curReq.reqType;
        let r = curReq.request;
        let cf_opaque = curReq.requestMetadata;

        let idx = cacheIdx(r);

        // The new request is permitted.  Do it.
        newCacheLookupValidW.send();
        entryFilter.set(filter_state);

        debugLog.record($format("    %s: addr=0x%x, entry=0x%x",
                                req_type == DM_CACHE_NEW_REQ ? "startNewReq" : 
                                ( req_type == DM_CACHE_SIDE_REQ ? "startSideReq" :
                                  "startPrefetchReq" ), r.addr, idx));

        let pf_req <- prefetcher.getReq();
        
    endrule

    (* fire_when_enabled *)
    rule dropStalePrefetches ( curReq.requestMetadata matches tagged Valid .filter_state &&& (
                               curReq.reqType != DM_CACHE_PREFETCH_REQ && 
                              ((prefetcher.peekReq().prio == PREFETCH_PRIO_LOW) && prefetcher.prefetcherNearlyFull())));

        let pf_req <- prefetcher.getReq();
        
    endrule


    //
    // shuntNewReq --
    //     If the current request is new (not a shunted request) and the
    //     line is busy, shunt the new request to a side queue in order to
    //     attempt to process a later request that may be ready to go.
    //
    //     This rule will not fire if startReq fires.
    //
    (* fire_when_enabled *)
    rule shuntNewReq (curReq.reqType == DM_CACHE_NEW_REQ &&
                      ! isValid(curReq.requestMetadata));
        let req_type = curReq.reqType;
        let r = curReq.request;
        let cf_opaque = curReq.requestMetadata;

        // Here, we need to see if we can put in an mshr.  This is
        // the only place that we put things in the sideReqQ. A real question is 
        // whether we need the side reqQ anymore. In this case, it is only 
        // handling read-after-write. 

        let sideReqFilterCount = sideReqFilter.sub(resize(cacheIdx(curReq.request))); 

        let idx = cacheIdx(r);
        RL_DM_CACHE_MSHR_IDX mshrIdx = truncateNP(pack(idx));

        // Can we put this request into an MSHR? 
        if (enableMSHRs                              &&  // are MSHRs enabled?
            mshr.notEmptyMSHR(mshrIdx, pack(r.addr)) &&  // is there a tag allocated for this index in the MSHR?
            mshr.notFullMSHR(mshrIdx, pack(r.addr))  &&  // is there space in the MSHR (does a tag check)?  
            sideReqFilterCount == 0)                     // is the side req Q filter empty (needed to preserve ordering)
        begin
            // place request in MSHR. 
            mshrReq.send();
            mshr.dump();
            newReqQ.deq();
            
            // inform fill handler of new entry
            newMSHRRequest.wset(mshrIdx);

            // Let the prefetcher know something interesting happened. 
            if (prefetchMode == RL_DM_PREFETCH_ENABLE)
            begin
                prefetcher.shuntNewCacheReq(idx, r.addr);
            end
        end
        else if (! curReq.request.globalReadMeta.orderedSourceDataReqs &&
           (sideReqFilterCount != maxBound) &&
           sideReqQ.notFull)
        begin
            debugLog.record($format("    shunt busy line req: addr=0x%x, entry=0x%x", r.addr, idx));

            sideReqQ.enq(r);
            newReqQ.deq();

            // Note line present in sideReqQ
            sideReqFilter.upd(resize(idx), sideReqFilter.sub(resize(idx)) + 1);

            // Let the prefetcher know something interesting happened. 
            if (prefetchMode == RL_DM_PREFETCH_ENABLE)
            begin
                prefetcher.shuntNewCacheReq(idx, r.addr);
            end
        end
        else
        // We can't eliminate this request.  We must block. 
        begin
            debugLog.record($format("    new req queue blocked: addr=0x%x, entry=0x%x", r.addr, idx));
            newReqNotBlocked[0] <= False;
        end
    endrule

    //
    // enqToMSHR --
    //     Places an incoming request into the MSHR.  This rule is removed from
    //     shuntNewReq so that fillReq can fire in the same cycle.
    //
    (* fire_when_enabled *)
    rule enqToMSHR(mshrReq);
        let r = curReq.request;
        let idx = cacheIdx(r);
        RL_DM_CACHE_MSHR_IDX mshrIdx = truncateNP(pack(idx));

        mshr.enqMSHR(mshrIdx, pack(r.addr), r);

    endrule

    //
    // sideReqBlocked --
    //     Detect when the side queue is blocked.  There is no point in polling
    //     it until the blocking in-flight request completes.
    //
    (* fire_when_enabled *)
    rule sideReqBlocked (curReq.reqType == DM_CACHE_SIDE_REQ &&
                         ! isValid(curReq.requestMetadata));
        let req_type = curReq.reqType;
        let r = curReq.request;
        let cf_opaque = curReq.requestMetadata; 

        let idx = cacheIdx(r);

        debugLog.record($format("    side req queue blocked: addr=0x%x, entry=0x%x", r.addr, idx));
        sideReqNotBlocked[0] <= False;
    endrule

    //
    // For collecting prefetch stats
    //
    (* fire_when_enabled *)
    rule dropPrefetchReqByBusy (curReq.reqType == DM_CACHE_PREFETCH_REQ && 
                                !isValid(curReq.requestMetadata) );
        let pf_req <- prefetcher.getReq();
        debugLog.record($format("    Prefetch req dropped by busy: addr=0x%x", curReq.request.addr));
        prefetcher.prefetchDroppedByBusy(curReq.request.addr);
    endrule


    //
    // Write cacheLookupQ to indicate whether a new request was started
    // this cycle.
    //
    (* fire_when_enabled *)
    rule didLookup (newCacheLookupW.wget() matches tagged Valid .r);
        // Was a valid new request started?
        if (newCacheLookupValidW)
        begin
            cacheLookupQ.enq(tagged Valid r);
            debugLog.record($format("    Lookup valid, entry=0x%x", cacheIdx(r)));
        end
        else
        begin
            cacheLookupQ.enq(tagged Invalid);
            debugLog.record($format("    Speculative lookup dropped"));
        end
    endrule


    // ====================================================================
    //
    // Drain (failed speculative read)
    //
    // ====================================================================

    rule drainRead (! isValid(cacheLookupQ.first));
        cacheLookupQ.deq();
        let cur_entry <- cache.readRsp();
    endrule


    // ====================================================================
    //
    // Read path
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule lookupRead (cacheLookupQ.first() matches tagged Valid .r &&&
                     r.act == DM_CACHE_READ);
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cache.readRsp();

        Bool needFill = True;

        if (cur_entry matches tagged Valid .e)
        begin
            if (e.tag == tag) // Hit!
            begin
                debugLog.record($format("    lookupRead: HIT addr=0x%x, entry=0x%x, val=0x%x", r.addr, idx, e.val));
                // Ignore prefetch hit response and prefetch hit status
                if (! r.readMeta.isLocalPrefetch)
                begin
                    readHitW.wset(r.readMeta.clientReadMeta);
                    if (prefetchMode == RL_DM_PREFETCH_ENABLE)
                    begin
                        prefetcher.readHit(idx, r.addr);
                    end
                    t_CACHE_LOAD_RESP resp;
                    resp.val = e.val;
                    resp.isCacheable = True;
                    resp.readMeta = r.readMeta.clientReadMeta;
                    resp.globalReadMeta = r.globalReadMeta;
                    readRespQ.enq(resp);
                end
                else
                begin
                    prefetcher.prefetchDroppedByHit();
                end
                entryFilterUpdateQ.enq(idx);
                needFill = False;
            end
            else if (e.dirty)
            begin
                // Miss.  Need to flush old data?
                let old_addr = cacheAddrFromEntry(e.tag, idx);
                debugLog.record($format("    lookupRead: FLUSH addr=0x%x, entry=0x%x, val=0x%x", old_addr, idx, e.val));
                sourceData.write(old_addr, e.val);
                dirtyEntryFlushW.send;
            end
        end

        // Request fill of new value
        if (needFill)
        begin
            fillReqQ.enq(r);
            if (prefetchMode == RL_DM_PREFETCH_ENABLE)
            begin
                prefetcher.readMiss(idx, r.addr,
                                    r.readMeta.isLocalPrefetch,
                                    r.readMeta.clientReadMeta);
            end

            debugLog.record($format("    lookupRead: MISS addr=0x%x, entry=0x%x", r.addr, idx));
        end
    endrule

    // ====================================================================
    //
    // Fill path
    //
    // ====================================================================

    //
    // fillReq --
    //     Request fill from backing storage.
    //
    (* conservative_implicit_conditions *)
    rule fillReq (True);
        let r = fillReqQ.first();

        let idx = cacheIdx(r);
        RL_DM_CACHE_MSHR_IDX mshrIdx = truncateNP(pack(idx));

        // If MSHRs are enabled, we will allocate here.  Otherwise, 
        // we simply issue the fill request.
        if (enableMSHRs)
        begin
            if ( mshr.notFullMSHR(mshrIdx, pack(r.addr)) &&
                 mshr.notEmptyMSHR(mshrIdx, pack(r.addr)))
            begin
                $display("Fill Req miss-under-miss mismatch");
                $finish;
            end

            // Fills require an MSHR.  Allocate one here. If we cannot allocate,
            // we must stall. 
            if (mshr.notFullMSHR(mshrIdx, pack(r.addr)))
            begin
                fillReqQ.deq();
                mshr.enqMSHR(mshrIdx, pack(r.addr), r);
                mshr.dump();
                debugLog.record($format("    fillReq: addr=0x%x", r.addr));

                if (!r.readMeta.isLocalPrefetch && !r.readMeta.isWriteMiss)
                begin
                    readMissW.wset(r.readMeta.clientReadMeta);
                end
                else if (r.readMeta.isWriteMiss)
                begin
                    writeMissW.wset(r.readMeta.clientReadMeta);
                end

                sourceData.readReq(r.addr, r.readMeta, r.globalReadMeta);
            end        
            else 
            begin 
                debugLog.record($format("    fillReq: addr=0x%x mshr=0x%x is blocked", r.addr, mshrIdx));
                mshr.dump();
            end
        end
        else // No MSHRs, just issue request.
        begin
            fillReqQ.deq();
            debugLog.record($format("    fillReq: addr=0x%x", r.addr));

            if (!r.readMeta.isLocalPrefetch && !r.readMeta.isWriteMiss)
            begin
                readMissW.wset(r.readMeta.clientReadMeta);
            end
            else if (r.readMeta.isWriteMiss)
            begin
                writeMissW.wset(r.readMeta.clientReadMeta);
            end

            sourceData.readReq(r.addr, r.readMeta, r.globalReadMeta);
        end
    endrule
    
    //
    // fillResp --
    //     Fill response.  Fill responses may return out of order relative to
    //     requests.
    //
    rule fillResp (True);
        let f = sourceData.peekResp();

        match {.tag, .idx} = cacheEntryFromAddr(f.addr);
        RL_DM_CACHE_MSHR_IDX mshrIdx = truncateNP(pack(idx));
       
        // Depending on state, we take either the fillBuffer data or 
        // the incoming data. 
        let  cacheData  = fillBuffer;
        Bool cacheDirty = fillBufferDirty;
        if(fillState == DM_CACHE_FILL_START)
        begin
            debugLog.record($format("    fill starting"));
            cacheData = f.val;
            cacheDirty = False;
        end
 
        // Assign a defaults the case that we do not use MSHRs
        let currentRequestReadMeta = f.readMeta;
        let currentRequestGlobalReadMeta = f.globalReadMeta;
       
        // We only spend multiple cycles merging requests if 
        // MSHRs are enabled.
        let fillComplete = True;

        if (enableMSHRs)           
        begin
            // Did a new request try to extend this mshr?  If it did, we should process it.
            Bool enqueueConflict = isValid(newMSHRRequest.wget()) && (fromMaybe(?, newMSHRRequest.wget()) == mshrIdx);  
            fillComplete = !enqueueConflict && mshr.countMSHR(mshrIdx) == 1;

            // If we have consumed all of the mshr requests, we can finally ship the data to the cache and drop the 
            // in bound request. 
            if(fillComplete)
            begin  
                let deadValue <- sourceData.readResp();
                entryFilterUpdateQ.enq(idx);
                fillState <= DM_CACHE_FILL_START;
                debugLog.record($format("    fill complete"));
                mshr.dump();
            end
            else 
            begin
                fillState <= DM_CACHE_FILL_ONGOING;
                debugLog.record($format("    fill continuing"));
            end
            
            // remove request from mshr.
            mshr.deqMSHR(mshrIdx);
            mshr.dump();
            let mshrRequest = mshr.firstMSHR(mshrIdx);
            // Populate metadata from MSHR. 
            currentRequestReadMeta = mshrRequest.readMeta;
            currentRequestGlobalReadMeta = mshrRequest.globalReadMeta;

            debugLog.record($format("    fillResp: FILL addr=0x%x req.addr=0x%x, entry=0x%x, cacheable=%b, val=0x%x", f.addr, mshrRequest.addr, idx, f.isCacheable, cacheData));

            if(pack(f.addr) != pack(mshrRequest.addr))
            begin
                $display("Fill Resp Address mismatch");
                $finish;
            end 
        end
        else
        begin
            let deadValue <- sourceData.readResp();
            entryFilterUpdateQ.enq(idx);          
        end

        if (!currentRequestReadMeta.isLocalPrefetch && !currentRequestReadMeta.isWriteMiss)
        begin
            t_CACHE_LOAD_RESP resp;
            resp.val = cacheData;
            resp.isCacheable = f.isCacheable;
            resp.readMeta = currentRequestReadMeta.clientReadMeta;
            resp.globalReadMeta = currentRequestGlobalReadMeta;
            readRespQ.enq(resp);
        end
        
        if (enMaskedWrite && currentRequestReadMeta.isWriteMiss) // do write
        begin
            // New data to write
            t_WRITE_HEAP_IDX w_idx = truncate(pack(currentRequestReadMeta.clientReadMeta));
            match { .w_data, .w_mask } = reqInfo_writeDataMask.sub(w_idx);
            reqInfo_writeDataMask.free(w_idx);
            cacheData = applyWriteMask(cacheData, w_data, w_mask);
            cacheDirty = True;

            // If we have handled all oustanding requests to this line, 
            // commit it to the cache. Otherwise, we will continue 
            // processing on fill buffer.
            if(fillComplete)
            begin
                cache.write(idx, tagged Valid RL_DM_CACHE_ENTRY { dirty: True,
                                                                  tag: tag,
                                                                  val: cacheData });
            end
        end
        else if (f.isCacheable) // Save value in cache.  
        begin

            // If we have handled all oustanding requests to this line, 
            // commit it to the cache. Otherwise, we will continue 
            // processing on fill buffer.
            if(fillComplete)
            begin
                cache.write(idx, tagged Valid RL_DM_CACHE_ENTRY { dirty: cacheDirty,
                                                                  tag: tag,
                                                                  val: cacheData });
            end
               
            prefetcher.fillResp(idx, f.addr,
                                currentRequestReadMeta.isLocalPrefetch,
                                currentRequestReadMeta.clientReadMeta);
        end
        else if (currentRequestReadMeta.isLocalPrefetch)
        begin
            prefetcher.prefetchIllegalReq();
        end

        if (enableMSHRs)
        begin
            // Update fill buffer for potential use in next cycle. 
            fillBuffer <= cacheData;
            fillBufferDirty <= cacheDirty;
        end
    endrule


    // ====================================================================
    //
    // Write path
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule doWrite (cacheLookupQ.first() matches tagged Valid .r &&&
                  r.act == DM_CACHE_WRITE);
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cache.readRsp();

        // New data to write
        t_CACHE_WORD w_data = ?;
        t_CACHE_MASK w_mask = ?;

        if (enMaskedWrite)
        begin
            let w_info = reqInfo_writeDataMask.sub(r.writeDataIdx);
            w_data = tpl_1(w_info);
            w_mask = tpl_2(w_info);
        end
        else
        begin
            w_data = reqInfo_writeData.sub(truncateNP(r.writeDataIdx));
            Vector#(t_CACHE_MASK_SZ, Bool) all_one_mask = replicate(True);
            w_mask = unpack(pack(all_one_mask));
        end

        Bool write_hit = False;
        t_CACHE_WORD old_val = ?;

        if (cur_entry matches tagged Valid .e) 
        begin
            if (e.tag == tag)
            begin
                old_val = e.val;
                write_hit = True;
            end
            else if (e.dirty)
            begin
                // Dirty data must be flushed
                let old_addr = cacheAddrFromEntry(e.tag, idx);
                debugLog.record($format("    doWrite: FLUSH addr=0x%x, entry=0x%x, val=0x%x", old_addr, idx, e.val));
                sourceData.write(old_addr, e.val);
                dirtyEntryFlushW.send;
            end
        end
        
        // To avoid proviso checking
        Vector#(TMax#(1, t_CACHE_MASK_SZ), Bool) mask_vec = unpack(zeroExtendNP(pack(w_mask)));
        if (write_hit || fold(\&& , mask_vec) || !enMaskedWrite) // do write
        begin
            t_CACHE_WORD new_val = write_hit? applyWriteMask(old_val, w_data, w_mask) : w_data;
            debugLog.record($format("    doWrite: WRITE addr=0x%x, entry=0x%x, val=0x%x, mask=0x%x, new_val=0x%x", 
                            r.addr, idx, w_data, w_mask, new_val));

            writeHitW.wset(r.readMeta.clientReadMeta);
            cache.write(idx, tagged Valid RL_DM_CACHE_ENTRY { dirty: True,
                                                              tag: tag,
                                                              val: new_val });
            if (prefetchMode == RL_DM_PREFETCH_ENABLE)
            begin
                prefetcher.prefetchInval(idx);
            end
            entryFilterUpdateQ.enq(idx);
            if (enMaskedWrite)
            begin
                reqInfo_writeDataMask.free(r.writeDataIdx);
            end
            else
            begin
                reqInfo_writeData.free(truncateNP(r.writeDataIdx));
            end
        end
        else // write miss
        begin 
            fillReqQ.enq(r);

            if (prefetchMode == RL_DM_PREFETCH_ENABLE)
            begin
                prefetcher.readMiss(idx, r.addr,
                                    r.readMeta.isLocalPrefetch,
                                    r.readMeta.clientReadMeta);
            end

            debugLog.record($format("    doWrite: MISS addr=0x%x, entry=0x%x", r.addr, idx));
        end
    endrule


    // ====================================================================
    //
    // Inval / flush path
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule evictForInval (cacheLookupQ.first() matches tagged Valid .r &&&
                        (r.act == DM_CACHE_INVAL) ||
                        (r.act == DM_CACHE_FLUSH));
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cache.readRsp();

        if (cur_entry matches tagged Valid .e &&& (e.tag == tag))
        begin
            forceInvalLineW.send;

            if (e.dirty)
            begin
                // Dirty data must be flushed
                let old_addr = cacheAddrFromEntry(e.tag, idx);
                debugLog.record($format("    evictForInval: FLUSH addr=0x%x, entry=0x%x, sync=%0d, val=0x%x", old_addr, idx, r.fullHierarchy, e.val));

                sourceData.write(old_addr, e.val);
            end

            // Clear the entry if invalidating
            if (r.act == DM_CACHE_INVAL)
            begin
                debugLog.record($format("    evictForInval: INVAL addr=0x%x, entry=0x%x", r.addr, idx));
                cache.write(idx, tagged Invalid);

                if (prefetchMode == RL_DM_PREFETCH_ENABLE)
                begin
                    prefetcher.prefetchInval(idx);
                end
            end
            else
            begin
                // Just ensure dirty bit is clear for flush
                let upd_entry = e;
                upd_entry.dirty = False;
                cache.write(idx, tagged Valid upd_entry);
            end
        end
        
        invalQ.enq(r);
    endrule


    (* descending_urgency = "enqToMSHR, fillResp, fillReq, lookupRead, doWrite, finishInval, evictForInval" *)
    rule finishInval (True);
        let r = invalQ.first();
        invalQ.deq();

        let idx = cacheIdx(r);

        //
        // Pass the message down the hierarchy.  There might be another cache
        // below this one.
        //
        if (r.fullHierarchy)
        begin
            if (r.act == DM_CACHE_INVAL)
                sourceData.invalReq(r.addr, True);
            else
                sourceData.flushReq(r.addr, True);
        end

        entryFilterUpdateQ.enq(idx);
    endrule


    // ====================================================================
    //
    // Management.
    //
    // ====================================================================

    //
    // finishEntry --
    //     Finish processing an entry.  Removing from the entry filter
    //     is expensive, so it is delayed a cycle.
    //
    rule finishEntry (True);
        let idx = entryFilterUpdateQ.first();
        entryFilterUpdateQ.deq();

        entryFilter.remove(idx);

        // Lift blocks on queues when the filter is updated.
        newReqNotBlocked[1] <= True;
        sideReqNotBlocked[1] <= True;
    endrule


    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
        debugLog.record($format("  New request: READ addr=0x%x", addr));

        t_CACHE_REQ r = ?;
        r.act = DM_CACHE_READ;
        r.addr = addr;
        r.readMeta = RL_DM_CACHE_READ_META { isLocalPrefetch: False,
                                             isWriteMiss: False,
                                             clientReadMeta: readMeta };
        r.globalReadMeta = globalReadMeta;

        match {.tag, .idx} = cacheEntryFromAddr(addr);
        r.tag = tag;
        r.idx = idx;

        newReqQ.enq(r);
    endmethod

    method ActionValue#(RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META)) readResp();
        let r = readRespQ.first();
        readRespQ.deq();

        return r;
    endmethod
    
    method RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META) peekResp();
        return readRespQ.first();
    endmethod


    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val);
        // Store the write data on a heap
        Vector#(t_CACHE_MASK_SZ, Bool) mask = replicate(True);
        t_WRITE_HEAP_IDX data_idx = ?; 
        if (enMaskedWrite)
        begin
            data_idx <- reqInfo_writeDataMask.malloc();
            reqInfo_writeDataMask.upd(data_idx, tuple2(val, unpack(pack(mask))));
        end
        else
        begin
            data_idx <- reqInfo_writeData.malloc();
            reqInfo_writeData.upd(data_idx, val);
        end

        t_CACHE_REQ r = ?;
        r.act = DM_CACHE_WRITE;
        r.addr = addr;
        r.readMeta = RL_DM_CACHE_READ_META { isLocalPrefetch: False,
                                             isWriteMiss: False,
                                             clientReadMeta: ? };
        r.globalReadMeta = ?;
        r.writeDataIdx = data_idx;

        match {.tag, .idx} = cacheEntryFromAddr(addr);
        r.tag = tag;
        r.idx = idx;

        newReqQ.enq(r);

        debugLog.record($format("  New request: WRITE addr=0x%x, wData heap=%0d, val=0x%x", addr, data_idx, val));
    endmethod
    
    method Action writeMasked(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_MASK mask) if (enMaskedWrite);
        // Store the write data on a heap
        let data_idx <- reqInfo_writeDataMask.malloc();
        reqInfo_writeDataMask.upd(data_idx, tuple2(val, mask));

        t_CACHE_REQ r = ?;
        r.act = DM_CACHE_WRITE;
        r.addr = addr;
        r.readMeta = RL_DM_CACHE_READ_META { isLocalPrefetch: False,
                                             isWriteMiss: True,
                                             clientReadMeta: unpack(zeroExtend(data_idx)) };
        r.globalReadMeta = defaultValue();
        r.writeDataIdx = data_idx;

        match {.tag, .idx} = cacheEntryFromAddr(addr);
        r.tag = tag;
        r.idx = idx;

        newReqQ.enq(r);

        debugLog.record($format("  New request: MASKED WRITE addr=0x%x, wData heap=%0d, val=0x%x, mask=0x%x", 
                        addr, data_idx, val, mask));
    endmethod
    

    method Action invalReq(t_CACHE_ADDR addr, Bool fullHierarchy);
        debugLog.record($format("  New request: INVAL addr=0x%x, full=%d", addr, fullHierarchy));

        t_CACHE_REQ r = ?;
        r.act = DM_CACHE_INVAL;
        r.addr = addr;
        r.readMeta = ?;
        r.globalReadMeta = ?;
        r.fullHierarchy = fullHierarchy;

        match {.tag, .idx} = cacheEntryFromAddr(addr);
        r.tag = tag;
        r.idx = idx;

        newReqQ.enq(r);
    endmethod

    method Action flushReq(t_CACHE_ADDR addr, Bool fullHierarchy);
        debugLog.record($format("  New request: FLUSH addr=0x%x, full=%d", addr, fullHierarchy));

        t_CACHE_REQ r = ?;
        r.act = DM_CACHE_FLUSH;
        r.addr = addr;
        r.readMeta = ?;
        r.globalReadMeta = ?;
        r.fullHierarchy = fullHierarchy;

        match {.tag, .idx} = cacheEntryFromAddr(addr);
        r.tag = tag;
        r.idx = idx;

        newReqQ.enq(r);
    endmethod

    method Action invalOrFlushWait();
        debugLog.record($format("    INVAL/FLUSH complete"));

        sourceData.invalOrFlushWait();
    endmethod

    method Action setCacheMode(RL_DM_CACHE_MODE mode, RL_DM_CACHE_PREFETCH_MODE en);
        cacheMode <= mode;
        if (mode == RL_DM_MODE_DISABLED)
            prefetchMode <= RL_DM_PREFETCH_DISABLE;
        else
            prefetchMode <= en;
    endmethod

    interface RL_CACHE_STATS stats;
        method readHit = readHitW.wget;
        method readMiss = readMissW.wget;
        method readRecentLineHit = False;    
        method writeHit = writeHitW.wget;
        method writeMiss = writeMissW.wget;
        method newMRU = False;
        method invalEntry = False;
        method dirtyEntryFlush = dirtyEntryFlushW;
        method forceInvalLine = forceInvalLineW;
        method reqQueueBlocked() = !newReqNotBlocked[0] && !sideReqNotBlocked[0];
        method entryAccesses = tagged Invalid;
    endinterface

endmodule


// ===================================================================
//
// Null cache implementation.  Use this to write a module that might
// have a cache without having to write two versions of the module.
//
// ===================================================================

//
// mkNullCacheDirectMapped --
//     Pass requests through directly to the source data.
//
module [m] mkNullCacheDirectMapped#(RL_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, t_CACHE_WORD, RL_DM_CACHE_READ_META#(t_CACHE_READ_META)) sourceData,
                                    DEBUG_FILE debugLog)
    // interface:
    (RL_DM_CACHE#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_READ_META))
    provisos (IsModule#(m, m__),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Bits#(t_CACHE_MASK, t_CACHE_MASK_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ));

    //
    // Consume read responses to a FIFO, mostly to support peekResp().
    //
    FIFO#(RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META)) readRespQ <- mkBypassFIFO();

    rule getReadResp (True);
        let r <- sourceData.readResp();
        readRespQ.enq(RL_DM_CACHE_LOAD_RESP { val: r.val,
                                              isCacheable: r.isCacheable,
                                              readMeta: r.readMeta.clientReadMeta,
                                              globalReadMeta: r.globalReadMeta });
    endrule

    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
        sourceData.readReq(addr,
                           RL_DM_CACHE_READ_META { isLocalPrefetch: False,
                                                   isWriteMiss: False,
                                                   clientReadMeta: readMeta },
                           globalReadMeta);
    endmethod

    method ActionValue#(RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META)) readResp();
        let r = readRespQ.first();
        readRespQ.deq();

        return r;
    endmethod

    method RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META) peekResp();
        return readRespQ.first();
    endmethod

    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val);
        debugLog.record($format("  Write: WRITE addr=0x%x, val=0x%x", addr, val));      
        sourceData.write(addr, val);
    endmethod
    
    method Action writeMasked(t_CACHE_ADDR addr, t_CACHE_WORD val,
                              t_CACHE_MASK byteWriteMask);
        error("writeMasked not supported by sourceData interface");
    endmethod

    method Action invalReq(t_CACHE_ADDR addr, Bool fullHierarchy);
        if (fullHierarchy)
            sourceData.invalReq(addr, True);
    endmethod

    method Action flushReq(t_CACHE_ADDR addr, Bool fullHierarchy);
        if (fullHierarchy)
            sourceData.flushReq(addr, True);
    endmethod

    method Action invalOrFlushWait();
        sourceData.invalOrFlushWait();
    endmethod
    
    method Action setCacheMode(RL_DM_CACHE_MODE mode, RL_DM_CACHE_PREFETCH_MODE en);
        noAction;
    endmethod
    
    interface RL_CACHE_STATS stats;
        method readHit() = tagged Invalid;
        method readMiss() = tagged Invalid;
        method readRecentLineHit() = False;    
        method writeHit() = tagged Invalid;
        method writeMiss() = tagged Invalid;
        method newMRU() = False;
        method invalEntry() = False;
        method dirtyEntryFlush() = False;
        method forceInvalLine() = False;
        method reqQueueBlocked() = False; 
        method entryAccesses = tagged Invalid;
    endinterface

endmodule
