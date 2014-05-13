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

import List::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_deps.bsh"

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
