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

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_service.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/PARAMS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/VDEV.bsh"

// ========================================================================
//
// Coherent scratchpad controller with private caches 
//
// ========================================================================

//
// Coherence message type 
//
typedef enum
{
    COH_MSG_GETS  = 0,
    COH_MSG_GETX  = 1,
    COH_MSG_PUTX  = 2,
    COH_MSG_RESP  = 3,
    COH_MSG_FWD   = 4
}
COH_SCRATCH_MSG_TYPE
    deriving (Eq, Bits);

//
// Coherence controller's RSHR (Request Status Handling Registers) request 
// passed through the pipeline
//
typedef struct
{
    COH_SCRATCH_PORT_NUM        requester;
    COH_SCRATCH_CTRLR_PORT_NUM  reqControllerId;
    COH_SCRATCH_MSG_TYPE        reqType;
    t_RSHR_ADDR                 addr;
    COH_SCRATCH_MEM_VALUE       val;
    COH_SCRATCH_CLIENT_META     clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
    t_RSHR_IDX                  idx;
    t_RSHR_TAG                  tag;
    Bool                        isCleanWB;
    Bool                        isExclusive;
}
COH_SCRATCH_CONTROLLER_RSHR_REQ#(type t_RSHR_ADDR,
                                 type t_RSHR_IDX,
                                 type t_RSHR_TAG)
    deriving (Eq, Bits);

//
// RSHR entry
//
typedef struct
{
    t_RSHR_TAG                 tag;
    COH_SCRATCH_MEM_VALUE      val;
    Bool                       needForward;
    Bool                       isExclusive;
    COH_SCRATCH_PORT_NUM       forwardId;
    COH_SCRATCH_CTRLR_PORT_NUM fwdControllerId;
    COH_SCRATCH_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
}
COH_SCRATCH_RSHR_ENTRY#(type t_RSHR_TAG)
    deriving (Eq, Bits);

//
// Ownerbit request table entry
//
typedef struct
{
    t_ADDR      addr;
    Bool        writeback;
    Bool        recheckout;
}
COH_SCRATCH_OWNERBIT_REQ_TABLE_ENTRY#(type t_ADDR)
    deriving (Eq, Bits);

//
// Coherence controller's ownerbit memory request 
//
typedef struct
{
    t_ADDR                     addr;
    t_IDX                      idx;
    COH_SCRATCH_PORT_NUM       requester;
    COH_SCRATCH_CTRLR_PORT_NUM reqControllerId;
    COH_SCRATCH_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
    Bool                       isExclusive;
    Bool                       needCheckout;
}
COH_SCRATCH_CONTROLLER_OWNER_BIT_REQ#(type t_ADDR,
                                      type t_IDX)
    deriving(Bits, Eq);

//
// Coherence controller's data memory request 
//
typedef struct
{
    COH_SCRATCH_PORT_NUM       requester;
    COH_SCRATCH_CTRLR_PORT_NUM reqControllerId;
    COH_SCRATCH_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
    Bool                       isExclusive;
}
COH_SCRATCH_CONTROLLER_DATA_REQ
    deriving(Bits, Eq);

`ifndef COHERENT_SCRATCHPAD_I_TO_M_ENABLE_Z

// Coherence controller's ownership states
typedef enum
{
    COH_MEM_STATE_E,  // Exclusive
    COH_MEM_STATE_O,  // Owned (but not exclusive)
    COH_MEM_STATE_I   // Invalid
}
COH_SCRATCH_CTRLR_OWNERSHIP_STATE
    deriving (Eq, Bits);

`endif

// Number of entries in request tables that stores GETX/GETS requests 
// that are checking out the ownership in ownerbitMem
typedef 32 COH_SCRATCH_CONTROLLER_GET_REQ_TABLE_ENTRIES;

//
// Statistics wires for coherent scratchpad controller.
// When a line becomes true the coresponding statistic should be incremented.
//
interface COH_SCRATCH_CONTROLLER_STATS;
    method Bool cleanPutxReceived();  // receive client's clean putX request
    method Bool dirtyPutxReceived();  // receive client's dirty putX request
    method Bool getsReceived();       // receive client's getS request
    method Bool getxReceived();       // receive client's getX request
    method Bool writebackReceived();  // receive client's write back response
    method Bool ownerbitCheckout();   // checkout ownerbit from lower level memory
    method Bool dataReceived();       // receive data from lower level memory
    method Bool respSent();           // send out data response to clients
    method Bool putRetry();           // retry putX because table entry is not available
    method Bool getRetry();           // retry getX because table entry is not available
endinterface: COH_SCRATCH_CONTROLLER_STATS

//
// Interface of cached coherent scratchpad controller's router
//
interface COH_SCRATCH_CACHED_CONTROLLER_ROUTER#(type t_ADDR);
    // activated request to network
    method Action sendActivatedReq(COH_SCRATCH_ACTIVATED_REQ#(t_ADDR) req);
    // response to network
    method Action sendMemoryResp(COH_SCRATCH_PORT_NUM dest, COH_SCRATCH_RESP resp);
    // unactivated request from network
    method ActionValue#(COH_SCRATCH_MEM_REQ#(t_ADDR)) unactivatedReq();
    method COH_SCRATCH_MEM_REQ#(t_ADDR) peekUnactivatedReq();
    // write-back response from network
    method ActionValue#(COH_SCRATCH_RESP) writebackResp();
    method COH_SCRATCH_RESP peekWritebackResp();
endinterface: COH_SCRATCH_CACHED_CONTROLLER_ROUTER

//
// mkCoherentScratchpadController --
//     Initialize a controller for a new coherent scratchpad memory region.
//
module [CONNECTED_MODULE] mkCoherentScratchpadController#(Integer dataScratchpadID, 
                                                          Integer ownerbitScratchpadID,
                                                          NumTypeParam#(t_IN_ADDR_SZ) inAddrSz,
                                                          NumTypeParam#(t_IN_DATA_SZ) inDataSz,
                                                          COH_SCRATCH_CONTROLLER_CONFIG conf)
    // interface:
    ();
    
    if (conf.cacheMode == COH_SCRATCH_CACHED)
    begin
        let statsConstructor = mkBasicCoherentScratchpadControllerStats("Coherent_scratchpad_" + integerToString(dataScratchpadID) + "_controller_", "");
        // Each coherent scratchpad client has a private cache.
        mkCachedCoherentScratchpadController(dataScratchpadID, ownerbitScratchpadID, inAddrSz, inDataSz, statsConstructor, conf);
    end
    else
    begin
        // There are no private caches in this coherence domain. 
        // Coherent scratchpad clients just send remote reads/writes to the centralized 
        // private scratchpad inside the conherent scratchpad controller
        mkUncachedCoherentScratchpadController(dataScratchpadID, inAddrSz, inDataSz, conf);
    end

endmodule


