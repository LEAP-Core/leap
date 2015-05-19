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

import List::*;
import Vector::*;
import FIFOF::*;

`include "awb/provides/librl_bsv.bsh"
`include "asim/provides/soft_connections.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services_deps.bsh"
`include "asim/provides/debug_scan_service.bsh"
`include "asim/provides/stdio_service.bsh"
`include "asim/provides/rrr.bsh"
`include "asim/provides/umf.bsh"
`include "asim/provides/rrr_common.bsh"
`include "asim/provides/channelio.bsh"

//
// A helper function for dealing with wide packet headers. This
// function can be generalized and maybe added to the debug scan 
// library.
//

module mkWideDebugScanField#(String prefix, Tuple2#(Integer,Bit#(64)) fieldChunk) (DEBUG_SCAN_FIELD); 
    let f <- mkDebugScanField(prefix + integerToString(tpl_1(fieldChunk)), tpl_2(fieldChunk), False);
    return f;
endmodule

// 
// A generic debugger for RRR servers.  This implementation must be separated
// from the RRR debugger typeclass definition because it makes use of debug 
// scan.  Having them together causes cyclic type dependencies.
//

module [CONNECTED_MODULE] mkRRRServerDebugger#(RRR_SERVER_DEBUG server) (Empty);
    Reg#(Bool) error <- mkReg(False);
    Reg#(Bool) print <- mkReg(True);
    Reg#(Bool) illegalMethod   <- mkReg(False);
    Reg#(Bool) misroutedPacket <- mkReg(False);
    Reg#(Bool) incorrectLength <- mkReg(False);
    Reg#(Bit#(64)) lastPackets <- mkReg(0);
    Reg#(Bit#(64)) lastChunks  <- mkReg(0);
   
    // Build header debug using mapM.
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil; 
    dbg_list <- addDebugScanField(dbg_list, "demarshaller notEmpty", server.notEmpty());
    dbg_list <- addDebugScanField(dbg_list, "demarshaller state", server.demarshallerState());
    
    dbg_list <- addDebugScanField(dbg_list, "current method", server.methodID());
    dbg_list <- addDebugScanField(dbg_list, "current service", server.serviceID());
    dbg_list <- addDebugScanField(dbg_list, "misrouted packet", server.misroutedPacket());
    dbg_list <- addDebugScanField(dbg_list, "illegal method", server.illegalMethod());
    dbg_list <- addDebugScanField(dbg_list, "incorrect length", server.incorrectLength());
    dbg_list <- addDebugScanField(dbg_list, "total packets", server.totalPackets());
    dbg_list <- addDebugScanField(dbg_list, "total chunks", server.totalChunks());
    dbg_list <- addDebugScanField(dbg_list, "last packets", lastPackets());
    dbg_list <- addDebugScanField(dbg_list, "last chunks", lastChunks());
    
    TriggeredStreamCaptureFIFOF#(Tuple2#(Bool,Tuple3#(Bit#(64), Bit#(64), UMF_CHUNK))) chunkBuffer <- mkTriggeredStreamCaptureFIFOF(1024);
    FIFOF#(Tuple3#(Bit#(64), Bit#(64), UMF_CHUNK)) chunkBufferIntermediate <- mkSizedBRAMFIFOF(512);
    Reg#(Bit#(8)) dumpCountdown <- mkReg(maxBound);

    let dbgNode <- mkDebugScanNode("RRR_SERVER_" + server.serviceName, dbg_list);

    let seqError <- getGlobalStringUID("RRR_SERVER_" + server.serviceName +" ERROR: got seq number %d, expected %d at packet %llx\n");
    let chunkMsg <- getGlobalStringUID("RRR_SERVER_" + server.serviceName +" Chunk Dump: error %d packet %0llx chunk %0llx  %0llx  %0llx\n");


    STDIO#(Bit#(64)) stdio  <- mkStdIO();

    rule latchError(!error);
        lastPackets <= server.totalPackets();
        lastChunks <= server.totalChunks();
    endrule

    rule transferMethod(server.illegalMethod());
       illegalMethod <= True;
    endrule

    rule transferMisrouted(server.misroutedPacket());
       misroutedPacket <= True;
    endrule

    rule transferLength(server.incorrectLength());
       incorrectLength <= True;
    endrule

    rule setError(illegalMethod || misroutedPacket || incorrectLength);
        error <= True;
    endrule

    // Enabling channelio debug causes sequence numbers to be inserted.  Otherwise, they will not
    // be inserted.  
    `ifdef DEBUG_CHANNELIO
        if(DEBUG_CHANNELIO != 0)
        begin
            rule checkSeqNum(server.sequenceNumber != 1 + server.sequenceNumberLast && print && `DEBUG_CHANNELIO);
                print <= False;
                stdio.printf(seqError, list3(zeroExtend(server.sequenceNumber), zeroExtend(server.sequenceNumberLast), server.totalPackets()));        
            endrule
        end
    `endif

    // Code for dumping buffer of RRR data.
    rule enqChunk;
        chunkBufferIntermediate.enq(server.chunk());
    endrule

    rule forwardChunk;
        chunkBufferIntermediate.deq();
        chunkBuffer.fifof.enq(tuple2((!print || error),chunkBufferIntermediate.first()));
    endrule

    rule dumpChunk;
        Tuple3#(Bit#(64), Bit#(64), UMF_CHUNK) rrrData = chunkBufferIntermediate.first();
        $display("RRR_SERVER_" + server.serviceName + " Chunk Dump: error: %h packet %h chunk %h  %h  %h\n", (!print || error), 
                                     tpl_1(rrrData),
                                     tpl_2(rrrData),
                                     tpl_3(rrrData)[127:64],
                                     tpl_3(rrrData)[63:0]);
    endrule

    rule errorCountdown ((!print || error) && dumpCountdown!= 0);
        dumpCountdown <= dumpCountdown - 1;
    endrule

    rule triggerDump(dumpCountdown == 0);
        chunkBuffer.trigger();
    endrule

    rule printChunks;
        Tuple3#(Bit#(64), Bit#(64), UMF_CHUNK) rrrData = tpl_2(chunkBuffer.fifof.first);
        Bool errorFlag = tpl_1(chunkBuffer.fifof.first);
        stdio.printf(chunkMsg, list5(zeroExtend(pack(errorFlag)),
                                     tpl_1(rrrData), 
                                     tpl_2(rrrData), 
                                     tpl_3(rrrData)[127:64], 
                                     tpl_3(rrrData)[63:0]));
        chunkBuffer.fifof.deq;
    endrule 

endmodule



