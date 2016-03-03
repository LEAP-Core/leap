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

import Arbiter::*;

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/central_cache_service.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"


module [CONNECTED_MODULE] mkScratchpadMemoryService
    // interface:
    (Empty)
    provisos (Bits#(SCRATCHPAD_MEM_REQ, t_SCRATCHPAD_MEM_REQ_SZ), 
              Bits#(SCRATCHPAD_READ_RSP, t_SCRATCHPAD_READ_RSP_SZ)); 
    
    //
    // Instantiate scratchpad server implementation.
    //
    // Multiple scratchpads get instantiated if there are multiple distributed
    // local memory banks
    //
    Vector#(SCRATCHPAD_N_SERVERS, SCRATCHPAD_MEMORY_VDEV) memories <- genWithM(mkScratchpadMemory);

    // ***** Assertion Checkers *****
    ASSERTION_NODE assertNode <- mkAssertionNode(`ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE__BASE);
    ASSERTION assertScratchpadSpace <- mkAssertionChecker(`ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE_FULL, ASSERT_ERROR, assertNode);

    // ====================================================================
    //
    // Scratchpad clients and this server are connected on a ring.  We
    // use a ring to avoid congested routing on the FPGA when there are
    // a lot of scratchpads.  When there is a small number of scratchpads
    // the ring is small, so it doesn't add much latency.
    //
    // Two rings are required to avoid deadlocks:  one for requests and
    // one for responses.
    //
    // When there are multiple scratchpad servers, multiple rings are 
    // constructed.
    //
    // ====================================================================

    let platformID <- getSynthesisBoundaryPlatformID();
   
    for (Integer c = 0; c < valueOf(SCRATCHPAD_N_SERVERS); c = c + 1)
    begin
        String ringBaseName = "Scratchpad_Platform_" + integerToString(platformID);
        if (c > 0)
        begin
            ringBaseName = "Scratchpad_" + integerToString(c) + "_" + "Platform_" + integerToString(platformID);
        end

        CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_MEM_REQ_SZ)) link_mem_req <- (`SCRATCHPAD_TOKEN_RING_ENABLE == 0 || `SCRATCHPAD_CHAIN_REMAP == 1)?
            mkConnectionAddrRingNode(ringBaseName + "_Req", 0):
            mkConnectionTokenRingNode(ringBaseName + "_Req", 0);

        CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_READ_RSP_SZ)) link_mem_rsp <- (`SCRATCHPAD_TOKEN_RING_ENABLE == 0 || `SCRATCHPAD_CHAIN_REMAP == 1)?
            mkConnectionAddrRingNode(ringBaseName + "_Resp", 0):
            mkConnectionTokenRingNode(ringBaseName + "_Resp", 0);

        messageM("Scratchpad Ring Name: "+ ringBaseName + "_Req, Port: 0");
        messageM("Scratchpad Ring Name: "+ ringBaseName + "_Resp, Port: 0");
        
        let memory = memories[c];
        
        //
        // sendScratchpadReq --
        //     Forward a scratchpad client's request to the scratchpad
        //     device.
        //
        //     At most one instance of this rule will fire, based on the
        //     arbiter.
        //
        rule sendScratchpadReq (True);
            SCRATCHPAD_MEM_REQ req = unpack(link_mem_req.first());
            link_mem_req.deq();

            case (req) matches
                tagged SCRATCHPAD_MEM_INIT .init:
                begin
                    let s <- memory.init(init.allocLastWordIdx,
                                         init.port,
                                         init.cached,
                                         init.initFilePath,
                                         init.initCacheOnly);
                    assertScratchpadSpace(s);
                end

                tagged SCRATCHPAD_MEM_READ .r_req:
                begin
                    let read_uid = SCRATCHPAD_READ_UID { portNum: r_req.port,
                                                         clientReadUID: r_req.readUID };
                    memory.readReq(r_req.addr,
                                   r_req.byteReadMask,
                                   read_uid,
                                   r_req.globalReadMeta);
                end

                tagged SCRATCHPAD_MEM_WRITE .w_req:
                begin
                    memory.write(w_req.addr, w_req.val, w_req.port);
                end

                tagged SCRATCHPAD_MEM_WRITE_MASKED .w_req:
                begin
                    memory.writeMasked(w_req.addr,
                                       w_req.val,
                                       w_req.byteWriteMask,
                                       w_req.port);
                end
            endcase
        endrule
        
        rule sendScratchpadResp (True);
            let r <- memory.readRsp();

            SCRATCHPAD_READ_RSP resp;
            resp.val = r.val;
            resp.addr = r.addr;
            resp.readUID = r.readUID.clientReadUID;
            resp.globalReadMeta = r.globalReadMeta;
            resp.isCacheable = r.isCacheable;

            link_mem_rsp.enq(r.readUID.portNum, pack(resp));
        endrule
    end

endmodule
