//
// Copyright (C) 2011 Intel Corporation
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

`include "asim/provides/librl_bsv_base.bsh"
`include "asim/provides/soft_connections.bsh"
`include "asim/provides/streams_device.bsh"

`include "asim/dict/RINGID.bsh"
`include "asim/dict/STREAMS.bsh"

import FIFOF::*;


interface STREAMS_CLIENT;
    // Send as default streamID
    method Action send(STREAMS_DICT_TYPE string_id,
                       Bit#(32) payload0,
                       Bit#(32) payload1);

    // Send with specified streamID
    method Action sendAs(STREAMID_DICT_TYPE stream_id,
                         STREAMS_DICT_TYPE string_id,
                         Bit#(32) payload0,
                         Bit#(32) payload1);
endinterface: STREAMS_CLIENT


module [CONNECTED_MODULE] mkStreamsClient#(STREAMID_DICT_TYPE streamID)
    // Interface:
    (STREAMS_CLIENT);

    // Incoming FIFO separates scheduling dependence of the ring from the
    // client.  FIFO1 is sufficient, since the off-FPGA bandwidth is low.
    FIFOF#(STREAMS_REQUEST) msgQ <- mkFIFOF1();
    
    Connection_Chain#(STREAMS_REQUEST) chain <- mkConnection_Chain(`RINGID_STREAMS);

    //
    // fwdLocalMsg --
    //     Put local messages on the outbound ring.
    //
    rule fwdLocalMsg (True);
        let msg = msgQ.first();
        msgQ.deq();

        chain.sendToNext(msg);
    endrule


    //
    // fwdRingMsg --
    //     Move remote messages along the ring.
    //
    rule fwdRingMsg (! msgQ.notEmpty());
        let msg <- chain.recvFromPrev();
        chain.sendToNext(msg);
    endrule

    
    //
    // send --
    //     Accept new local message.
    //
    method Action send(STREAMS_DICT_TYPE string_id,
                       Bit#(32) payload0,
                       Bit#(32) payload1);
        msgQ.enq(STREAMS_REQUEST { streamID: streamID,
                                   stringID: string_id,
                                   payload0: payload0,
                                   payload1: payload1 });
    endmethod

    
    //
    // sendAs --
    //     Accept new local message with non-default stream ID
    //
    method Action sendAs(STREAMID_DICT_TYPE stream_id,
                         STREAMS_DICT_TYPE string_id,
                         Bit#(32) payload0,
                         Bit#(32) payload1);
        msgQ.enq(STREAMS_REQUEST { streamID: stream_id,
                                   stringID: string_id,
                                   payload0: payload0,
                                   payload1: payload1 });
    endmethod
endmodule


module mkStreamsClient_Disabled
    // Interface:
    (STREAMS_CLIENT);

    //
    // send --
    //     Accept new local message.
    //
    method Action send(STREAMS_DICT_TYPE string_id,
                       Bit#(32) payload0,
                       Bit#(32) payload1);
        noAction;
    endmethod

    
    //
    // sendAs --
    //     Accept new local message with non-default stream ID
    //
    method Action sendAs(STREAMID_DICT_TYPE stream_id,
                         STREAMS_DICT_TYPE string_id,
                         Bit#(32) payload0,
                         Bit#(32) payload1);
        noAction;
    endmethod
endmodule
