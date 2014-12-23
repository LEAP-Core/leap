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
import DefaultValue::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/scratchpad_memory_service.bsh"
`include "awb/provides/shared_scratchpad_memory_common.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/fpga_components.bsh"

// Number of slots in a read port's reorder buffer.

typedef SCRATCHPAD_PORT_ROB_SLOTS UNCACHED_SHARED_SCRATCH_PORT_ROB_SLOTS;

//
// mkUncachedSharedScratchpadClient --
//     Allocate an uncached connection to the shared scratchpad rings of a 
// particular shared scratchpad memory region. 
//
module [CONNECTED_MODULE] mkUncachedSharedScratchpadClient#(Integer scratchpadID, 
                                                            DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // request/response messages
              Alias#(SHARED_SCRATCH_UNCACHED_REQ#(Bit#(t_ADDR_SZ), Bit#(t_DATA_SZ)), t_SHARED_SCRATCH_REQ),
              Alias#(SHARED_SCRATCH_UNCACHED_RESP#(Bit#(t_DATA_SZ)), t_SHARED_SCRATCH_RESP),
              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(UNCACHED_SHARED_SCRATCH_PORT_ROB_SLOTS), t_REORDER_ID),
              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ));

    // ===============================================================================
    //
    // Shared scratchpad clients and their associated controller are connected via rings.
    //
    // Two rings are required to avoid deadlocks: one for requests, one for responses.
    //
    // ===============================================================================

    Reg#(SHARED_SCRATCH_PORT_NUM) myPort <- mkWriteValidatedReg();
    
    String clientControllerRingName = "Uncached_Shared_Scratchpad_" + integerToString(scratchpadID);
   
    // Addressable ring (self-enumeration)
    CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, t_SHARED_SCRATCH_REQ) link_mem_req <- 
        (`SHARED_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingDynNode(clientControllerRingName + "_Req"):
        mkConnectionTokenRingDynNode(clientControllerRingName + "_Req");

    // Addressable ring
    CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, t_SHARED_SCRATCH_RESP) link_mem_resp <-
        (`SHARED_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Resp", myPort._read()):
        mkConnectionTokenRingNode(clientControllerRingName + "_Resp", myPort._read());
   
    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    Reg#(Bool) initialized <- mkReg(False);
    
    // Assign the port number got from request ring's self-enumeration to the response ring
    rule doInit (!initialized);
        initialized <= True;
        let port_num = link_mem_req.nodeID();
        myPort <= port_num;
        debugLog.record($format("assigned port ID = %0d", port_num));
    endrule

    // =======================================================================
    //
    // Request / response forwarding
    //
    // =======================================================================

    // Merge FIFOF combines read, write requests in temporal order, with reads 
    // from the same cycle as a write going first.  Each read port gets a slot. 
    // The write port is always last.
    MERGE_FIFOF#(TAdd#(n_READERS, 1), Tuple2#(t_ADDR, t_REORDER_ID)) incomingReqQ <- mkMergeFIFOF();
    
    // Write data is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(t_DATA) writeDataQ <- mkFIFO();
    
    // Cache responses are not ordered.  Sort them with a reorder buffer.
    Vector#(n_READERS, SCOREBOARD_FIFOF#(UNCACHED_SHARED_SCRATCH_PORT_ROB_SLOTS, t_DATA)) sortResponseQ <- replicateM(mkScoreboardFIFOF());
    
    // Read and write request counter
    COUNTER#(TLog#(TAdd#(TMul#(n_READERS, UNCACHED_SHARED_SCRATCH_PORT_ROB_SLOTS),1))) numPendingReads  <- mkLCounter(0);
    COUNTER#(TLog#(TAdd#(UNCACHED_SHARED_SCRATCH_PORT_ROB_SLOTS,1))) numPendingWrites <- mkLCounter(0);
    Vector#(n_READERS, PulseWire) readIssuedW <- replicateM(mkPulseWire());

    //
    // Update read request counter
    //
    rule incrNumReads (True);
        Bit#(n_READERS) reads = ?;
        for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
        begin
            reads[p] = readIssuedW[p]? 1 : 0;
        end
        numPendingReads.upBy(zeroExtendNP(pack(countOnesAlt(reads))));
    endrule
    
    // Read requests
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        rule forwardReadReq (initialized && incomingReqQ.firstPortID() == fromInteger(p));
            match {.addr, .idx} = incomingReqQ.first();
            incomingReqQ.deq();

            t_MAF_IDX maf_idx = tuple2(fromInteger(p), idx);

            // Send read request on the ring
            let req_info = SHARED_SCRATCH_UNCACHED_READ_REQ_INFO { clientMeta: unpack(zeroExtendNP(pack(maf_idx))),
                                                                   globalReadMeta: defaultValue() };
            
            link_mem_req.enq(0, SHARED_SCRATCH_UNCACHED_REQ { requester: myPort, 
                                                              addr: pack(addr), 
                                                              reqInfo: tagged SHARED_SCRATCH_READ req_info });
        endrule
    end

    //
    // recvDataResp --
    //     Push read responses to the reorder buffer.  They will be returned
    //     through readRsp() in order.
    //
    rule recvDataResp (link_mem_resp.first() matches tagged UNCACHED_READ_RESP .resp);
        link_mem_resp.deq();
        t_MAF_IDX maf_idx = unpack(truncateNP(pack(resp.clientMeta)));
        match {.port_num, .req_idx} = maf_idx;
        sortResponseQ[pack(port_num)].setValue(req_idx, unpack(resp.val));
        numPendingReads.down();
        debugLog.record($format("1 read request being processed, numPendingReads=0x%x", numPendingReads.value()));
    endrule

    // Write requests
    rule forwardWriteReq (initialized && incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS)));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();
        let w_data = writeDataQ.first();
        writeDataQ.deq();
        // Send write request on the ring
        let req_info = SHARED_SCRATCH_UNCACHED_WRITE_REQ_INFO { data: pack(w_data) };
        link_mem_req.enq(0, SHARED_SCRATCH_UNCACHED_REQ { requester: myPort, 
                                                          addr: pack(addr), 
                                                          reqInfo: tagged SHARED_SCRATCH_WRITE req_info });
    endrule
   
    // Write ack
    rule recvWriteAck (link_mem_resp.first() matches tagged UNCACHED_WRITE_ACK);
        link_mem_resp.deq();
        numPendingWrites.down();
        debugLog.record($format("1 write request being processed, numPendingWrites=0x%x", numPendingWrites.value()));
    endrule

    // =======================================================================
    //
    // Methods.  All requests are stored in the incomingReqQ to maintain their
    // order.
    //
    // =======================================================================

    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr);
                    // Allocate a slot in the reorder buffer for the read request.  Each
                    // read port gets its own reorder buffer.
                    let idx <- sortResponseQ[p].enq();
                    incomingReqQ.ports[p].enq(tuple2(addr, idx));
                    readIssuedW[p].send();
                    debugLog.record($format("read port %0d: req addr=0x%x, rob idx=%0d, numPendingReads=0x%x", 
                                    p, addr, idx, numPendingReads.value()));
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let r = sortResponseQ[p].first();
                    sortResponseQ[p].deq();
                    debugLog.record($format("read port %0d: resp val=0x%x", p, r));
                    return r;
                endmethod

                method t_DATA peek();
                    return sortResponseQ[p].first();
                endmethod
                method Bool notEmpty() = sortResponseQ[p].notEmpty();
                method Bool notFull() = incomingReqQ.ports[p].notFull() &&
                                        sortResponseQ[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val) if (numPendingWrites.value() != maxBound);
        // The write port is the second from last in the merge FIFO
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, ?));
        writeDataQ.enq(val);
        numPendingWrites.up(); 
        debugLog.record($format("write addr=0x%x, val=0x%x, numPendingWrites=0x%x", 
                        addr, val, numPendingWrites.value()));
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val) if (numPendingWrites.value() != maxBound);
        noAction;
    endmethod
    
    method ActionValue#(t_MEM_DATA) testAndSetRsp();
        noAction;
        return ?;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence();
        noAction;
    endmethod
    
    method Action writeFence();
        noAction;
    endmethod
    
    method Action readFence();
        noAction;
    endmethod
`endif
    
    method Bool writePending() = (numPendingWrites.value() != 0);
    method Bool readPending() = (numPendingReads.value() != 0);
      
endmodule
