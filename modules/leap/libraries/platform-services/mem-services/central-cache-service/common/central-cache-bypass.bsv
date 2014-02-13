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
// Bypass implementation of a central cache, routing requests directly to the
// backing storage.  This is effectively a NULL implementation of the central
// cache, while maintaining the interface for use by clients.
//
// In addition to being used by the explicit NULL central cache implementation,
// the hybrid implementation switches to this bypass version when the platform
// has no local memory.
//


import FIFO::*;
import FIFOF::*;
import Vector::*;


`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/fpga_components.bsh"


module mkBypassCentralCache
    // interface:
    (CENTRAL_CACHE_IFC);
    
    DEBUG_FILE debugLog <- mkDebugFile("memory_central_cache.out");

    //
    // Internal communication
    //
    Vector#(CENTRAL_CACHE_N_CLIENTS, FIFOF#(Tuple4#(CENTRAL_CACHE_LINE_ADDR,
                                                    CENTRAL_CACHE_WORD_IDX,
                                                    CENTRAL_CACHE_READ_META,
                                                    RL_CACHE_GLOBAL_READ_META))) readQ <- replicateM(mkFIFOF());
    Vector#(CENTRAL_CACHE_N_CLIENTS, FIFO#(Bool)) invalAckQ <- replicateM(mkFIFO());


    // ====================================================================
    //
    // Central cache port methods.
    //
    // ====================================================================

    //
    // Allocate the interfaces.
    //

    // Allocate connector between a standard cache backing storage interface
    // and a central back backing storage port.
    Vector#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_BACKING_CONNECTION) backingStore = newVector();

    // These vectors will be the central cache ports.
    Vector#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_CLIENT_PORT) clientPortsLocal = newVector();
    Vector#(CENTRAL_CACHE_N_CLIENTS, CENTRAL_CACHE_BACKING_PORT) backingPortsLocal = newVector();
    
    //
    // Allocate an interface for each port.
    //
    for (Integer p = 0; p < valueOf(CENTRAL_CACHE_N_CLIENTS); p = p + 1)
    begin
        backingStore[p] <- mkCentralCacheBackingConnection(p, debugLog);

        let backing_source = backingStore[p].cacheSourceData;

        clientPortsLocal[p] = (
            interface CENTRAL_CACHE_CLIENT_PORT;
                method Action newReq(CENTRAL_CACHE_REQ req);
                    case (req) matches
                        tagged CENTRAL_CACHE_READ .rd:
                        begin
                            debugLog.record($format("port %0d: readReq addr=0x%x, wordIdx=0x%x, readMeta=0x%x, globalReadMeta=0x%x", p, rd.addr, rd.wordIdx, rd.readMeta, pack(rd.globalReadMeta)));

                            backing_source.readReq(rd.addr, rd.readMeta, rd.globalReadMeta);
                            readQ[p].enq(tuple4(rd.addr, rd.wordIdx, rd.readMeta, rd.globalReadMeta));
                        end

                        tagged CENTRAL_CACHE_WRITE .wr:
                        begin
                            debugLog.record($format("port %0d: write addr=0x%x, wIdx=%d, val=0x%x", p, wr.addr, wr.wordIdx, wr.val));

                            //
                            // Backing storage write takes a line and a mask to indicate
                            // which words are valid in the line.  Build the line and mask.
                            //
                            Vector#(CENTRAL_CACHE_WORDS_PER_LINE, CENTRAL_CACHE_WORD) v = ?;
                            v[wr.wordIdx] = wr.val;

                            Vector#(CENTRAL_CACHE_WORDS_PER_LINE, Bool) mask = replicate(False);
                            mask[wr.wordIdx] = True;
           
                            backing_source.write(wr.addr, mask, pack(v));
                        end

                        tagged CENTRAL_CACHE_INVAL .inv:
                        begin
                            debugLog.record($format("port %0d: inval addr=0x%x, ack=%d", p, inv.addr, inv.sendAck));

                            if (inv.sendAck)
                            begin
                                invalAckQ[p].enq(True);
                            end
                        end

                        tagged CENTRAL_CACHE_FLUSH .fl:
                        begin
                            debugLog.record($format("port %0d: flush addr=0x%x, ack=%d", p, fl.addr, fl.sendAck));

                            if (fl.sendAck)
                            begin
                                invalAckQ[p].enq(True);
                            end
                        end
                    endcase
                endmethod


                method ActionValue#(CENTRAL_CACHE_READ_RESP) readResp();
                    let rsp <- backing_source.readResp();

                    match {.addr, .word_idx, .read_meta, .global_read_meta} = readQ[p].first();
                    readQ[p].deq();
           
                    debugLog.record($format("port %0d: readResp addr=0x%x, readMeta=0x%x, globalReadMeta=0x%x, val=0x%x", p, addr, read_meta, pack(global_read_meta), rsp.val));

                    Vector#(CENTRAL_CACHE_WORDS_PER_LINE, CENTRAL_CACHE_WORD) v = unpack(rsp.val);
                    CENTRAL_CACHE_READ_RESP r;
                    r.val = v[word_idx];
                    r.addr = addr;
                    r.wordIdx = word_idx;
                    r.isCacheable = rsp.isCacheable;
                    r.readMeta = read_meta;
                    r.globalReadMeta = global_read_meta;

                    return r;
                endmethod

    
                //
                // Inval / flush don't need to do anything (no cache).
                //
                method Action invalOrFlushWait();
                    debugLog.record($format("port %0d: inval/flush done"));
                    invalAckQ[p].deq();
                endmethod
            endinterface
        );

        backingPortsLocal[p] = backingStore[p].backingPort;
    end
    
    interface clientPorts = clientPortsLocal;
    interface backingPorts = backingPortsLocal;
endmodule
