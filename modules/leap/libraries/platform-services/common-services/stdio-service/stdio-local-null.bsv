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

import FIFO::*;
import FIFOF::*;
import Vector::*;
import List::*;

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/librl_bsv.bsh"

// Maximum number of data arguments for writes
typedef 8 STDIO_WRITE_MAX;

// FILE handle
typedef Bit#(8) STDIO_FILE;

typedef enum {
   STDIO_STDOUT = 0,
   STDIO_STDIN = 1,
   STDIO_STDERR = 2
}
STDIO_STD_FILES
    deriving (Eq, Bits);

//
// For now, RRR does not provide virtual channels for each service.  As
// a result, it is possible to deadlock the shared RRR I/O channel if
// responses to read requests back up.  Instead of forcing each STDIO
// client to manage buffers, the implementation here guarantees to provide
// buffering for all outstanding read requests.  (This would also let us
// replace RRR with virtual channels and change only the code here to
// eliminate the buffering.
//

// Maximum number of read requests in flight
typedef 4 STDIO_MAX_READS_IN_FLIGHT;
// Maximum elements per read request.  Varies with element size due to
// buffering requirements.
typedef TDiv#(TDiv#(32768, STDIO_MAX_READS_IN_FLIGHT), SizeOf#(t_DATA))
    STDIO_MAX_ELEM_PER_READ#(type t_DATA);
typedef Bit#(TLog#(STDIO_MAX_ELEM_PER_READ#(t_DATA))) STDIO_NUM_READ_ELEMS#(type t_DATA);

interface STDIO#(type t_DATA);
    // fopen is a request/response interface, returning the file handle
    method Action fopen_req(GLOBAL_STRING_UID nameID, GLOBAL_STRING_UID modeID);
    method ActionValue#(STDIO_FILE) fopen_rsp();
    method Action fclose(STDIO_FILE file);

    method Action popen_req(GLOBAL_STRING_UID nameID, Bool forRead);
    method ActionValue#(STDIO_FILE) popen_rsp();
    method Action pclose(STDIO_FILE file);


    // Start a read that will stream back nmemb elements serially.  The
    // implementation guarantees to provide local buffering sufficient to
    // hold the full response, avoiding the need for client buffer management.
    method Action fread_req(STDIO_FILE file,
                            STDIO_NUM_READ_ELEMS#(t_DATA) nmemb) provisos(Bits#(t_DATA, t_DATA_SZ));

    // Convenience method for making the largest request possible
    method Action freadMax_req(STDIO_FILE file);

    // Return either one element from a read or Invalid for EOF.  Responses
    // from a single read request terminate on EOF even if fewer responses are
    // returned than originally requested.
    method ActionValue#(Maybe#(t_DATA)) fread_rsp();

    // Number of reads currently in flight.  This method enables clients
    // to track and consume results of all read requests, especially when
    // some read returns EOF.  Following EOF, the client must continue to
    // sink read responses (which will all return EOF) until no reads are
    // in flight.
    method Bit#(TLog#(TAdd#(1, STDIO_MAX_READS_IN_FLIGHT))) fread_numInFlight();


    // The list of arguments to fwrite may be up to STDIO_WRITE_MAX elements
    method Action fwrite(STDIO_FILE file, List#(t_DATA) args);

    // The list of arguments to printf may be up to STDIO_WRITE_MAX elements
    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    method Action fprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID, List#(t_DATA) args);

    // sprintf is a request/response interface, allocating a GLOBAL_STRING_UID
    // on the host to hold the new string.  The new string remains allocated
    // until released by a sprintf_delete call.
    method Action sprintf_req(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    method ActionValue#(GLOBAL_STRING_UID) sprintf_rsp();

    // Delete a dynamically allocated global string (e.g. one created by
    // sprintf_req).
    method Action string_delete(GLOBAL_STRING_UID strID);

    method Action fflush(STDIO_FILE file);
    method Action rewind(STDIO_FILE file);

    // sync request/response both invokes the sync() system call and guarantees
    // all previous commands have been received.
    method Action sync_req();
    method Action sync_rsp();
endinterface


module mkStdIO
    // interface:
    (STDIO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Add#(a__, 32, TMul#(STDIO_WRITE_MAX, t_DATA_SZ)));
    
    let io <- mkStdIO_Disabled();
    return io;

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
module mkStdIO_Debug
    // interface:
    (STDIO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Add#(a__, 32, TMul#(STDIO_WRITE_MAX, t_DATA_SZ)));

    let io <- (`STDIO_ENABLE_DEBUG != 0 ? mkStdIO() :
                                          mkStdIO_Disabled());
    return io;
endmodule


//
// mkStdIO_Disabled --
//     NULL version of STDIO.
//
module mkStdIO_Disabled
    // interface:
    (STDIO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Add#(a__, 32, TMul#(STDIO_WRITE_MAX, t_DATA_SZ)));

    FIFO#(Bool) fopenFIFO <- mkFIFO();
    FIFO#(Bool) popenFIFO <- mkFIFO();
    FIFOF#(Bool) freadFIFO <- mkFIFOF();
    FIFO#(Bool) sprintfFIFO <- mkFIFO();
    FIFO#(Bool) syncFIFO <- mkFIFO();

    method Action fopen_req(GLOBAL_STRING_UID nameID, GLOBAL_STRING_UID modeID);
        fopenFIFO.enq(?);
    endmethod

    method ActionValue#(STDIO_FILE) fopen_rsp();
        fopenFIFO.deq();
        return ?;
    endmethod

    method Action fclose(STDIO_FILE file);
    endmethod

    method Action popen_req(GLOBAL_STRING_UID nameID, Bool forRead);
        popenFIFO.enq(?);
    endmethod

    method ActionValue#(STDIO_FILE) popen_rsp();
        popenFIFO.deq();
        return ?;
    endmethod

    method Action pclose(STDIO_FILE file);
    endmethod

    method Action fread_req(STDIO_FILE file,
                            STDIO_NUM_READ_ELEMS#(t_DATA) nmemb) provisos(Bits#(t_DATA, t_DATA_SZ));
        freadFIFO.enq(?);
    endmethod

    method Action freadMax_req(STDIO_FILE file);
        freadFIFO.enq(?);
    endmethod

    method ActionValue#(Maybe#(t_DATA)) fread_rsp();
        freadFIFO.deq();
        return tagged Invalid;
    endmethod

    method Bit#(TLog#(TAdd#(1, STDIO_MAX_READS_IN_FLIGHT))) fread_numInFlight();
        return (freadFIFO.notEmpty ? 1 : 0);
    endmethod

    method Action fwrite(STDIO_FILE file, List#(t_DATA) args);
    endmethod

    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    endmethod

    method Action fprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    endmethod

    method Action sprintf_req(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
        sprintfFIFO.enq(?);
    endmethod

    method ActionValue#(GLOBAL_STRING_UID) sprintf_rsp();
        sprintfFIFO.deq();
        return ?;
    endmethod

    method Action string_delete(GLOBAL_STRING_UID strID);
    endmethod

    method Action fflush(STDIO_FILE file);
    endmethod

    method Action rewind(STDIO_FILE file);
    endmethod

    method Action sync_req();
        syncFIFO.enq(?);
    endmethod

    method Action sync_rsp();
        syncFIFO.deq();
    endmethod
endmodule


