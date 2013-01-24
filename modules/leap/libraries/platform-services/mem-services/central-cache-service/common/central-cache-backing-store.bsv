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
// The cache expects an interface to backing storage.  Clients of the central
// cache must provide backing storage.  The cache interface and the client
// interface are, necessarily, different since the cache storage interface
// is method based and the client interface is message based, often over
// a soft connection.
//
// This module bridges the gap between the interfaces by providing two interfaces:
// one for the base cache backing storage and one for the central cache virtual
// device communication with clients.  The module implements the connection
// between the two interfaces.
//


import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"


interface CENTRAL_CACHE_BACKING_CONNECTION;
    interface CENTRAL_CACHE_BACKING_PORT backingPort;
    interface RL_SA_CACHE_SOURCE_DATA#(CENTRAL_CACHE_LINE_ADDR,
                                       CENTRAL_CACHE_LINE,
                                       CENTRAL_CACHE_WORDS_PER_LINE,
                                       CENTRAL_CACHE_READ_META) cacheSourceData;
endinterface: CENTRAL_CACHE_BACKING_CONNECTION

//
// Backing storage connectors ultimately compete for RRR slots.  The central
// cache consumes read responses in the order it issues requests.  If multiple
// competing clients generate their RRR read requests in an order different
// than the central cache's order, it is possible to deadlock in RRR buffers.
// To solve this, each backing connection in this module provides local
// buffering to store responses for all of its outstanding requests.
//
typedef 8 CENTRAL_CACHE_BACKING_MAX_LIVE_READS;

