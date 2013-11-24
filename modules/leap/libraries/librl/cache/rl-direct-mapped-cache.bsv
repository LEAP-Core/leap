//
// Copyright (C) 2009 Intel Corporation
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
    
    interface RL_CACHE_STATS stats;

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
       
//
// Index of the write data heap index.  To save space, write data is passed
// through the cache pipelines as a pointer.  The heap size limits the number
// of writes in flight.  Writes never wait for a fill, so the heap doesn't
// have to be especially large.
//
typedef Bit#(2) RL_DM_WRITE_DATA_HEAP_IDX;


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
   RL_DM_WRITE_DATA_HEAP_IDX writeDataIdx;
 
   // Flush / inval info
   Bool fullHierarchy;

   // Hashed address and tag, passed through the pipeline instead of recomputed.
   t_CACHE_TAG tag;
   t_CACHE_IDX idx;
}
RL_DM_CACHE_REQ#(type t_CACHE_ADDR, type t_CACHE_READ_META,
                 type t_CACHE_TAG, type t_CACHE_IDX)
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
    t_CACHE_READ_META clientReadMeta;
}
RL_DM_CACHE_READ_META#(type t_CACHE_READ_META)
    deriving (Eq, Bits);


// ===================================================================
//
// Cache implementation
//
// ===================================================================

