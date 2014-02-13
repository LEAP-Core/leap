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

// RRR Server: my job is to scan channelio for incoming requests and queue
// them in service-private internal buffers. Services will periodically probe
// me to inquire if there are any outstanding requests for them

`define SERVER_CHANNEL_ID  1

// request/response port interfaces
interface SERVER_REQUEST_PORT;
    method ActionValue#(UMF_PACKET) read();
endinterface

interface SERVER_RESPONSE_PORT;
    method Action write(UMF_PACKET data);
endinterface

// channelio interface
interface RRR_SERVER;
    interface Vector#(`NUM_SERVICES, SERVER_REQUEST_PORT)  requestPorts;
    interface Vector#(`NUM_SERVICES, SERVER_RESPONSE_PORT) responsePorts;
endinterface

interface ARBITED_SERVER#(numeric type n);
    interface Vector#(n, SERVER_REQUEST_PORT)  requestPorts;
    interface Vector#(n, SERVER_RESPONSE_PORT) responsePorts;
endinterface

//    method ActionValue#(UMF_PACKET) read(UMF_SERVICE_ID i);

// server

module mkRRRServer#(CHANNEL_IO#(UMF_PACKET) channel) (RRR_SERVER);
  ARBITED_SERVER#(`NUM_SERVICES) server <- mkArbitedServer(channel.readPorts[`SERVER_CHANNEL_ID].read,
                                                           channel.writePorts[`SERVER_CHANNEL_ID].write);
  interface requestPorts = server.requestPorts;
  interface responsePorts = server.responsePorts;
endmodule

module mkArbitedServer#(function ActionValue#(UMF_PACKET) read(), function Action write(UMF_PACKET data)) (ARBITED_SERVER#(n));
  ARBITED_SERVER#(n) m = ?;
  if(valueof(n) > 0)
    begin
      m <- mkArbitedServerNonZero(read,write);
    end
  return m;
endmodule

module mkArbitedServerNonZero#(function ActionValue#(UMF_PACKET) read(), function Action write(UMF_PACKET data)) (ARBITED_SERVER#(n));

    // ==============================================================
    //                        Ports and Queues
    // ==============================================================

    // create request/response buffers and link them to ports
    FIFOF#(UMF_PACKET)                    requestQueues[valueof(n)];
    Vector#(n, SERVER_REQUEST_PORT)  req_ports = newVector();

    FIFOF#(UMF_PACKET)                    responseQueues[valueof(n)];
    Vector#(n, SERVER_RESPONSE_PORT) resp_ports = newVector();

    for (Integer s = 0; s < fromInteger(valueof(n)); s = s + 1)
    begin
        requestQueues[s]  <- mkFIFOF();
        responseQueues[s] <- mkFIFOF();

        // create a new request port and link it to the FIFO
        req_ports[s] = interface SERVER_REQUEST_PORT
                           method ActionValue#(UMF_PACKET) read();

                               UMF_PACKET val = requestQueues[s].first();
                               requestQueues[s].deq();
                               return val;

                           endmethod
                       endinterface;

        // create a new response port and link it to the FIFO
        resp_ports[s] = interface SERVER_RESPONSE_PORT
                            method Action write(UMF_PACKET data);

                                responseQueues[s].enq(data);

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
    //                          Request Rules
    // ==============================================================

    // scan channel for incoming request headers
    rule scan_requests (requestChunksRemaining == 0);

        UMF_PACKET packet <- read();

        // enqueue header in service's queue
        requestQueues[packet.UMF_PACKET_header.serviceID].enq(packet);

        // set up remaining chunks
        requestChunksRemaining <= packet.UMF_PACKET_header.numChunks;
        requestActiveQueue     <= packet.UMF_PACKET_header.serviceID;

    endrule

    // scan channel for request message chunks
    rule scan_params (requestChunksRemaining != 0);

        // grab a chunk from channelio and place it into the active request queue
        UMF_PACKET packet <- read();
        requestQueues[requestActiveQueue].enq(packet);

        // one chunk processed
        requestChunksRemaining <= requestChunksRemaining - 1;

    endrule

    // ==============================================================
    //                          Response Rules
    // ==============================================================

    //
    // Start writing new message.  The write_response_newmsg rule is broken
    // into two parts in order to help Bluespec generate a significantly simpler
    // schedule than if the rules are combined.  Separating the rules breaks
    // the connection between arbiter input vector state and the test for
    // whether a responseQueue has data.
    //

    Wire#(Maybe#(UInt#(TLog#(n)))) newMsgQIdx <- mkDWire(tagged Invalid);

    //
    // First half -- pick an incoming responseQueue
    //
    rule write_response_newmsg1 (responseChunksRemaining == 0);

        // arbitrate
        Bit#(n) request = '0;
        for (Integer s = 0; s < valueof(n); s = s + 1)
        begin
            request[s] = pack(responseQueues[s].notEmpty());
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
        rule write_response_newmsg2 (newMsgQIdx matches tagged Valid .idx &&&
                                     fromInteger(s) == idx &&&
                                     responseChunksRemaining == 0);

            // get header packet
            UMF_PACKET packet = responseQueues[s].first();
            responseQueues[s].deq();

            // add my virtual channelID to header
            UMF_PACKET newpacket = tagged UMF_PACKET_header UMF_PACKET_HEADER
                                       {
                                         filler: packet.UMF_PACKET_header.filler, // The packet knows more than we do.
                                         phyChannelPvt: ?,
                                         channelID: `SERVER_CHANNEL_ID,
                                         serviceID: packet.UMF_PACKET_header.serviceID,
                                         methodID : packet.UMF_PACKET_header.methodID,
                                         numChunks: packet.UMF_PACKET_header.numChunks
                                        };

            // send the header packet to channelio
            write(newpacket);

            // setup remaining chunks
            responseChunksRemaining <= newpacket.UMF_PACKET_header.numChunks;
            responseActiveQueue <= fromInteger(s);

        endrule
    end
    
    // continue writing message
    rule write_response_continue (responseChunksRemaining != 0);

        // get the next packet from the active response queue
        UMF_PACKET packet = responseQueues[responseActiveQueue].first();
        responseQueues[responseActiveQueue].deq();

        // send the packet to channelio
        write(packet);

        // one more chunk processed
        responseChunksRemaining <= responseChunksRemaining - 1;

    endrule

    // ==============================================================
    //                        Set Interfaces
    // ==============================================================

    interface requestPorts  = req_ports;
    interface responsePorts = resp_ports;

endmodule
