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

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/rrr/server_stub_STDIO.bsh"
`include "awb/rrr/client_stub_STDIO.bsh"


module [CONNECTED_MODULE] mkStdIOService
    // interface:
    ();

    // ****** State Elements ******

    // Communication to/from our SW via RRR
    ClientStub_STDIO clientStub <- mkClientStub_STDIO();
    ServerStub_STDIO serverStub <- mkServerStub_STDIO();

    // Request ring.  All requests are handled by the service.
    CONNECTION_CHAIN#(STDIO_REQ_RING_MSG) reqChain <-
        mkConnectionChain("stdio_req_ring");

    // Response ring is addressable, since responses are to specific clients.
    CONNECTION_ADDR_RING#(STDIO_CLIENT_ID, STDIO_RSP) rspChain <-
        mkConnectionAddrRingNode("stdio_rsp_ring", 0);
    
    Reg#(Bool) swReady <- mkReg(False);
    Reg#(Maybe#(STDIO_REQ_RING_CHUNK)) mergeChunk <- mkReg(tagged Invalid);
    Reg#(Maybe#(Tuple2#(STDIO_CLIENT_ID, STDIO_RSP))) rspBuf <- mkReg(tagged Invalid);

    // ****** Rules ******

    rule init (True);
        let dummy <- serverStub.acceptRequest_Ready();
        swReady <= True;
    endrule


    //
    // processReq --
    //
    //    Process a request from an individual scan node.
    //  
    rule processReq (swReady);
        let msg <- reqChain.recvFromPrev();

        //
        // To reduce trips through the software stack we combine two chunks
        // into a larger chunk.
        //

        if (msg.condMask)
        begin
            // Local initialization of mask for mkStdio_CondMask.  Drop the
            // message.
            noAction;
        end
        else if (msg.sync)
        begin
            // Software-initiated sync request has reached every local node
            // and is now complete.
            serverStub.sendResponse_Sync(0);
        end
        else if (mergeChunk matches tagged Valid .prev)
        begin
            // New chunk fills the buffer.  Send the group.
            clientStub.makeRequest_Req({msg.chunk, prev},
                                       zeroExtend(pack(msg.eom)));
            mergeChunk <= tagged Invalid;
        end
        else if (msg.eom)
        begin
            // At EOM send whatever we have.
            clientStub.makeRequest_Req(zeroExtend(msg.chunk),
                                       zeroExtend(pack(msg.eom)));
        end
        else
        begin
            // Buffer the current chunk and send it later.
            mergeChunk <= tagged Valid msg.chunk;
        end
    endrule

    //
    // processRsp --
    //
    //     Process a response from software.
    //
    rule processRsp (! isValid(rspBuf));
        let rsp <- serverStub.acceptRequest_Rsp();
        rspChain.enq(rsp.tgtNode,
                     STDIO_RSP { eom: unpack(rsp.meta[2]),
                                 nValid: rsp.meta[1:0],
                                 data: rsp.data,
                                 operation: unpack(truncate(rsp.command)) });
    endrule

    //
    // processRsp64 --
    //
    //     Process a 64-bit response from software.  The response has to
    //     be marshalled into a pair of 32-bit chunks.
    //
    (* descending_urgency = "processRsp64, processRsp" *)
    rule processRsp64 (! isValid(rspBuf));
        let rsp <- serverStub.acceptRequest_Rsp64();

        // Send the low 32 bits first.  The metadata for the first chunk is
        // always 0.
        rspChain.enq(rsp.tgtNode,
                     STDIO_RSP { eom: False,
                                 nValid: 0,
                                 data: rsp.data[31:0],
                                 operation: unpack(truncate(rsp.command)) });

        // Buffer the rest of the response for the later
        rspBuf <= tagged Valid tuple2(rsp.tgtNode,
                                      STDIO_RSP { eom: unpack(rsp.meta[2]),
                                                  nValid: rsp.meta[1:0],
                                                  data: rsp.data[63:32],
                                                  operation: unpack(truncate(rsp.command)) });
    endrule

    //
    // processRspBuf --
    //
    //     Finish a 64-bit response.
    //
    rule processRspBuf (rspBuf matches tagged Valid {.tgtNode, .rsp});
        rspChain.enq(tgtNode, rsp);
        rspBuf <= tagged Invalid;
    endrule

    //
    // processSyncReq --
    //
    //    The run is ending.  Tell all clients to flush their requests.
    //
    rule processSyncReq (True);
        let dummy <- serverStub.acceptRequest_Sync();

        let msg = STDIO_REQ_RING_MSG { chunk: ?,
                                       eom: True,
                                       sync: True,
                                       condMask: False };
        reqChain.sendToNext(msg);
    endrule

    //
    // processCondMaskUpd --
    //
    //    Set the conditional mask for mkStdio_CondPrintf.
    //
    rule processCondMaskUpd (True);
        let mask <- serverStub.acceptRequest_SetCondMask();

        let msg = STDIO_REQ_RING_MSG { chunk: mask,
                                       eom: True,
                                       sync: False,
                                       condMask: True };
        reqChain.sendToNext(msg);
    endrule
endmodule
