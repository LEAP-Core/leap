//
// Copyright (C) 2013 Intel Corporation
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

import FIFO::*;
import Vector::*;
import List::*;
import GetPut::*;


// ========================================================================
//
//   Stream in a file.
//
// ========================================================================

//
// mkStdIO_GetFile --
//     Stream in t_DATA sized objects from file "fileName."  Return one
//     Invalid to signal EOF.  Streaming begins when "start" is True.
//
//     The current implementation uses standard STDIO local nodes, so is less
//     space efficient than it could be.  If needed, we could change the code
//     to be more efficient without changing the interface.
//
module [CONNECTED_MODULE] mkStdIO_GetFile#(Bool start,
                                           GLOBAL_STRING_UID fileName)
    // Interface:
    (Get#(Maybe#(t_DATA)))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              // The size of the STDIO raw read data stream.  Ideally we would pick
              // a larger word size, since it reduces traffic.  Unfortunately,
              // chunking larger than 8 bits leaves open the possibility of
              // missing one or more t_DATA chunks at the end of the file.
              Alias#(t_STDIO_DATA, Bit#(8)));

    STDIO#(t_STDIO_DATA) stdio <- mkStdIO();
    let fmode <- getGlobalStringUID("r");

    // Convert the STDIO raw stream to the requested data size.
    STDIO_DEMARSHALLER#(t_STDIO_DATA, t_DATA) dem <- mkStdIORspDemarshaller();

    Reg#(Maybe#(STDIO_FILE)) fHandle <- mkReg(tagged Invalid);
    Reg#(Bool) didStart <- mkReg(False);
    Reg#(Bool) eof <- mkReg(False);
    Reg#(Bool) done <- mkReg(False);

    // Open the file when start is asserted.
    rule openReq (start && ! didStart);
        stdio.fopen_req(fileName, fmode);
        didStart <= True;
    endrule

    // Get the file handle from the host.
    rule openRsp (True);
        let fh <- stdio.fopen_rsp();
        fHandle <= tagged Valid fh;
    endrule

    // Send read requests until EOF is reached.
    rule readReq (! eof &&& fHandle matches tagged Valid .fh);
        stdio.freadMax_req(fh);
    endrule

    // Clear out extra read requests still outstanding after EOF is reached.
    rule readSink (eof &&& fHandle matches tagged Valid .fh &&&
                   stdio.fread_numInFlight != 0);
        let rsp <- stdio.fread_rsp();
    endrule

    // Consume the STDIO raw stream and send it to the demarshaller.
    rule readData (! eof &&& fHandle matches tagged Valid .fh);
        let rsp <- stdio.fread_rsp();
        if (rsp matches tagged Valid .v)
        begin
            let chunks = fromInteger(valueOf(MARSHALLER_MSG_LEN#(t_DATA, t_STDIO_DATA)));
            dem.enq(v, chunks);
        end
        else
        begin
            eof <= True;
        end
    endrule

    // Receive the desired, properly sized, data stream.
    method ActionValue#(Maybe#(t_DATA)) get() if (! done &&
                                                  (dem.notEmpty || eof));
        Maybe#(t_DATA) rsp;

        if (dem.notEmpty)
        begin
            rsp = tagged Valid dem.first();
            dem.deq();
        end
        else
        begin
            rsp = tagged Invalid;
            done <= True;
        end

        return rsp;
    endmethod
endmodule


// ========================================================================
//
//   Conditional printf wrapper, useful for debugging code.
//
// ========================================================================

interface STDIO_COND_PRINTF#(type t_DATA);
    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    method Action fprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID, List#(t_DATA) args);
endinterface

//
// mkStdIO_CondPrintf --
//     Wrap the provided STDIO node and expose printf and fprintf.  Output
//     is enabled conditionally, based on the requested bit of the dynamic
//     parameter STDIO_COND_PRINTF_MASK.
//
//     This module provides internal buffering.  If you share a single
//     STDIO node and instantiate a mkStdIO_CondPrintf for each of a set
//     of parallel, independent, rules then the rules may still be
//     scheduled independently.  When I/O is disabled, rules will always
//     be independent.  For designs where space is more important than
//     parallelism, allocate one mkStdIO_CondPrintf and share it among
//     multiple rules.
//
//     By convention we leave the high mask bit for use by LEAP infrastructure.
//
module [CONNECTED_MODULE] mkStdIO_CondPrintf#(Integer maskBitIdx,
                                              STDIO#(t_DATA) stdio)
    // Interface:
    (STDIO_COND_PRINTF#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Add#(a__, 32, TMul#(STDIO_WRITE_MAX, t_DATA_SZ)));

    // Only print if enabled by the user
    Reg#(Maybe#(Bool)) enablePrintf <- mkReg(tagged Invalid);

    (* fire_when_enabled *)
    rule init (True);
        enablePrintf <= tagged Valid unpack(stdio.cond_mask_update[maskBitIdx]);
    endrule


    FIFO#(Tuple4#(STDIO_FILE,
                  GLOBAL_STRING_UID,
                  Vector#(STDIO_WRITE_MAX, t_DATA),
                  STDIO_NUM_DATA)) newReqQ <- mkFIFO1();

    rule fwdReq (True);
        match {.file, .msgID, .data, .numData} = newReqQ.first();
        newReqQ.deq();

        stdio.vfprintf(file, msgID, data, numData);
    endrule


    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args) if (enablePrintf matches tagged Valid .en);
        if (en)
        begin
            newReqQ.enq(tuple4(0, msgID,
                               stdioListToVec(args),
                               fromInteger(List::length(args))));
        end
    endmethod

    method Action fprintf(STDIO_FILE file,
                          GLOBAL_STRING_UID msgID,
                          List#(t_DATA) args) if (enablePrintf matches tagged Valid .en);
        if (en)
        begin
            newReqQ.enq(tuple4(file, msgID,
                               stdioListToVec(args),
                               fromInteger(List::length(args))));
        end
    endmethod
endmodule


// ========================================================================
//
//   NULL and debugging versions of StdIO nodes.  The debugging version
//   enables the node if STDIO_ENABLE_DEBUG is is non-zero.  If zero,
//   a NULL node is allocated.
//
// ========================================================================

//
// mkStdIO_Debug --
//     Conditionally make either a StdIO client or a NULL client, depending
//     on the state of the STDIO_ENABLE_DEBUG awb parameter.
//
module [CONNECTED_MODULE] mkStdIO_Debug
    // interface:
    (STDIO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Add#(a__, 32, TMul#(STDIO_WRITE_MAX, t_DATA_SZ)));

    let io <- (`STDIO_ENABLE_DEBUG != 0 ? mkStdIO() :
                                          mkStdIO_Disabled());
    return io;
endmodule
