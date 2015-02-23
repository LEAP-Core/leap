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
// Interfaces to the central cache.
//

import FIFO::*;
import Vector::*;
import SpecialFIFOs::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/provides/virtual_devices.bsh"

`include "awb/dict/VDEV.bsh"
`ifdef VDEV_CACHE__BASE
`define CACHE_BASE `VDEV_CACHE__BASE
`else
`define CACHE_BASE 0
`endif


// ========================================================================
//
// Interface for any client of the central cache.
//
// ========================================================================

//
// Interface provided to clients of the central cache is identical to the
// standard direct mapped cache interface.
//

typedef RL_DM_CACHE#(t_ADDR, t_DATA, t_READ_META)
    CENTRAL_CACHE_CLIENT#(type t_ADDR, type t_DATA, type t_READ_META);


//
// Interface for filling and spilling the cache.  An instance of this interface
// must be created by the client and passed to the central cache module.
//
interface CENTRAL_CACHE_CLIENT_BACKING#(type t_ADDR, type t_DATA, type t_READ_META);
    // Request a full line
    method Action readLineReq(t_ADDR addr,
                              t_READ_META readMeta,
                              RL_CACHE_GLOBAL_READ_META globalReadMeta);

    // The read line response is pipelined.  For every readLineReq there must
    // be one readResp for every word in the requested line.  Cache entries
    // have CENTRAL_CACHE_WORDS_PER_LINE.  Low bits of the line are received
    // first.  The bool argument indicates whether the line is cacheable.
    // The value has is consumed only in the cycle when the last word in a
    // line is transmitted.
    method ActionValue#(Tuple2#(t_DATA, Bool)) readResp();
    
    // Write to backing storage.  A write begins with a write request.
    // It is followed by multiple write data calls, one call per word
    // in a cache line.
    method Action writeLineReq(t_ADDR addr,
                               Vector#(CENTRAL_CACHE_WORDS_PER_LINE, Bool) wordValidMask,
                               Bool sendAck);

    // Called multiple times after a write request is received -- once for
    // each word in a line.  THIS METHOD WILL BE CALLED FOR A WORD EVEN
    // IF THE CONTROL INFORMATION SAYS THE WORD IS NOT VALID.  Low bits
    // of the line are sent first.
    method Action writeData(t_DATA val);

    // Ack from write request when sendAck is True
    method Action writeAckWait();
endinterface: CENTRAL_CACHE_CLIENT_BACKING


// ========================================================================
//
// Public interface to central cache.
//
// ========================================================================
    
//
// mkCentralCacheClient --
//     Make a client of the central cache.  The client defines its own address
//     and data types, which must fit in the central cache's containers.
//     The client interface uses only word-level addressing.  Methods that
//     refer to entire lines expect line-aligned addresses.
//
//     The n_ENTRIES parameter is the number of entries in a PRIVATE cache that
//     will be allocated automatically in front of the central cache.  Setting
//     n_ENTRIES to 0 instantiates a direct connection between the client and
//     the central cache with no intermediate private cache.
//
module [CONNECTED_MODULE] mkCentralCacheClient#(Integer cacheID,
                                                NumTypeParam#(n_ENTRIES) nEntries,
                                                CACHE_PREFETCHER#(UInt#(TLog#(n_ENTRIES)), t_ADDR, t_READ_META) prefetcher,
                                                Bool hashLocalCacheAddrs,
                                                CENTRAL_CACHE_CLIENT_BACKING#(t_ADDR, t_DATA, t_BACKING_READ_META) backing)
    // interface:
    (CENTRAL_CACHE_CLIENT#(t_ADDR, t_DATA, t_READ_META))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_READ_META, t_READ_META_SZ),
       
              // data must fit in central cache space
              Bits#(CENTRAL_CACHE_WORD, t_CENTRAL_CACHE_WORD_SZ),
              Add#(extraDataBits, t_DATA_SZ, t_CENTRAL_CACHE_WORD_SZ),

              // readMeta must fit in central cache space
              Bits#(CENTRAL_CACHE_READ_META, t_CENTRAL_CACHE_READ_META_SZ),
              Alias#(RL_DM_CACHE_READ_META#(t_READ_META), t_BACKING_READ_META),
              Bits#(t_BACKING_READ_META, t_BACKING_READ_META_SZ),
              Add#(extraReadMetaBits, t_BACKING_READ_META_SZ, t_CENTRAL_CACHE_READ_META_SZ),

              // Address space must fit in central cache addressing
              Bits#(CENTRAL_CACHE_LINE_ADDR, t_CENTRAL_CACHE_LINE_ADDR_SZ),
              Bits#(CENTRAL_CACHE_WORD_IDX, t_CENTRAL_CACHE_WORD_IDX_SZ),
              // Full central cache word-addressed space
              Add#(t_CENTRAL_CACHE_LINE_ADDR_SZ, t_CENTRAL_CACHE_WORD_IDX_SZ, t_CENTRAL_CACHE_WORD_ADDR_SZ),
              Add#(extraAddrBits, t_ADDR_SZ, t_CENTRAL_CACHE_WORD_ADDR_SZ));

    DEBUG_FILE debugLog <- mkDebugFile("memory_central_cache_" + integerToString(cacheID - `CACHE_BASE) + ".out");

    //
    // Function to allocate the connection between a private cache and the
    // central cache.
    //
    let centralCacheConnection <- mkCentralCacheConnection(cacheID,
                                                           backing,
                                                           debugLog);

    // Private cache
    RL_DM_CACHE#(t_ADDR, t_DATA, t_READ_META) pvtCache;
    if (valueOf(n_ENTRIES) == 0)
    begin
        pvtCache <- mkNullCacheDirectMapped(centralCacheConnection,
                                            debugLog);
    end
    else
    begin
        pvtCache <- mkCacheDirectMapped(centralCacheConnection,
                                        prefetcher,
                                        nEntries,
                                        hashLocalCacheAddrs,
                                        debugLog);
    end

    return pvtCache;
