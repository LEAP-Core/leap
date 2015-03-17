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


import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import List::*;
import DefaultValue::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/local_mem.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/central_cache_service_params.bsh"

`include "awb/dict/PARAMS_CENTRAL_CACHE.bsh"


//
// Internal CENTRAL_CACHE_BACKING interface is mostly a backing storage interface
// for a set-associative cache.  In addition it has a debugging method.
//
interface CENTRAL_CACHE_BACKING#(type t_CACHE_ADDR,
                                 type t_CACHE_LINE,
                                 numeric type nWordsPerLine,
                                 type t_CACHE_READ_META);
    interface RL_SA_CACHE_SOURCE_DATA#(t_CACHE_ADDR,
                                       t_CACHE_LINE,
                                       nWordsPerLine,
                                       t_CACHE_READ_META) sourceData;
    
    // Debug info for DEBUG_SCAN
    method Bit#(4) nReadsInFlight();
endinterface: CENTRAL_CACHE_BACKING


//
// mkCentralCache --
//     Central cache using local memory.  One port is created for each
//     client.
//
module [CONNECTED_MODULE] mkCentralCache
    // interface:
    (CENTRAL_CACHE_IFC)
    provisos (Bits#(CENTRAL_CACHE_LINE_ADDR, t_CENTRAL_CACHE_LINE_ADDR_SZ),
              Bits#(CENTRAL_CACHE_PORT_NUM, t_CENTRAL_CACHE_PORT_NUM_SZ),
              Add#(t_CENTRAL_CACHE_PORT_NUM_SZ, t_CENTRAL_CACHE_LINE_ADDR_SZ, t_CENTRAL_CACHE_INTERNAL_ADDR_SZ),

              Alias#(Tuple2#(CENTRAL_CACHE_PORT_NUM, CENTRAL_CACHE_LINE_ADDR), t_CENTRAL_CACHE_INTERNAL_ADDR),

              // Compute the number of sets in the cache based on the size of local
              // memory.  The memory is broken down into 4 equal chunks:
              // 3 for the 3 ways in each set and one for a set's tag.
              Alias#(Bit#(TSub#(LOCAL_MEM_LINE_ADDR_SZ, 2)),  // 4 regions per set
                     t_CENTRAL_CACHE_SET_IDX),
              Bits#(t_CENTRAL_CACHE_SET_IDX, t_CENTRAL_CACHE_SET_IDX_SZ));

    DEBUG_FILE debugLog <- (`CENTRAL_CACHE_DEBUG_ENABLE == 1)?
                           mkDebugFile("memory_central_cache.out"):
                           mkDebugFileNull("memory_central_cache.out"); 

    DEBUG_FILE debugLogBacking <- (`CENTRAL_CACHE_DEBUG_ENABLE == 1)?
                           mkDebugFile("memory_central_cache_backing.out"):
                           mkDebugFileNull("memory_central_cache_backing.out"); 

    DEBUG_FILE debugLogInt <- (`CENTRAL_CACHE_DEBUG_ENABLE == 1)?
                             mkDebugFile("memory_central_cache_internal.out"):
                             mkDebugFileNull("memory_central_cache_internal.out"); 
   

    // Debug state
    COUNTER#(5) dbgCacheReadsInFlight <- mkLCounter(0);
    Wire#(Bool) dbgCacheReadRespReady <- mkBypassWire();
    Wire#(Bool) dbgReqLineLocked <- mkDWire(False);


    // Allocate connector between a standard cache backing storage interface
    // and a central cache backing storage port.
    Vector#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_BACKING_CONNECTION) backingStore = newVector();
    for (Integer p = 0; p < valueOf(CENTRAL_CACHE_N_CLIENTS); p = p + 1)
    begin
        backingStore[p] <- mkCentralCacheBackingConnection(p, debugLogBacking);
    end

    //
    // The cache talks to a single backing storage interface.  The module allocated
    // here routes cache requests to client ports.
    //
    CENTRAL_CACHE_BACKING#(Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ),
                           CENTRAL_CACHE_LINE,
                           CENTRAL_CACHE_WORDS_PER_LINE,
                           CENTRAL_CACHE_READ_META) backingConnection <- mkCentralCacheBacking(backingStore);


    //
    // The cache
    //
    RL_SA_CACHE_LOCAL_DATA#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ,
                            CENTRAL_CACHE_WORD,
                            CENTRAL_CACHE_WORDS_PER_LINE,
                            TExp#(t_CENTRAL_CACHE_SET_IDX_SZ),
                            3,
                            RL_SA_CACHE_DATA_READ_PORTS) cacheLocalData <- mkLocalMemCacheData(debugLogInt);

    NumTypeParam#(`CENTRAL_CACHE_LINE_RESP_CACHE_IDX_BITS) nRecentReadCacheIdxBits = ?;
    NumTypeParam#(0) nTagExtraLowBits = ?;
    RL_SA_CACHE#(Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ),
                 CENTRAL_CACHE_WORD,
                 CENTRAL_CACHE_WORDS_PER_LINE,
                 CENTRAL_CACHE_READ_META
                 ) cache <- mkCacheSetAssoc(backingConnection.sourceData,
                                            cacheLocalData,
                                            nRecentReadCacheIdxBits,
                                            nTagExtraLowBits,
                                            debugLogInt);

    // Attach statistics to the cache
   
    let cacheStats <- mkCentralCacheStats(cache.stats);
   

    // Manage routing of flush/inval ACK back to requesting port
    FIFO#(CENTRAL_CACHE_PORT_NUM) flushAckRespQ <- mkFIFO();

    //
    // addPortToAddr --
    //     Convert from a client's private address space to the global central
    //     cache address space by concatenating the port ID and the client
    //     address.
    //
    function Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ) addPortToAddr(CENTRAL_CACHE_PORT_NUM port,
                                                                  CENTRAL_CACHE_LINE_ADDR addr);
        return pack(tuple2(port, addr));
    endfunction


    // ====================================================================
    //
    // Initialization.
    //
    // ====================================================================

    // Dynamic parameters
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();
    Param#(3) centralCacheMode <- mkDynamicParameter(`PARAMS_CENTRAL_CACHE_CENTRAL_CACHE_MODE, paramNode);

    // Initialization
    Reg#(Bool) initialized <- mkReg(False);

    rule doInit (! initialized);
        // Write-back, through, or bypass
        cache.setCacheMode(unpack(centralCacheMode[1:0]));

        cache.setRecentLineCacheMode(! unpack(centralCacheMode[2]));
                          
        initialized <= True;
    endrule


    // ====================================================================
    //
    // Process incoming requests here.  All requests are merged in the
    // module's methods into a single FIFO.  This is both fair and
    // eliminates compiler warnings about rule schedule conflicts.
    //
    // ====================================================================

    MERGE_FIFOF#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_REQ) reqQ <- mkMergeFIFOF();

    (* conservative_implicit_conditions *)
    rule processWriteReq (initialized &&&
                          reqQ.first() matches tagged CENTRAL_CACHE_WRITE .r);
        CENTRAL_CACHE_PORT_NUM port = zeroExtend(reqQ.firstPortID());
        let addr = addPortToAddr(port, r.addr);

        reqQ.deq();

        debugLog.record($format("port %0d: write addr=0x%x, wIdx=%d, val=0x%x", port, r.addr, r.wordIdx, r.val));
        cache.write(addr, r.val, r.wordIdx);
    endrule


    (* conservative_implicit_conditions *)
    rule processInvalReq (initialized &&&
                          reqQ.first() matches tagged CENTRAL_CACHE_INVAL .r);
        CENTRAL_CACHE_PORT_NUM port = zeroExtend(reqQ.firstPortID());
        let addr = addPortToAddr(port, r.addr);

        reqQ.deq();

        debugLog.record($format("port %0d: inval addr=0x%x, ack=%d", port, r.addr, r.sendAck));
        cache.invalReq(addr, r.sendAck);

        if (r.sendAck)
        begin
            // Keep track of ACK requests for routing back to the port
            flushAckRespQ.enq(port);
        end
    endrule


    (* conservative_implicit_conditions *)
    rule processFlushReq (initialized &&&
                          reqQ.first() matches tagged CENTRAL_CACHE_FLUSH .r);
        CENTRAL_CACHE_PORT_NUM port = zeroExtend(reqQ.firstPortID());
        let addr = addPortToAddr(port, r.addr);

        reqQ.deq();

        debugLog.record($format("port %0d: flush addr=0x%x, ack=%d", port, r.addr, r.sendAck));
        cache.flushReq(addr, r.sendAck);

        if (r.sendAck)
        begin
            // Keep track of ACK requests for routing back to the port
            flushAckRespQ.enq(port);
        end
    endrule


    // ====================================================================
    //
    // Read pipeline.
    //
    // ====================================================================

    // Route read responses back to the correct port.
    FIFOF#(Tuple2#(CENTRAL_CACHE_PORT_NUM, CENTRAL_CACHE_READ_RESP)) readRespQ <- mkFIFOF();

    //
    // processReadReq --
    //     Forward read requests to the cache.
    //
    (* conservative_implicit_conditions *)
    rule processReadReq (initialized &&&
                         reqQ.first() matches tagged CENTRAL_CACHE_READ .r);
        CENTRAL_CACHE_PORT_NUM port = zeroExtend(reqQ.firstPortID());
        let addr = addPortToAddr(port, r.addr);

        reqQ.deq();

        debugLog.record($format("port %0d: readReq addr=0x%x, wordIdx=0x%x, readMeta=0x%x, globalReadMeta=0x%x", port, r.addr, r.wordIdx, r.readMeta, pack(r.globalReadMeta)));
        cache.readReq(addr, r.wordIdx, r.readMeta, r.globalReadMeta);

        dbgCacheReadsInFlight.up();
    endrule


    //
    // cacheReadResp --
    //     Optional 3rd stage of read request.  Forward main cache response to
    //     the client port.
    //
    rule cacheReadResp (True);
        let d <- cache.readResp();
        dbgCacheReadsInFlight.down();

        //
        // Convert internal cache response to port-specific response.
        //
        t_CENTRAL_CACHE_INTERNAL_ADDR i_addr = unpack(d.addr);
        match {.port, .addr} = i_addr;

        CENTRAL_CACHE_READ_RESP r;
        r.val = validValue(d.words[d.reqWordIdx]);
        r.addr = addr;
        r.wordIdx = d.reqWordIdx;
        r.isCacheable = d.isCacheable;
        r.readMeta = d.readMeta;
        r.globalReadMeta = d.globalReadMeta;

        // Forward data to the correct port
        readRespQ.enq(tuple2(port, r));

        debugLog.record($format("port %0d: queue readResp addr=0x%x, wordIdx=0x%x, readMeta=0x%x, globalReadMeta=0x%x", port, r.addr, r.wordIdx, r.readMeta, pack(r.globalReadMeta)));
    endrule


    //
    // debugReadRespReady --
    //     Collect debug scan info about the cache that the scheduler.  This
    //     ought to work in the method, below, but the Bluespec scheduler
    //     can't deal with it.
    //
    rule debugReadRespReady (True);
        dbgCacheReadRespReady <= cache.readRespReady();
    endrule


    // ====================================================================
    //
    // Central cache debug scan for deadlock debugging.
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    dbg_list <- addDebugScanField(dbg_list, "Reads in flight", dbgCacheReadsInFlight.value());
    dbg_list <- addDebugScanField(dbg_list, "Req line locked", dbgReqLineLocked);
    dbg_list <- addDebugScanField(dbg_list, "Num backing reads in flight", backingConnection.nReadsInFlight());
    dbg_list <- addDebugScanField(dbg_list, "readRespQ not empty", readRespQ.notEmpty());
    dbg_list <- addDebugScanField(dbg_list, "cache readRespReady", dbgCacheReadRespReady);

    // Append set associative cache pipeline state
    List#(Tuple2#(String, Bool)) sa_cache_state = cache.debugScanState();
    while (sa_cache_state matches tagged Nil ? False : True)
    begin
        let fld = List::head(sa_cache_state);
        dbg_list <- addDebugScanField(dbg_list, tpl_1(fld), tpl_2(fld));

        sa_cache_state = List::tail(sa_cache_state);
    end

    let dbgNode <- mkDebugScanNode("Central Cache (local-mem-central-cache.bsv)", dbg_list);


    // ====================================================================
    //
    // Central cache port methods.
    //
    // ====================================================================

    //
    // Allocate the interfaces.
    //

    // These vectors will be the central cache ports.
    Vector#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_CLIENT_PORT) clientPortsLocal = newVector();
    Vector#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_BACKING_PORT) backingPortsLocal = newVector();


    //
    // Allocate an interface for each port.
    //
    for (Integer p = 0; p < valueOf(CENTRAL_CACHE_N_CLIENTS); p = p + 1)
    begin
        clientPortsLocal[p] = (
            interface CENTRAL_CACHE_CLIENT_PORT;
                method Action newReq(CENTRAL_CACHE_REQ req);
                    // Add request to the FIFO.  Requests will be processed in
                    // order across all ports.
                    reqQ.ports[p].enq(req);
                endmethod

                method ActionValue#(CENTRAL_CACHE_READ_RESP) readResp() if (tpl_1(readRespQ.first()) == fromInteger(p));
                    let r = tpl_2(readRespQ.first());
                    readRespQ.deq();

                    debugLog.record($format("port %0d: readResp addr=0x%x, readMeta=0x%x, globalReadMeta=0x%x", p, r.addr, r.readMeta, pack(r.globalReadMeta)));
                    return r;
                endmethod

                method Action invalOrFlushWait() if (flushAckRespQ.first() == fromInteger(p));
                    flushAckRespQ.deq();
                    debugLog.record($format("port %0d: inval/flush done", p));

                    cache.invalOrFlushWait();
                endmethod
            endinterface
        );

        backingPortsLocal[p] = backingStore[p].backingPort;
    end
    
    interface clientPorts = clientPortsLocal;
    interface backingPorts = backingPortsLocal;
