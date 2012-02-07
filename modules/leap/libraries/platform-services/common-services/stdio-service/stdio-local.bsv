//
// Copyright (C) 2012 Intel Corporation
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

import Vector::*;
import List::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"

//`include "awb/rrr/server_stub_STDIO.bsh"
//`include "awb/rrr/client_stub_STDIO.bsh"

interface STDIO#(type t_DATA);
    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
endinterface

// Pick a power of 2!
typedef Bit#(32) STDIO_REQ_RING_CHUNK;

typedef enum
{
    STDIO_REQ_PRINTF
}
STDIO_REQ_COMMAND
    deriving (Eq, Bits);

//
// STDIO_REQ_HEADER is sent at the beginning of all requests sent to software.
//
typedef struct
{
    GLOBAL_STRING_UID text;
    Bit#(11) unused;
    Bit#(3) numData;                // Number of elements in data vector
    Bit#(2) dataSize;               // Size of data elements (1, 2, 4 or 8 bytes)
    Bit#(8) fileHandle;             // Used only for commands refering to a file
    Bit#(8) command;                // STDIO_REQ_COMMAND
}
STDIO_REQ_HEADER
    deriving (Eq, Bits);

//
// STDIO_REQ is marshalled over the request ring and sent to software.
//
typedef struct
{
    Vector#(7, t_DATA) data;        // Number of elements actually transmitted
                                    // varies, depending on the value of numData
    STDIO_REQ_HEADER header;
}
STDIO_REQ#(type t_DATA)
    deriving (Eq, Bits);

typedef struct
{
}
STDIO_RSP
    deriving (Eq, Bits);

//
// STDIO_CLIENT_ID is used to identify a particular standard I/O instance on
// the response ring.
//
typedef Bit#(TLog#(`STDIO_MAX_CLIENTS)) STDIO_CLIENT_ID;

typedef enum
{
    STDIO_REQ_IDLE,
    STDIO_REQ_SEND_REQ
}
STDIO_REQ_STATE
    deriving (Eq, Bits);


