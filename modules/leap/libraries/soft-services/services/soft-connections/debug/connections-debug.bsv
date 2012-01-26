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

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/debug_scan_service.bsh"


//
// Global strings have two parts:  a component guaranteed constant within a
// given synthesis boundary and a component representing a given string
// within a single synthesis boundary.  In the debug scan messages here
// the synthesis boundary UID is sent only once.
//

typedef struct
{
    Bool notFull;
    Bool notEmpty;
    GLOBAL_STRING_LOCAL_UID sendName;
}
DEBUG_SCAN_CONNECTION_SEND
    deriving (Eq, Bits);

typedef Vector#(n_ELEM, DEBUG_SCAN_CONNECTION_SEND)
    DEBUG_SCAN_CONNECTION_SEND_VEC#(numeric type n_ELEM);


//
// mkSoftConnectionDebugInfo --
//     Generate debug scan data for every soft connection FIFO.
//
module [CONNECTED_MODULE] mkSoftConnectionDebugInfo (Empty);
    let dbgInfo <- getConnectionDebugInfo();

    Integer pos = 0;
    Integer len = List::length(dbgInfo);

    //
    // The List type can't be packed into bits and the length of the list can't
    // be used to generate a type.  We are forced to pack the list into a
    // set of vectors of known sizes.
    //

    while (pos < len)
    begin
        Integer n_elem = len - pos;
        Integer grp_len = (n_elem > 32 ? 32 : n_elem);
        
        if (grp_len == 32)      DEBUG_SCAN_CONNECTION_SEND_VEC#(32) dbg32 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 31) DEBUG_SCAN_CONNECTION_SEND_VEC#(31) dbg31 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 30) DEBUG_SCAN_CONNECTION_SEND_VEC#(30) dbg30 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 29) DEBUG_SCAN_CONNECTION_SEND_VEC#(29) dbg29 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 28) DEBUG_SCAN_CONNECTION_SEND_VEC#(28) dbg28 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 27) DEBUG_SCAN_CONNECTION_SEND_VEC#(27) dbg27 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 26) DEBUG_SCAN_CONNECTION_SEND_VEC#(26) dbg26 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 25) DEBUG_SCAN_CONNECTION_SEND_VEC#(25) dbg25 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 24) DEBUG_SCAN_CONNECTION_SEND_VEC#(24) dbg24 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 23) DEBUG_SCAN_CONNECTION_SEND_VEC#(23) dbg23 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 22) DEBUG_SCAN_CONNECTION_SEND_VEC#(22) dbg22 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 21) DEBUG_SCAN_CONNECTION_SEND_VEC#(21) dbg21 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 20) DEBUG_SCAN_CONNECTION_SEND_VEC#(20) dbg20 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 19) DEBUG_SCAN_CONNECTION_SEND_VEC#(19) dbg19 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 18) DEBUG_SCAN_CONNECTION_SEND_VEC#(18) dbg18 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 17) DEBUG_SCAN_CONNECTION_SEND_VEC#(17) dbg17 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 16) DEBUG_SCAN_CONNECTION_SEND_VEC#(16) dbg16 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 15) DEBUG_SCAN_CONNECTION_SEND_VEC#(15) dbg15 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 14) DEBUG_SCAN_CONNECTION_SEND_VEC#(14) dbg14 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 13) DEBUG_SCAN_CONNECTION_SEND_VEC#(13) dbg13 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 12) DEBUG_SCAN_CONNECTION_SEND_VEC#(12) dbg12 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 11) DEBUG_SCAN_CONNECTION_SEND_VEC#(11) dbg11 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len == 10) DEBUG_SCAN_CONNECTION_SEND_VEC#(10) dbg10 <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  9) DEBUG_SCAN_CONNECTION_SEND_VEC#( 9) dbg9  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  8) DEBUG_SCAN_CONNECTION_SEND_VEC#( 8) dbg8  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  7) DEBUG_SCAN_CONNECTION_SEND_VEC#( 7) dbg7  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  6) DEBUG_SCAN_CONNECTION_SEND_VEC#( 6) dbg6  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  5) DEBUG_SCAN_CONNECTION_SEND_VEC#( 5) dbg5  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  4) DEBUG_SCAN_CONNECTION_SEND_VEC#( 4) dbg4  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  3) DEBUG_SCAN_CONNECTION_SEND_VEC#( 3) dbg3  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else if (grp_len ==  2) DEBUG_SCAN_CONNECTION_SEND_VEC#( 2) dbg2  <- mkSoftConnectionDebugNode(pos, dbgInfo);
        else                    DEBUG_SCAN_CONNECTION_SEND_VEC#( 1) dbg1  <- mkSoftConnectionDebugNode(pos, dbgInfo);

        pos = pos + grp_len;
    end
endmodule


//
// mkSoftconnectionDebugNode --
//     Generate a debug scan node for a set of soft connection FIFOs.
//
module [CONNECTED_MODULE] mkSoftConnectionDebugNode#(Integer startPos,
                                                     List#(CONNECTION_DEBUG_INFO) info)
    (DEBUG_SCAN_CONNECTION_SEND_VEC#(n_ELEM));

    DEBUG_SCAN_CONNECTION_SEND_VEC#(n_ELEM) dbg_scan_data = newVector();

    for (Integer i = 0; i < valueOf(n_ELEM); i = i + 1)
    begin
        let elem = info[startPos + i];

        // Allocate an integer tag for the name.
        GLOBAL_STRING_UID tag <- getGlobalStringUID(elem.sendName);

        dbg_scan_data[i] = DEBUG_SCAN_CONNECTION_SEND {
            notFull: elem.state.notFull,
            notEmpty: elem.state.notEmpty,
            sendName: getGlobalStringLocalUID(tag) };
    end

    if (`CON_DEBUG_ENABLE != 0)
    begin
        let debugScan <- mkDebugScanNode(
           debugScanSoftConnections(integerToString(valueOf(n_ELEM))),
           dbg_scan_data);
    end

    return dbg_scan_data;
endmodule
