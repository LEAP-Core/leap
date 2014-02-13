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
import FIFOF::*;

`include "awb/provides/channelio.bsh"
`include "awb/provides/rrr.bsh"
`include "awb/provides/rrr_common.bsh"
`include "awb/provides/umf.bsh"

`include "awb/rrr/service_ids.bsh"

// RRR Client

`define CLIENT_CHANNEL_ID  0

// request/response port interfaces
interface CLIENT_REQUEST_PORT;
    method Action write(UMF_PACKET data);
endinterface

interface CLIENT_RESPONSE_PORT;
    method ActionValue#(UMF_PACKET) read();
endinterface

// client interface
interface RRR_CLIENT;
    interface Vector#(`NUM_SERVICES, CLIENT_REQUEST_PORT)  requestPorts;
    interface Vector#(`NUM_SERVICES, CLIENT_RESPONSE_PORT) responsePorts;
endinterface

interface ARBITED_CLIENT#(numeric type n);
    interface Vector#(n, CLIENT_REQUEST_PORT)  requestPorts;
    interface Vector#(n, CLIENT_RESPONSE_PORT) responsePorts;
endinterface

// client
module mkRRRClient#(CHANNEL_IO#(UMF_PACKET) channel) (RRR_CLIENT);
  ARBITED_CLIENT#(`NUM_SERVICES) client <- mkArbitedClient(channel.readPorts[`CLIENT_CHANNEL_ID].read,
                                                           channel.writePorts[`CLIENT_CHANNEL_ID].write);
  interface requestPorts = client.requestPorts;
  interface responsePorts = client.responsePorts;
endmodule

module mkArbitedClient#(function ActionValue#(UMF_PACKET) read(), function Action write(UMF_PACKET data)) (ARBITED_CLIENT#(n));
  ARBITED_CLIENT#(n) m = ?;
  if(valueof(n) > 0)
    begin
      m <- mkArbitedClientNonZero(read, write);
    end
  return m;
endmodule

// Doesn't work if n == 0
module mkArbitedClientNonZero#(function ActionValue#(UMF_PACKET) read(), function Action write(UMF_PACKET data)) (ARBITED_CLIENT#(n));

    // ==============================================================
    //                        Ports and Queues
    // ==============================================================

    // create request/response buffers and link them to ports
    FIFOF#(UMF_PACKET)                     requestQueues[valueof(n)];
    Vector#(n, CLIENT_REQUEST_PORT) req_ports = newVector();

    FIFOF#(UMF_PACKET)                      responseQueues[valueof(n)];
    Vector#(n, CLIENT_RESPONSE_PORT) resp_ports = newVector();

    for (Integer s = 0; s < valueof(n); s = s + 1)
    begin
        requestQueues[s]  <- mkFIFOF();
        responseQueues[s] <- mkFIFOF();

        // create a new request port and link it to the FIFO
        req_ports[s] = interface CLIENT_REQUEST_PORT
                           method Action write(UMF_PACKET data);
                               requestQueues[s].enq(data);
                           endmethod
                       endinterface;

        // create a new response port and link it to the FIFO
        resp_ports[s] = interface CLIENT_RESPONSE_PORT
                            method ActionValue#(UMF_PACKET) read();

                                UMF_PACKET val = responseQueues[s].first();
                                responseQueues[s].deq();
                                return val;
                            endmethod
                        endinterface;
    end

    // === arbiters ===

    ARBITER#(n) arbiter <- mkRoundRobinArbiter();

    // === other state ===

    Reg#(UMF_MSG_LENGTH) requestChunksRemaining  <- mkReg(0);
    Reg#(UMF_MSG_LENGTH) responseChunksRemaining <- mkReg(0);

    Reg#(UMF_SERVICE_ID) requestActiveQueue  <- mkReg(0);
    Reg#(UMF_SERVICE_ID) responseActiveQueue <- mkReg(0);

    // ==============================================================
    //                          Response Rules
    // ==============================================================

    // scan channel for incoming response headers
    rule scan_responses (responseChunksRemaining == 0);

        UMF_PACKET packet <- read();

        // enqueue header in service's queue
        responseQueues[packet.UMF_PACKET_header.serviceID].enq(packet);

        // set up remaining chunks
        responseChunksRemaining <= packet.UMF_PACKET_header.numChunks;
        responseActiveQueue     <= packet.UMF_PACKET_header.serviceID;

    endrule

    // scan channel for response message chunks
    rule scan_params (responseChunksRemaining != 0);

        // grab a chunk from channelio and place it into the active response queue
        UMF_PACKET packet <- read();
        responseQueues[responseActiveQueue].enq(packet);

        // one chunk processed
        responseChunksRemaining <= responseChunksRemaining - 1;

    endrule

    // ==============================================================
    //                          Request Rules
    // ==============================================================

    //
    // Start writing new message.  The write_request_newmsg rule is broken
    // into two parts in order to help Bluespec generate a significantly simpler
    // schedule than if the rules are combined.  Separating the rules breaks
    // the connection between arbiter input vector state and the test for
    // whether a requestQueue has data.
    //

    Wire#(Maybe#(UInt#(TLog#(n)))) newMsgQIdx <- mkDWire(tagged Invalid);

    //
    // First half -- pick an incoming requestQueue
    //
    rule write_request_newmsg1 (requestChunksRemaining == 0);

        // arbitrate
        Bit#(n) request = '0;
        for (Integer s = 0; s < valueof(n); s = s + 1)
        begin
            request[s] = pack(requestQueues[s].notEmpty());
        end

        newMsgQIdx <= arbiter.arbitrate(request);

    endrule

    //
    // Second half -- consume a value from the chosen responseQueue.  If the
    // rule fails to fire because the channel write port is full it will fire
    // again later after being reselected by the first half.
    //
    for (Integer s = 0; s < valueof(n); s = s + 1)
    begin
        rule write_request_newmsg2 (newMsgQIdx matches tagged Valid .idx &&&
                                    fromInteger(s) == idx &&&
                                    requestChunksRemaining == 0);

            // get header packet
            UMF_PACKET packet = requestQueues[s].first();
            requestQueues[s].deq();

            // add my virtual channelID to header
            UMF_PACKET newpacket = tagged UMF_PACKET_header UMF_PACKET_HEADER
                                       {
                                        filler: ?,
                                        phyChannelPvt: ?,
                                        channelID: `CLIENT_CHANNEL_ID,
                                        serviceID: packet.UMF_PACKET_header.serviceID,
                                        methodID : packet.UMF_PACKET_header.methodID,
                                        numChunks: packet.UMF_PACKET_header.numChunks
                                       };

            // send the header packet to channelio
            write(newpacket);

            // setup remaining chunks
            requestChunksRemaining <= newpacket.UMF_PACKET_header.numChunks;
            requestActiveQueue <= fromInteger(s);
        endrule

    end

    // continue writing message
    rule write_request_continue (requestChunksRemaining != 0);

        // get the next packet from the active request queue
        UMF_PACKET packet = requestQueues[requestActiveQueue].first();
        requestQueues[requestActiveQueue].deq();

        // send the packet to channelio
        write(packet);

        // one more chunk processed
        requestChunksRemaining <= requestChunksRemaining - 1;

    endrule

    // ==============================================================
    //                        Set Interfaces
    // ==============================================================

    interface requestPorts  = req_ports;
    interface responsePorts = resp_ports;

endmodule
