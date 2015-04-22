//
// Copyright (c) 2015, Intel Corporation
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

/**
 * @file rrr-debug.bsv
 * @author Kermin Fleming
 * @brief A debug wrapper for RRR.
 */

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services_deps.bsh"
`include "asim/provides/common_services.bsh"
`include "asim/provides/rrr.bsh"
`include "asim/provides/umf.bsh"
`include "asim/provides/rrr_common.bsh"

// 
// A generic debugger for RRR servers.  This implementation must be separated
// from the RRR debugger typeclass definition because it makes use of debug 
// scan.  Having them together causes cyclic type dependencies.
//

module [CONNECTED_MODULE] mkRRRServerDebugger#(RRR_SERVER_DEBUG server) (Empty);


    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil ; 
    dbg_list <- addDebugScanField(dbg_list, "demarshaller notEmpty", server.notEmpty());
    dbg_list <- addDebugScanField(dbg_list, "demarshaller state", server.demarshallerState());
    dbg_list <- addDebugScanField(dbg_list, "current function", server.methodID());
    dbg_list <- addDebugScanField(dbg_list, "misrouted packet", server.misroutedPacket());
    dbg_list <- addDebugScanField(dbg_list, "illegal method", server.illegalMethod());
    dbg_list <- addDebugScanField(dbg_list, "incorrect length", server.incorrectLength());
    
    let dbgNode <- mkDebugScanNode("RRR_SERVER_" + server.serviceName, dbg_list);
    
endmodule



