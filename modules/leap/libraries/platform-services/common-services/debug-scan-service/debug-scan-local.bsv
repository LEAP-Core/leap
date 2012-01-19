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
`include "awb/provides/librl_bsv.bsh"
`include "awb/provides/debug_scan_device.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/DEBUG_SCAN.bsh"

//
// Debug scan nodes accept any size data to scan out by breaking the data
// into chunks.  The mkDebugScanNode() module takes a wire as input, with
// the expectation that the wire will have no predicate (e.g. a mkBypassWire)
// and that it will have a meaningful value on any cycle.
//

//
// Debug scan nodes have no methods.
//
interface DEBUG_SCAN#(type t_DEBUG_DATA);
endinterface: DEBUG_SCAN


typedef 8 DEBUG_SCAN_VALUE_SZ;
typedef Bit#(DEBUG_SCAN_VALUE_SZ) DEBUG_SCAN_VALUE;

typedef union tagged
{
    void DS_DUMP;
    struct {DEBUG_SCAN_DICT_TYPE id; DEBUG_SCAN_VALUE value; Bool eom;} DS_VAL;
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
//   during scan the wire should have no predicates (e.g. mkBypassWire).
// 
module [CONNECTED_MODULE] mkDebugScanNode#(DEBUG_SCAN_DICT_TYPE myID,
                                           function t_DEBUG_DATA debugValue())
    // interface:
    (DEBUG_SCAN#(t_DEBUG_DATA))
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ),
              Div#(t_DEBUG_DATA_SZ, DEBUG_SCAN_VALUE_SZ, n_ENTRIES));

    Connection_Chain#(DEBUG_SCAN_DATA) chain <- mkConnection_Chain(`RINGID_DEBUG_SCAN);

    Reg#(DEBUG_SCAN_STATE) state <- mkReg(DS_IDLE);

    // Marshall the debug data to the message size.
    MARSHALLER#(DEBUG_SCAN_VALUE, t_DEBUG_DATA) mar <- mkSimpleMarshallerHighToLow();

    //
    // sendDumpData --
    //     Forward dump data and token around the ring.
    //
    rule sendDumpData (state == DS_DUMPING);
        if (mar.notEmpty)
        begin
            // More data remains for this node
            chain.sendToNext(tagged DS_VAL { id: myID,
                                             value: mar.first(),
                                             eom: mar.isLast() });
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
                mar.enq(debugValue);
                state <= DS_DUMPING;
            end

            default: chain.sendToNext(ds);
        endcase
    endrule
endmodule
