//
// Copyright (C) 2008 Massachusetts Institute of Technology
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


import FIFO::*;
import Counter::*;
import Vector::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"
`include "awb/provides/debug_scan_device.bsh"

`include "awb/dict/RINGID.bsh"

//
// Debug scan nodes accept any size data to scan out by breaking the data
// into chunks.  The mkDebugScanNode() module takes a function as input, with
// the expectation that the function will have no predicate and that it will
// have a meaningful value on any cycle.
//


//
// Formatting of debug scan output is encoded in the string passed to the
// module.  The following functions construct the encoded string.  An
// encoded ID string begins with a name record and, in some cases, is
// followed by descriptions of data fields.
//
// WARNING:  The formatting parser is very simple!  Do not put a ~ in your string!
//

//
// debugScanSimpleName --
//     A simple heading prints a name for the data and emits the debug scan
//     value as a raw data stream.  No other strings should be appended to
//     the returned string.
//
function String debugScanSimpleName(String name);
    return "S:" + name;
endfunction

//
// debugScanName --
//     The name of a debug scan record.  The record will be printed as a
//     set of named fields.  Define fields by appending the result of
//     debugScanField to the returned string.
//
function String debugScanName(String name);
    return "N:" + name;
endfunction

//
// debugScanField --
//     Describe one field in a debug scan record.  Mutiple fields may be defined
//     by concatenation.  Describe fields starting with the low bits.
//
function String debugScanField(String field, Integer bits);
    return "~" + integerToString(bits) + "~" + field;
endfunction

//
// debugScanMaybeField --
//     Same as a debugScanField, but the value is wrapped by a Maybe#().  Do
//     not include the maybe bit in the size.
//
function String debugScanMaybeField(String field, Integer bits);
    return "~M" + integerToString(bits) + "~" + field;
endfunction


//
// debugScanSoftConnections --
//     Special heading used only by the soft connections state dumping code.
//
function String debugScanSoftConnections(String name);
    return "C:" + name;
endfunction



typedef 8 DEBUG_SCAN_VALUE_SZ;
typedef Bit#(DEBUG_SCAN_VALUE_SZ) DEBUG_SCAN_VALUE;

typedef union tagged
{
    void             DS_DUMP;
    DEBUG_SCAN_VALUE DS_VAL;        // One marshalled chunk (sent low to high)
    DEBUG_SCAN_VALUE DS_VAL_LAST;   // Last chunk of a value
}
DEBUG_SCAN_DATA
    deriving (Eq, Bits);


typedef enum
{
    DS_IDLE,
    DS_DUMPING
}
DEBUG_SCAN_STATE
    deriving (Eq, Bits);


//
// mkDebugScanNode --
//
//   Scan out the data coming in on wire debugValue.  To avoid deadlocks
//   during scan the value should have no predicates.
//
//   Construct the "myID" argument using the functions above.
// 
module [CONNECTED_MODULE] mkDebugScanNode#(String myID,
                                           function t_DEBUG_DATA debugValue())
    // interface:
    (Empty)
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ),
              Div#(t_DEBUG_DATA_SZ, DEBUG_SCAN_VALUE_SZ, n_ENTRIES));

    Connection_Chain#(DEBUG_SCAN_DATA) chain <- mkConnection_Chain(`RINGID_DEBUG_SCAN);

    Reg#(DEBUG_SCAN_STATE) state <- mkReg(DS_IDLE);

    let id <- getGlobalStringUID(myID);

    // Marshall the debug data to the message size.
    MARSHALLER#(DEBUG_SCAN_VALUE,
                Tuple2#(t_DEBUG_DATA, GLOBAL_STRING_UID)) mar <- mkSimpleMarshaller();

    //
    // sendDumpData --
    //     Forward dump data and token around the ring.
    //
    rule sendDumpData (state == DS_DUMPING);
        if (mar.notEmpty)
        begin
            // More data remains for this node
            if (! mar.isLast())
                chain.sendToNext(tagged DS_VAL mar.first());
            else
                chain.sendToNext(tagged DS_VAL_LAST mar.first());

            mar.deq();
        end
        else
        begin
            // Done with this node's data
            chain.sendToNext(tagged DS_DUMP);
            state <= DS_IDLE;
        end
    endrule


    //
    // receiveCmd --
    //     Receive a command on the ring.
    //
    (* conservative_implicit_conditions *)
    rule receiveCmd (state == DS_IDLE);
        let ds <- chain.recvFromPrev();

        case (ds) matches 
            tagged DS_DUMP:
            begin
                mar.enq(tuple2(debugValue, id));
                state <= DS_DUMPING;
            end

            default: chain.sendToNext(ds);
        endcase
    endrule
endmodule
