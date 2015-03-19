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

import Vector::*;
import List::*;
import DefaultValue::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/fpga_components.bsh"

module [CONNECTED_MODULE] mkCentralCacheWithBRAMCache#(RL_SA_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_CACHE_READ_META) sourceData,
                                                       RL_SA_CACHE_LOCAL_DATA#(t_CACHE_ADDR_SZ, t_CACHE_WORD, nWordsPerLine, nSets, nWays, nReaders) localData,
                                                       NumTypeParam#(t_RECENT_READ_CACHE_IDX_SZ) param0,
                                                       NumTypeParam#(nTagExtraLowBits) param1,
                                                       DEBUG_FILE debugLog,
                                                       DEBUG_FILE debugLogBRAM)
    // interface:
        (RL_SA_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_LINE, t_CACHE_LINE_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              Alias#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META), t_CACHE_LOAD_RESP),
              Alias#(Bit#(TLog#(nWordsPerLine)), t_CACHE_WORD_IDX),
              Mul#(nWordsPerLine, t_CACHE_WORD_SZ, t_CACHE_LINE_SZ),
              Add#(t_CACHE_ADDR_SZ, a__, 128),
              Add#(TLog#(nSets), b__, 32),
              Add#(TLog#(TDiv#(TExp#(TLog#(nSets)), 2)), x__, TLog#(nSets)));
              
    RL_SA_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META) cache <-
        mkCacheSetAssoc(sourceData, localData, param0, param1, False, True, debugLog);
    
    NumTypeParam#(TExp#(`CENTRAL_CACHE_BRAM_CACHE_SET_IDX_BTIS)) nBramCacheSets = ?;
    NumTypeParam#(TExp#(`CENTRAL_CACHE_BRAM_CACHE_WAY_IDX_BTIS)) nBramCacheWays = ?;
    RL_SA_BRAM_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), 
                                  t_CACHE_LINE, 
                                  nWordsPerLine, 
                                  Bit#(TLog#(RL_SA_BRAM_CACHE_MAF_ENTRIES))) bramCacheSourceData <- mkCentralCacheBRAMCacheSourceData(cache);

    RL_SA_BRAM_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META) bramCache <-
        mkCacheSetAssocWithBRAM(bramCacheSourceData, nBramCacheSets, nBramCacheWays, param1, debugLogBRAM);

    let bramCacheStats <- mkCentralCacheBRAMCacheStats(bramCache.stats);
    
    // ====================================================================
    //
    // Central cache bram cache debug scan for deadlock debugging.
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    List#(Tuple2#(String, Bool)) sa_cache_state = bramCache.debugScanState();
    while (sa_cache_state matches tagged Nil ? False : True)
    begin
        let fld = List::head(sa_cache_state);
        dbg_list <- addDebugScanField(dbg_list, tpl_1(fld), tpl_2(fld));
        sa_cache_state = List::tail(sa_cache_state);
    end

    let dbgNode <- mkDebugScanNode("Central Cache Bram Cache (local-mem-central-cache-with-bram-cache.bsv)", dbg_list);
    
    // ====================================================================
    //
    // Methods
    //
    // ====================================================================
    
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
        bramCache.readReq(addr, wordIdx, readMeta, globalReadMeta);
    endmethod

    method Action readLineReq(t_CACHE_ADDR addr,
                              t_CACHE_READ_META readMeta,
                              RL_CACHE_GLOBAL_READ_META globalReadMeta);
        noAction;
    endmethod


    method ActionValue#(t_CACHE_LOAD_RESP) readResp();
        let r <- bramCache.readResp();
        return r;
    endmethod

    method t_CACHE_ADDR peekRespAddr() = bramCache.peekRespAddr();

    method Bool readRespReady() = bramCache.readRespReady();

    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_WORD_IDX wordIdx);
        bramCache.write(addr, val, wordIdx);
    endmethod

    method Action writeLine(t_CACHE_ADDR addr, Vector#(nWordsPerLine, Bool) wordValidMask, Vector#(nWordsPerLine, t_CACHE_WORD) val);
        noAction;
    endmethod

    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
        bramCache.invalReq(addr, sendAck);
    endmethod
    
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
        bramCache.flushReq(addr, sendAck);
    endmethod

    method Action invalOrFlushWait();
        bramCache.invalOrFlushWait();
    endmethod

    method Action setCacheMode(RL_SA_CACHE_MODE mode);
        cache.setCacheMode(mode);
        bramCache.setCacheMode(mode);
    endmethod

    method Action setRecentLineCacheMode(Bool enabled);
        cache.setRecentLineCacheMode(enabled);
    endmethod

    method List#(Tuple2#(String, Bool)) debugScanState() = cache.debugScanState;
    interface RL_CACHE_STATS stats = cache.stats;

endmodule


module [CONNECTED_MODULE] mkCentralCacheBRAMCacheSourceData#(RL_SA_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META) cache)
    // interface:
    (RL_SA_BRAM_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_CACHE_META))
    provisos (Bits#(t_CACHE_LINE, t_CACHE_LINE_SZ),
              Bits#(t_CACHE_META, t_CACHE_META_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Mul#(nWordsPerLine, t_CACHE_WORD_SZ, t_CACHE_LINE_SZ),
              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              Alias#(RL_SA_BRAM_CACHE_FILL_RESP#(t_CACHE_LINE, Bit#(t_CACHE_ADDR_SZ), t_CACHE_META), t_CACHE_FILL_RESP));


    // Read request and response with data
    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
        cache.readLineReq(addr, unpack(zeroExtendNP(pack(readMeta))), globalReadMeta);
    endmethod

    method ActionValue#(t_CACHE_FILL_RESP) readResp();
        let r <- cache.readResp();
        t_CACHE_FILL_RESP resp;
        
        Vector#(nWordsPerLine, t_CACHE_WORD) vals = newVector();
        for (Integer w = 0; w < valueOf(nWordsPerLine); w = w + 1)
            vals[w] = fromMaybe(?, r.words[w]);
        resp.val = unpack(pack(vals));
        resp.addr = r.addr;
        resp.isCacheable = r.isCacheable;    
        resp.readMeta = unpack(resize(pack(r.readMeta)));
        resp.globalReadMeta = r.globalReadMeta;
        return resp;
    endmethod
    
    method Action write(t_CACHE_ADDR addr, 
                        Vector#(nWordsPerLine, Bool) wordValidMask, 
                        t_CACHE_LINE val);
        
        cache.writeLine(addr, wordValidMask, unpack(pack(val)));
    endmethod
    
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
        cache.invalReq(addr, sendAck);
    endmethod
    
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
        cache.flushReq(addr, sendAck);
    endmethod
    
    method Action invalOrFlushWait();
        cache.invalOrFlushWait();
    endmethod

endmodule

// ===================================================================
//
// Statistics Interface
//
// ===================================================================

module [CONNECTED_MODULE] mkCentralCacheBRAMCacheStats#(RL_CACHE_STATS cacheStats)
    // interface:
    ();

    // Disambiguate central caches on multiple platforms    
    String platform <- getSynthesisBoundaryPlatform();

    STAT_ID statIDs[8];

    statIDs[0] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_LOAD_HIT_" + platform,
                          "Central Cache: Load hits");
    let statLoadHit = 0;

    statIDs[1] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_LOAD_MISS_" + platform,
                          "Central Cache: Load misses");
    let statLoadMiss = 1;

    statIDs[2] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_STORE_HIT_" + platform,
                          "Central Cache: Store hits");
    let statStoreHit  = 2;

    statIDs[3] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_STORE_MISS_" + platform,
                          "Central Cache: Store misses");
    let statStoreMiss = 3;

    statIDs[4] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_INVAL_LINE_" + platform,
                          "Central Cache: Lines invalidated due to capacity");
    let statInvalEntry = 4;

    statIDs[5] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_DIRTY_LINE_FLUSH_" + platform,
                          "Central Cache: Dirty lines flushed to memory");
    let statDirtyEntryFlush = 5;

    statIDs[6] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_FORCE_INVAL_LINE_" + platform,
                          "Central Cache: Lines forcibly invalidated (not due to capacity)");
    let statForceInvalLine = 6;

    statIDs[7] = statName("LEAP_CENTRAL_CACHE_BRAM_CACHE_LOAD_NEW_MRU_" + platform,
                          "Central Cache: Reference changed MRU way for valid entry (hit)");
    let statNewMRU = 7;

    STAT_VECTOR#(8) stats <- mkStatCounter_Vector(statIDs);

    rule readHit (cacheStats.readHit());
        stats.incr(statLoadHit);
    endrule

    rule readMiss (cacheStats.readMiss());
        stats.incr(statLoadMiss);
    endrule

    rule writeHit (cacheStats.writeHit());
        stats.incr(statStoreHit);
    endrule

    rule writeMiss (cacheStats.writeMiss());
        stats.incr(statStoreMiss);
    endrule

    rule invalEntry (cacheStats.invalEntry());
        stats.incr(statInvalEntry);
    endrule

    rule dirtyEntryFlush (cacheStats.dirtyEntryFlush());
        stats.incr(statDirtyEntryFlush);
    endrule

    rule forceInvalLine (cacheStats.forceInvalLine());
        stats.incr(statForceInvalLine);
    endrule

    rule newMRU (cacheStats.newMRU());
        stats.incr(statNewMRU);
    endrule

endmodule