module [CONNECTED_MODULE] mkStdIO
    // interface:
    (STDIO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));
    
    // Response ring is addressable, since responses are to specific clients.
    CONNECTION_ADDR_RING#(STDIO_CLIENT_ID, STDIO_RSP) rspChain <-
        mkConnectionAddrRingDynNode("stdio_rsp_ring");


    // ====================================================================
    //
    //   Request ring -- FPGA to host.
    //
    // ====================================================================

    // Request ring.  All requests are handled by the service.
    CONNECTION_CHAIN#(Tuple2#(STDIO_REQ_RING_CHUNK, Bool)) reqChain <-
        mkConnectionChain("stdio_req_ring");

    STDIO_MARSHALLER#(STDIO_REQ_RING_CHUNK, t_DATA) mar <- mkStdIOReqMarshaller();

    Reg#(STDIO_REQ_STATE) reqState <- mkReg(STDIO_REQ_IDLE);
    Reg#(Bool) reqNotBusy <- mkReg(True);

    //
    // sendLocalReq --
    //     Send local request.
    //
    rule sendLocalReq (reqState == STDIO_REQ_SEND_REQ);
        if (! mar.isLast())
        begin
            reqChain.sendToNext(tuple2(mar.first(), False));
        end
        else
        begin
            reqChain.sendToNext(tuple2(mar.first(), True));
            reqState <= STDIO_REQ_IDLE;
        end

        mar.deq();
    endrule

    //
    // manageReq --
    //     Forward requests from others and switch to local sending when
    //     appropriate.
    //
    rule forwardReq (reqState == STDIO_REQ_IDLE);
        if (mar.notEmpty && reqNotBusy)
        begin
            reqState <= STDIO_REQ_SEND_REQ;
        end
        else
        begin
            match {.chunk, .eom} <- reqChain.recvFromPrev();
            reqChain.sendToNext(tuple2(chunk, eom));
            reqNotBusy <= eom;
        end
    endrule


    // ====================================================================
    //
    //   Methods
    //
    // ====================================================================

    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
        STDIO_REQ_HEADER header = ?;
        header.command = zeroExtend(pack(STDIO_REQ_PRINTF));
        header.dataSize = fromInteger(valueOf(TSub#(TLog#(t_DATA_SZ), 3)));
        header.text = msgID;
        header.numData = fromInteger(List::length(args));

        Vector#(7, t_DATA) data = newVector();

        if (List::length(args) == 1)
        begin
            Vector#(1, t_DATA) v = toVector(args);
            for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
        end
        else if (List::length(args) == 2)
        begin
            Vector#(2, t_DATA) v = toVector(args);
            for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
        end
        else if (List::length(args) == 3)
        begin
            Vector#(3, t_DATA) v = toVector(args);
            for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
        end
        else if (List::length(args) == 4)
        begin
            Vector#(4, t_DATA) v = toVector(args);
            for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
        end
        else if (List::length(args) == 5)
        begin
            Vector#(5, t_DATA) v = toVector(args);
            for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
        end
        else if (List::length(args) == 6)
        begin
            Vector#(6, t_DATA) v = toVector(args);
            for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
        end
        else if (List::length(args) == 7)
        begin
            Vector#(7, t_DATA) v = toVector(args);
            for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
        end
        else if (List::length(args) != 0)
        begin
            errorM("Unsupported number of arguments to STDIO printf.");
        end

        STDIO_REQ#(t_DATA) req = STDIO_REQ { data: data, header: header };
        mar.enq(req);
    endmethod
endmodule


interface STDIO_MARSHALLER#(type t_FIFO_DATA, type t_DATA);
    method Action enq(STDIO_REQ#(t_DATA) msg);
    method Action deq();
    method t_FIFO_DATA first();
    method Bool notFull();
    method Bool notEmpty();
    method Bool isLast();     // Last chunk from the original enqueued data
endinterface

module mkStdIOReqMarshaller
    // Interface:
    (STDIO_MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(STDIO_REQ_HEADER, t_REQ_HEADER_SZ),
              Bits#(STDIO_REQ#(t_DATA), t_REQ_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA_SZ, t_REQ_SZ)));

    Reg#(Vector#(n, t_FIFO_DATA)) buffer <- mkRegU();
    Reg#(Bit#(TAdd#(1, TLog#(n)))) count <- mkReg(0);
    Reg#(Bool) empty <- mkReg(True);

    method Action enq(STDIO_REQ#(t_DATA) msg) if (empty);
        empty <= False;

        // Send only as much of the message as necessary.  Most messages
        // don't require the entire buffer.

        let hdr_cnt = valueOf(MARSHALLER_MSG_LEN#(t_FIFO_DATA_SZ,
                                                  t_REQ_HEADER_SZ));

        if (valueOf(t_FIFO_DATA_SZ) <= valueOf(t_DATA_SZ))
        begin
            // Data elements are larger than the marshaller's chunk size.
            // This it the easy case, since both must be powers of 2.

            Bit#(TAdd#(1, TLog#(n))) data_cnt = zeroExtendNP(msg.header.numData);
            data_cnt = data_cnt *
                       fromInteger(valueOf(MARSHALLER_MSG_LEN#(t_FIFO_DATA_SZ,
                                                               t_DATA_SZ)));
            count <= fromInteger(hdr_cnt) + data_cnt;
        end
        else
        begin
            // Data elements are smaller than the marshaller's chunk size,
            // making the dynamic size harder to compute but also less important
            // since the data vector is short.  Just special case 0.
            if (msg.header.numData == 0)
                count <= fromInteger(hdr_cnt);
            else
                count <= fromInteger(valueOf(n));
        end

        // Convert the message to a vector of the marshalled size.
        buffer <= toChunks(msg);
    endmethod

    method Action deq() if (! empty);
        t_FIFO_DATA dummy = ?;
        buffer <= shiftInAtN(buffer, dummy);

        empty <= (count == 1);
        count <= count - 1;
    endmethod

    method t_FIFO_DATA first() if (! empty);
        return buffer[0];
    endmethod

    method Bool notFull();
        return empty;
    endmethod

    method Bool notEmpty();
        return ! empty;
    endmethod

    method Bool isLast();
        return count == 1;
    endmethod
endmodule
