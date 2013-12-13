//
// Copyright (C) 2013 MIT
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

import FIFO::*;
import FIFOF::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/fpga_components.bsh"

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
    COH_SCRATCH_MSG_TYPE        reqType;
    t_RSHR_ADDR                 addr;
    COH_SCRATCH_MEM_VALUE       val;
    COH_SCRATCH_CLIENT_META     clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
    t_RSHR_IDX                  idx;
    t_RSHR_TAG                  tag;
    Bool                        isCleanWB;
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
    COH_SCRATCH_PORT_NUM       forwardId;
    COH_SCRATCH_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
}
COH_SCRATCH_RSHR_ENTRY#(type t_RSHR_TAG)
    deriving (Eq, Bits);

//
// Coherence controller's ownerbit memory request 
//
typedef struct
{
    t_ADDR                     addr;
    t_IDX                      idx;
    COH_SCRATCH_PORT_NUM       requester;
    COH_SCRATCH_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
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
    COH_SCRATCH_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
}
COH_SCRATCH_CONTROLLER_DATA_REQ
    deriving(Bits, Eq);

// Number of entries in request tables that stores GETX/GETS requests 
// that are checking out the ownership in ownerbitMem
typedef 16 COH_SCRATCH_CONTROLLER_GET_REQ_TABLE_ENTRIES;

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
    method Bool putRetry();          // retry putX because table entry is not available
    method Bool getRetry();          // retry getX because table entry is not available
endinterface: COH_SCRATCH_CONTROLLER_STATS