endmodule


//
// mkCentralCacheBacking --
//     Connect cache module, that talks to a single backing storage interface,
//     to individual backing storage of each client connected to the central
//     cache.  The client port ID is part of the central cache address.
//
module mkCentralCacheBacking#(Vector#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_BACKING_CONNECTION) backingStore)
    // interface:
    (CENTRAL_CACHE_BACKING#(Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ),
                            CENTRAL_CACHE_LINE,
                            CENTRAL_CACHE_WORDS_PER_LINE,
                            CENTRAL_CACHE_READ_META))
    provisos (Bits#(CENTRAL_CACHE_LINE_ADDR, t_CENTRAL_CACHE_LINE_ADDR_SZ),
              Bits#(CENTRAL_CACHE_PORT_NUM, t_CENTRAL_CACHE_PORT_NUM_SZ),
              Add#(t_CENTRAL_CACHE_PORT_NUM_SZ, t_CENTRAL_CACHE_LINE_ADDR_SZ, t_CENTRAL_CACHE_INTERNAL_ADDR_SZ),

              Alias#(Tuple2#(CENTRAL_CACHE_PORT_NUM, CENTRAL_CACHE_LINE_ADDR), t_CENTRAL_CACHE_INTERNAL_ADDR));

    FIFO#(CENTRAL_CACHE_PORT_NUM) readQ <- mkSizedFIFO(8);
    FIFO#(CENTRAL_CACHE_PORT_NUM) writeSyncQ <- mkSizedFIFO(8);

    // Debug state
    COUNTER#(4) nActiveReads <- mkLCounter(0);

    //
    // Add a buffering stage for read responses to reduce timing pressure.
    //
    FIFO#(RL_SA_CACHE_FILL_RESP#(CENTRAL_CACHE_LINE)) readRespQ <- mkFIFO();

    rule bufferReadResp (True);
        // The cache expects readReq/readResp in order.  Forward the response from
        // the appropriate central cache port.
        let r <- backingStore[readQ.first()].cacheSourceData.readResp();
        readQ.deq();
        nActiveReads.down();

        readRespQ.enq(r);
    endrule


    //
    // splitInternalAddr --
    //     Break central cache address into port ID and client address.
    //
    function t_CENTRAL_CACHE_INTERNAL_ADDR splitInternalAddr(Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ) addr);
        t_CENTRAL_CACHE_INTERNAL_ADDR i_addr = unpack(addr);
        return i_addr;
    endfunction


    interface RL_SA_CACHE_SOURCE_DATA sourceData;
        method Action readReq(Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ) addr,
                              CENTRAL_CACHE_READ_META readMeta,
                              RL_CACHE_GLOBAL_READ_META globalReadMeta);
            // Figure out from which central cache port to request the data and
            // forward the request.
            match {.i_port, .i_addr} = splitInternalAddr(addr);
            backingStore[i_port].cacheSourceData.readReq(i_addr, readMeta, globalReadMeta);

            // Note read request port ID
            readQ.enq(i_port);
            nActiveReads.up();
        endmethod

        method ActionValue#(RL_SA_CACHE_FILL_RESP#(CENTRAL_CACHE_LINE)) readResp();
            let r = readRespQ.first();
            readRespQ.deq();

            return r;
        endmethod

        // Asynchronous write (no response)
        method Action write(Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ) addr,
                            Vector#(CENTRAL_CACHE_WORDS_PER_LINE, Bool) wordValidMask,
                            CENTRAL_CACHE_LINE val);
            // Figure out to which central cache port the write should be sent.
            match {.i_port, .i_addr} = splitInternalAddr(addr);
            backingStore[i_port].cacheSourceData.write(i_addr, wordValidMask, val);
        endmethod

        // Synchronous write.  writeSyncWait() blocks until the response arrives.
        method Action writeSyncReq(Bit#(t_CENTRAL_CACHE_INTERNAL_ADDR_SZ) addr,
                                   Vector#(CENTRAL_CACHE_WORDS_PER_LINE, Bool) wordValidMask,
                                   CENTRAL_CACHE_LINE val);
            match {.i_port, .i_addr} = splitInternalAddr(addr);
            backingStore[i_port].cacheSourceData.writeSyncReq(i_addr, wordValidMask, val);

            // Note sync request port ID
            writeSyncQ.enq(i_port);
        endmethod

        method Action writeSyncWait();
            // Tell cache when write syncs send an ACK
            backingStore[writeSyncQ.first()].cacheSourceData.writeSyncWait();
            writeSyncQ.deq();
        endmethod
    endinterface

    // Debug info for DEBUG_SCAN
    method Bit#(4) nReadsInFlight();
        return nActiveReads.value();
    endmethod