//
// mkCentralCacheBackingConnection --
//     The backing store connection is essentially an interface mapper between
//     the backing store interface required by the standard cache interface
//     and the backing store interface required by a central cache client.
//
//     The port and debugLog arguments are provided solely for debugging
//     messages.
//
module mkCentralCacheBackingConnection#(Integer port, DEBUG_FILE debugLog)
    // interface:
    (CENTRAL_CACHE_BACKING_CONNECTION);
    
    // Internal communication
    FIFO#(CENTRAL_CACHE_BACKING_READ_REQ) readReqQ <- mkFIFO();
    FIFOF#(Bool) writeAckQ <- mkBypassFIFOF();

    // Buffering for read responses
    FIFO#(RL_SA_CACHE_FILL_RESP#(CENTRAL_CACHE_LINE)) readRespQ <- mkSizedFIFO(valueOf(CENTRAL_CACHE_BACKING_MAX_LIVE_READS));
    COUNTER_Z#(TLog#(TAdd#(1, CENTRAL_CACHE_BACKING_MAX_LIVE_READS))) readReqCredits <-
        mkLCounter_Z(fromInteger(valueOf(CENTRAL_CACHE_BACKING_MAX_LIVE_READS)));

    // FIFO1 to save space.  Throughput isn't terribly important here
    // since the call will go through RRR.
    FIFOF#(CENTRAL_CACHE_BACKING_WRITE_REQ) writeCtrlQ <- mkFIFOF1();
    MARSHALLER#(CENTRAL_CACHE_WORD, CENTRAL_CACHE_LINE) writeDataQ <- mkSimpleMarshaller();

    // Read response logic.  Combine pipelined read response (words) into a single
    // line-sized register.
    Reg#(Vector#(CENTRAL_CACHE_WORDS_PER_LINE, CENTRAL_CACHE_WORD)) readData <- mkRegU();
    Reg#(Bit#(TLog#(CENTRAL_CACHE_WORDS_PER_LINE))) readWordIdx <- mkReg(0);

    //
    // Flush writes before reads, since ultimately a read may depend on a write.
    // The central cache only allows a single access at a time to a line, but
    // if the write queue here backs up reads could bypass writes.
    //
    function Bool noWritesPending() = ! writeCtrlQ.notEmpty() && ! writeDataQ.notEmpty();

    //
    // Central cache interface.
    //
    interface CENTRAL_CACHE_BACKING_PORT backingPort;
        //
        // Central cache client polls getReadReq.
        //
        method ActionValue#(CENTRAL_CACHE_BACKING_READ_REQ) getReadReq() if (noWritesPending());
            let r = readReqQ.first();
            readReqQ.deq();
    
            debugLog.record($format("port %0d: BACKING getReadReq addr=0x%x, readMeta=0x%x, globalReadMeta=0x%x", port, r.addr, r.readMeta, pack(r.globalReadMeta)));

            return r;
        endmethod


        //
        // Provide read data in response to getReadReq.  This method is called
        // multiple times for each getReadReq.
        //
        method Action sendReadResp(CENTRAL_CACHE_WORD val, Bool isCacheable);
            let v = shiftInAtN(readData, val);
            readData <= v;

            debugLog.record($format("port %0d: BACKING sendReadResp idx=%0d, val=0x%x", port, readWordIdx, val));

            // Have all the chunks for the response arrived?
            if (readWordIdx == maxBound)
            begin
                // Yes.  Forward the response to the central cache.
                let rsp = RL_SA_CACHE_FILL_RESP { val: unpack(pack(v)),
                                                  isCacheable: isCacheable };
                readRespQ.enq(rsp);
            end
    
            readWordIdx <= readWordIdx + 1;
        endmethod

    
        //
        // Poll for request from cache to write to backing storage.
        //
        method ActionValue#(CENTRAL_CACHE_BACKING_WRITE_REQ) getWriteReq();
            let w = writeCtrlQ.first();
            writeCtrlQ.deq();

            debugLog.record($format("port %0d: BACKING getWriteReq addr=0x%x, wMask=0x%x, ack=%d", port, w.addr, w.wordValidMask, w.sendAck));
    
            return w;
        endmethod

        //
        // Poll for write data following a getWriteReq().
        //
        method ActionValue#(CENTRAL_CACHE_WORD) getWriteData() if (! writeCtrlQ.notEmpty());
            let v = writeDataQ.first();
            writeDataQ.deq();

            return v;
        endmethod

        //
        // Client ack that write to backing storage is complete.
        //
        method Action sendWriteAck();
            writeAckQ.enq(?);
            debugLog.record($format("port %0d: BACKING sendWriteAck", port));
        endmethod
    endinterface

    
    //
    // Cache backing storage interface.
    //
    interface RL_SA_CACHE_SOURCE_DATA cacheSourceData;
        method Action readReq(CENTRAL_CACHE_LINE_ADDR addr,
                              CENTRAL_CACHE_READ_META readMeta,
                              RL_CACHE_GLOBAL_READ_META globalReadMeta) if (! readReqCredits.isZero());
            readReqCredits.down();
            readReqQ.enq(CENTRAL_CACHE_BACKING_READ_REQ { addr: addr,
                                                          readMeta: readMeta,
                                                          globalReadMeta: globalReadMeta });
            debugLog.record($format("port %0d: BACKING readReq addr=0x%x, readMeta=0x%x, globalReadMeta=0x%x", port, addr, readMeta, pack(globalReadMeta)));
        endmethod

        method ActionValue#(RL_SA_CACHE_FILL_RESP#(CENTRAL_CACHE_LINE)) readResp();
            let rsp = readRespQ.first();
            readRespQ.deq();
            readReqCredits.up();

            debugLog.record($format("port %0d: BACKING readResp val=0x%x, cacheable=%d", port, rsp.val, rsp.isCacheable));
            return rsp;
        endmethod

    
        // Asynchronous write (no response)
        method Action write(CENTRAL_CACHE_LINE_ADDR addr,
                            Vector#(CENTRAL_CACHE_WORDS_PER_LINE, Bool) wordValidMask,
                            CENTRAL_CACHE_LINE val);

            CENTRAL_CACHE_BACKING_WRITE_REQ w;
            w.addr = addr;
            w.wordValidMask = wordValidMask;
            w.sendAck = False;

            writeCtrlQ.enq(w);
            writeDataQ.enq(val);
            debugLog.record($format("port %0d: BACKING write addr=0x%x, wMask=0x%x, ack=%d, val=0x%x", port, w.addr, w.wordValidMask, w.sendAck, val));
        endmethod
    
        // Synchronous write.  writeSyncWait() blocks until the response arrives.
        method Action writeSyncReq(CENTRAL_CACHE_LINE_ADDR addr,
                                   Vector#(CENTRAL_CACHE_WORDS_PER_LINE, Bool) wordValidMask,
                                   CENTRAL_CACHE_LINE val);

            CENTRAL_CACHE_BACKING_WRITE_REQ w;
            w.addr = addr;
            w.wordValidMask = wordValidMask;
            w.sendAck = True;

            writeCtrlQ.enq(w);
            writeDataQ.enq(val);
            debugLog.record($format("port %0d: BACKING write addr=0x%x, wMask=0x%x, ack=%d, val=0x%x", port, w.addr, w.wordValidMask, w.sendAck, val));
        endmethod

        method Action writeSyncWait() if (writeAckQ.notEmpty());
            writeAckQ.deq();
            debugLog.record($format("port %0d: BACKING writeSyncWait fired", port));
        endmethod
    endinterface

endmodule