//
// mkCoherentScratchpadController --
//     Initialize a controller for a new coherent scratchpad memory region.
//
module [CONNECTED_MODULE] mkCoherentScratchpadController#(Integer dataScratchpadID, 
                                                          Integer ownerbitScratchpadID,
                                                          NumTypeParam#(t_IN_ADDR_SZ) inAddrSz,
                                                          NumTypeParam#(t_IN_DATA_SZ) inDataSz,
                                                          COH_SCRATCH_CONFIG conf)
    // interface:
    ();
    
    if (conf.cacheMode == COH_SCRATCH_CACHED)
    begin
        let statsConstructor = mkBasicCoherentScratchpadControllerStats("Coherent_scratchpad_" + integerToString(dataScratchpadID) + "_controller_", "");
        // Each coherent scratchpad client has a private cache.
        mkCachedCoherentScratchpadController(dataScratchpadID, ownerbitScratchpadID, inAddrSz, inDataSz, statsConstructor);
    end
    else
    begin
        // There are no private caches in this coherence domain. 
        // Coherent scratchpad clients just send remote reads/writes to the centralized 
        // private scratchpad inside the conherent scratchpad controller
        mkUncachedCoherentScratchpadController(dataScratchpadID, inAddrSz, inDataSz);
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
                                                                COH_SCRATCH_CONTROLLER_STATS_CONSTRUCTOR statsConstructor)
    // interface:
    ()
    provisos (
              // Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_IN_DATA_SZ)), t_NATURAL_SZ),
              Bits#(COH_SCRATCH_MEM_VALUE, t_COH_SCRATCH_MEM_VALUE_SZ),
              // Compute the container (scratchpad) address size
              NumAlias#(TSub#(t_IN_ADDR_SZ, TLog#(TDiv#(t_COH_SCRATCH_MEM_VALUE_SZ, t_NATURAL_SZ))), t_ADDR_SZ),
              Alias#(Bit#(t_ADDR_SZ), t_ADDR),
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
              Alias#(UInt#(TMin#(t_RSHR_IDX_SZ, TLog#(COH_SCRATCH_CONTROLLER_GET_REQ_TABLE_ENTRIES))), t_GET_REQ_TABLE_IDX),
              // Memory request
              Alias#(COH_SCRATCH_CONTROLLER_OWNER_BIT_REQ#(t_ADDR, t_GET_REQ_TABLE_IDX), t_OWNER_BIT_REQ),
              Bounded#(t_RSHR_IDX));


    String debugLogFilename = "coherent_scratchpad_" + integerToString(dataScratchpadID) + ".out";
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
        error("Coherent scratchpad doesn't support data larger than scratchpad's base size");
    end

    // =======================================================================
    //
    // Coherent scratchpad clients and this controller are connected via rings.
    //
    // Three rings are required to avoid deadlocks: one for requests, 
    // one for responses, and one for activated requests.
    //
    // =======================================================================

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_REQ) link_mem_req <- 
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Req", 0):
        mkConnectionTokenRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Req", 0);


    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP) link_mem_resp <-
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Resp", 0):
        mkConnectionTokenRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Resp", 0);

    // Broadcast ring
    CONNECTION_CHAIN#(t_COH_SCRATCH_ACTIVATED_REQ) link_mem_activatedReq <- 
        mkConnectionChain("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_ActivatedReq");


    //
    // Instantiate two private scratchpads
    //
    // (1) dataMem: a private scratchpad that serves as the interface to read/write data from/to local memory
    // (2) ownerbitMem: a private scratchpad that manages coherence owner bits storage
    

    SCRATCHPAD_CONFIG dataMemConfig = defaultValue;
    SCRATCHPAD_CONFIG ownerbitMemConfig = defaultValue;
    
    dataMemConfig.cacheMode = SCRATCHPAD_NO_PVT_CACHE;
    ownerbitMemConfig.cacheMode = SCRATCHPAD_CACHED;
    
    MEMORY_IFC#(t_ADDR, COH_SCRATCH_MEM_VALUE) dataMem  <- mkScratchpad(dataScratchpadID, dataMemConfig);
    MEMORY_IFC#(t_ADDR, Bool) ownerbitMem  <- mkScratchpad(ownerbitScratchpadID, ownerbitMemConfig); 


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
    LUTRAM#(t_GET_REQ_TABLE_IDX, Maybe#(t_ADDR)) ownerbitReqTable <- mkLUTRAM(tagged Invalid);

    // Pipeline FIFOs
    FIFO#(t_RSHR_REQ) incomingReqQ                                       <- mkFIFO();
    FIFO#(t_RSHR_REQ) rshrLookupQ                                        <- mkFIFO();
    FIFOF#(t_RSHR_REQ) putReqRetryQ                                      <- mkFIFOF();
    FIFOF#(t_RSHR_REQ) getReqRetryQ                                      <- mkFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) rshrRespQ    <- mkBypassFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) memRespQ     <- mkBypassFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) outputRespQ  <- mkSizedFIFOF(8);
    FIFOF#(COH_SCRATCH_CONTROLLER_DATA_REQ) dataMemLookupQ               <- mkSizedFIFOF(16);
    FIFOF#(t_OWNER_BIT_REQ) ownerbitMemLookupQ                           <- mkSizedFIFOF(16);
    FIFOF#(t_OWNER_BIT_REQ) ownerbitMemCheckoutQ                         <- mkSizedFIFOF(16);
  
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
    // Initialization: initialize the ownerbitMem
    //
    // =======================================================================

    Reg#(Bool) initialized <- mkReg(False);
    Reg#(t_ADDR) initAddr  <- mkReg(unpack(0));  

    (* fire_when_enabled *)
    rule doInit (!initialized);
        ownerbitMem.write(initAddr, True);
        if (initAddr == maxBound)
        begin
            initialized <= True;
            debugLog.record($format("    ownerbitMem initialization: done"));
            debugLog.record($format("    client addr size = %d, scratchpad addr size = %d, rshr idx size = %d", 
                            valueOf(t_IN_ADDR_SZ), valueOf(t_ADDR_SZ), valueOf(t_RSHR_IDX_SZ)));
        end
        initAddr <= initAddr + 1;
    endrule

    // =======================================================================
    //
    // Start RSHR lookup requests:
    // 
    // There are five possible lookup request candidates:
    // (1) GETX/GETS/PUTX unactivated requests from coherent scratchpad clients
    // (2) Write back responses (PUTX responses) from coherent scratchpad clients
    // (3) PUTX retry requests
    // (4) GETX/GETS retry reqeusts
    // (5) Second-time forwarding requests
    //
    // Priority: (2) > (5) > (3) > (4) > (1)
    //
    // To avoid deadlocks, received responses cannot be blocked.
    //
    // =======================================================================

    //
    // collectClientReq --
    //     Collect scratchpad client requests from the request ring.
    //
    rule colletClientReq (initialized);
        let req = link_mem_req.first();
        let start_req = False;
        t_RSHR_REQ lookup_req = ?;

        case (req) matches
            tagged COH_SCRATCH_GETS .gets_req:
            begin
                lookup_req.reqType        = COH_MSG_GETS;
                lookup_req.requester      = gets_req.requester;
                lookup_req.addr           = gets_req.addr;
                lookup_req.clientMeta     = gets_req.clientMeta;
                lookup_req.globalReadMeta = gets_req.globalReadMeta;
                start_req                 = True;
                debugLog.record($format("  collect GETS request: sender=%d, addr=0x%x, meta=0x%x",  
                                lookup_req.requester, lookup_req.addr, lookup_req.clientMeta));
            end
            tagged COH_SCRATCH_GETX .getx_req:
            begin
                lookup_req.reqType        = COH_MSG_GETX;
                lookup_req.requester      = getx_req.requester;
                lookup_req.addr           = getx_req.addr;
                lookup_req.clientMeta     = getx_req.clientMeta;
                lookup_req.globalReadMeta = getx_req.globalReadMeta;
                start_req                 = True;
                debugLog.record($format("  collect GETX request: sender=%d, addr=0x%x, meta=0x%x", 
                                lookup_req.requester, lookup_req.addr, lookup_req.clientMeta));
            end
            tagged COH_SCRATCH_PUTX .putx_req:
            begin
                lookup_req.reqType        = COH_MSG_PUTX;
                lookup_req.requester      = putx_req.requester;
                lookup_req.addr           = putx_req.addr;
                lookup_req.isCleanWB      = putx_req.isCleanWB;
                start_req                 = !putReqRetryQ.notEmpty();
                debugLog.record($format("  collect PUTX request: sender=%d, addr=0x%x, isCleanWB=%s",  
                                lookup_req.requester, lookup_req.addr, lookup_req.isCleanWB? "True" : "False"));
            end
        endcase
        
        if (start_req)
        begin
            link_mem_req.deq();
            match {.tag, .idx} = rshrEntryFromAddr(lookup_req.addr);
            lookup_req.tag = tag;
            lookup_req.idx = idx;
            rshr.readReq(idx);
            rshrLookupQ.enq(lookup_req);
            debugLog.record($format("  start rshr lookup: addr=0x%x, idx=0x%x", lookup_req.addr, idx));
        end
    endrule

    //
    // collectResp --
    //     Collect scratchpad client responses (PUTX write-back data) from the 
    // response ring.
    //
    rule collectClientResp (initialized);
        let resp = link_mem_resp.first();
        link_mem_resp.deq();

        t_RSHR_REQ lookup_req = ?;
        lookup_req.reqType = COH_MSG_RESP;
        lookup_req.val = resp.val;
        lookup_req.idx = unpack(pack(truncate(resp.meta)));
        rshr.readReq(lookup_req.idx);
        rshrLookupQ.enq(lookup_req);
        debugLog.record($format("  collectClientResp: idx=0x%x", lookup_req.idx));
    endrule

    //
    // startPutRetry 
    //
    rule startPutRetry (processPutRetry);
        let r = putReqRetryQ.first();
        putReqRetryQ.deq();
        rshr.readReq(r.idx);
        rshrLookupQ.enq(r);
        debugLog.record($format("  startPutRetry: idx=0x%x", r.idx));
    endrule

    //
    // startGetRetry 
    //
    rule startGetRetry (processGetRetry);
        let r = getReqRetryQ.first();
        getReqRetryQ.deq();
        rshr.readReq(r.idx);
        rshrLookupQ.enq(r);
        debugLog.record($format("  startGetRetry: idx=0x%x", r.idx));
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
        Bool retry = False;

        // rshr hit
        if (cur_entry matches tagged Valid .e &&& e.tag == r.tag)
        begin
            debugLog.record($format("      rshrGetLookup HIT: idx=0x%x, %s", r.idx, (e.needForward)? "ignore" : "wait to be forwarded"));
            if (!e.needForward)
            begin
                let new_entry = e;
                new_entry.needForward    = True;
                new_entry.forwardId      = r.requester;
                new_entry.clientMeta     = r.clientMeta;
                new_entry.globalReadMeta = r.globalReadMeta;
                rshrWriteBypass(r.idx, tagged Valid new_entry);
            end
        end
        else // rshr miss
        begin
            let req_table_idx = unpack(truncateNP(pack(r.idx)));
            if (ownerbitReqTable.sub(req_table_idx) matches tagged Valid .addr)
            begin
                // if hit (r.addr == addr), which means there is already one 
                // GETS/GETX going to check out the ownerbit, then do nothing.
                // if miss (r.addr != addr), retry and wait until the table
                // entry is free
                retry = r.addr != addr;
            end
            else
            begin
                ownerbitMemLookupQ.enq( COH_SCRATCH_CONTROLLER_OWNER_BIT_REQ { addr: r.addr,
                                                                               idx: req_table_idx,
                                                                               requester: r.requester,
                                                                               clientMeta: r.clientMeta,
                                                                               globalReadMeta: r.globalReadMeta,
                                                                               needCheckout: ?} );
                ownerbitMem.readReq(r.addr);
                ownerbitReqTable.upd(req_table_idx, tagged Valid r.addr);
                debugLog.record($format("      rshrGetLookup MISS: idx=0x%x, read ownerbitMem: addr=0x%x", r.idx, r.addr));
            end
        end
        
        if (retry)
        begin
            getReqRetryQ.enq(r);
            if (!getReqRetryQ.notEmpty())
            begin
                processGetRetry <= False;
            end
            debugLog.record($format("      rshrGetLookup: idx=0x%x, retry!", r.idx));
            getRetryW.send();
        end
        else
        begin
            // forward request to the activated request ring
            t_COH_SCRATCH_ACTIVATED_REQ activated_req = ?;
            let get_req = COH_SCRATCH_GET_REQ { requester: r.requester,
                                                addr: r.addr,
                                                clientMeta: r.clientMeta,
                                                globalReadMeta: r.globalReadMeta };

            
            if (r.reqType == COH_MSG_GETS)
            begin
                activated_req = tagged COH_SCRATCH_ACTIVATED_GETS get_req;
                getsReceivedW.send();
            end
            else
            begin
                activated_req = tagged COH_SCRATCH_ACTIVATED_GETX get_req;
                getxReceivedW.send();
            end

            link_mem_activatedReq.sendToNext(activated_req);
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
            debugLog.record($format("      rshrPutLookup: idx=0x%x, addr=0x%x, retry!", r.idx, r.addr));
            putRetryW.send();
        end
        else // entry available
        begin
            debugLog.record($format("      rshrPutLookup: idx=0x%x, addr=0x%x, allocate new entry", r.idx, r.addr));
            
            rshrWriteBypass(r.idx, tagged Valid COH_SCRATCH_RSHR_ENTRY { tag: r.tag,
                                                                         val: ?,
                                                                         needForward: False,
                                                                         forwardId: ?,
                                                                         clientMeta: ?,
                                                                         globalReadMeta: ? });
            // forward request to the activated request ring
            let put_req = COH_SCRATCH_ACTIVATED_PUT_REQ { requester: r.requester,
                                                          addr: r.addr,
                                                          controllerMeta: unpack(zeroExtend(pack(r.idx))),
                                                          isCleanWB: False };

            link_mem_activatedReq.sendToNext(tagged COH_SCRATCH_ACTIVATED_PUTX put_req);
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
        debugLog.record($format("      rshrCleanPutLookup: addr=0x%x, write back ownerbit", r.addr));
        ownerbitMem.write(r.addr, True);
            
        // forward request to the activated request ring
        let put_req = COH_SCRATCH_ACTIVATED_PUT_REQ { requester: r.requester,
                                                      addr: r.addr,
                                                      controllerMeta:?,
                                                      isCleanWB: True };

        link_mem_activatedReq.sendToNext(tagged COH_SCRATCH_ACTIVATED_PUTX put_req);
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
            let sent_resp = False;
            // write back data and ownerbit to memory if the ownership has not 
            // been checked-out by a GETS/GETX
            // (Here we respond GETS with ownership to enable automatically S->M upgrades)
            if (!e.needForward)
            begin
                let w_addr = rshrAddrFromEntry(e.tag, r.idx);
                ownerbitMem.write(w_addr, True);
                dataMem.write(w_addr, r.val);
                debugLog.record($format("      rshrRespLookup: idx=0x%x, ownerbitMem & dataMem write back, addr=0x%x, val=0x%x", r.idx, w_addr, r.val));
            end

            // forward write-back data to a client if response queue is not full
            if (e.needForward && outputRespQ.notFull())
            begin
                sent_resp = True;
                rshrRespQ.enq(tuple2(e.forwardId, COH_SCRATCH_RESP { val: r.val,
                                                                     ownership: True,
                                                                     meta: zeroExtend(e.clientMeta), 
                                                                     globalReadMeta: e.globalReadMeta,
                                                                     isCacheable: True,
                                                                     retry: False }));

                debugLog.record($format("      rshrRespLookup: idx=0x%x, forward response: dest=%d, val=0x%x", r.idx, e.forwardId, r.val));
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
        let ownership <- ownerbitMem.readRsp();
        debugLog.record($format("      ownerbitMemLookup: addr=0x%x, ownership=%s", r.addr, ownership? "True" : "False"));

        if (ownership)
        begin
            dataMemLookupQ.enq( COH_SCRATCH_CONTROLLER_DATA_REQ { requester: r.requester,
                                                                  clientMeta: r.clientMeta,
                                                                  globalReadMeta: r.globalReadMeta } );
            dataMem.readReq(r.addr);
            debugLog.record($format("      ownerbitMemLookup: read dataMem: addr=0x%x, meta=0x%x", r.addr, r.clientMeta));
        end

        let req = r;
        req.needCheckout = ownership; 
        ownerbitMemCheckoutQ.enq(req);
    endrule

    rule ownerbitMemCheckout (True);
        let r = ownerbitMemCheckoutQ.first();
        ownerbitMemCheckoutQ.deq();
        if (r.needCheckout)
        begin
            ownerbitMem.write(r.addr, False);
            debugLog.record($format("      ownerbitMemCheckout: checkout ownerbitMem: addr=0x%x", r.addr));
            ownerbitCheckoutW.send();
        end
        // release ownerbitReqTable entry
        ownerbitReqTable.upd(r.idx, tagged Invalid);
        ownerbitReqTableReleaseIdx <= r.idx;
        debugLog.record($format("      ownerbitMemCheckout: release ownerbitReqTable: addr=0x%x, idx=0x%x", r.addr, r.idx));
    endrule

    (* descending_urgency = "doInit, collectClientResp, rshrRespLookup, rshrFwdLookup, rshrCleanPutLookup, enablePutRetry, enableGetRetry, startForward, startPutRetry, startGetRetry, colletClientReq, ownerbitMemCheckout, rshrDirtyPutLookup, rshrGetLookup, ownerbitMemLookup, dataMemLookup" *)
    rule dataMemLookup (True);
        let r = dataMemLookupQ.first();
        dataMemLookupQ.deq();
        let data <- dataMem.readRsp();
        memRespQ.enq(tuple2(r.requester, COH_SCRATCH_RESP { val: data,
                                                            ownership: True,
                                                            meta: zeroExtend(r.clientMeta), 
                                                            globalReadMeta: r.globalReadMeta,
                                                            isCacheable: True,
                                                            retry: False }));
        debugLog.record($format("      dataMemLookup: send data response: dest=%d, val=0x%x, meta=0x%x", r.requester, data, r.clientMeta));
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
        link_mem_resp.enq(tpl_1(resp), tpl_2(resp));
    endrule


    // =======================================================================
    //
    // Drop activated requests
    //
    // =======================================================================

    (* fire_when_enabled *)
    rule dropActivatedReq (True);
        
        let req <- link_mem_activatedReq.recvFromPrev();
        
        case (req) matches
            tagged COH_SCRATCH_ACTIVATED_GETS .gets_req:
            begin
                debugLog.record($format("  dropActivatedReq: drop activated GETS request: addr=0x%x, sender=%d", gets_req.addr, gets_req.requester));
            end
            tagged COH_SCRATCH_ACTIVATED_GETX .getx_req:
            begin
                debugLog.record($format("  dropActivatedReq: drop activated GETX request: addr=0x%x, sender=%d", getx_req.addr, getx_req.requester));
            end
            tagged COH_SCRATCH_ACTIVATED_PUTX .putx_req:
            begin
                debugLog.record($format("  dropActivatedReq: drop activated PUTX request: addr=0x%x, sender=%d", putx_req.addr, putx_req.requester));
            end
        endcase

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

