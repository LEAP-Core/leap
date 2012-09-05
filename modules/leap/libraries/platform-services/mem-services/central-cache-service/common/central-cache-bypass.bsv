//
// Copyright (C) 2009 Intel Corporation
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
    Vector#(CENTRAL_CACHE_N_CLIENTS, FIFOF#(Tuple3#(CENTRAL_CACHE_LINE_ADDR,
                                                    CENTRAL_CACHE_WORD_IDX,
                                                    CENTRAL_CACHE_READ_META))) readQ <- replicateM(mkFIFOF());
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
                            debugLog.record($format("port %0d: readReq addr=0x%x, wordIdx=0x%x, readMeta=0x%x", p, rd.addr, rd.wordIdx, rd.readMeta));

                            backing_source.readReq(rd.addr, rd.readMeta);
                            readQ[p].enq(tuple3(rd.addr, rd.wordIdx, rd.readMeta));
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
                    let d <- backing_source.readResp();

                    match {.addr, .word_idx, .read_meta} = readQ[p].first();
                    readQ[p].deq();
           
                    debugLog.record($format("port %0d: readResp addr=0x%x, readMeta=0x%x, val=0x%x", p, addr, read_meta, d));

                    Vector#(CENTRAL_CACHE_WORDS_PER_LINE, CENTRAL_CACHE_WORD) v = unpack(d);
                    CENTRAL_CACHE_READ_RESP r;
                    r.val = v[word_idx];
                    r.addr = addr;
                    r.wordIdx = word_idx;
                    r.readMeta = read_meta;

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