//
// mkCacheDirectMapped --
//   n_ENTRIES parameter defines the number of entries in the cache.  The true
//   number of entries will be rounded up to a power of 2.
//
module [m] mkCacheDirectMapped#(RL_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, t_CACHE_WORD, RL_DM_CACHE_READ_META#(t_CACHE_READ_META)) sourceData,
                                CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_READ_META) prefetcher,
                                NumTypeParam#(n_ENTRIES) dummy,
                                Bool hashAddresses,
                                DEBUG_FILE debugLog)
    // interface:
    (RL_DM_CACHE#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_READ_META))
    provisos (IsModule#(m, m__),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),

              // Entry index.  Round n_ENTRIES request up to a power of 2.
              Log#(n_ENTRIES, t_CACHE_IDX_SZ),
              Alias#(RL_DM_CACHE_IDX#(t_CACHE_IDX_SZ), t_CACHE_IDX),

              // Tag is the address bits other than the entry index
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, t_CACHE_IDX_SZ)), t_CACHE_TAG),
              Alias#(Maybe#(RL_DM_CACHE_ENTRY#(t_CACHE_WORD, t_CACHE_TAG)), t_CACHE_ENTRY),

              Alias#(RL_DM_CACHE_REQ#(t_CACHE_ADDR, t_CACHE_READ_META, t_CACHE_TAG, t_CACHE_IDX), t_CACHE_REQ),
              Alias#(RL_DM_CACHE_LOAD_RESP#(t_CACHE_WORD, t_CACHE_READ_META), t_CACHE_LOAD_RESP),
       
              // Required by the compiler:
              Bits#(t_CACHE_LOAD_RESP, t_CACHE_LOAD_RESP_SZ),
              Bits#(t_CACHE_TAG, t_CACHE_TAG_SZ));
    
    Reg#(RL_DM_CACHE_MODE) cacheMode <- mkReg(RL_DM_MODE_WRITE_BACK);
    Reg#(RL_DM_CACHE_PREFETCH_MODE) prefetchMode <- mkReg(RL_DM_PREFETCH_DISABLE);
    
    // Cache data and tag
    BRAM#(t_CACHE_IDX, t_CACHE_ENTRY) cache <- mkBRAMInitialized(tagged Invalid);

    // Track busy entries
    COUNTING_FILTER#(t_CACHE_IDX, 0) entryFilter <- mkCountingFilter(debugLog);

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(RL_DM_WRITE_DATA_HEAP_IDX, t_CACHE_WORD) reqInfo_writeData <- mkMemoryHeapUnionLUTRAM();

    // Incoming data.  One method may fire at a time.
    FIFOF#(t_CACHE_REQ) newReqQ <- mkFIFOF();

    // Pipelines
    FIFO#(t_CACHE_REQ) cacheLookupQ <- mkFIFO();
    FIFO#(t_CACHE_REQ) fillReqQ <- mkFIFO();
    FIFO#(t_CACHE_REQ) invalQ <- mkFIFO();

    FIFO#(t_CACHE_LOAD_RESP) readRespQ <- mkBypassFIFO();
    
    // Wires for communicating stats
    PulseWire readHitW         <- mkPulseWire();
    PulseWire dirtyEntryFlushW <- mkPulseWire();
    PulseWire readMissW        <- mkPulseWire();
    PulseWire writeHitW        <- mkPulseWire();
    PulseWire forceInvalLineW  <- mkPulseWire();

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
    LUTRAM#(Bit#(5), Bit#(2)) sideReqFilter <- mkLUTRAM(0);
    Reg#(Bit#(2)) newReqArb <- mkReg(0);

    Wire#(Tuple2#(RL_DM_CACHE_REQ_TYPE, t_CACHE_REQ)) pickReq <- mkWire();
    Wire#(Tuple3#(RL_DM_CACHE_REQ_TYPE, t_CACHE_REQ, Maybe#(CF_OPAQUE#(t_CACHE_IDX, 0))))
        curReq <- mkWire();

    (* fire_when_enabled, no_implicit_conditions *)
    rule incrReqArb (True);
        newReqArb <= newReqArb + 1;
    endrule

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
        
        Bool pick_new_req = newReqQ.notEmpty &&
                            ((newReqArb != 0) || ! sideReqQ.notEmpty);

        t_CACHE_REQ r = ?;
        RL_DM_CACHE_REQ_TYPE req_type;
        
        if ( prefetchMode == RL_DM_PREFETCH_ENABLE && prefetcher.hasReq() && 
           ((!newReqQ.notEmpty && !sideReqQ.notEmpty) || 
           ((newReqArb > 2) && (prefetcher.peekReq().prio == PREFETCH_PRIO_LOW)) || 
           ((newReqArb > 1) && (prefetcher.peekReq().prio == PREFETCH_PRIO_HIGH))))
        begin
            req_type      = DM_CACHE_PREFETCH_REQ;
            let pref_req  = prefetcher.peekReq();
            r.act         = DM_CACHE_READ;
            r.addr        = pref_req.addr;
            r.readMeta    = RL_DM_CACHE_READ_META { isLocalPrefetch: True,
                                                    clientReadMeta: pref_req.readMeta };
            r.globalReadMeta  = defaultValue();
            r.globalReadMeta.isPrefetch = True;
            match {.tag, .idx} = cacheEntryFromAddr(pref_req.addr);
            r.tag = tag;
            r.idx = idx;
            debugLog.record($format("    pick prefetch req: addr=0x%x, entry=0x%x", r.addr, idx));
        end
        else
        begin
            r = pick_new_req ? newReqQ.first() : sideReqQ.first();
            req_type = pick_new_req ? DM_CACHE_NEW_REQ : DM_CACHE_SIDE_REQ;
        end
        
        pickReq <= tuple2(req_type, r);
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
        match {.req_type, .r} = pickReq;
        
        // In order to preserve read/write and write/write order, the
        // request must either come from the side buffer or be a new request
        // referencing a line not already in the side buffer.
        //
        // The array sideReqFilter tracks lines active in the side request
        // queue.
        if ((req_type == DM_CACHE_SIDE_REQ) ||
            (sideReqFilter.sub(resize(cacheIdx(r))) == 0))
        begin
            curReq <= tuple3(req_type, r, entryFilter.test(cacheIdx(r)));
        end
        else
        begin
            curReq <= tuple3(req_type, r, tagged Invalid);
        end
    endrule


    //
    // startReq --
    //     Start the current request if the line is not busy.
    //
    (* fire_when_enabled *)
    rule startReq (tpl_3(curReq) matches tagged Valid .filter_state);
        match {.req_type, .r, .cf_opaque} = curReq;
        let idx = cacheIdx(r);

        entryFilter.set(filter_state);

        debugLog.record($format("    %s: addr=0x%x, entry=0x%x",
                                req_type == DM_CACHE_NEW_REQ ? "startNewReq" : 
                                ( req_type == DM_CACHE_SIDE_REQ ? "startSideReq" :
                                  "startPrefetchReq" ), r.addr, idx));

        // Read the entry either to return the value (READ) or to see whether
        // the entry is dirty and flush it.
        cache.readReq(idx);
        cacheLookupQ.enq(r);

        if (req_type == DM_CACHE_NEW_REQ)
        begin
            newReqQ.deq();
        end
        else if (req_type == DM_CACHE_SIDE_REQ)
        begin
            sideReqQ.deq();
            sideReqFilter.upd(resize(idx), sideReqFilter.sub(resize(idx)) - 1);
        end
        else
        begin
            let pf_req <- prefetcher.getReq();
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
    (* fire_when_enabled *)
    rule shuntNewReq (tpl_1(curReq) == DM_CACHE_NEW_REQ &&
                      ! tpl_2(curReq).globalReadMeta.orderedSourceDataReqs &&
                      (sideReqFilter.sub(resize(cacheIdx(tpl_2(curReq)))) != maxBound) &&
                      ! isValid(tpl_3(curReq)) &&
                      (cacheMode != RL_DM_MODE_DISABLED));
        match {.req_type, .r, .cf_opaque} = curReq;
        let idx = cacheIdx(r);

        debugLog.record($format("    shunt busy line req: addr=0x%x, entry=0x%x", r.addr, idx));

        sideReqQ.enq(r);
        newReqQ.deq();

        // Note line present in sideReqQ
        sideReqFilter.upd(resize(idx), sideReqFilter.sub(resize(idx)) + 1);
        
        if (prefetchMode == RL_DM_PREFETCH_ENABLE)
        begin
            prefetcher.shuntNewCacheReq(idx, r.addr);
        end
    endrule
    
    //
    // For collecting prefetch stats
    //
    (* fire_when_enabled *)
    rule dropPrefetchReqByBusy ( tpl_1(curReq) == DM_CACHE_PREFETCH_REQ && 
                                 !isValid(tpl_3(curReq)) );
        let pf_req <- prefetcher.getReq();
        debugLog.record($format("    Prefetch req dropped by busy: addr=0x%x", tpl_2(curReq).addr));
        prefetcher.prefetchDroppedByBusy(tpl_2(curReq).addr);
    endrule


    // ====================================================================
    //
    // Read path
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule lookupRead (cacheLookupQ.first().act == DM_CACHE_READ);
        let r = cacheLookupQ.first();
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cache.readRsp();

        Bool needFill = True;

        if (cacheMode != RL_DM_MODE_DISABLED &&& cur_entry matches tagged Valid .e)
        begin
            if (e.tag == tag) // Hit!
            begin
                debugLog.record($format("    lookupRead: HIT addr=0x%x, entry=0x%x, val=0x%x", r.addr, idx, e.val));
                // Ignore prefetch hit response and prefetch hit status
                if (! r.readMeta.isLocalPrefetch)
                begin
                    readHitW.send();
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
                entryFilter.remove(idx);
                needFill = False;
            end
            else if (e.dirty)
            begin
                // Miss.  Need to flush old data?
                let old_addr = cacheAddrFromEntry(e.tag, idx);
                debugLog.record($format("    doWrite: FLUSH addr=0x%x, entry=0x%x, val=0x%x", old_addr, idx, e.val));
                sourceData.write(old_addr, e.val);
                dirtyEntryFlushW.send();
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


    //
    // fillReq --
    //     Request fill from backing storage.
    //
    rule fillReq (True);
        let r = fillReqQ.first();
        fillReqQ.deq();

        debugLog.record($format("    fillReq: addr=0x%x", r.addr));

        if (! r.readMeta.isLocalPrefetch)
        begin
            readMissW.send();
        end

        sourceData.readReq(r.addr, r.readMeta, r.globalReadMeta);
    endrule
    

    //
    // fillResp --
    //     Fill response.  Fill responses may return out of order relative to
    //     requests.
    //
    rule fillResp (True);
        let f <- sourceData.readResp();
        
        match {.tag, .idx} = cacheEntryFromAddr(f.addr);

        debugLog.record($format("    fillResp: FILL addr=0x%x, entry=0x%x, cacheable=%b, val=0x%x", f.addr, idx, f.isCacheable, f.val));

        if (! f.readMeta.isLocalPrefetch)
        begin
            t_CACHE_LOAD_RESP resp;
            resp.val = f.val;
            resp.isCacheable = f.isCacheable;
            resp.readMeta = f.readMeta.clientReadMeta;
            resp.globalReadMeta = f.globalReadMeta;
            readRespQ.enq(resp);
        end
        
        // Save value in cache
        if (f.isCacheable)
        begin
            cache.write(idx, tagged Valid RL_DM_CACHE_ENTRY { dirty: False,
                                                              tag: tag,
                                                              val: f.val });

            prefetcher.fillResp(idx, f.addr,
                                f.readMeta.isLocalPrefetch,
                                f.readMeta.clientReadMeta);
        end
        else if (f.readMeta.isLocalPrefetch)
        begin
            prefetcher.prefetchIllegalReq();
        end

        entryFilter.remove(idx);
    endrule


    // ====================================================================
    //
    // Write path
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule doWrite (cacheLookupQ.first().act == DM_CACHE_WRITE);
        let r = cacheLookupQ.first();
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cache.readRsp();

        // New data to write
        let w_data = reqInfo_writeData.sub(r.writeDataIdx);
        reqInfo_writeData.free(r.writeDataIdx);

        if (cacheMode != RL_DM_MODE_WRITE_BACK)
        begin
            // Caching writes is disabled.  Write through or around.
            debugLog.record($format("    doWrite: WRITE THROUGH addr=0x%x, entry=0x%x, val=0x%x", r.addr, idx, w_data));
            sourceData.write(r.addr, w_data);
        end
        else if (cur_entry matches tagged Valid .e &&&
                 e.dirty &&&
                 e.tag != tag)
        begin
            // Dirty data must be flushed
            let old_addr = cacheAddrFromEntry(e.tag, idx);
            debugLog.record($format("    doWrite: FLUSH addr=0x%x, entry=0x%x, val=0x%x", old_addr, idx, e.val));

            sourceData.write(old_addr, e.val);
            dirtyEntryFlushW.send();
        end

        // Now do the write.  The write may be skipped in NO ALLOC mode as long
        // as the current cache entry isn't for the address being written.
        if ((cacheMode != RL_DM_MODE_WRITE_NO_ALLOC) ||
            (isValid(cur_entry) && (validValue(cur_entry).tag == tag)))
        begin
            debugLog.record($format("    doWrite: WRITE addr=0x%x, entry=0x%x, val=0x%x", r.addr, idx, w_data));

            writeHitW.send();
            cache.write(idx, tagged Valid RL_DM_CACHE_ENTRY { dirty: (cacheMode == RL_DM_MODE_WRITE_BACK),
                                                              tag: tag,
                                                              val: w_data });
            if (prefetchMode == RL_DM_PREFETCH_ENABLE)
            begin
                prefetcher.prefetchInval(idx);
            end
        end

        entryFilter.remove(idx);
    endrule


    // ====================================================================
    //
    // Inval / flush path
    //
    // ====================================================================

    (* conservative_implicit_conditions *)
    rule evictForInval ((cacheLookupQ.first().act == DM_CACHE_INVAL) ||
                        (cacheLookupQ.first().act == DM_CACHE_FLUSH));
        let r = cacheLookupQ.first();
        cacheLookupQ.deq();

        let idx = cacheIdx(r);
        let tag = cacheTag(r);

        let cur_entry <- cache.readRsp();

        if (cur_entry matches tagged Valid .e &&& (e.tag == tag))
        begin
            forceInvalLineW.send();

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


    (* descending_urgency = "fillResp, fillReq, lookupRead, doWrite, finishInval, evictForInval" *)
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

        entryFilter.remove(idx);
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
        let data_idx <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(data_idx, val);

        t_CACHE_REQ r = ?;
        r.act = DM_CACHE_WRITE;
        r.addr = addr;
        r.readMeta = ?;
        r.globalReadMeta = ?;
        r.writeDataIdx = data_idx;

        match {.tag, .idx} = cacheEntryFromAddr(addr);
        r.tag = tag;
        r.idx = idx;

        newReqQ.enq(r);

        debugLog.record($format("  New request: WRITE addr=0x%x, wData heap=%0d, val=0x%x", addr, data_idx, val));
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
        method Bool readHit() = readHitW;
        method Bool readMiss() = readMissW;
        method Bool readRecentLineHit() = False;    
        method Bool writeHit() = writeHitW;
        method Bool writeMiss() = False;
        method Bool newMRU() = False;
        method Bool invalEntry() = False;
        method Bool dirtyEntryFlush() = dirtyEntryFlushW;
        method Bool forceInvalLine() = forceInvalLineW;
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
    (RL_DM_CACHE#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_READ_META))
    provisos (IsModule#(m, m__),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
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
        method Bool readHit() = False;
        method Bool readMiss() = False;
        method Bool readRecentLineHit() = False;    
        method Bool writeHit() = False;
        method Bool writeMiss() = False;
        method Bool newMRU() = False;
        method Bool invalEntry() = False;
        method Bool dirtyEntryFlush() = False;
        method Bool forceInvalLine() = False;
    endinterface

endmodule