endmodule

typedef Bit#(2) COH_SCRATCH_CTRLR_WRITE_DATA_IDX;

typedef struct
{
    COH_SCRATCH_PORT_NUM            requester;
    COH_SCRATCH_REMOTE_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META       globalReadMeta;
}
COH_SCRATCH_CTRLR_REMOTE_READ_REQ_INFO
    deriving (Eq, Bits);

typedef struct
{
    COH_SCRATCH_PORT_NUM              requester;
    t_ADDR                            addr;
    COH_SCRATCH_CTRLR_WRITE_DATA_IDX  writeDataIdx;
    COH_SCRATCH_REMOTE_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META         globalReadMeta;
    Bool                              isRead;
}
COH_SCRATCH_CTRLR_REMOTE_REQ#(type t_ADDR)
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
                                                                  NumTypeParam#(t_IN_DATA_SZ) inDataSz)
    // interface:
    ()
    provisos (Alias#(Bit#(t_IN_ADDR_SZ), t_ADDR),
              Alias#(Bit#(t_IN_DATA_SZ), t_DATA),
              // Coherence messages
              Alias#(COH_SCRATCH_REMOTE_REQ#(t_ADDR, t_DATA), t_COH_SCRATCH_REQ),
              Alias#(COH_SCRATCH_REMOTE_READ_RESP#(t_DATA), t_COH_SCRATCH_READ_RESP),
              Alias#(COH_SCRATCH_REMOTE_RESP#(t_DATA), t_COH_SCRATCH_RESP),
              Alias#(COH_SCRATCH_CTRLR_REMOTE_REQ#(t_ADDR), t_MEM_REQ),
              Bits#(COH_SCRATCH_CTRLR_WRITE_DATA_IDX, t_WRITE_DATA_IDX_SZ),
              NumAlias#(TExp#(t_WRITE_DATA_IDX_SZ), n_WRITES));

    String debugLogFilename = "coherent_scratchpad_" + integerToString(dataScratchpadID) + ".out";
    DEBUG_FILE debugLog <- (`COHERENT_SCRATCHPAD_DEBUG_ENABLE == 1)?
                           mkDebugFile(debugLogFilename):
                           mkDebugFileNull(debugLogFilename); 

    // ===============================================================================
    //
    // Coherent scratchpad clients and this controller are connected via rings.
    //
    // Two rings are required to avoid deadlocks: one for requests, one for responses.
    //
    // ===============================================================================

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_REQ) link_mem_req <- 
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Req", 0):
        mkConnectionTokenRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Req", 0);

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_RESP) link_mem_resp <-
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Resp", 0):
        mkConnectionTokenRingNode("Coherent_Scratchpad_" + integerToString(dataScratchpadID) + "_Resp", 0);

    //
    // Instantiate a private scratchpad that serves as the interface to read/write data from/to local memory
    //
    SCRATCHPAD_CONFIG dataMemConfig = defaultValue;
    dataMemConfig.cacheMode = SCRATCHPAD_CACHED;
    MEMORY_IFC#(t_ADDR, t_DATA) dataMem  <- mkScratchpad(dataScratchpadID, dataMemConfig);

    MEMORY_HEAP_IMM#(COH_SCRATCH_CTRLR_WRITE_DATA_IDX, t_DATA) reqInfo_writeData <- mkMemoryHeapUnionLUTRAM();
    
    FIFOF#(t_MEM_REQ) incomingReqQ                                            <- mkSizedFIFOF(2*valueOf(n_WRITES));
    FIFOF#(COH_SCRATCH_CTRLR_REMOTE_READ_REQ_INFO) dataMemReqQ                <- mkSizedFIFOF(32);
    FIFOF#(COH_SCRATCH_PORT_NUM) ackRespQ                                     <- mkBypassFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_READ_RESP)) memRespQ   <- mkBypassFIFOF();
    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_RESP)) outputRespQ     <- mkSizedFIFOF(8);

    //
    // collectClientReq --
    //     Collect scratchpad client requests from the request ring.
    // For write and fence requests, send ack back to the clients. 
    //
    rule colletClientReq (True);
        let req = link_mem_req.first();
        link_mem_req.deq();
        t_MEM_REQ lookup_req = ?;
        if (req matches tagged COH_SCRATCH_REMOTE_READ .read_req)
        begin
            lookup_req.requester      = read_req.requester;
            lookup_req.addr           = read_req.addr;
            lookup_req.clientMeta     = read_req.clientMeta;
            lookup_req.globalReadMeta = read_req.globalReadMeta;
            lookup_req.isRead         = True;
            incomingReqQ.enq(lookup_req);
            debugLog.record($format("  collect READ request: sender=%d, addr=0x%x, meta=0x%x",  
                            lookup_req.requester, lookup_req.addr, lookup_req.clientMeta));
        end
        else if (req matches tagged COH_SCRATCH_REMOTE_WRITE .write_req)
        begin
            let data_idx <- reqInfo_writeData.malloc();
            reqInfo_writeData.upd(data_idx, write_req.data);
            
            lookup_req.requester      = write_req.requester;
            lookup_req.addr           = write_req.addr;
            lookup_req.writeDataIdx   = data_idx;
            lookup_req.isRead         = False;
            incomingReqQ.enq(lookup_req);
            ackRespQ.enq(write_req.requester);
            debugLog.record($format("  collect WRITE request: sender=%d, addr=0x%x, data=0x%x", 
                            lookup_req.requester, lookup_req.addr, write_req.data));
        end
    endrule

    rule accessDataMem (True);
        let req = incomingReqQ.first();
        incomingReqQ.deq();

        if (req.isRead) // read request
        begin
            dataMemReqQ.enq(COH_SCRATCH_CTRLR_REMOTE_READ_REQ_INFO { requester: req.requester,
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
        memRespQ.enq(tuple2(r.requester, COH_SCRATCH_REMOTE_READ_RESP { val: data,
                                                                        clientMeta: r.clientMeta, 
                                                                        globalReadMeta: r.globalReadMeta }));
        debugLog.record($format("    recvDataResp: send data response: dest=%d, val=0x%x, meta=0x%x", r.requester, data, r.clientMeta));
    endrule

    Reg#(Bit#(2)) ackRespArb <- mkReg(0);

    (* fire_when_enabled *)
    rule sendToOutputRespQ (True);
        if (ackRespQ.notEmpty() && ((ackRespArb != 0) || !memRespQ.notEmpty()))
        begin
            let ack = ackRespQ.first();
            ackRespQ.deq();
            outputRespQ.enq(tuple2(ack, tagged COH_SCRATCH_REMOTE_WRITE));    
            debugLog.record($format("    sendToOutputRespQ: WRITE ACK response: dest=%d", ack)); 
        end
        else
        begin
            let mem_resp = memRespQ.first();
            memRespQ.deq();
            outputRespQ.enq(tuple2(tpl_1(mem_resp), tagged COH_SCRATCH_REMOTE_READ tpl_2(mem_resp)));
            debugLog.record($format("    sendToOutputRespQ: READ DATA response: dest=%d, val=0x%x, meta=0x%x", 
                            tpl_1(mem_resp), tpl_2(mem_resp).val, tpl_2(mem_resp).clientMeta));
        end
        ackRespArb <= ackRespArb + 1;
    endrule

    (* fire_when_enabled *)
    rule sendCoherentScratchpadResp (True);
        let resp = outputRespQ.first();
        outputRespQ.deq();
        link_mem_resp.enq(tpl_1(resp), tpl_2(resp));
    endrule

endmodule
