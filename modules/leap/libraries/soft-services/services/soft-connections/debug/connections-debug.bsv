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

import List::*;

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

//
// mkSoftConnectionDebugInfo --
//     Generate debug scan data for every soft connection FIFO.
//
module [CONNECTED_MODULE] mkSoftConnectionDebugInfo (Empty);
    List#(CONNECTION_DEBUG_INFO) info <- getConnectionDebugInfo();

    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;

    while (info matches tagged Nil ? False : True)
    begin
        let elem = List::head(info);

        // Allocate an integer tag for the name.
        GLOBAL_STRING_UID tag <- getGlobalStringUID(elem.sendName);

        dbg_list <- addDebugScanField(dbg_list,
                                      "",
                                      tuple3(elem.state.notFull,
                                             elem.state.notEmpty,
                                             getGlobalStringLocalUID(tag)));

        info = List::tail(info);
    end

    if (`CON_DEBUG_ENABLE != 0)
    begin
        mkDebugScanSoftConnections("", dbg_list);
    end
endmodule