endmodule



// ========================================================================
//
// Internal modules
//
// ========================================================================
    
//
// mkCentralCacheConnection --
//     Internal module connecting the backing store interface of a direct
//     mapped cache to the central cache.  The central cache client interface
//     above allocates a direct mapped private cache and uses this module
//     to make the connection to the central cache.
//
module [CONNECTED_MODULE] mkCentralCacheConnection#(Integer cacheID,
                                                    CENTRAL_CACHE_CLIENT_BACKING#(t_ADDR, t_DATA, t_READ_META) backing,
                                                    DEBUG_FILE debugLog)
    // interface:
    (RL_DM_CACHE_SOURCE_DATA#(t_ADDR, t_DATA, t_READ_META))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_READ_META, t_READ_META_SZ),
       
              // data must fit in central cache space
              Bits#(CENTRAL_CACHE_WORD, t_CENTRAL_CACHE_WORD_SZ),
              Add#(extraDataBits, t_DATA_SZ, t_CENTRAL_CACHE_WORD_SZ),

              // readMeta must fit in central cache space
              Bits#(CENTRAL_CACHE_READ_META, t_CENTRAL_CACHE_READ_META_SZ),
              Add#(extraReadMetaBits, t_READ_META_SZ, t_CENTRAL_CACHE_READ_META_SZ),

              // Address space must fit in central cache addressing
              Bits#(CENTRAL_CACHE_LINE_ADDR, t_CENTRAL_CACHE_LINE_ADDR_SZ),
              Bits#(CENTRAL_CACHE_WORD_IDX, t_CENTRAL_CACHE_WORD_IDX_SZ),
              // Full central cache word-addressed space
              Add#(t_CENTRAL_CACHE_LINE_ADDR_SZ, t_CENTRAL_CACHE_WORD_IDX_SZ, t_CENTRAL_CACHE_WORD_ADDR_SZ),
              Add#(extraAddrBits, t_ADDR_SZ, t_CENTRAL_CACHE_WORD_ADDR_SZ));
    
    // Acquire a platform name for LI Channel disambiguation
    let platformName <- getSynthesisBoundaryPlatform();


    Connection_Client#(CENTRAL_CACHE_REQ, CENTRAL_CACHE_RESP) link_cache <- mkConnection_Client(cachePortName(cacheID, platformName));
    Connection_Server#(CENTRAL_CACHE_BACKING_REQ, CENTRAL_CACHE_BACKING_RESP) link_cache_backing <- mkConnection_Server(backingPortName(cacheID, platformName));


    function Tuple2#(CENTRAL_CACHE_LINE_ADDR, CENTRAL_CACHE_WORD_IDX) addrToCentralAddr(t_ADDR addr);
        return unpack(zeroExtend(pack(addr)));
    endfunction

    function t_ADDR centralAddrToAddr(CENTRAL_CACHE_LINE_ADDR lAddr, CENTRAL_CACHE_WORD_IDX wIdx);
        return unpack(truncate({lAddr, wIdx}));
    endfunction


    // ====================================================================
    //
    // Backing storage requests and responses
    //
    // ====================================================================

    rule backingReadLineReq (link_cache_backing.getReq() matches tagged CENTRAL_CACHE_BACK_READ .req);
        link_cache_backing.deq();

        let addr = centralAddrToAddr(req.addr, 0);
        debugLog.record($format("backReadLineReq: addr=0x%x, l_addr=0x%x", addr, req.addr));
        
        // Backing storage request requires original ref info from the client.
        t_READ_META cache_read_meta = unpack(truncate(req.readMeta));
        backing.readLineReq(addr, cache_read_meta, req.globalReadMeta);
    endrule

    rule backingReadResp (True);
        match {.val, .is_cacheable} <- backing.readResp();
        debugLog.record($format("backReadResp: val=0x%x, cacheable=%b", val, is_cacheable));

        let rsp = CENTRAL_CACHE_BACK_READ_RSP { wordVal: zeroExtend(pack(val)),
                                                isCacheable: is_cacheable };

        link_cache_backing.makeResp(tagged CENTRAL_CACHE_BACK_READ rsp);
    endrule
    
    rule backingWriteLineReq (link_cache_backing.getReq() matches tagged CENTRAL_CACHE_BACK_WREQ .req);
        link_cache_backing.deq();
        let addr = centralAddrToAddr(req.addr, 0);

        debugLog.record($format("backWrite: addr=0x%x, l_addr=0x%x, valid=0x%x", addr, req.addr, req.wordValidMask));
        
        backing.writeLineReq(addr, req.wordValidMask, req.sendAck);
    endrule

    rule backingWriteData (link_cache_backing.getReq() matches tagged CENTRAL_CACHE_BACK_WDATA .val);
        link_cache_backing.deq();

        debugLog.record($format("backWriteData: val=0x%x", val));

        backing.writeData(unpack(truncate(val)));
    endrule

    //
    // backingWriteAck --
    //     Response from backing storage that a write has arrived.  The responses
    //     returns up the cache hierarchy from the bottom to the top.
    //
    (* descending_urgency = "backingWriteAck, backingReadResp" *)
    rule backingWriteAck (True);
        backing.writeAckWait();
        debugLog.record($format("backWriteAck"));

        link_cache_backing.makeResp(tagged CENTRAL_CACHE_BACK_WACK False);
    endrule


    // ====================================================================
    //
    // Cache request methods
    //
    // ====================================================================

    // Read request
    method Action readReq(t_ADDR addr,
                          t_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
        match {.l_addr, .w_idx} = addrToCentralAddr(addr);
        let r = CENTRAL_CACHE_READ_REQ { addr: l_addr,
                                         wordIdx: w_idx,
                                         readMeta: zeroExtend(pack(readMeta)),
                                         globalReadMeta: globalReadMeta };

        link_cache.makeReq(tagged CENTRAL_CACHE_READ r);
        debugLog.record($format("readReq: addr=0x%x, l_addr=0x%x, wIdx=%0d", addr, l_addr, w_idx));
    endmethod

    // Read response
    method ActionValue#(RL_DM_CACHE_FILL_RESP#(t_ADDR, t_DATA, t_READ_META)) readResp() if (link_cache.getResp() matches tagged CENTRAL_CACHE_READ .resp);
        link_cache.deq();

        let addr = centralAddrToAddr(resp.addr, resp.wordIdx);
        t_DATA val = unpack(truncate(resp.val));
        let r = RL_DM_CACHE_FILL_RESP { addr: addr,
                                        val: val,
                                        isCacheable: resp.isCacheable,
                                        readMeta: unpack(truncate(resp.readMeta)),
                                        globalReadMeta: resp.globalReadMeta };

        debugLog.record($format("readResp: addr=0x%x, val=0x%x", addr, val));

        return r;
    endmethod

    // Read response peek
    method RL_DM_CACHE_FILL_RESP#(t_ADDR, t_DATA, t_READ_META) peekResp() if (link_cache.getResp() matches tagged CENTRAL_CACHE_READ .resp);

        let addr = centralAddrToAddr(resp.addr, resp.wordIdx);
        t_DATA val = unpack(truncate(resp.val));
        let r = RL_DM_CACHE_FILL_RESP { addr: addr,
                                        val: val,
                                        isCacheable: resp.isCacheable,
                                        readMeta: unpack(truncate(resp.readMeta)),
                                        globalReadMeta: resp.globalReadMeta };

        return r;
    endmethod

    // Write request
    method Action write(t_ADDR addr, t_DATA val);
        match {.l_addr, .w_idx} = addrToCentralAddr(addr);
        let r = CENTRAL_CACHE_WRITE_REQ { addr: l_addr,
                                          wordIdx: w_idx,
                                          val: zeroExtend(pack(val)) };

        link_cache.makeReq(tagged CENTRAL_CACHE_WRITE r);
        debugLog.record($format("write: addr=0x%x, l_addr=0x%x, wIdx=%0d, val=0x%x", addr, l_addr, w_idx, val));
    endmethod


    // Line invalidation request
    method Action invalReq(t_ADDR addr, Bool sendAck);
        match {.l_addr, .w_idx} = addrToCentralAddr(addr);
        let r = CENTRAL_CACHE_INVAL_REQ { addr: l_addr, sendAck: sendAck };

        link_cache.makeReq(tagged CENTRAL_CACHE_INVAL r);
        debugLog.record($format("inval: addr=0x%x, l_addr=0x%x, ack=%0d", addr, l_addr, sendAck));
    endmethod

    // Line flush request
    method Action flushReq(t_ADDR addr, Bool sendAck);
        match {.l_addr, .w_idx} = addrToCentralAddr(addr);
        let r = CENTRAL_CACHE_INVAL_REQ { addr: l_addr, sendAck: sendAck };

        link_cache.makeReq(tagged CENTRAL_CACHE_FLUSH r);
        debugLog.record($format("flush: addr=0x%x, l_addr=0x%x, ack=%0d", addr, l_addr, sendAck));
    endmethod

    // Line inval/flush response (blocks until ACK arrives)
    method Action invalOrFlushWait() if (link_cache.getResp() matches tagged CENTRAL_CACHE_FLUSH_ACK .dummy);
        link_cache.deq();
        debugLog.record($format("flush/inval: ACK"));
    endmethod
endmodule
