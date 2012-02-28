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


import List::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/dict/RINGID.bsh"

//
// Debug scan nodes accept any size data to scan out by breaking the data
// into chunks.  The addDebugScanField() module takes a function as input, with
// the expectation that the function will have no predicate and that it will
// have a meaningful value on any cycle.
//


// ========================================================================
//
//   Public interface and modules
//
// ========================================================================

//
// Sets of values to scan are collected in DEBUG_SCAN_FIELD_LISTs by
// adding them with module addDebugScanField.  For example:
//
//    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
//    dbg_list <- addDebugScanField(dbg_list, "Read state", readState);
//    dbg_list <- addDebugScanField(dbg_list, "Write state", writeState);
//
// The list of fields must then be attached to a scan node:
//
//    let dbgNode <- mkDebugScanNode("My module's state", dbg_list);
//

interface DEBUG_SCAN_FIELD;
    method String name();
    method Integer size();
    method Bit#(64) value();
    method Bool isMaybe();
endinterface: DEBUG_SCAN_FIELD

typedef List#(DEBUG_SCAN_FIELD) DEBUG_SCAN_FIELD_LIST;

//
// addDebugScanField --
//     Insert a new field name and value into a list of monitored objects.
//
module addDebugScanField#(List#(DEBUG_SCAN_FIELD) curFields, 
                          String fieldName,
                          function t_DEBUG_DATA debugValue())
    // Interface:
    (List#(DEBUG_SCAN_FIELD))
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ));

    return List::nil;
endmodule

//
// addDebugScanMaybeField --
//     Insert a new field name and Maybe#(value) into a list of monitored
//     objects.
//
module addDebugScanMaybeField#(List#(DEBUG_SCAN_FIELD) curFields, 
                               String fieldName,
                               function t_DEBUG_DATA debugValue())
    // Interface:
    (List#(DEBUG_SCAN_FIELD))
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ));

    return List::nil;
endmodule


//
// mkDebugScanNode --
//     Instantiate a scan node for a set of fields.
//
module [CONNECTED_MODULE] mkDebugScanNode#(String nodeName,
                                           List#(DEBUG_SCAN_FIELD) allFields)
    // Interface:
    (Empty);

endmodule

//
// mkDebugScanSoftConnections --
//     Special hook used only by soft connections debugging code to dump
//     the state of a set of soft connections.
//
module [CONNECTED_MODULE] mkDebugScanSoftConnections#(String nodeName,
                                                      List#(DEBUG_SCAN_FIELD) allFields)
    // interface:
    (Empty);

endmodule