//
// mkCachedCoherentScratchpadController --
//     This module handles the situation when each coherent scratchpad client 
//     has a private cache. 
//
//     The controller handles coherence requests/responses within a particular 
//     coherence region and forward requests/responses to/from the next 
//     level memory (central cache) through a private scratchpad interface. 
//
//     Under the snoopy-based protocol, this module serves as an ordering point 
//     and stores cache owner bits in a private scratchpad. 
//
module [CONNECTED_MODULE] mkCachedCoherentScratchpadController#(Integer dataScratchpadID, 
                                                                Integer ownerbitScratchpadID,
                                                                NumTypeParam#(t_IN_ADDR_SZ) inAddrSz,
                                                                NumTypeParam#(t_IN_DATA_SZ) inDataSz,
                                                                COH_SCRATCH_CONTROLLER_STATS_CONSTRUCTOR statsConstructor,
                                                                COH_SCRATCH_CONTROLLER_CONFIG conf)
    // interface:
    ()
    provisos (
              // Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_IN_DATA_SZ)), t_NATURAL_SZ),
              Bits#(COH_SCRATCH_MEM_VALUE, t_COH_SCRATCH_MEM_VALUE_SZ),
              // Compute the container (scratchpad) address size
              NumAlias#(TLog#(TDiv#(t_COH_SCRATCH_MEM_VALUE_SZ, t_NATURAL_SZ)), t_NATURAL_IDX_SZ),
              NumAlias#(TSub#(t_IN_ADDR_SZ, t_NATURAL_IDX_SZ), t_ADDR_SZ),
              Alias#(Bit#(t_ADDR_SZ), t_ADDR),
              Bits#(COH_SCRATCH_MEM_ADDRESS, t_COH_SCRATCH_MEM_ADDR_SZ),
              // Coherence messages
              Alias#(COH_SCRATCH_MEM_REQ#(t_ADDR), t_COH_SCRATCH_REQ),
              Alias#(COH_SCRATCH_ACTIVATED_REQ#(t_ADDR), t_COH_SCRATCH_ACTIVATED_REQ),
              // Compute request status handling registers (RSHR) index and tag
              NumAlias#(TMin#(t_ADDR_SZ, COH_SCRATCH_CONTROLLER_META_SZ), t_RSHR_IDX_SZ),
              NumAlias#(TExp#(t_RSHR_IDX_SZ), n_RSHR_ENTRIES),
              Alias#(UInt#(t_RSHR_IDX_SZ), t_RSHR_IDX),
              Alias#(Bit#(TSub#(t_ADDR_SZ, t_RSHR_IDX_SZ)), t_RSHR_TAG),
              // RSHR entry
              Alias#(COH_SCRATCH_RSHR_ENTRY#(t_RSHR_TAG), t_RSHR_ENTRY),
              // RSHR request
              Alias#(COH_SCRATCH_CONTROLLER_RSHR_REQ#(t_ADDR, t_RSHR_IDX, t_RSHR_TAG), t_RSHR_REQ),
              // Get request table entry
              Alias#(COH_SCRATCH_OWNERBIT_REQ_TABLE_ENTRY#(t_ADDR), t_GET_REQ_TABLE_ENTRY),
              Alias#(UInt#(TMin#(t_RSHR_IDX_SZ, TLog#(COH_SCRATCH_CONTROLLER_GET_REQ_TABLE_ENTRIES))), t_GET_REQ_TABLE_IDX),
              // Memory request
              Alias#(COH_SCRATCH_CONTROLLER_OWNER_BIT_REQ#(t_ADDR, t_GET_REQ_TABLE_IDX), t_OWNER_BIT_REQ),
              Bounded#(t_RSHR_IDX));


    String debugLogFilename = "coherent_scratchpad_" + integerToString(dataScratchpadID) + "_controller.out";

    DEBUG_FILE debugLog <- (`COHERENT_SCRATCHPAD_DEBUG_ENABLE == 1)?
                           mkDebugFile(debugLogFilename):
                           mkDebugFileNull(debugLogFilename); 
    //
    // Elaboration time checks
    //
    if (valueOf(t_NATURAL_SZ) > valueOf(t_COH_SCRATCH_MEM_VALUE_SZ))
    begin
        //
        // Object size is larger than COH_SCRATCH_MEM_VALUE 
        // This requires issuing multiple reads and writes for every reference,
        // and they need to be automic.
        // This requires a locking scheme so currently is not supported. 
        //
        error("Coherent scratchpad doesn't support data larger than coherent scratchpad's base size. Change COH_SCRATCH_MEM_VALUE.");
    end

    if (valueOf(t_IN_ADDR_SZ) > valueOf(t_COH_SCRATCH_MEM_ADDR_SZ))
    begin
        error("Coherent scratchpad address size is not big enough. Increase parameter COHERENT_SCRATCHPAD_MEMORY_ADDR_BITS.");
    end
    
    // =======================================================================
    //
    // Coherent scratchpad controller partition module
    //
    // =======================================================================
    
    let partition <- conf.partition();

    // =======================================================================
    //
    // Coherent scratchpad controller router
    //
    // =======================================================================
    
    COH_SCRATCH_CACHED_CONTROLLER_ROUTER#(t_ADDR) router;

`ifndef COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z

    router <- (!conf.multiController)? mkCachedCoherentScratchpadSingleControllerRouter(dataScratchpadID, debugLog):
                                       mkCachedCoherentScratchpadMultiControllerRouter(dataScratchpadID, conf.coherenceDomainID, 
                                                                                       partition.isLocalReq, conf.isMaster, debugLog);
`else
    
    if (conf.multiController)
    begin
        error("COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE is not enabled");
    end
    router <- mkCachedCoherentScratchpadSingleControllerRouter(dataScratchpadID, debugLog);

`endif

    // =======================================================================
    //
    // Instantiate two private scratchpads
    //
    // (1) dataMem: a private scratchpad that serves as the interface to 
    //              read/write data from/to local memory
    // (2) ownerbitMem: a private scratchpad that serves as a small directory 
    //                  to store coherence owner bits
    //
    // =======================================================================

    SCRATCHPAD_CONFIG dataMemConfig = defaultValue;
    SCRATCHPAD_CONFIG ownerbitMemConfig = defaultValue;
    
    dataMemConfig.cacheMode = (`COHERENT_SCRATCHPAD_DATA_MEM_CACHE_ENABLE == 1)? SCRATCHPAD_CACHED : SCRATCHPAD_NO_PVT_CACHE;
    dataMemConfig.requestMerging = False;
    ownerbitMemConfig.cacheMode = SCRATCHPAD_CACHED;
    ownerbitMemConfig.requestMerging = False;

    // dataMem
    MEMORY_IFC#(t_ADDR, COH_SCRATCH_MEM_VALUE) dataMem  <- mkScratchpad(dataScratchpadID, dataMemConfig);

    // ownerbitMem
`ifndef COHERENT_SCRATCHPAD_I_TO_M_ENABLE_Z
    MEMORY_IFC#(t_ADDR, COH_SCRATCH_CTRLR_OWNERSHIP_STATE) ownerbitMem  <- mkScratchpad(ownerbitScratchpadID, ownerbitMemConfig);
`else
    MEMORY_IFC#(t_ADDR, Bool) ownerbitMem  <- mkScratchpad(ownerbitScratchpadID, ownerbitMemConfig); 
`endif

    // =======================================================================
    //
    // Process incoming requests from coherent scratchpad clients. 
    // 
    // This controller serves as an ordering point and the interfaces to the 
    // next level memory (central cache). Therefore, it needs to
    // (1) accept PUTX request messages and write-back data (responses) from 
    //     coherent scratchpad clients
    // (2) repond to GETX/GETS messages if none of the coherent scratchpad
    //     clients is the owner
    // (3) forward requests from the request ring to the activatedReq ring
    //
    // =======================================================================

    // Request status handling registers (for write back PUTXs)
    BRAM#(t_RSHR_IDX, Maybe#(t_RSHR_ENTRY)) rshr <- mkBRAMInitialized(tagged Invalid);
    // Reguest table that stores get requests that are checking out ownerbits in the ownerbitMem
    LUTRAM#(t_GET_REQ_TABLE_IDX, Maybe#(t_GET_REQ_TABLE_ENTRY)) ownerbitReqTable <- mkLUTRAM(tagged Invalid);

    // Pipeline FIFOs
    FIFOF#(t_RSHR_REQ) rshrLookupQ                                       <- mkFIFOF();
    FIFOF#(t_RSHR_REQ) putReqRetryQ                                      <- mkFIFOF();
    FIFOF#(t_RSHR_REQ) getReqRetryQ                                      <- mkFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) rshrRespQ    <- mkBypassFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) memRespQ     <- mkBypassFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) outputRespQ  <- mkSizedFIFOF(8);
    FIFOF#(COH_SCRATCH_CONTROLLER_DATA_REQ) dataMemLookupQ               <- mkSizedFIFOF(32);
    FIFOF#(t_OWNER_BIT_REQ) ownerbitMemLookupQ                           <- mkSizedFIFOF(valueOf(COH_SCRATCH_CONTROLLER_GET_REQ_TABLE_ENTRIES));
    FIFOF#(t_OWNER_BIT_REQ) ownerbitMemCheckoutQ                         <- mkSizedFIFOF(valueOf(COH_SCRATCH_CONTROLLER_GET_REQ_TABLE_ENTRIES));
  
    Reg#(Bool) processPutRetry                                <- mkReg(False);
    Reg#(Bool) processGetRetry                                <- mkReg(False);
    Vector#(n_RSHR_ENTRIES, Reg#(Bool)) forwardEntries        <- replicateM(mkReg(False));
    Wire#(t_RSHR_IDX) rshrReleaseIdx                          <- mkWire();
    Wire#(t_GET_REQ_TABLE_IDX) ownerbitReqTableReleaseIdx     <- mkWire();
    PulseWire updFowardEntry                                  <- mkPulseWire();

    // Controller stats wires
    PulseWire cleanPutxReceivedW   <- mkPulseWire(); 
    PulseWire dirtyPutxReceivedW   <- mkPulseWire();
    PulseWire getsReceivedW        <- mkPulseWire();
    PulseWire getxReceivedW        <- mkPulseWire(); 
    PulseWire writebackReceivedW   <- mkPulseWire(); 
    PulseWire ownerbitCheckoutW    <- mkPulseWire();
    PulseWire dataReceivedW        <- mkPulseWire();
    PulseWire respSentW            <- mkPulseWire();
    PulseWire putRetryW            <- mkPulseWire(); 
    PulseWire getRetryW            <- mkPulseWire();

    //
    // Convert address to rshr index and tag
    //
    function Tuple2#(t_RSHR_TAG, t_RSHR_IDX) rshrEntryFromAddr(t_ADDR addr);
        return unpack(truncateNP(hashBits(pack(addr))));
    endfunction
    
    function t_ADDR rshrAddrFromEntry(t_RSHR_TAG tag, t_RSHR_IDX idx);
        t_ADDR a = unpack(hashBits_inv(zeroExtendNP({tag, pack(idx)})));
        return a;
    endfunction

    //
    // Requests in the RSHR lookup pipeline (rshrLookupQ) may target the same 
    // RSHR entry and thus cause read-after-write hazards. To deal with 
    // read-after-write hazards, we add a bypass path to allow RSHR reads to 
    // get the latest update:
    //
    // Each time when updating RSHR, bypassRshrEntry and bypassRshrIdx 
    // are also updated. If bypassRshrIdx is the same as the index of the 
    // followed read request, bypassRshrEntry (instead of the response recieved 
    // from the BRAM) is used as response.
    //
    Reg#(t_RSHR_IDX) bypassRshrIdx <- mkReg(unpack(0));
    Reg#(Maybe#(t_RSHR_ENTRY)) bypassRshrEntry <- mkReg(tagged Invalid);
    
    //
    // Return bypassRshrEntry if idx is the same as bypassRshrIdx; otherwise, 
    // return rshr.readResp()
    //
    function ActionValue#(Maybe#(t_RSHR_ENTRY)) rshrReadRespBypass(t_RSHR_IDX idx);
        actionvalue
            let resp <- rshr.readRsp();
            if (idx == bypassRshrIdx)
            begin
                resp = bypassRshrEntry;
                debugLog.record($format("      rshr read response bypass"));
            end
            return resp;
        endactionvalue
    endfunction
    
    //
    // Update rshr as well as bypass registers (bypassRshrEntry, bypassRshrIdx)
    //
    function Action rshrWriteBypass(t_RSHR_IDX idx, Maybe#(t_RSHR_ENTRY) entry);
        return
            action
                rshr.write(idx, entry);
                bypassRshrIdx <= idx;
                bypassRshrEntry <= entry;
            endaction;
    endfunction

    // =======================================================================
    //
    // Start RSHR lookup requests:
    // 
    // There are five possible lookup request candidates:
    // (1) GETX/GETS/PUTX unactivated requests from coherent scratchpad clients
    // (2) Write back responses (PUTX responses) from coherent scratchpad clients
    // (3) PUTX retry requests
    // (4) GETX/GETS retry requests
    // (5) Second-time forwarding requests
    //
    // Priority: (2) > (5) > (3) > (4) > (1)
    //
    // To avoid deadlocks, received responses cannot be blocked.
    //
    // =======================================================================

    //
    // collectClientReq --
    //     Collect scratchpad client requests.
    //
    rule colletClientReq (True);
        let req = router.peekUnactivatedReq();
        let start_req = False;
        t_RSHR_REQ lookup_req = ?;
        lookup_req.requester       = req.requester;
        lookup_req.reqControllerId = req.reqControllerId;
        lookup_req.addr            = unpack(truncateNP(partition.globalToLocalAddr(zeroExtendNP(pack(req.addr)))));

        case (req.reqInfo) matches
            tagged COH_SCRATCH_GETS .gets_req:
            begin
                lookup_req.reqType        = COH_MSG_GETS;
                lookup_req.clientMeta     = gets_req.clientMeta;
                lookup_req.globalReadMeta = gets_req.globalReadMeta;
                start_req                 = True;
                debugLog.record($format("  collect GETS request: sender=%03d, reqControllerId=%02d, addr=0x%x, meta=0x%x",  
                                lookup_req.requester, lookup_req.reqControllerId, lookup_req.addr, lookup_req.clientMeta));
            end
            tagged COH_SCRATCH_GETX .getx_req:
            begin
                lookup_req.reqType        = COH_MSG_GETX;
                lookup_req.clientMeta     = getx_req.clientMeta;
                lookup_req.globalReadMeta = getx_req.globalReadMeta;
                start_req                 = True;
                debugLog.record($format("  collect GETX request: sender=%03d, reqControllerId=%02d, addr=0x%x, meta=0x%x", 
                                lookup_req.requester, lookup_req.reqControllerId, lookup_req.addr, lookup_req.clientMeta));
            end
            tagged COH_SCRATCH_PUTX .putx_req:
            begin
                lookup_req.reqType        = COH_MSG_PUTX;
                lookup_req.isCleanWB      = putx_req.isCleanWB;
                lookup_req.isExclusive    = putx_req.isExclusive;
                start_req                 = !putReqRetryQ.notEmpty();
                debugLog.record($format("  collect PUTX request: sender=%03d, reqControllerId=%02d, addr=0x%x, isCleanWB=%s, isExclusive=%s",  
                                lookup_req.requester, lookup_req.reqControllerId, lookup_req.addr, 
                                lookup_req.isCleanWB? "True" : "False", lookup_req.isExclusive? "True" : "False"));
            end
        endcase
        
        if (start_req)
        begin
            let deq_req <- router.unactivatedReq();
            match {.tag, .idx} = rshrEntryFromAddr(lookup_req.addr);
            lookup_req.tag = tag;
            lookup_req.idx = idx;
            rshr.readReq(idx);
            rshrLookupQ.enq(lookup_req);
            debugLog.record($format("  start rshr lookup: addr=0x%x, idx=0x%x (original addr=0x%x)", 
                            lookup_req.addr, idx, req.addr));
        end
    endrule

    //
    // collectResp --
    //     Collect scratchpad client responses (PUTX write-back data).
    //
    rule collectClientResp (True);
        let resp <- router.writebackResp();
        t_RSHR_REQ lookup_req = ?;
        lookup_req.reqType = COH_MSG_RESP;
        lookup_req.val = resp.val;
        lookup_req.idx = unpack(pack(truncate(resp.meta)));
        lookup_req.isExclusive = resp.isExclusive;
        rshr.readReq(lookup_req.idx);
        rshrLookupQ.enq(lookup_req);
        debugLog.record($format("  collectClientResp: idx=0x%x, val=0x%x, isExclusive=%s", 
                        lookup_req.idx, lookup_req.val, lookup_req.isExclusive? "True" : "False"));
    endrule

    //
    // startPutRetry 
    //
    rule startPutRetry (processPutRetry);
        let r = putReqRetryQ.first();
        putReqRetryQ.deq();
        rshr.readReq(r.idx);
        rshrLookupQ.enq(r);
        debugLog.record($format("  startPutRetry: idx=0x%x, addr=0x%x", r.idx, r.addr));
    endrule

    //
    // startGetRetry 
    //
    rule startGetRetry (processGetRetry);
        let r = getReqRetryQ.first();
        getReqRetryQ.deq();
        rshr.readReq(r.idx);
        rshrLookupQ.enq(r);
        debugLog.record($format("  startGetRetry: idx=0x%x, addr=0x%x", r.idx, r.addr));
    endrule

    //
    // startForward --
    //     If there is an un-forwarded rshr entry, start second-time forwarding 
    // when the response queue is not full.
    //
    rule startForward (findElem(True, readVReg(forwardEntries)) matches tagged Valid .rshr_idx &&& outputRespQ.notFull() &&& !updFowardEntry);
        t_RSHR_REQ lookup_req = ?;
        lookup_req.reqType = COH_MSG_FWD;
        lookup_req.idx = unpack(pack(rshr_idx));
        rshr.readReq(unpack(pack(rshr_idx)));
        rshrLookupQ.enq(lookup_req);
        forwardEntries[rshr_idx] <= False;
        debugLog.record($format("  startForward: idx=0x%x", rshr_idx));
    endrule

    // =======================================================================
    //
    // RSHR lookup paths
    //
    // =======================================================================
    
    //
    // rshrGetLookup --
    //     Look up rshr for GETS/GETX requests. If rshr hits, which means the 
    // ownership is returned but data is not back yet, record request meta in 
    // the rshr. (If there is a previous GETS already waiting to be forwarded, 
    // ignore the request because the memory is not the owner anymore.) If 
    // rshr misses, look up the ownership status in ownerbitMem. 
    //
    rule rshrGetLookup (rshrLookupQ.first().reqType == COH_MSG_GETS || rshrLookupQ.first().reqType == COH_MSG_GETX);
        let r = rshrLookupQ.first();
        rshrLookupQ.deq();

        let cur_entry <- rshrReadRespBypass(r.idx);
        let req_table_idx = unpack(truncateNP(pack(r.idx)));
        Bool retry = False;
        Bool ownerbit_checkout = False;
        t_GET_REQ_TABLE_ENTRY new_req_entry = ?;

        // rshr hit
        if (cur_entry matches tagged Valid .e &&& e.tag == r.tag)
        begin
            debugLog.record($format("      rshrGetLookup HIT: idx=0x%x, addr=0x%x, %s", 
                            r.idx, r.addr, (e.needForward)? "ignore" : "wait to be forwarded"));
            if (!e.needForward)
            begin
                let new_entry = e;
                new_entry.needForward     = True;
                new_entry.isExclusive     = e.isExclusive || (r.reqType == COH_MSG_GETX);
                new_entry.forwardId       = r.requester;
                new_entry.fwdControllerId = r.reqControllerId;
                new_entry.clientMeta      = r.clientMeta;
                new_entry.globalReadMeta  = r.globalReadMeta;
                rshrWriteBypass(r.idx, tagged Valid new_entry);
                debugLog.record($format("      rshrGetLookup HIT: update RSHR, idx=0x%x, forwardId=%03d, fwdControllerId=%02d, isExclusive=%s",
                                r.idx, new_entry.forwardId, new_entry.fwdControllerId, (new_entry.isExclusive)? "True" : "False"));
            end
        end
        else // rshr miss
        begin
            if (ownerbitReqTable.sub(req_table_idx) matches tagged Valid .req_entry)
            begin
                // If hit (r.addr == addr), which means there is already one 
                // GETS/GETX going to check out the ownerbit, then do nothing.
                // There is an exception: 
                // If there is a write-back coming after the inflight GETS/GETX, 
                // that inflight request won't obtain ownership. Therefore, it
                // requires to re-checkout the ownerbit. 
                //
                // If miss (r.addr != addr), retry and wait until the table 
                // entry is free

                retry = (r.addr != req_entry.addr);
                ownerbit_checkout = (r.addr == req_entry.addr) && req_entry.writeback && !req_entry.recheckout;
                debugLog.record($format("      rshrGetLookup: idx=0x%x, addr=0x%x (entry: addr=0x%x, writeback=%s, recheckout=%s)", 
                                r.idx, r.addr, req_entry.addr, req_entry.writeback? "True" : "False", req_entry.recheckout? "True" : "False"));
                new_req_entry = COH_SCRATCH_OWNERBIT_REQ_TABLE_ENTRY { addr: r.addr, writeback: req_entry.writeback, recheckout: True };
            end
            else
            begin
                ownerbit_checkout = True;
                debugLog.record($format("      rshrGetLookup MISS: idx=0x%x, addr=0x%x", r.idx, r.addr));
                new_req_entry = COH_SCRATCH_OWNERBIT_REQ_TABLE_ENTRY { addr: r.addr, writeback: False, recheckout: False };
            end
        end

        if (ownerbit_checkout)
        begin
            ownerbitMemLookupQ.enq( COH_SCRATCH_CONTROLLER_OWNER_BIT_REQ { addr: r.addr,
                                                                           idx: req_table_idx,
                                                                           requester: r.requester,
                                                                           reqControllerId: r.reqControllerId,
                                                                           clientMeta: r.clientMeta,
                                                                           globalReadMeta: r.globalReadMeta,
                                                                           isExclusive: (r.reqType == COH_MSG_GETX),
                                                                           needCheckout: ?} );
            ownerbitMem.readReq(r.addr);
            ownerbitReqTable.upd(req_table_idx, tagged Valid new_req_entry);
            debugLog.record($format("      rshrGetLookup: idx=0x%x, read ownerbitMem: addr=0x%x", r.idx, r.addr));
        end
        
        if (retry)
        begin
            getReqRetryQ.enq(r);
            if (!getReqRetryQ.notEmpty())
            begin
                processGetRetry <= False;
            end
            debugLog.record($format("      rshrGetLookup: idx=0x%x, addr=0x%x, retry!", r.idx, r.addr));
            getRetryW.send();
        end
        else
        begin
            // forward request to the activated request ring
            t_COH_SCRATCH_ACTIVATED_REQ activated_req = ?;
            let get_req_info = COH_SCRATCH_GET_REQ_INFO { clientMeta: r.clientMeta,
                                                          globalReadMeta: r.globalReadMeta };
            
            activated_req.requester = r.requester;
            activated_req.reqControllerId = r.reqControllerId;
            activated_req.addr = unpack(truncateNP(partition.localToGlobalAddr(zeroExtendNP(pack(r.addr))))); 
            if (r.reqType == COH_MSG_GETS)
            begin
                activated_req.reqInfo = tagged COH_SCRATCH_ACTIVATED_GETS get_req_info;
                getsReceivedW.send();
            end
            else
            begin
                activated_req.reqInfo = tagged COH_SCRATCH_ACTIVATED_GETX get_req_info;
                getxReceivedW.send();
            end
            router.sendActivatedReq(activated_req);
        end
   endrule

    //
    // rshrDirtyPutLookup --
    //     Allocate an entry for a PUTX request (that is not clean write-back) in rshr. 
    // If the entry is already taken, store PUTX request into putReqRetryQ and wait 
    // until the entry is available for use.
    //
    rule rshrDirtyPutLookup (rshrLookupQ.first().reqType == COH_MSG_PUTX && !rshrLookupQ.first().isCleanWB);
        let r = rshrLookupQ.first();
        rshrLookupQ.deq();

        let cur_entry <- rshrReadRespBypass(r.idx);

        // rshr entry not available
        if (isValid(cur_entry))
        begin
            putReqRetryQ.enq(r);
            if (!putReqRetryQ.notEmpty())
            begin
                processPutRetry <= False;
            end
            debugLog.record($format("      rshrDirtyPutLookup: idx=0x%x, addr=0x%x, retry!", r.idx, r.addr));
            putRetryW.send();
        end
        else // entry available
        begin
            debugLog.record($format("      rshrDirtyPutLookup: idx=0x%x, addr=0x%x, allocate new entry", r.idx, r.addr));
            
            rshrWriteBypass(r.idx, tagged Valid COH_SCRATCH_RSHR_ENTRY { tag: r.tag,
                                                                         val: ?,
                                                                         needForward: False,
                                                                         isExclusive: False,
                                                                         forwardId: ?,
                                                                         fwdControllerId: ?,
                                                                         clientMeta: ?,
                                                                         globalReadMeta: ? });
            
            
            // If hit in the ownerbitReqTable, update the entry's writeback bit
            // The GETS/GETX request following this request needs to re-checkout the ownerbit
            let req_table_idx = unpack(truncateNP(pack(r.idx)));
            if (ownerbitReqTable.sub(req_table_idx) matches tagged Valid .req_entry &&& r.addr == req_entry.addr)
            begin
                debugLog.record($format("      rshrDirtyPutLookup: idx=0x%x, addr=0x%x, hit in ownerbitReqTable, update writeback bit", r.idx, r.addr));
                ownerbitReqTable.upd(req_table_idx, tagged Valid COH_SCRATCH_OWNERBIT_REQ_TABLE_ENTRY { addr: r.addr, 
                                                                                                        writeback: True,
                                                                                                        recheckout: False });
            end
            
            // forward request to the activated request ring
            let put_req_info = COH_SCRATCH_ACTIVATED_PUT_REQ_INFO { controllerMeta: unpack(zeroExtend(pack(r.idx))),
                                                                    isCleanWB: False };

            router.sendActivatedReq( COH_SCRATCH_ACTIVATED_REQ { requester: r.requester,
                                                                 reqControllerId: r.reqControllerId,
                                                                 homeControllerId: ?,
                                                                 addr: unpack(truncateNP(partition.localToGlobalAddr(zeroExtendNP(pack(r.addr))))),
                                                                 reqInfo: tagged COH_SCRATCH_ACTIVATED_PUTX put_req_info } );
            dirtyPutxReceivedW.send();
        end
    endrule

    //
    // rshrCleanPutLookup
    //
    rule rshrCleanPutLookup (rshrLookupQ.first().reqType == COH_MSG_PUTX && rshrLookupQ.first().isCleanWB);
        let r = rshrLookupQ.first();
        rshrLookupQ.deq();
        let cur_entry <- rshrReadRespBypass(r.idx);
        debugLog.record($format("      rshrCleanPutLookup: addr=0x%x, write back ownerbit, isExclusive=%s", 
                        r.addr, r.isExclusive? "True" : "False"));

`ifndef COHERENT_SCRATCHPAD_I_TO_M_ENABLE_Z
        let ownership_state = r.isExclusive? COH_MEM_STATE_E : COH_MEM_STATE_O;
        ownerbitMem.write(r.addr, ownership_state);
`else
        ownerbitMem.write(r.addr, False);
`endif

        // If hit in the ownerbitReqTable, update the entry's writeback bit
        // The GETS/GETX request following this request needs to re-checkout the ownerbit
        let req_table_idx = unpack(truncateNP(pack(r.idx)));
        if (ownerbitReqTable.sub(req_table_idx) matches tagged Valid .req_entry &&& r.addr == req_entry.addr)
        begin
            debugLog.record($format("      rshrCleanPutLookup: idx=0x%x, addr=0x%x, hit in ownerbitReqTable, update writeback bit", r.idx, r.addr));
            ownerbitReqTable.upd(req_table_idx, tagged Valid COH_SCRATCH_OWNERBIT_REQ_TABLE_ENTRY { addr: r.addr, 
                                                                                                    writeback: True,
                                                                                                    recheckout: False });
        end
            
        // forward request to the activated request ring
        let put_req_info = COH_SCRATCH_ACTIVATED_PUT_REQ_INFO { controllerMeta: ?,
                                                                isCleanWB: True };

        router.sendActivatedReq( COH_SCRATCH_ACTIVATED_REQ { requester: r.requester,
                                                             reqControllerId: r.reqControllerId,
                                                             homeControllerId: ?,
                                                             addr: unpack(truncateNP(partition.localToGlobalAddr(zeroExtendNP(pack(r.addr))))),
                                                             reqInfo: tagged COH_SCRATCH_ACTIVATED_PUTX put_req_info } );
        cleanPutxReceivedW.send();
    endrule

    //
    // rshrRespLookup --
    //     Free the rshr entry associated with the write-back response.
    // Forward write-back data as a response to previous GETX/GETS request 
    // if there is one. If the response queue (outputRespQ) is full,
    // don't free the rshr entry and mark the entry index in forwardEntries 
    // register to enable future forwarding when the response queue is 
    // available. 
    //
    rule rshrRespLookup (rshrLookupQ.first().reqType == COH_MSG_RESP);
        let r = rshrLookupQ.first();
        rshrLookupQ.deq();

        let cur_entry <- rshrReadRespBypass(r.idx);

        if (cur_entry matches tagged Valid .e)
        begin
            Bool sent_resp = False;
            // write back data and ownerbit to memory if the ownership has not 
            // been checked-out by a GETS/GETX
            // (Here we respond GETS with ownership to enable automatically S->O or S->M upgrades)
            if (!e.needForward)
            begin
                let w_addr = rshrAddrFromEntry(e.tag, r.idx);
                // write back ownership
`ifndef COHERENT_SCRATCHPAD_I_TO_M_ENABLE_Z
                let ownership_state = r.isExclusive? COH_MEM_STATE_E : COH_MEM_STATE_O;
                ownerbitMem.write(w_addr, ownership_state);
                debugLog.record($format("      rshrRespLookup: idx=0x%x, ownerbitMem write back, addr=0x%x, state=%0d", r.idx, w_addr, ownership_state));
`else
                ownerbitMem.write(w_addr, False);
                debugLog.record($format("      rshrRespLookup: idx=0x%x, ownerbitMem write back, addr=0x%x", r.idx, w_addr));
`endif
                // write back data value
                dataMem.write(w_addr, r.val);
                debugLog.record($format("      rshrRespLookup: idx=0x%x, dataMem write back, addr=0x%x, val=0x%x", r.idx, w_addr, r.val));
            end

            // forward write-back data to a client if response queue is not full
            if (e.needForward && outputRespQ.notFull())
            begin
                sent_resp = True;
                rshrRespQ.enq(tuple2(e.forwardId, COH_SCRATCH_RESP { val: r.val,
                                                                     ownership: True,
                                                                     isExclusive: e.isExclusive || r.isExclusive,
`ifndef COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z
                                                                     controllerId: e.fwdControllerId, 
                                                                     clientId: e.forwardId,
`endif
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
                                                                     needFwd: False,
                                                                     lastFwdControllerId: ?,
                                                                     lastFwdClientId: ?,
`endif
                                                                     meta: zeroExtend(e.clientMeta), 
                                                                     globalReadMeta: e.globalReadMeta,
                                                                     isCacheable: True,
                                                                     retry: False }));

                debugLog.record($format("      rshrRespLookup: idx=0x%x, forward response: dest=%d, val=0x%x", 
                                r.idx, e.forwardId, r.val));
            end
            
            // release rshr entry if finish forwarding
            if (sent_resp || !e.needForward)
            begin
                rshrWriteBypass(r.idx, tagged Invalid);
                rshrReleaseIdx <= r.idx;
                debugLog.record($format("      rshrRespLookup: idx=0x%x, release entry", r.idx));
            end
            else // save for future forwarding
            begin
                let new_entry = e;
                new_entry.val = r.val;
                new_entry.isExclusive = e.isExclusive || r.isExclusive;
                rshrWriteBypass(r.idx, tagged Valid new_entry);
                forwardEntries[r.idx] <= True;
                updFowardEntry.send();
                debugLog.record($format("      rshrRespLookup: idx=0x%x, wait for future forwarding", r.idx));
            end
            writebackReceivedW.send();
        end
    endrule
    
    //
    // rshrFwdLookup --
    //     Second-time forward the write-back response.
    // Free the rshr entry associated with the write-back response if
    // successfully forwarding the response.
    //
    rule rshrFwdLookup (rshrLookupQ.first().reqType == COH_MSG_FWD);
        let r = rshrLookupQ.first();
        rshrLookupQ.deq();

        let cur_entry <- rshrReadRespBypass(r.idx);

        if (cur_entry matches tagged Valid .e)
        begin
            if (outputRespQ.notFull())
            begin
                // forward write-back data to a client 
                rshrRespQ.enq(tuple2(e.forwardId, COH_SCRATCH_RESP { val: e.val,
                                                                     ownership: True,
                                                                     isExclusive: e.isExclusive,
`ifndef COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z
                                                                     controllerId: e.fwdControllerId, 
                                                                     clientId: e.forwardId,
`endif
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
                                                                     needFwd: False,
                                                                     lastFwdControllerId: ?,
                                                                     lastFwdClientId: ?,
`endif
                                                                     meta: zeroExtend(e.clientMeta), 
                                                                     globalReadMeta: e.globalReadMeta,
                                                                     isCacheable: True,
                                                                     retry: False }));
                // release rshr entry
                rshrWriteBypass(r.idx, tagged Invalid);
                rshrReleaseIdx <= r.idx;
                debugLog.record($format("      rshrFwdLookup: idx=0x%x, forward response: dest=%d, val=0x%x, release rshr entry", r.idx, e.forwardId, e.val));
            end
            else
            begin
                forwardEntries[r.idx] <= True;
                updFowardEntry.send();
                debugLog.record($format("      rshrFwdLookup: idx=0x%x, wait for future forwarding", r.idx));
            end
        end
    endrule

    (* preempts = "enablePutRetry, rshrDirtyPutLookup" *)
    rule enablePutRetry (putReqRetryQ.notEmpty() && !processPutRetry);
        if (rshrReleaseIdx == putReqRetryQ.first().idx)
        begin
            processPutRetry <= True;
            debugLog.record($format("  enablePutRetry: idx=0x%x", rshrReleaseIdx));
        end
    endrule

    (* preempts = "enableGetRetry, rshrGetLookup" *)
    rule enableGetRetry (getReqRetryQ.notEmpty() && !processGetRetry);
        if (ownerbitReqTableReleaseIdx == unpack(truncateNP(pack(getReqRetryQ.first().idx))))
        begin
            processGetRetry <= True;
            debugLog.record($format("  enableGetRetry: idx=0x%x", ownerbitReqTableReleaseIdx));
        end
    endrule

    // =======================================================================
    //
    // Memory lookup paths
    //
    // =======================================================================

    rule ownerbitMemLookup (True);
        let r = ownerbitMemLookupQ.first();
        ownerbitMemLookupQ.deq();
        let ownership = False;
        let is_exclusive = False;

`ifndef COHERENT_SCRATCHPAD_I_TO_M_ENABLE_Z
        let state <- ownerbitMem.readRsp();
        ownership = (state != COH_MEM_STATE_I);
        is_exclusive = (state == COH_MEM_STATE_E);
`else
        let checkout <- ownerbitMem.readRsp(); // True means the ownership has been checked out
        ownership = !checkout;
 `endif

        debugLog.record($format("      ownerbitMemLookup: addr=0x%x, ownership=%s, isExclusive=%s", 
                        r.addr, ownership? "True" : "False", is_exclusive? "True" : "False"));

        let req = r;
        req.needCheckout = ownership; 
        req.isExclusive = r.isExclusive || is_exclusive;
        ownerbitMemCheckoutQ.enq(req);
    endrule

    rule ownerbitMemCheckout (True);
        let r = ownerbitMemCheckoutQ.first();
        ownerbitMemCheckoutQ.deq();
        if (r.needCheckout)
        begin
            // checkout ownerbit
`ifndef COHERENT_SCRATCHPAD_I_TO_M_ENABLE_Z
            ownerbitMem.write(r.addr, COH_MEM_STATE_I);
`else
            ownerbitMem.write(r.addr, True);
`endif
            debugLog.record($format("      ownerbitMemCheckout: checkout ownerbitMem: addr=0x%x", r.addr));
            ownerbitCheckoutW.send();
            // read data memory
            dataMemLookupQ.enq( COH_SCRATCH_CONTROLLER_DATA_REQ { requester: r.requester,
                                                                  reqControllerId: r.reqControllerId,
                                                                  clientMeta: r.clientMeta,
                                                                  globalReadMeta: r.globalReadMeta,
                                                                  isExclusive: r.isExclusive } );
            dataMem.readReq(r.addr);
            debugLog.record($format("      ownerbitMemCheckout: read dataMem: addr=0x%x, meta=0x%x, isExclusive=%s", 
                            r.addr, r.clientMeta, r.isExclusive? "True" : "False"));
        end
        
        // Mark the writeback bit to False if there is a following recheckout request
        if (ownerbitReqTable.sub(r.idx) matches tagged Valid .req_entry &&& req_entry.writeback == True &&& req_entry.recheckout == True)
        begin
            ownerbitReqTable.upd(r.idx, tagged Valid COH_SCRATCH_OWNERBIT_REQ_TABLE_ENTRY { addr: r.addr, 
                                                                                            writeback: False,
                                                                                            recheckout: True });

            debugLog.record($format("      ownerbitMemCheckout: update writeback bit in ownerbitReqTable: addr=0x%x, idx=0x%x", r.addr, r.idx));
        end 
        else // release ownerbitReqTable entry
        begin
            ownerbitReqTable.upd(r.idx, tagged Invalid);
            ownerbitReqTableReleaseIdx <= r.idx;
            debugLog.record($format("      ownerbitMemCheckout: release ownerbitReqTable: addr=0x%x, idx=0x%x", r.addr, r.idx));
        end
    endrule

    (* descending_urgency = "collectClientResp, rshrRespLookup, rshrFwdLookup, rshrCleanPutLookup, enablePutRetry, enableGetRetry, startForward, startPutRetry, startGetRetry, colletClientReq, ownerbitMemCheckout, rshrDirtyPutLookup, rshrGetLookup, ownerbitMemLookup, dataMemLookup" *)
    rule dataMemLookup (True);
        let r = dataMemLookupQ.first();
        dataMemLookupQ.deq();
        let data <- dataMem.readRsp();
        memRespQ.enq(tuple2(r.requester, COH_SCRATCH_RESP { val: data,
                                                            ownership: True,
                                                            isExclusive: r.isExclusive,
`ifndef COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z
                                                            controllerId: r.reqControllerId,
                                                            clientId: r.requester,
`endif
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
                                                            needFwd: False,
                                                            lastFwdControllerId: ?,
                                                            lastFwdClientId: ?,
`endif
                                                            meta: zeroExtend(r.clientMeta), 
                                                            globalReadMeta: r.globalReadMeta,
                                                            isCacheable: True,
                                                            retry: False }));
        debugLog.record($format("      dataMemLookup: send data response: dest=%d, val=0x%x, meta=0x%x, isExclusive=%s", 
                        r.requester, data, r.clientMeta, r.isExclusive? "True" : "False"));
        dataReceivedW.send();
    endrule

    // =======================================================================
    //
    // Send out responses 
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule sendToOutputRespQ (True);
        let resp = ?;
        if (rshrRespQ.notEmpty())
        begin
            resp = rshrRespQ.first();
            rshrRespQ.deq();
            outputRespQ.enq(resp);
        end
        else
        begin
            resp = memRespQ.first();
            memRespQ.deq();
            outputRespQ.enq(resp);
        end
    endrule

    (* fire_when_enabled *)
    rule sendCoherentScratchpadResp (True);
        let resp = outputRespQ.first();
        outputRespQ.deq();
        respSentW.send();
        router.sendMemoryResp(tpl_1(resp), tpl_2(resp));
    endrule
    
    // =======================================================================
    //
    // Controller stats
    //
    // =======================================================================

    let stats = interface COH_SCRATCH_CONTROLLER_STATS;
                    method Bool cleanPutxReceived() = cleanPutxReceivedW;  
                    method Bool dirtyPutxReceived() = dirtyPutxReceivedW;
                    method Bool getsReceived() = getsReceivedW;
                    method Bool getxReceived() = getxReceivedW;
                    method Bool writebackReceived() = writebackReceivedW;
                    method Bool ownerbitCheckout() = ownerbitCheckoutW;
                    method Bool dataReceived() = dataReceivedW;
                    method Bool respSent() = respSentW;
                    method Bool putRetry() = putRetryW;
                    method Bool getRetry() = getRetryW;
                endinterface;

    statsConstructor(stats);
    
    // ====================================================================
    //
    // Coherent scratchpad controller debug scan for deadlock debugging.
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    dbg_list <- addDebugScanField(dbg_list, "rshrLookupQ notEmpty", rshrLookupQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "rshrLookupQ notFull", rshrLookupQ.notFull);
    dbg_list <- addDebugScanField(dbg_list, "outputRespQ notEmpty", outputRespQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "outputRespQ notFull", outputRespQ.notFull);
    dbg_list <- addDebugScanField(dbg_list, "dataMemLookupQ notEmpty", dataMemLookupQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "dataMemLookupQ notFull", dataMemLookupQ.notFull);
    dbg_list <- addDebugScanField(dbg_list, "ownerbitMemLookupQ notEmpty", ownerbitMemLookupQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "ownerbitMemLookupQ notFull", ownerbitMemLookupQ.notFull);
    dbg_list <- addDebugScanField(dbg_list, "ownerbitMemCheckoutQ notEmpty", ownerbitMemCheckoutQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "ownerbitMemCheckoutQ notFull", ownerbitMemCheckoutQ.notFull);
   
    String debugScanName = (conf.multiController)? 
                           "Coherent Scratchpad Controller " + integerToString(dataScratchpadID) + " in Domain " + integerToString(conf.coherenceDomainID): 
                           "Coherent Scratchpad Controller in Domain " + integerToString(dataScratchpadID);

    let dbgNode <- mkDebugScanNode(debugScanName + "(coherent-scratchpad-memory-controller.bsv)", dbg_list);

endmodule

//
// mkCachedCoherentScratchpadMultiControllerRouter --
//     This module handles the situation when each coherent scratchpad client 
//     has a private cache and there are multiple controllers in the coherence
//     domain. 
//
//     The controller router collects coherence requests from its local clients,
//     forwards local requests to its local controller and forwards the rest to
//     the remote controller(s). The router also forwards associated responses 
//     to its local clients. 
//
//     Under the snoopy-based protocol, this module serves as an ordering point
//     for local requests. 
//
`ifndef COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z

module [CONNECTED_MODULE] mkCachedCoherentScratchpadMultiControllerRouter#(Integer dataScratchpadID,
                                                                           Integer coherenceDomainID,  
                                                                           function Bool isLocalReq(COH_SCRATCH_MEM_ADDRESS addr),
                                                                           Bool isMaster,
                                                                           DEBUG_FILE debugLog)
    // interface:
    (COH_SCRATCH_CACHED_CONTROLLER_ROUTER#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              // Coherence messages
              Alias#(COH_SCRATCH_MEM_REQ#(t_ADDR), t_COH_SCRATCH_REQ),
              Alias#(COH_SCRATCH_ACTIVATED_REQ#(t_ADDR), t_COH_SCRATCH_ACTIVATED_REQ));
 
    FIFOF#(t_COH_SCRATCH_ACTIVATED_REQ) activatedReqQ <- mkBypassFIFOF();
    FIFOF#(COH_SCRATCH_RESP)            localMemRespQ <- mkBypassFIFOF();
    FIFOF#(t_COH_SCRATCH_REQ)         unactivatedReqQ <- mkFIFOF();
    FIFOF#(COH_SCRATCH_RESP)           writebackRespQ <- mkFIFOF();

    // =======================================================================
    //
    // Coherent scratchpad clients and this controller are connected via rings.
    //
    // Three rings are required to avoid deadlocks: one for requests, 
    // one for responses, and one for activated requests.
    //
    // For multi-controller settings, hierarchical rings are used, which means
    // controllers are also connected via three rings.
    //
    // To prevent deadlocks, the broadcast rings require 2 channels and the 
    // dateline technique is used to avoid circular dependency. 
    // Dateline is allocated at the master controller. 
    //
    // =======================================================================

    //
    // Connections between the coherent scratchpad controller and its local clients
    //
    String clientControllerRingName = "Coherent_Scratchpad_" + integerToString(dataScratchpadID);
    
    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_REQ) link_mem_req <- 
        mkConnectionAddrRingNode(clientControllerRingName + "_Req", 0);

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP) link_mem_resp <-
        (`ADDR_RING_DEBUG_ENABLE == 1)?
        mkDebugConnectionAddrRingNodeNtoN(clientControllerRingName + "_Resp", 0, debugLog):
        mkConnectionAddrRingNodeNtoN(clientControllerRingName + "_Resp", 0);

    // Broadcast ring (with 2 channels)
    Vector#(2, CONNECTION_CHAIN#(t_COH_SCRATCH_ACTIVATED_REQ)) links_mem_activatedReq = newVector();
    links_mem_activatedReq[0] <- mkConnectionChain(clientControllerRingName + "_ActivatedReq_0");
    links_mem_activatedReq[1] <- mkConnectionChain(clientControllerRingName + "_ActivatedReq_1");
    
    //
    // Connections between multiple controllers
    //
    String controllersRingName = "Coherent_Scratchpad_Controllers_" + integerToString(coherenceDomainID);
    
    // Broadcast ring (with 2 channels)
    Vector#(2, CONNECTION_CHAIN#(t_COH_SCRATCH_REQ)) links_controllers_req = newVector();
    links_controllers_req[0] <- mkConnectionChain(controllersRingName + "_Req_0");
    links_controllers_req[1] <- mkConnectionChain(controllersRingName + "_Req_1");

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_CTRLR_PORT_NUM, COH_SCRATCH_RESP) link_controllers_resp <- (isMaster)?
        mkConnectionAddrRingNodeNtoN(controllersRingName + "_Resp", 0):
        mkConnectionAddrRingDynNodeNtoN(controllersRingName + "_Resp");

    // Broadcast ring (with 2 channels)
    Vector#(2, CONNECTION_CHAIN#(t_COH_SCRATCH_ACTIVATED_REQ)) links_controllers_activatedReq = newVector();
    links_controllers_activatedReq[0] <- mkConnectionChain(controllersRingName + "_ActivatedReq_0");
    links_controllers_activatedReq[1] <- mkConnectionChain(controllersRingName + "_ActivatedReq_1");
  
    Reg#(COH_SCRATCH_CTRLR_PORT_NUM) controllerPort <- mkReg(0);
    Reg#(Bool) initialized <- mkReg(False);
    Reg#(Bit#(1)) initCnt  <- mkReg(0); 

    rule doInit0 (!initialized && initCnt == 0);
        let port_num = link_controllers_resp.nodeID();
        controllerPort <= port_num;
        debugLog.record($format("    router: assigned controller port ID = %02d", port_num));
        // broadcast the controller port number to local clients
        t_COH_SCRATCH_ACTIVATED_REQ req = ?;
        req.reqControllerId = port_num;
        links_mem_activatedReq[0].sendToNext(req);
        initCnt <= 1;
    endrule
    
    rule doInit1 (!initialized && initCnt == 1);
        initialized <= True;
        let req <- links_mem_activatedReq[0].recvFromPrev();
        debugLog.record($format("    router: initDone: drop broacast controller port ID"));
    endrule

    // =======================================================================
    //
    // Activated requests:
    // 
    // (1) send local activated requests (activated by the local controller) 
    //     on to link_mem_activatedReq ring
    // 
    // (2) on the local link_mem_activatedReq ring: forward requests to the
    //     global link_controllers_activatedReq ring
    //     Optimization: for PUTX, if the requester is local, do not need to
    //     keep forwarding since the requester has already seen the activated
    //     request
    //
    // (3) on the global link_controllers_activatedReq ring: drop requests if 
    //     local to the controller (which means the activated requests have 
    //     traveled the whole loop); otherwise forward them to the local 
    //     link_mem_activatedReq ring
    //
    // =======================================================================

    // An arbiter to choose whether to send local or forwarding message on links_mem_activatedReq[0]
    Reg#(Bool)      localPrior <- mkReg(True); 
    PulseWire      fwdMsgSentW <- mkPulseWire();
    PulseWire    hasMsgToDropW <- mkPulseWire();
    
    //
    // The activated request's broadcast trip starts here
    // local controller -> local links_mem_activatedReq[0]
    //
    (* fire_when_enabled *)
    rule sendLocalActivatedReq (initialized && !fwdMsgSentW);
        let req = activatedReqQ.first();
        activatedReqQ.deq();
        req.homeControllerId = controllerPort;
        links_mem_activatedReq[0].sendToNext(req);
        localPrior <= False;
        debugLog.record($format("    router: sendLocalActivatedReq: addr=0x%x, sender=%03d, reqControllerId=%02d, homeControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId, req.homeControllerId));
    endrule

    // Check if the incoming activated request from the global ring 0 is waiting to be dropped
    (* fire_when_enabled *)
    rule checkDropActivatedReqOnGlobalRing0 (initialized && links_controllers_activatedReq[0].recvNotEmpty());
        let req = links_controllers_activatedReq[0].peekFromPrev();
        if (req.homeControllerId == controllerPort)
        begin
            hasMsgToDropW.send();
        end
    endrule
    
    // Drop the incoming activated request from the global ring 0 (for non-master controller)
    (* fire_when_enabled *)
    rule dropActivatedReqOnGlobalRingNonMaster0 (initialized && !isMaster && hasMsgToDropW);
        let req <- links_controllers_activatedReq[0].recvFromPrev();
        debugLog.record($format("    router: dropActivatedReqOnGlobalRing[0]: drop activated request: addr=0x%x, sender=%03d, reqControllerId=%02d, homeControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId, req.homeControllerId));
    endrule
    
    // Forward the incoming activated request from the global ring 0 to the local ring 0 (for non-master controller)
    (* mutually_exclusive = "fwdActivatedReqOnGlobalRingNonMaster0, sendLocalActivatedReq" *)
    (* fire_when_enabled *)
    rule fwdActivatedReqOnGlobalRingNonMaster0 (initialized && !isMaster && !hasMsgToDropW && (!localPrior || !activatedReqQ.notEmpty()));
        let req <- links_controllers_activatedReq[0].recvFromPrev();
        debugLog.record($format("    router: fwdActivatedReqOnGlobalRing[0]: forward activated request to local ring: addr=0x%x, sender=%03d, reqControllerId=%02d, homeControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId, req.homeControllerId));
        links_mem_activatedReq[0].sendToNext(req);
        fwdMsgSentW.send();
        localPrior <= True;
    endrule
    
    (* fire_when_enabled *)
    rule handleActivatedReqOnGlobalRingNonMaster1 (initialized && !isMaster);
        let req <- links_controllers_activatedReq[1].recvFromPrev();
        Bool drop_req = (req.homeControllerId == controllerPort);
        debugLog.record($format("    router: handleActivatedReqOnGlobalRing[1]: %s: addr=0x%x, sender=%03d, reqControllerId=%02d, homeControllerId=%02d", 
                        drop_req? "drop activated request" : "forward activated request to local ring 1", req.addr, req.requester, req.reqControllerId, req.homeControllerId));
        if (!drop_req)
        begin
            links_mem_activatedReq[1].sendToNext(req);
        end
    endrule

    (* fire_when_enabled *)
    rule handleActivatedReqOnGlobalRingMaster (initialized && isMaster);
        let req <- links_controllers_activatedReq[0].recvFromPrev();
        Bool drop_req = (req.homeControllerId == controllerPort);
        debugLog.record($format("    router: handleActivatedReqOnGlobalRing[0]: %s: addr=0x%x, sender=%03d, reqControllerId=%02d, homeControllerId=%02d", 
                        drop_req? "drop activated request" : "forward activated request to local ring 1", req.addr, req.requester, req.reqControllerId, req.homeControllerId));
        if (!drop_req)
        begin
            links_mem_activatedReq[1].sendToNext(req);
        end
    endrule

    for(Integer p = 0; p < 2; p = p + 1)
    begin
        (* fire_when_enabled *)
        rule handleActivatedReqOnLocalRing (initialized);
            let req <- links_mem_activatedReq[p].recvFromPrev();
           
            // The request is PUTX and the requester is local
            Bool drop_req = False;
            if (req.reqInfo matches tagged COH_SCRATCH_ACTIVATED_PUTX .putx_req &&& req.reqControllerId == controllerPort)
            begin
                drop_req = True;
            end
            
            debugLog.record($format("    router: handleActivatedReqOnLocalRing[%01d]: %s: addr=0x%x, sender=%03d, reqControllerId=%02d, homeControllerId=%02d", 
                            p, drop_req? "drop activated PUTX request" : "forward activated request to global ring", 
                            req.addr, req.requester, req.reqControllerId, req.homeControllerId));
            
            if (!drop_req)
            begin
                links_controllers_activatedReq[p].sendToNext(req);
            end
        endrule
    end

    // =======================================================================
    //
    // Unactivated requests (from clients or from global request ring)
    //  (1) local: forward to the local controller to get activated
    //  (2) non-local: forward to the link_controllers_req ring to get 
    //                 activated by a remote controller
    //
    // =======================================================================
   
    PulseWire   clientReqLocalW             <- mkPulseWire();
    PulseWire   clientReqRemoteW            <- mkPulseWire();
    PulseWire   localReqToRemoteW           <- mkPulseWire();
    Vector#(2, PulseWire) networkReqLocalW  <- replicateM(mkPulseWire());
    Vector#(2, PulseWire) networkReqRemoteW <- replicateM(mkPulseWire());
    LOCAL_ARBITER#(3) unactivatedReqRecvArb <- mkLocalArbiter();
    Reg#(Bool)  unactivatedReqFwdArb        <- mkReg(True);
    Wire#(Bit#(2)) pickLocalReqIdx          <- mkWire();

    (* fire_when_enabled *)
    rule checkClientReq (True);
        let req = link_mem_req.first();
        let addr = req.addr;
        Bool is_local = isLocalReq(zeroExtendNP(pack(addr)));
        Bool is_put = False;
        if (req.reqInfo matches tagged COH_SCRATCH_PUTX .info)
        begin
            is_put = True;
        end
        //debugLog.record($format("    router: check an unactivated request from client: addr=0x%x, %s %s request", 
        //                addr, is_local? "local" : "remote", is_put? "PUT" : "GET" ));
        if (is_local)
        begin
            clientReqLocalW.send();
        end
        else
        begin
            clientReqRemoteW.send();
        end
    endrule

    for(Integer p = 0; p < 2; p = p + 1)
    begin
        (* fire_when_enabled *)
        rule checkGlobalRingReq (True);
            let req = links_controllers_req[p].peekFromPrev();
            let addr = req.addr;
            Bool is_local = isLocalReq(zeroExtendNP(pack(addr)));
            Bool is_put = False;
            if (req.reqInfo matches tagged COH_SCRATCH_PUTX .info)
            begin
                is_put = True;
            end
            //debugLog.record($format("    router: check an unactivated request from global chain[%01d]: addr=0x%x, %s %s request, requester=%03d, reqControllerId=%02d", 
            //                p, addr, is_local? "local" : "remote", is_put? "PUT" : "GET", req.requester, req.reqControllerId));
            if (is_local)
            begin
                networkReqLocalW[p].send();
            end
            else
            begin
                networkReqRemoteW[p].send();
            end
        endrule
    end
    
    (* fire_when_enabled *)
    rule pickLocalUnactivatedReq (initialized);
        LOCAL_ARBITER_CLIENT_MASK#(3) reqs = newVector();
        reqs[0] = clientReqLocalW;
        reqs[1] = networkReqLocalW[0];
        reqs[2] = networkReqLocalW[1];
        let winner_idx <- unactivatedReqRecvArb.arbitrate(reqs, False);
        if (winner_idx matches tagged Valid .req_idx)
        begin
            pickLocalReqIdx <= pack(req_idx);
        end
    endrule
    
    (* fire_when_enabled *)
    rule recvLocalUnactivatedReqFromClient (initialized && pickLocalReqIdx == 0);
        let req = link_mem_req.first(); 
        link_mem_req.deq(); 
        req.reqControllerId = controllerPort;
        unactivatedReqQ.enq(req);
        debugLog.record($format("    router: receive an unactivated local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "clients", req.addr, req.requester, req.reqControllerId));
    endrule
    
    (* fire_when_enabled *)
    rule recvLocalUnactivatedReqFromGlobalChain0 (initialized && pickLocalReqIdx == 1);
        let req <- links_controllers_req[0].recvFromPrev();
        unactivatedReqQ.enq(req);
        debugLog.record($format("    router: receive an unactivated local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "global chain 0", req.addr, req.requester, req.reqControllerId));
    endrule
    
    (* fire_when_enabled *)
    rule recvLocalUnactivatedReqFromGlobalChain1 (initialized && pickLocalReqIdx == 2);
        let req <- links_controllers_req[1].recvFromPrev();
        unactivatedReqQ.enq(req);
        debugLog.record($format("    router: receive an unactivated local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "global chain 1", req.addr, req.requester, req.reqControllerId));
    endrule

    (* fire_when_enabled *)
    rule fwdLocalUnactivatedReqToChain0NonMaster (!isMaster && initialized && clientReqRemoteW && (unactivatedReqFwdArb || !networkReqRemoteW[0]));
        let req = link_mem_req.first();
        link_mem_req.deq();
        req.reqControllerId = controllerPort;
        links_controllers_req[0].sendToNext(req);
        unactivatedReqFwdArb <= False;
        localReqToRemoteW.send();
        debugLog.record($format("    router: forward client's unactivated request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId));
    endrule

    (* mutually_exclusive = "fwdLocalUnactivatedReqToChain0NonMaster, fwdRemoteUnactivatedReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdRemoteUnactivatedReqToChain0NonMaster (!isMaster && initialized && !localReqToRemoteW && networkReqRemoteW[0]);
        let req <- links_controllers_req[0].recvFromPrev();
        links_controllers_req[0].sendToNext(req);
        unactivatedReqFwdArb <= True;
        debugLog.record($format("    router: forward global unactivated request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId));
    endrule

    (* mutually_exclusive = "recvLocalUnactivatedReqFromGlobalChain1, fwdUnactivatedReqToChain1NonMaster" *)
    (* fire_when_enabled *)
    rule fwdUnactivatedReqToChain1NonMaster (!isMaster && networkReqRemoteW[1]);
        let req <- links_controllers_req[1].recvFromPrev();
        links_controllers_req[1].sendToNext(req);
        debugLog.record($format("    router: forward global unactivated request to global chain 1, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId));
    endrule

    (* mutually_exclusive = "recvLocalUnactivatedReqFromClient, fwdUnactivatedReqToChain0Master, fwdLocalUnactivatedReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdUnactivatedReqToChain0Master (isMaster && clientReqRemoteW);
        let req = link_mem_req.first();
        link_mem_req.deq();
        req.reqControllerId = controllerPort;
        links_controllers_req[0].sendToNext(req);
        debugLog.record($format("    router: forward client's unactivated request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId));
    endrule
    
    (* mutually_exclusive = "recvLocalUnactivatedReqFromGlobalChain0, fwdUnactivatedReqToChain1Master, fwdRemoteUnactivatedReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdUnactivatedReqToChain1Master (isMaster && networkReqRemoteW[0]);
        let req <- links_controllers_req[0].recvFromPrev();
        links_controllers_req[1].sendToNext(req);
        debugLog.record($format("    router: forward global unactivated request to global chain 1, addr =0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, req.reqControllerId));
    endrule

    // =======================================================================
    //
    // Responses
    //
    // (1) Responses from local memory 
    // (2) Write back responses from local clients
    // (3) Responses from remote memory/clients
    //
    // =======================================================================
    
    Reg#(Bool)   localRespArb          <- mkReg(True);
    Reg#(Bool)   fwdRespArb            <- mkReg(True);
    Reg#(Bool)   writebackRespArb      <- mkReg(True);
    PulseWire    writebackLocalW       <- mkPulseWire();
    PulseWire    writebackRemoteW      <- mkPulseWire();
    PulseWire    memoryLocalRespW      <- mkPulseWire();
    PulseWire    memoryRemoteRespW     <- mkPulseWire();
    PulseWire    remoteRespWritebackW  <- mkPulseWire();
    PulseWire    remoteRespLocalW      <- mkPulseWire();
    PulseWire    remoteWritebackRespW  <- mkPulseWire();

    (* fire_when_enabled *)
    rule checkLocalClientResp (True);
        let resp = link_mem_resp.first();
        if (resp.controllerId == controllerPort) // local write back responses
        begin
            writebackLocalW.send();
        end
        else 
        begin
            writebackRemoteW.send();
        end
    endrule

    (* fire_when_enabled *)
    rule checkRemoteResp (True);
        let resp = link_controllers_resp.first();
        if (resp.clientId == 0) // is write back response
        begin
            remoteRespWritebackW.send();
        end
        else 
        begin
            remoteRespLocalW.send();
        end
    endrule


    (* fire_when_enabled *)
    rule memoryFwdResp (localMemRespQ.first().controllerId != controllerPort && (fwdRespArb || !writebackRemoteW));
        let resp = localMemRespQ.first();
        localMemRespQ.deq();
        fwdRespArb <= False;
        link_controllers_resp.enq(resp.controllerId, resp);
        memoryRemoteRespW.send();
        debugLog.record($format("    router: forward memory response to remote response network, val=0x%x, meta=0x%x, dest=%03d, controller=%02d",
                        resp.val, resp.meta, resp.clientId, resp.controllerId));
    endrule
    
    (* mutually_exclusive = "wbFwdResp, memoryFwdResp" *)
    (* fire_when_enabled *)
    rule wbFwdResp (!memoryRemoteRespW && writebackRemoteW);
        let resp = link_mem_resp.first();
        link_mem_resp.deq();
        fwdRespArb <= True;
        link_controllers_resp.enq(resp.controllerId, resp);
        debugLog.record($format("    router: forward %s response to remote response network, val=0x%x, meta=0x%x, dest=%03d, controller=%02d",
                        (resp.clientId == 0)? "write-back" : "client", resp.val, resp.meta, resp.clientId, resp.controllerId));
    endrule
    
    (* fire_when_enabled *)
    rule memoryLocalResp (localMemRespQ.first().controllerId == controllerPort && (localRespArb || !remoteRespLocalW));
        let resp = localMemRespQ.first();
        localMemRespQ.deq();
        link_mem_resp.enq(resp.clientId, resp);
        localRespArb <= False;
        memoryLocalRespW.send();
        debugLog.record($format("    router: send memory response to local response network, val=0x%x, meta=0x%x, dest=%03d, controller=%02d",
                        resp.val, resp.meta, resp.clientId, resp.controllerId));
    endrule
    
    (* mutually_exclusive = "memoryLocalResp, remoteToLocalResp" *)
    (* fire_when_enabled *)
    rule remoteToLocalResp (!memoryLocalRespW && remoteRespLocalW);
        let resp = link_controllers_resp.first();
        link_controllers_resp.deq();
        link_mem_resp.enq(resp.clientId, resp);
        localRespArb <= True;
        debugLog.record($format("    router: send remote response to local response network, val=0x%x, meta=0x%x, dest=%03d, controller=%02d",
                        resp.val, resp.meta, resp.clientId, resp.controllerId));
    endrule

    (* mutually_exclusive = "remoteToLocalResp, remoteWritebackResp" *)
    (* fire_when_enabled *)
    rule remoteWritebackResp (remoteRespWritebackW && (writebackRespArb || !writebackLocalW));
        let resp = link_controllers_resp.first();
        link_controllers_resp.deq();
        writebackRespQ.enq(resp);
        writebackRespArb <= False;
        remoteWritebackRespW.send();
        debugLog.record($format("    router: receive a remote writeback response, val=0x%x, dest=%03d",
                        resp.val, resp.clientId));
    endrule

    (* mutually_exclusive = "wbLocalResp, wbFwdResp" *)
    (* mutually_exclusive = "wbLocalResp, remoteWritebackResp" *)
    (* fire_when_enabled *)
    rule wbLocalResp (writebackLocalW && !remoteWritebackRespW);
        let resp = link_mem_resp.first();
        link_mem_resp.deq();
        writebackRespQ.enq(resp);
        writebackRespArb <= True;
        debugLog.record($format("    router: receive a local writeback response from a local client, val=0x%x", resp.val));
    endrule
    
    // ====================================================================
    //
    // Coherent scratchpad multi controller router debug scan for 
    // deadlock debugging.
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    // Local network channels
    dbg_list <- addDebugScanField(dbg_list, "link_mem_req notEmpty", link_mem_req.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_req notFull", link_mem_req.notFull);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_resp notEmpty", link_mem_resp.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_resp notFull", link_mem_resp.notFull);
    dbg_list <- addDebugScanField(dbg_list, "links_mem_activatedReq0 notEmpty", links_mem_activatedReq[0].recvNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "links_mem_activatedReq0 notFull", links_mem_activatedReq[0].sendNotFull);
    dbg_list <- addDebugScanField(dbg_list, "links_mem_activatedReq1 notEmpty", links_mem_activatedReq[1].recvNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "links_mem_activatedReq1 notFull", links_mem_activatedReq[1].sendNotFull);
    // Global network channels
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_req0 notEmpty", links_controllers_req[0].recvNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_req0 notFull", links_controllers_req[0].sendNotFull);
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_req1 notEmpty", links_controllers_req[1].recvNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_req1 notFull", links_controllers_req[1].sendNotFull);
    dbg_list <- addDebugScanField(dbg_list, "link_controllers_resp notEmpty", link_controllers_resp.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "link_controllers_resp notFull", link_controllers_resp.notFull);
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_activatedReq0 notEmpty", links_controllers_activatedReq[0].recvNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_activatedReq0 notFull", links_controllers_activatedReq[0].sendNotFull);
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_activatedReq1 notEmpty", links_controllers_activatedReq[1].recvNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "links_controllers_activatedReq1 notFull", links_controllers_activatedReq[1].sendNotFull);

    String debugScanName = "Coherent Scratchpad Controller " + integerToString(dataScratchpadID) + " Router in Domain " + integerToString(coherenceDomainID);

    let dbgNode <- mkDebugScanNode(debugScanName + "(coherent-scratchpad-memory-controller.bsv)", dbg_list);

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action sendActivatedReq(COH_SCRATCH_ACTIVATED_REQ#(t_ADDR) req);
        activatedReqQ.enq(req);
        debugLog.record($format("    router: receive an activated request from local controller, addr=0x%x", req.addr));
    endmethod                       
   
    method Action sendMemoryResp(COH_SCRATCH_PORT_NUM dest, COH_SCRATCH_RESP resp);
        localMemRespQ.enq(resp);
        debugLog.record($format("    router: receive a memory response from local controller, receiver: clientId=%03d, controllerId=%02d",
                        resp.clientId, resp.controllerId));
    endmethod

    method ActionValue#(COH_SCRATCH_MEM_REQ#(t_ADDR)) unactivatedReq();
        let r = unactivatedReqQ.first();
        unactivatedReqQ.deq();
        return r;
    endmethod

    method COH_SCRATCH_MEM_REQ#(t_ADDR) peekUnactivatedReq();
        let r = unactivatedReqQ.first();
        return r;
    endmethod

    method ActionValue#(COH_SCRATCH_RESP) writebackResp();
        let r = writebackRespQ.first();
        writebackRespQ.deq();
        return r;
    endmethod

    method COH_SCRATCH_RESP peekWritebackResp();
        let r = writebackRespQ.first();
        return r;
    endmethod

endmodule

`endif

//
// mkCachedCoherentScratchpadSingleControllerRouter --
//     This module handles the situation when each coherent scratchpad client 
//     has a private cache and there is only one controller in the coherence 
//     domain. 
//
//     The controller router collects coherence requests from clients and 
//     send responses back to the clients. 
//
//     Under the snoopy-based protocol, this module serves as an ordering point.
//
module [CONNECTED_MODULE] mkCachedCoherentScratchpadSingleControllerRouter#(Integer dataScratchpadID,
                                                                            DEBUG_FILE debugLog)
    // interface:
    (COH_SCRATCH_CACHED_CONTROLLER_ROUTER#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              // Coherence messages
              Alias#(COH_SCRATCH_MEM_REQ#(t_ADDR), t_COH_SCRATCH_REQ),
              Alias#(COH_SCRATCH_ACTIVATED_REQ#(t_ADDR), t_COH_SCRATCH_ACTIVATED_REQ));

    FIFOF#(t_COH_SCRATCH_ACTIVATED_REQ) activatedReqQ <- mkBypassFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) localMemRespQ <- mkBypassFIFOF();
    FIFOF#(t_COH_SCRATCH_REQ) unactivatedReqQ <- mkFIFOF();
    FIFOF#(COH_SCRATCH_RESP)  writebackRespQ  <- mkFIFOF();
    
    // =======================================================================
    //
    // Coherent scratchpad clients and this controller are connected via rings.
    //
    // Three rings are required to avoid deadlocks: one for requests, 
    // one for responses, and one for activated requests.
    //
    // =======================================================================

    //
    // Connections between the coherent scratchpad controller and its local clients
    //
    String clientControllerRingName = "Coherent_Scratchpad_" + integerToString(dataScratchpadID);
    
    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_REQ) link_mem_req <- 
        mkConnectionAddrRingNode(clientControllerRingName + "_Req", 0);

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP) link_mem_resp <-
        (`ADDR_RING_DEBUG_ENABLE == 1)?
        mkDebugConnectionAddrRingNodeNtoN(clientControllerRingName + "_Resp", 0, debugLog):
        mkConnectionAddrRingNodeNtoN(clientControllerRingName + "_Resp", 0);

    // Broadcast ring
    CONNECTION_CHAIN#(t_COH_SCRATCH_ACTIVATED_REQ) link_mem_activatedReq <- 
        mkConnectionChain(clientControllerRingName + "_ActivatedReq");

    // =======================================================================
    //
    // Unactivated requests
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule collectClientReq (True);
        let req = link_mem_req.first();
        link_mem_req.deq();
        debugLog.record($format("    router: receive an unactivated request: addr=0x%x", req.addr));
        unactivatedReqQ.enq(req);
    endrule
   
    // =======================================================================
    //
    // Activated requests
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule sendActivatedReqToNetwork (True);
        let req = activatedReqQ.first();
        activatedReqQ.deq();
        link_mem_activatedReq.sendToNext(req);
        debugLog.record($format("    router: sendActivatedReq: addr=0x%x, sender=%d", req.addr, req.requester));
    endrule

    (* fire_when_enabled *)
    rule dropActivatedReqFromNetwork (True);
        let req <- link_mem_activatedReq.recvFromPrev();
        debugLog.record($format("    router: dropActivatedReq: addr=0x%x, sender=%d", req.addr, req.requester));
    endrule
    
    // =======================================================================
    //
    // Responses
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule sendMemoryResponse (True);
        let resp = localMemRespQ.first();
        localMemRespQ.deq();
        debugLog.record($format("    router: send a memory response"));
        link_mem_resp.enq(tpl_1(resp), tpl_2(resp));
    endrule

    (* fire_when_enabled *)
    rule collectClientResponse (True);
        let resp = link_mem_resp.first();
        link_mem_resp.deq();
        debugLog.record($format("    router: receive a writeback response"));
        writebackRespQ.enq(resp);
    endrule
    
    // ====================================================================
    //
    // Coherent scratchpad single controller router debug scan for 
    // deadlock debugging.
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    // Network channels
    dbg_list <- addDebugScanField(dbg_list, "link_mem_req notEmpty", link_mem_req.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_req notFull", link_mem_req.notFull);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_resp notEmpty", link_mem_resp.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_resp notFull", link_mem_resp.notFull);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_activatedReq notEmpty", link_mem_activatedReq.recvNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "link_mem_activatedReq notFull", link_mem_activatedReq.sendNotFull);
   
    String debugScanName = "Coherent Scratchpad Controller Router in Domain " + integerToString(dataScratchpadID);

    let dbgNode <- mkDebugScanNode(debugScanName + "(coherent-scratchpad-memory-controller.bsv)", dbg_list);

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action sendActivatedReq(COH_SCRATCH_ACTIVATED_REQ#(t_ADDR) req);
        activatedReqQ.enq(req);
        debugLog.record($format("    router: receive an activated request"));
    endmethod                       
   
    method Action sendMemoryResp(COH_SCRATCH_PORT_NUM dest, COH_SCRATCH_RESP resp);
        localMemRespQ.enq(tuple2(dest,resp));
        debugLog.record($format("    router: receive a memory response"));
    endmethod

    method ActionValue#(COH_SCRATCH_MEM_REQ#(t_ADDR)) unactivatedReq();
        let r = unactivatedReqQ.first();
        unactivatedReqQ.deq();
        return r;
    endmethod

    method COH_SCRATCH_MEM_REQ#(t_ADDR) peekUnactivatedReq();
        let r = unactivatedReqQ.first();
        return r;
    endmethod

    method ActionValue#(COH_SCRATCH_RESP) writebackResp();
        let r = writebackRespQ.first();
        writebackRespQ.deq();
        return r;
    endmethod

    method COH_SCRATCH_RESP peekWritebackResp();
        let r = writebackRespQ.first();
        return r;
    endmethod

endmodule


// ========================================================================
//
// Coherent scratchpad controller without private caches (remote access) 
//
// ========================================================================

//
// Interface of uncached coherent scratchpad controller's router
//
typedef Tuple2#(COH_SCRATCH_REMOTE_REQ#(t_ADDR, t_DATA), COH_SCRATCH_CTRLR_PORT_NUM) COH_SCRATCH_UNCACHED_CTRLR_REQ#(type t_ADDR, type t_DATA);

interface COH_SCRATCH_UNCACHED_CONTROLLER_ROUTER#(type t_ADDR, type t_DATA);
    // response to network
    method Action sendResp(COH_SCRATCH_PORT_NUM dest, 
                           COH_SCRATCH_CTRLR_PORT_NUM controllerId, 
                           COH_SCRATCH_REMOTE_RESP#(t_DATA) resp);
    // client's request from network
    method ActionValue#(COH_SCRATCH_UNCACHED_CTRLR_REQ#(t_ADDR, t_DATA)) getReq();
    method COH_SCRATCH_UNCACHED_CTRLR_REQ#(t_ADDR, t_DATA) peekReq();
endinterface: COH_SCRATCH_UNCACHED_CONTROLLER_ROUTER

typedef Bit#(2) COH_SCRATCH_CTRLR_WRITE_DATA_IDX;

typedef struct
{
    COH_SCRATCH_PORT_NUM            requester;
    COH_SCRATCH_CTRLR_PORT_NUM      reqControllerId;
    COH_SCRATCH_REMOTE_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META       globalReadMeta;
}
COH_SCRATCH_UNCACHED_CTRLR_READ_REQ_INFO
    deriving (Eq, Bits);

typedef struct
{
    COH_SCRATCH_PORT_NUM              requester;
    COH_SCRATCH_CTRLR_PORT_NUM        reqControllerId;
    t_ADDR                            addr;
    COH_SCRATCH_CTRLR_WRITE_DATA_IDX  writeDataIdx;
    COH_SCRATCH_REMOTE_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META         globalReadMeta;
    Bool                              isRead;
}
COH_SCRATCH_UNCACHED_CTRLR_MEM_REQ#(type t_ADDR)
    deriving (Eq, Bits);

//
// mkUncachedCoherentScratchpadController --
//     This module handles the situation where there are no private caches
//     in this coherence domain. 
//
//     The controller collects the remote read/write requests from coherent 
///    scratchpad clients and forwards them to the next level memory (central 
//     cache) through a private scratchpad interface. It also sends the private
//     scratchpad responses back to the coherent scratchpad clients. 
//
module [CONNECTED_MODULE] mkUncachedCoherentScratchpadController#(Integer dataScratchpadID, 
                                                                  NumTypeParam#(t_IN_ADDR_SZ) inAddrSz,
                                                                  NumTypeParam#(t_IN_DATA_SZ) inDataSz,
                                                                  COH_SCRATCH_CONTROLLER_CONFIG conf)
    // interface:
    ()
    provisos (Alias#(Bit#(t_IN_ADDR_SZ), t_ADDR),
              Alias#(Bit#(t_IN_DATA_SZ), t_DATA),
              // Coherence messages
              Alias#(COH_SCRATCH_REMOTE_READ_RESP#(t_DATA), t_COH_SCRATCH_READ_RESP),
              Alias#(COH_SCRATCH_REMOTE_RESP#(t_DATA), t_COH_SCRATCH_RESP),
              Alias#(COH_SCRATCH_UNCACHED_CTRLR_MEM_REQ#(t_ADDR), t_MEM_REQ),
              Bits#(COH_SCRATCH_CTRLR_WRITE_DATA_IDX, t_WRITE_DATA_IDX_SZ),
              Bits#(COH_SCRATCH_MEM_ADDRESS, t_COH_SCRATCH_MEM_ADDR_SZ),
              NumAlias#(TExp#(t_WRITE_DATA_IDX_SZ), n_WRITES));

    String debugLogFilename = "coherent_scratchpad_" + integerToString(dataScratchpadID) + "_controller.out";

    DEBUG_FILE debugLog <- (`COHERENT_SCRATCHPAD_DEBUG_ENABLE == 1)?
                           mkDebugFile(debugLogFilename):
                           mkDebugFileNull(debugLogFilename); 
    //
    // Elaboration time checks
    //
    if (valueOf(t_IN_ADDR_SZ) > valueOf(t_COH_SCRATCH_MEM_ADDR_SZ))
    begin
        error("Coherent scratchpad address size is not big enough. Increase parameter COHERENT_SCRATCHPAD_MEMORY_ADDR_BITS.");
    end
    
    // =======================================================================
    //
    // Coherent scratchpad controller partition module
    //
    // =======================================================================
    
    let partition <- conf.partition();

    // =======================================================================
    //
    // Coherent scratchpad controller router
    //
    // =======================================================================
    
    COH_SCRATCH_UNCACHED_CONTROLLER_ROUTER#(t_ADDR, t_DATA) router;

`ifndef COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z

    router <- (!conf.multiController)? mkUncachedCoherentScratchpadSingleControllerRouter(dataScratchpadID, debugLog):
                                       mkUncachedCoherentScratchpadMultiControllerRouter(dataScratchpadID, conf.coherenceDomainID, 
                                                                                         partition.isLocalReq, conf.isMaster, debugLog);
`else
    
    if (conf.multiController)
    begin
        error("COHERENT_SCRATCHPAD_MULTI_CONTROLLER_ENABLE is not enabled");
    end
    router <- mkUncachedCoherentScratchpadSingleControllerRouter(dataScratchpadID, debugLog);

`endif

    // ===============================================================================
    //
    // Instantiate a private scratchpad that serves as the interface to read/write 
    // data from/to local memory
    //
    // ===============================================================================
    
    SCRATCHPAD_CONFIG dataMemConfig = defaultValue;
    dataMemConfig.cacheMode = SCRATCHPAD_CACHED;
    MEMORY_IFC#(t_ADDR, t_DATA) dataMem  <- mkScratchpad(dataScratchpadID, dataMemConfig);

    MEMORY_HEAP_IMM#(COH_SCRATCH_CTRLR_WRITE_DATA_IDX, t_DATA) reqInfo_writeData <- mkMemoryHeapUnionLUTRAM();
    
    FIFOF#(t_MEM_REQ) incomingReqQ                                                                       <- mkSizedFIFOF(2*valueOf(n_WRITES));
    FIFOF#(COH_SCRATCH_UNCACHED_CTRLR_READ_REQ_INFO) dataMemReqQ                                         <- mkSizedFIFOF(32);
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_CTRLR_PORT_NUM)) ackRespQ                           <- mkBypassFIFOF();
    FIFOF#(Tuple3#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_CTRLR_PORT_NUM, t_COH_SCRATCH_READ_RESP)) memRespQ  <- mkBypassFIFOF();
    FIFOF#(Tuple3#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_CTRLR_PORT_NUM, t_COH_SCRATCH_RESP)) outputRespQ    <- mkSizedFIFOF(8);

    //
    // collectClientReq --
    //     Collect scratchpad client requests from the router.
    // For write and fence requests, send ack back to the clients. 
    //
    rule colletClientReq (True);
        let client_req <- router.getReq();
        match {.req, .controller_id} = client_req;
        
        t_MEM_REQ lookup_req = ?;
        lookup_req.requester       = req.requester;
        lookup_req.reqControllerId = controller_id;
        lookup_req.addr            = req.addr;
        
        if (req.reqInfo matches tagged COH_SCRATCH_REMOTE_READ .read_info)
        begin
            lookup_req.clientMeta      = read_info.clientMeta;
            lookup_req.globalReadMeta  = read_info.globalReadMeta;
            lookup_req.isRead          = True;
            debugLog.record($format("  collect READ request: sender=%d, addr=0x%x, meta=0x%x",  
                            lookup_req.requester, lookup_req.addr, lookup_req.clientMeta));
        end
        else if (req.reqInfo matches tagged COH_SCRATCH_REMOTE_WRITE .write_info)
        begin
            let data_idx <- reqInfo_writeData.malloc();
            reqInfo_writeData.upd(data_idx, write_info.data);
            lookup_req.writeDataIdx = data_idx;
            lookup_req.isRead       = False;
            ackRespQ.enq(tuple2(req.requester, controller_id));
            debugLog.record($format("  collect WRITE request: sender=%d, addr=0x%x, data=0x%x", 
                            lookup_req.requester, lookup_req.addr, write_info.data));
        end
        incomingReqQ.enq(lookup_req);
    endrule

    rule accessDataMem (True);
        let req = incomingReqQ.first();
        incomingReqQ.deq();

        if (req.isRead) // read request
        begin
            dataMemReqQ.enq(COH_SCRATCH_UNCACHED_CTRLR_READ_REQ_INFO { requester: req.requester,
                                                                       reqControllerId: req.reqControllerId,
                                                                       clientMeta: req.clientMeta,
                                                                       globalReadMeta: req.globalReadMeta });
            dataMem.readReq(req.addr);
            debugLog.record($format("  accessDataMem: READ sender=%d, addr=0x%x, meta=0x%x",
                             req.requester, req.addr, req.clientMeta));
        end
        else // write request
        begin
            let w_data = reqInfo_writeData.sub(req.writeDataIdx);
            reqInfo_writeData.free(req.writeDataIdx);
            dataMem.write(req.addr, w_data); 
            debugLog.record($format("  accessDataMem: WRTIE sender=%d, addr=0x%x, data=0x%x",  
                             req.requester, req.addr, w_data));
        end

    endrule

    rule recvDataResp (True);
        let data <- dataMem.readRsp();
        let r = dataMemReqQ.first();
        dataMemReqQ.deq();
        memRespQ.enq(tuple3(r.requester, r.reqControllerId, COH_SCRATCH_REMOTE_READ_RESP { val: data,
                                                                                           clientMeta: r.clientMeta, 
                                                                                           globalReadMeta: r.globalReadMeta }));
        debugLog.record($format("    recvDataResp: send data response: dest=%03d, controllerId=%02d, val=0x%x, meta=0x%x", 
                        r.requester, r.reqControllerId, data, r.clientMeta));
    endrule

    Reg#(Bit#(2)) ackRespArb <- mkReg(0);

    (* fire_when_enabled *)
    rule sendToOutputRespQ (True);
        if (ackRespQ.notEmpty() && ((ackRespArb != 0) || !memRespQ.notEmpty()))
        begin
            match {.client_id, .controller_id} = ackRespQ.first();
            ackRespQ.deq();
            outputRespQ.enq(tuple3(client_id, controller_id, tagged COH_SCRATCH_REMOTE_WRITE));    
            debugLog.record($format("    sendToOutputRespQ: WRITE ACK response: dest=%03d, controllerId=%02d", 
                            client_id, controller_id)); 
        end
        else
        begin
            let mem_resp = memRespQ.first();
            memRespQ.deq();
            outputRespQ.enq(tuple3(tpl_1(mem_resp), tpl_2(mem_resp), tagged COH_SCRATCH_REMOTE_READ tpl_3(mem_resp)));
            debugLog.record($format("    sendToOutputRespQ: READ DATA response: dest=%03d, controllerId=%02d, val=0x%x, meta=0x%x", 
                            tpl_1(mem_resp), tpl_2(mem_resp), tpl_3(mem_resp).val, tpl_3(mem_resp).clientMeta));
        end
        ackRespArb <= ackRespArb + 1;
    endrule

    (* fire_when_enabled *)
    rule sendCoherentScratchpadResp (True);
        let resp = outputRespQ.first();
        outputRespQ.deq();
        router.sendResp(tpl_1(resp), tpl_2(resp), tpl_3(resp));
    endrule

endmodule

//
// mkUncachedCoherentScratchpadMultiControllerRouter --
//     This module handles the situation where there are no private caches
//     in this coherence domain. 
//
//     The controller router collects requests from its local clients, forwards 
//     local requests to its local controller and forwards the rest to the 
//     remote controller(s). The router also forwards associated responses 
//     to its local clients. 
//
module [CONNECTED_MODULE] mkUncachedCoherentScratchpadMultiControllerRouter#(Integer dataScratchpadID,
                                                                             Integer coherenceDomainID,  
                                                                             function Bool isLocalReq(COH_SCRATCH_MEM_ADDRESS addr),
                                                                             Bool isMaster,
                                                                             DEBUG_FILE debugLog)
    // interface:
    (COH_SCRATCH_UNCACHED_CONTROLLER_ROUTER#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Coherence messages
              Alias#(COH_SCRATCH_REMOTE_REQ#(t_ADDR, t_DATA), t_COH_SCRATCH_REQ),
              Alias#(COH_SCRATCH_REMOTE_RESP#(t_DATA), t_COH_SCRATCH_RESP),
              Alias#(COH_SCRATCH_UNCACHED_CTRLR_REQ#(t_ADDR, t_DATA), t_CTRLR_REQ),
              Alias#(COH_SCRATCH_CONTROLLERS_REMOTE_REQ#(t_ADDR, t_DATA), t_CONTROLLERS_REQ),
              Alias#(COH_SCRATCH_CONTROLLERS_REMOTE_RESP#(t_DATA), t_CONTROLLERS_RESP));
    
    FIFOF#(t_CTRLR_REQ) remoteReqQ <- mkFIFOF();
    FIFOF#(Tuple3#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_CTRLR_PORT_NUM, t_COH_SCRATCH_RESP)) localMemRespQ <- mkBypassFIFOF();
    
    // ==============================================================================
    //
    // Coherent scratchpad clients and this controller are connected via rings.
    //
    // Two rings are required to avoid deadlocks: one for requests, one for responses.
    //
    // For multi-controller settings, hierarchical rings are used, which means
    // controllers are also connected via two rings.
    //
    // To prevent deadlocks, the broadcast request ring require 2 channels and the 
    // dateline technique is used to avoid circular dependency. 
    // Dateline is allocated at the master controller. 
    //
    // ===============================================================================

    //
    // Connections between the coherent scratchpad controller and its local clients
    //
    String clientControllerRingName = "Coherent_Scratchpad_" + integerToString(dataScratchpadID);
    
    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_REQ) link_mem_req <- 
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Req", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Req", 0);

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_RESP) link_mem_resp <-
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Resp", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Resp", 0);

    //
    // Connections between multiple controllers
    //
    String controllersRingName = "Coherent_Scratchpad_Controllers_" + integerToString(coherenceDomainID);
    
    // Broadcast ring (with 2 channels)
    Vector#(2, CONNECTION_CHAIN#(t_CONTROLLERS_REQ)) links_controllers_req = newVector();
    links_controllers_req[0] <- mkConnectionChain(controllersRingName + "_Req_0");
    links_controllers_req[1] <- mkConnectionChain(controllersRingName + "_Req_1");

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_CTRLR_PORT_NUM, t_CONTROLLERS_RESP) link_controllers_resp <- (isMaster)?
        mkConnectionAddrRingNodeNtoN(controllersRingName + "_Resp", 0):
        mkConnectionAddrRingDynNodeNtoN(controllersRingName + "_Resp");

    Reg#(COH_SCRATCH_CTRLR_PORT_NUM) controllerPort <- mkReg(0);
    Reg#(Bool) initialized <- mkReg(False);
    
    rule doInit (!initialized);
        let port_num = link_controllers_resp.nodeID();
        debugLog.record($format("    router: assigned controller port ID = %02d", port_num));
        controllerPort <= port_num;
        initialized    <= True;
    endrule
    
    // =======================================================================
    //
    // Remote requests (from clients or from global request ring)
    //  (1) local: forward to the local controller
    //  (2) non-local: forward to the link_controllers_req ring
    //
    // =======================================================================
    
    PulseWire   clientReqLocalW             <- mkPulseWire();
    PulseWire   clientReqRemoteW            <- mkPulseWire();
    PulseWire   localReqToRemoteW           <- mkPulseWire();
    Vector#(2, PulseWire) networkReqLocalW  <- replicateM(mkPulseWire());
    Vector#(2, PulseWire) networkReqRemoteW <- replicateM(mkPulseWire());
    LOCAL_ARBITER#(3) reqRecvArb            <- mkLocalArbiter();
    Wire#(Bit#(2)) pickLocalReqIdx          <- mkWire();
    Reg#(Bool) reqFwdArb                    <- mkReg(True);

    (* fire_when_enabled *)
    rule checkClientReq (True);
        let req  = link_mem_req.first();
        let addr = req.addr;
        Bool is_local = isLocalReq(zeroExtendNP(pack(addr)));
        Bool is_read = False;
        if (req.reqInfo matches tagged COH_SCRATCH_REMOTE_READ .info)
        begin
            is_read = True;
        end
        debugLog.record($format("    router: check a request from client: addr=0x%x, %s %s request", 
                        addr, is_local? "local" : "remote", is_read? "READ" : "WRITE" ));
        if (is_local)
        begin
            clientReqLocalW.send();
        end
        else
        begin
            clientReqRemoteW.send();
        end
    endrule

    for(Integer p = 0; p < 2; p = p + 1)
    begin
        (* fire_when_enabled *)
        rule checkGlobalRingReq (True);
            let req = links_controllers_req[p].peekFromPrev();
            let addr = req.reqLocal.addr;
            Bool is_local = isLocalReq(zeroExtendNP(pack(addr)));
            Bool is_read = False;
            if (req.reqLocal.reqInfo matches tagged COH_SCRATCH_REMOTE_READ .info)
            begin
                is_read = True;
            end
            debugLog.record($format("    router: check a request from global chain[%01d]: addr=0x%x, %s %s request, requester=%03d, reqControllerId=%02d",
                            p, addr, is_local? "local" : "remote", is_read? "READ" : "WRITE", req.reqLocal.requester, req.reqControllerId));
            if (is_local)
            begin
                networkReqLocalW[p].send();
            end
            else
            begin
                networkReqRemoteW[p].send();
            end
        endrule
    end

    (* fire_when_enabled *)
    rule pickLocalReq (initialized);
        LOCAL_ARBITER_CLIENT_MASK#(3) reqs = newVector();
        reqs[0] = clientReqLocalW;
        reqs[1] = networkReqLocalW[0];
        reqs[2] = networkReqLocalW[1];
        let winner_idx <- reqRecvArb.arbitrate(reqs, False);
        if (winner_idx matches tagged Valid .req_idx)
        begin
            pickLocalReqIdx <= pack(req_idx);
        end
    endrule

    (* fire_when_enabled *)
    rule recvLocalReqFromClient (initialized && pickLocalReqIdx == 0);
        let req = link_mem_req.first(); 
        link_mem_req.deq(); 
        remoteReqQ.enq(tuple2(req, controllerPort));
        debugLog.record($format("    router: receive a local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "clients", req.addr, req.requester, controllerPort));
    endrule

    (* fire_when_enabled *)
    rule recvLocalReqFromGlobalChain0 (initialized && pickLocalReqIdx == 1);
        let req <- links_controllers_req[0].recvFromPrev();
        remoteReqQ.enq(tuple2(req.reqLocal, req.reqControllerId));
        debugLog.record($format("    router: receive a local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "global chain 0", req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* fire_when_enabled *)
    rule recvLocalReqFromGlobalChain1 (initialized && pickLocalReqIdx == 2);
        let req <- links_controllers_req[1].recvFromPrev();
        remoteReqQ.enq(tuple2(req.reqLocal, req.reqControllerId));
        debugLog.record($format("    router: receive a local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "global chain 1", req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* fire_when_enabled *)
    rule fwdLocalReqToChain0NonMaster (!isMaster && initialized && clientReqRemoteW && (reqFwdArb || !networkReqRemoteW[0]));
        let req = link_mem_req.first();
        link_mem_req.deq();
        let controller_req = COH_SCRATCH_CONTROLLERS_REMOTE_REQ { reqControllerId: controllerPort, 
                                                                  reqLocal: req };
        links_controllers_req[0].sendToNext(controller_req);
        reqFwdArb <= False;
        localReqToRemoteW.send();
        debugLog.record($format("    router: forward client's request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, controller_req.reqControllerId));
    endrule

    (* mutually_exclusive = "fwdLocalReqToChain0NonMaster, fwdRemoteReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdRemoteReqToChain0NonMaster (!isMaster && initialized && !localReqToRemoteW && networkReqRemoteW[0]);
        let req <- links_controllers_req[0].recvFromPrev();
        links_controllers_req[0].sendToNext(req);
        reqFwdArb <= True;
        debugLog.record($format("    router: forward a global request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* mutually_exclusive = "recvLocalReqFromGlobalChain1, fwdReqToChain1NonMaster" *)
    (* fire_when_enabled *)
    rule fwdReqToChain1NonMaster (!isMaster && networkReqRemoteW[1]);
        let req <- links_controllers_req[1].recvFromPrev();
        links_controllers_req[1].sendToNext(req);
        debugLog.record($format("    router: forward a global request to global chain 1, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* mutually_exclusive = "recvLocalReqFromClient, fwdReqToChain0Master, fwdLocalReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdReqToChain0Master (isMaster && clientReqRemoteW);
        let req = link_mem_req.first();
        link_mem_req.deq();
        let controller_req = COH_SCRATCH_CONTROLLERS_REMOTE_REQ { reqControllerId: controllerPort, 
                                                                  reqLocal: req };
        links_controllers_req[0].sendToNext(controller_req);
        debugLog.record($format("    router: forward client's request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, controller_req.reqControllerId));
    endrule
    
    (* mutually_exclusive = "recvLocalReqFromGlobalChain0, fwdReqToChain1Master, fwdRemoteReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdReqToChain1Master (isMaster && networkReqRemoteW[0]);
        let req <- links_controllers_req[0].recvFromPrev();
        links_controllers_req[1].sendToNext(req);
        debugLog.record($format("    router: forward global unactivated request to global chain 1, addr =0x%x, requester=%03d, reqControllerId=%02d",
                        req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule


    // =======================================================================
    //
    // Responses
    //
    // (1) Responses from local memory 
    // (2) Responses from remote memories
    //
    // =======================================================================
    
    Reg#(Bool)  localRespArb      <- mkReg(True);
    PulseWire   memoryLocalRespW  <- mkPulseWire();

    (* fire_when_enabled *)
    rule memoryFwdResp (tpl_2(localMemRespQ.first()) != controllerPort);
        match {.client_id, .controller_id, .resp} = localMemRespQ.first();
        localMemRespQ.deq();
        link_controllers_resp.enq(controller_id, COH_SCRATCH_CONTROLLERS_REMOTE_RESP{ clientId: client_id, resp: resp});
        debugLog.record($format("    router: forward memory response to remote response network, dest=%03d, controller=%02d",
                        client_id, controller_id));
    endrule

    (* fire_when_enabled *)
    rule memoryLocalResp (tpl_2(localMemRespQ.first()) == controllerPort && (localRespArb || !link_controllers_resp.notEmpty()));
        match {.client_id, .controller_id, .resp} = localMemRespQ.first();
        localMemRespQ.deq();
        link_mem_resp.enq(client_id, resp);
        localRespArb <= False;
        memoryLocalRespW.send();
        debugLog.record($format("    router: send memory response to local response network, dest=%03d, controller=%02d",
                        client_id, controller_id));
    endrule

    (* mutually_exclusive = "memoryLocalResp, remoteToLocalResp" *)
    (* fire_when_enabled *)
    rule remoteToLocalResp (!memoryLocalRespW);
        let controller_resp = link_controllers_resp.first();
        link_controllers_resp.deq();
        link_mem_resp.enq(controller_resp.clientId, controller_resp.resp);
        localRespArb <= True;
        debugLog.record($format("    router: send remote response to local response network, dest=%03d, controller=%02d",
                        controller_resp.clientId, controllerPort));
    endrule
    
    // =======================================================================
    //
    // Methods
    //
    // =======================================================================
    
    method Action sendResp(COH_SCRATCH_PORT_NUM dest, 
                           COH_SCRATCH_CTRLR_PORT_NUM controllerId, 
                           COH_SCRATCH_REMOTE_RESP#(t_DATA) resp);
        localMemRespQ.enq(tuple3(dest, controllerId, resp));
        debugLog.record($format("    router: receive a controller response, dest=%03d, controllerId=%02d", 
                        dest, controllerId));
    endmethod
    
    method ActionValue#(COH_SCRATCH_UNCACHED_CTRLR_REQ#(t_ADDR, t_DATA)) getReq();
        let r = remoteReqQ.first();
        remoteReqQ.deq();
        return r;
    endmethod

    method COH_SCRATCH_UNCACHED_CTRLR_REQ#(t_ADDR, t_DATA) peekReq();
        return remoteReqQ.first();
    endmethod

endmodule

//
// mkUncachedCoherentScratchpadSingleControllerRouter --
//     This module handles the situation where there are no private caches
//     in this coherence domain. 
//
//     The controller router collects remote read/write requests from coherent 
//     scratchpad clients and send responses back to the clients. 
//
module [CONNECTED_MODULE] mkUncachedCoherentScratchpadSingleControllerRouter#(Integer dataScratchpadID,
                                                                              DEBUG_FILE debugLog)
    // interface:
    (COH_SCRATCH_UNCACHED_CONTROLLER_ROUTER#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Coherence messages
              Alias#(COH_SCRATCH_REMOTE_REQ#(t_ADDR, t_DATA), t_COH_SCRATCH_REQ),
              Alias#(COH_SCRATCH_REMOTE_RESP#(t_DATA), t_COH_SCRATCH_RESP));
    
    FIFOF#(t_COH_SCRATCH_REQ) remoteReqQ <- mkFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_RESP)) localMemRespQ <- mkBypassFIFOF();

    // ===============================================================================
    //
    // Coherent scratchpad clients and this controller are connected via rings.
    //
    // Two rings are required to avoid deadlocks: one for requests, one for responses.
    //
    // ===============================================================================

    String clientControllerRingName = "Coherent_Scratchpad_" + integerToString(dataScratchpadID);
    
    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_REQ) link_mem_req <- 
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Req", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Req", 0);

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_RESP) link_mem_resp <-
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Resp", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Resp", 0);

    //
    // collectClientReq --
    //     Collect scratchpad client requests from the router.
    // For write and fence requests, send ack back to the clients. 
    //
    (* fire_when_enabled *)
    rule colletClientReq (True);
        let req = link_mem_req.first();
        link_mem_req.deq();
        debugLog.record($format("    router: receive a client request: sender=%03d, addr=0x%x",
                        req.requester, req.addr));
        remoteReqQ.enq(req);
    endrule
    
    // =======================================================================
    //
    // Responses
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule sendResponse (True);
        let resp = localMemRespQ.first();
        localMemRespQ.deq();
        debugLog.record($format("    router: send a controller response: dest=%03d", tpl_1(resp)));
        link_mem_resp.enq(tpl_1(resp), tpl_2(resp));
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================
    
    method Action sendResp(COH_SCRATCH_PORT_NUM dest, 
                           COH_SCRATCH_CTRLR_PORT_NUM controllerId, 
                           COH_SCRATCH_REMOTE_RESP#(t_DATA) resp);
        localMemRespQ.enq(tuple2(dest,resp));
        debugLog.record($format("    router: receive a controller response, dest=%03d", dest));
    endmethod
    
    method ActionValue#(COH_SCRATCH_UNCACHED_CTRLR_REQ#(t_ADDR, t_DATA)) getReq();
        let r = remoteReqQ.first();
        remoteReqQ.deq();
        return tuple2(r, ?);
    endmethod

    method COH_SCRATCH_UNCACHED_CTRLR_REQ#(t_ADDR, t_DATA) peekReq();
        return tuple2(remoteReqQ.first(), ?);
    endmethod

endmodule