endmodule



// ========================================================================
//
// Set associative cache's local memory storage.
//
// ========================================================================

//
// mkLocalMemCacheData --
//     Set associative cache local storage using local memory.
//
module [CONNECTED_MODULE] mkLocalMemCacheData#(DEBUG_FILE debugLog)
    // interface:
    (RL_SA_CACHE_LOCAL_DATA#(t_CACHE_ADDR_SZ, t_CACHE_WORD, LOCAL_MEM_WORDS_PER_LINE, nSets, nWays, nReaders))
    provisos (Bits#(t_CACHE_WORD, LOCAL_MEM_WORD_SZ),
              Alias#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, LOCAL_MEM_WORDS_PER_LINE, nSets, nWays), t_SET_METADATA),
              Bits#(t_SET_METADATA, t_SET_METADATA_SZ),
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Alias#(RL_SA_CACHE_WAY_IDX#(nWays), t_CACHE_WAY_IDX),

              // Assert size relationship of number of sets & ways to address
              Bits#(t_CACHE_SET_IDX, t_CACHE_SET_IDX_SZ),
              Bits#(t_CACHE_WAY_IDX, t_CACHE_WAY_IDX_SZ),
              Add#(t_CACHE_SET_IDX_SZ, t_CACHE_WAY_IDX_SZ, LOCAL_MEM_LINE_ADDR_SZ),

              // Assert size of data relative to local memory
              Add#(t_SET_METADATA_SZ, t_UNUSED_META_BIT_SZ, LOCAL_MEM_LINE_SZ),
              Bits#(Vector#(LOCAL_MEM_WORDS_PER_LINE, t_CACHE_WORD), LOCAL_MEM_LINE_SZ));

    //
    // Instantiate the shim to local memory.
    //
    LOCAL_MEM localMem <- mkLocalMem();

    PulseWire didWrite <- mkPulseWire();

    // ====================================================================
    //
    // Data and metadata address mapping functions.  Each set is organized
    // as a local memory line of metadata in slot 0 and the set's ways
    // in the remaining slots.  Each set is assumed to have ways equal
    // to (2^n - 1) in order to tile metadata and data efficiently.
    //
    // ====================================================================

    //
    // getDataAddr --
    //     Convert set and way into a local memory address.
    //
    function LOCAL_MEM_ADDR getDataIdx(t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        return localMemLineAddrToAddr({ pack(set), pack(way + 1) });
    endfunction


    //
    // getMetadataAddr --
    //     Convert set and way into a local memory address.
    //
    function LOCAL_MEM_ADDR getMetadataIdx(t_CACHE_SET_IDX set);
        t_CACHE_WAY_IDX metaWay = 0;
        return localMemLineAddrToAddr({ pack(set), pack(metaWay) });
    endfunction


    // ====================================================================
    //
    // Initialization
    //
    // ====================================================================

    Reg#(Bool) initialized <- mkReg(False);
    Reg#(RL_SA_CACHE_SET_IDX#(nSets)) initIdx <- mkReg(0);
    
    rule initMetaData (! initialized);
        t_SET_METADATA m_init = defaultValue;
        localMem.writeLine(getMetadataIdx(initIdx), zeroExtend(pack(m_init)));

        if (initIdx == maxBound)
        begin
            initialized <= True;
        end

        initIdx <= initIdx + 1;
    endrule


    // ====================================================================
    //
    // Set read logic.
    //
    // ====================================================================

    // Limit readers to available output buffering in order to avoid
    // deadlocks with the local memory write channel.
    let maxRead = 8;
    COUNTER#(4) activeReadCnt <- mkLCounter(maxRead);

    FIFO#(Tuple2#(t_CACHE_SET_IDX, Bool)) setReqQ <- mkBypassFIFO();
    FIFOF#(Tuple2#(Bit#(TLog#(RL_SA_CACHE_DATA_READ_PORTS)),
                   t_CACHE_WAY_IDX)) wayReqQ <- mkFIFOF();
    Reg#(t_CACHE_WAY_IDX) setReqWayIdx <- mkReg(0);
    FIFO#(Bool) readIsMetaQ <- mkSizedFIFO(32);

    // Hold the prefetched set
    Reg#(Vector#(nWays, CENTRAL_CACHE_LINE)) prefetchSetBuf <- mkRegU();
    Reg#(t_CACHE_WAY_IDX) setRspWayIdx <- mkReg(0);
    FIFO#(Vector#(nWays, CENTRAL_CACHE_LINE)) setRspQ <- mkSizedFIFO(maxRead);

    // Final buffers for read data
    FIFOF#(t_SET_METADATA) metaRspQ <- mkSizedFIFOF(maxRead);
    FIFOF#(Tuple2#(Bit#(TLog#(RL_SA_CACHE_DATA_READ_PORTS)),
                   CENTRAL_CACHE_LINE)) dataRspQ <- mkBypassFIFOF();

    //
    // memReadReq --
    //   Receive a request to read a set.  Iterate multiple times over each
    //   request in order to prefetch metadata and all ways.
    //
    rule memReadReq (initialized && ! didWrite && (activeReadCnt.value != 0));
        match {.set, .prefetch_set} = setReqQ.first();

        // Read a way (or metadata if setReqWayIdx is 0)
        LOCAL_MEM_ADDR addr = localMemLineAddrToAddr({ pack(set), pack(setReqWayIdx) });
        localMem.readLineReq(addr);
        readIsMetaQ.enq(setReqWayIdx == 0);

        // Prefetch the entire set
        if (! prefetch_set || (setReqWayIdx == fromInteger(valueOf(nWays))))
        begin
            // Not prefetching or set is now fully prefetched
            setReqQ.deq();
            setReqWayIdx <= 0;
        end
        else
        begin
            setReqWayIdx <= setReqWayIdx + 1;
        end
    endrule

    //
    // fwdMetaReadRsp --
    //   Forward metadata read from local memory to the response queue.
    //
    rule fwdMetaReadRsp (readIsMetaQ.first());
        let val <- localMem.readLineRsp();
        readIsMetaQ.deq();

        metaRspQ.enq(unpack(truncate(val)));
    endrule

    //
    // fwdMemReadRsp --
    //   Forward prefetched ways to an intermediate queue.
    //
    rule fwdMemReadRsp (! readIsMetaQ.first());
        let val <- localMem.readLineRsp();
        readIsMetaQ.deq();

        let set_val = shiftInAtN(prefetchSetBuf, unpack(val));
        prefetchSetBuf <= set_val;

        // Have all ways for a set arrived?
        if (setRspWayIdx == fromInteger(valueOf(TSub#(nWays, 1))))
        begin
            // Yes
            setRspWayIdx <= 0;
            setRspQ.enq(set_val);
        end
        else
        begin
            // No.  Keep collecting ways.
            setRspWayIdx <= setRspWayIdx + 1;
        end
    endrule

    //
    // memGetWay --
    //   Pick the requested way from the prefetched set data and route
    //   to the requested response port.
    //
    rule memGetWay (True);
        match {.port, .way} = wayReqQ.first();
        wayReqQ.deq();

        let val = setRspQ.first();
        setRspQ.deq();

        dataRspQ.enq(tuple2(port, val[way]));
    endrule


    //
    // Data read ports.  These ports return ways prefetched as a side-effect
    // of calling setReadReq().
    //
    Vector#(nReaders,
            MEMORY_READER_IFC#(RL_SA_CACHE_WAY_IDX#(nWays),
                               Vector#(LOCAL_MEM_WORDS_PER_LINE,
                                       t_CACHE_WORD))) dataReadPorts = newVector();

    for (Integer p = 0; p < valueOf(nReaders); p = p + 1)
    begin
        dataReadPorts[p] =
           (interface MEMORY_READER_IFC#(RL_SA_CACHE_WAY_IDX#(nWays),
                                         Vector#(LOCAL_MEM_WORDS_PER_LINE,
                                                 t_CACHE_WORD));
                method Action readReq(RL_SA_CACHE_WAY_IDX#(nWays) way);
                    wayReqQ.enq(tuple2(fromInteger(p), way));
                endmethod

                method ActionValue#(Vector#(LOCAL_MEM_WORDS_PER_LINE, t_CACHE_WORD)) readRsp() if (tpl_1(dataRspQ.first()) == fromInteger(p));
                    let val = tpl_2(dataRspQ.first());
                    dataRspQ.deq();

                    return unpack(val);
                endmethod

                method Vector#(LOCAL_MEM_WORDS_PER_LINE, t_CACHE_WORD) peek() = unpack(tpl_2(dataRspQ.first()));

                method Bool notEmpty() = dataRspQ.notEmpty();
                method Bool notFull() = wayReqQ.notFull();
            endinterface);
    end

    interface dataRead = dataReadPorts;


    //
    // Metadata access methods
    //
    method Action setReadReq(RL_SA_CACHE_SET_IDX#(nSets) set,
                             Bool prefetchSet);
        setReqQ.enq(tuple2(set, prefetchSet));
        activeReadCnt.up();
    endmethod

    // Set's metadata, returned as a response to setReadReq().
    method ActionValue#(t_SET_METADATA) metaReadRsp();
        let meta = metaRspQ.first();
        metaRspQ.deq();
        activeReadCnt.down();

        return meta;
    endmethod

    method Bool metaReadNotEmpty() = metaRspQ.notEmpty();


    method Action metaWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, LOCAL_MEM_WORDS_PER_LINE, nSets, nWays) metaUpd) if (initialized);
        localMem.writeLine(getMetadataIdx(set), zeroExtend(pack(metaUpd)));
        didWrite.send();
    endmethod    

    method Action dataWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_WAY_IDX#(nWays) way,
                            Vector#(LOCAL_MEM_WORDS_PER_LINE, Bool) wordMask,
                            Vector#(LOCAL_MEM_WORDS_PER_LINE, t_CACHE_WORD) val) if (initialized);
        // The memory interface uses byte write masks.  Convert the word mask
        // to bytes.
        Vector#(LOCAL_MEM_WORDS_PER_LINE,
                Vector#(LOCAL_MEM_BYTES_PER_WORD, Bool)) byte_mask = newVector();
        for (Integer w = 0; w < valueOf(LOCAL_MEM_WORDS_PER_LINE); w = w + 1)
        begin
            byte_mask[w] = replicate(wordMask[w]);
        end

        localMem.writeLineMasked(getDataIdx(set, way),
                                 zeroExtend(pack(val)),
                                 byte_mask);
        didWrite.send();
    endmethod

    method Action dataWriteWord(RL_SA_CACHE_SET_IDX#(nSets) set,
                                RL_SA_CACHE_WAY_IDX#(nWays) way,
                                Bit#(TLog#(LOCAL_MEM_WORDS_PER_LINE)) wordIdx,
                                t_CACHE_WORD val) if (initialized);
        LOCAL_MEM_ADDR addr = getDataIdx(set, way) | zeroExtendNP(wordIdx);
        localMem.writeWord(addr, zeroExtend(pack(val)));
        didWrite.send();
    endmethod

endmodule
