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

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/central_cache.bsh"
`include "awb/provides/local_mem.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"


module [CONNECTED_MODULE] mkCentralCacheService
    // interface:
    (CENTRAL_CACHE_IFC);

    //
    // The central cache service is just a wrapper.  Instantiate the central
    // cache implementation.
    //
    // The central cache will always miss if there is no local memory.  Only
    // build a real cache if the local storage exists.
    //
    CENTRAL_CACHE_IFC centralCache <- platformHasLocalMem ? mkCentralCache() :
                                                            mkBypassCentralCache();

    // ====================================================================
    //
    // Central cache connections.  Two soft connections for each individual
    // port.  One connection is for requests to the cache.  The other
    // is for requests from the cache to backing storage provided by the
    // client.
    //
    // ====================================================================

    Vector#(CENTRAL_CACHE_N_CLIENTS, CONNECTION_SERVER#(CENTRAL_CACHE_REQ, CENTRAL_CACHE_RESP)) link_cache = newVector();
    Vector#(CENTRAL_CACHE_N_CLIENTS, CONNECTION_CLIENT#(CENTRAL_CACHE_BACKING_REQ, CENTRAL_CACHE_BACKING_RESP)) link_cache_backing = newVector();

    for (Integer p = 0; p < valueOf(CENTRAL_CACHE_N_CLIENTS); p = p + 1)
    begin
        //
        // The central cache may have clients that are inside the virtual platform,
        // such as scratchpad memory.  Internal clients tag themselves by
        // setting their dictionary string to "platform".  Do not build soft
        // connections for internal clients.
        //
`ifdef VDEV_CACHE__BASE
        if (strVDEV_DICT[p + `VDEV_CACHE__BASE] != "platform")
        begin
            link_cache[p] <- mkConnectionServerOptional("vdev_cache_" + integerToString(p));

            //
            // Forward requests to the central cache.
            //
            rule sendCentralCacheReq (True);
                let req = link_cache[p].getReq();
                link_cache[p].deq();

                centralCache.clientPorts[p].newReq(req);
            endrule

            //
            // Return responses from the central cache.
            //
            let resp_data =
                (rules
                    // Return the requested word of the line fetched from
                    // the cache.
                    rule recvCentralCacheData (True);
                        let d <- centralCache.clientPorts[p].readResp();
                        link_cache[p].makeRsp(tagged CENTRAL_CACHE_READ d);
                    endrule
                endrules);

            let resp_flush_ack =
                (rules
                    // Flush or invalidate ACK response
                    rule recvCentralCacheFlushAck (True);
                        let d <- centralCache.clientPorts[p].invalOrFlushWait();
                        link_cache[p].makeRsp(tagged CENTRAL_CACHE_FLUSH_ACK False);
                    endrule
                endrules);

            addRules(rJoinDescendingUrgency(resp_flush_ack, resp_data));


            //
            // Backing storage communication.  Requests come from the cache
            // back to the client.
            //

            link_cache_backing[p] <- mkConnectionClientOptional("vdev_cache_backing_" + integerToString(p));

            //
            // Forward requests to the central cache.
            //
            let back_rules =
                (rules
                    rule sendCentralCacheBackingReadReq (True);
                        let r <- centralCache.backingPorts[p].getReadReq();
                        link_cache_backing[p].makeReq(tagged CENTRAL_CACHE_BACK_READ r);
                    endrule
                endrules);

            let back_wreq =
                (rules
                    rule sendCentralCacheBackingWriteReq (True);
                        let r <- centralCache.backingPorts[p].getWriteReq();
                        link_cache_backing[p].makeReq(tagged CENTRAL_CACHE_BACK_WREQ r);
                    endrule
                endrules);

            back_rules = rJoinDescendingUrgency(back_rules, back_wreq);

            let back_wdata =
                (rules
                    rule sendCentralCacheBackingWriteData (True);
                        let d <- centralCache.backingPorts[p].getWriteData();
                        link_cache_backing[p].makeReq(tagged CENTRAL_CACHE_BACK_WDATA d);
                    endrule
                endrules);

            back_rules = rJoinDescendingUrgency(back_rules, back_wdata);
            addRules(back_rules);

            //
            // Backing storage responses
            //
            rule recvCentralCacheBackingResp (True);
                let resp = link_cache_backing[p].getRsp();
                link_cache_backing[p].deq();

                case (resp) matches
                    tagged CENTRAL_CACHE_BACK_READ .r:
                    begin
                        centralCache.backingPorts[p].sendReadResp(r.wordVal,
                                                                  r.isCacheable);
                    end

                    tagged CENTRAL_CACHE_BACK_WACK .dummy:
                    begin
                        centralCache.backingPorts[p].sendWriteAck();
                    end
                endcase
            endrule
        end
`endif
    end


    //
    // Expose the port-based interface.  These interfaces may be used only
    // within the platform services modules (e.g. scratchpads).  Clients in the
    // application will use soft connections.
    //
    return centralCache;

endmodule
