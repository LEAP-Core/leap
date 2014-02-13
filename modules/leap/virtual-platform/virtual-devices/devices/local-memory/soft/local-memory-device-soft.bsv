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

//
// Expose local memory as a set of soft connections, making it possible to
// operate on local memory without access to the low level platform interface.
//


`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/local_mem.bsh"


//
// Read and write requests are combined into a single control channel, making
// read/write order synchronization easy.  For SRAM or DRAM the control is
// merged anyway, so we give up no performance.
//
typedef union tagged
{
    LOCAL_MEM_ADDR LM_READ_WORD;
    LOCAL_MEM_ADDR LM_READ_LINE;

    LOCAL_MEM_ADDR LM_WRITE_WORD;
    LOCAL_MEM_ADDR LM_WRITE_LINE;

    LOCAL_MEM_ADDR LM_WRITE_WORD_MASKED;
    LOCAL_MEM_ADDR LM_WRITE_LINE_MASKED;
}
LOCAL_MEM_CMD
    deriving (Eq, Bits);

typedef union tagged
{
    LOCAL_MEM_WORD LM_READ_WORD_DATA;
    LOCAL_MEM_LINE LM_READ_LINE_DATA;
}
LOCAL_MEM_READ_DATA
    deriving (Eq, Bits);


module [CONNECTED_MODULE] mkLocalMemory#(LowLevelPlatformInterface llpi)
    // Interface:
    ();

    let localMem = llpi.localMem;

    //
    // Commands requesting memory operations.  Response only for loads.
    //
    CONNECTION_SERVER#(LOCAL_MEM_CMD, LOCAL_MEM_READ_DATA) lms
        <- mkConnectionServerOptional("local_memory_device");

    //
    // Write data side channel.  Word writes use the low bits of the line
    // value and index 0 of the mask.
    //
    CONNECTION_RECV#(Tuple2#(LOCAL_MEM_LINE, LOCAL_MEM_LINE_MASK)) lmWriteData
        <- mkConnectionRecvOptional("local_memory_device_wdata");

    DEBUG_FILE debugLog <- mkDebugFile("memory_local_device.out");

    //
    // readWordReq --
    //     Request word read.
    //
    rule readWordReq (lms.getReq() matches tagged LM_READ_WORD .addr);
        lms.deq();
        localMem.readWordReq(addr);

        debugLog.record($format("REQ read word addr=0x%x", addr));
    endrule

    //
    // readLineReq --
    //     Request line read.
    //
    rule readLineReq (lms.getReq() matches tagged LM_READ_LINE .addr);
        lms.deq();
        localMem.readLineReq(addr);

        debugLog.record($format("REQ read line addr=0x%x", addr));
    endrule

    //
    // readWordRsp --
    //     Forward word read data to the client.
    //
    rule readWordRsp (True);
        let val <- localMem.readWordRsp();
        lms.makeRsp(tagged LM_READ_WORD_DATA val);

        debugLog.record($format("RESP read word val=0x%x", val));
    endrule

    //
    // readLineRsp --
    //     Forward line read data to the client.
    //
    (* descending_urgency = "readLineRsp, readWordRsp" *)
    rule readLineRsp (True);
        let val <- localMem.readLineRsp();
        lms.makeRsp(tagged LM_READ_LINE_DATA val);

        debugLog.record($format("RESP read line val=0x%x", val));
    endrule

    //
    // writeWord --
    //     Write a word to local memory, combining separate receipt of address
    //     and data messages.
    //
    rule writeWord (lms.getReq() matches tagged LM_WRITE_WORD .addr);
        lms.deq();

        match {.val, .mask} = lmWriteData.receive();
        lmWriteData.deq();

        LOCAL_MEM_WORD w = truncate(val);
        localMem.writeWord(addr, w);

        debugLog.record($format("REQ write word addr=0x%x, val=0x%x", addr, w));
    endrule

    //
    // writeLine --
    //     Write a line to local memory, combining separate receipt of address
    //     and data messages.
    //
    rule writeLine (lms.getReq() matches tagged LM_WRITE_LINE .addr);
        lms.deq();

        match {.val, .mask} = lmWriteData.receive();
        lmWriteData.deq();

        localMem.writeLine(addr, val);

        debugLog.record($format("REQ write line addr=0x%x, val=0x%x", addr, val));
    endrule

    //
    // writeWordMasked --
    //     Write a masked word to local memory, combining separate receipt
    //     of address and data messages.
    //
    rule writeWordMasked (lms.getReq() matches tagged LM_WRITE_WORD_MASKED .addr);
        lms.deq();
        
        match {.val, .mask} = lmWriteData.receive();
        lmWriteData.deq();

        LOCAL_MEM_WORD w = truncate(val);
        localMem.writeWordMasked(addr, w, mask[0]);

        debugLog.record($format("REQ write word addr=0x%x, val=0x%x, mask=0x%x", addr, w, mask[0]));
    endrule

    //
    // writeLineMasked --
    //     Write a masked line to local memory, combining separate receipt
    //     of address and data messages.
    //
    rule writeLineMasked (lms.getReq() matches tagged LM_WRITE_LINE_MASKED .addr);
        lms.deq();
        
        match {.val, .mask} = lmWriteData.receive();
        lmWriteData.deq();

        localMem.writeLineMasked(addr, val, mask);

        debugLog.record($format("REQ write line addr=0x%x, val=0x%x, mask=0x%x", addr, val, mask));
    endrule


    // ====================================================================
    //
    // Debugging
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    dbg_list <- addDebugScanField(dbg_list, "Server REQ not empty", lms.reqNotEmpty);
    dbg_list <- addDebugScanField(dbg_list, "Server RSP not full", lms.rspNotFull);
    dbg_list <- addDebugScanField(dbg_list, "Server WRITE DATA not empty", lmWriteData.notEmpty);

    // Append set associative cache pipeline state
    List#(Tuple2#(String, Bool)) lm_scan = localMem.debugScanState();
    while (lm_scan matches tagged Nil ? False : True)
    begin
        let fld = List::head(lm_scan);
        dbg_list <- addDebugScanField(dbg_list, tpl_1(fld), tpl_2(fld));

        lm_scan = List::tail(lm_scan);
    end

    let dbgNode <- mkDebugScanNode("Local Memory (local-memory-device-soft.bsv)", dbg_list);
endmodule
