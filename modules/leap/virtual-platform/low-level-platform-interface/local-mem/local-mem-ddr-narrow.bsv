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

// ========================================================================
//
// Local memory using DDR memory driver.
//
// This code provides an abstraction layer for memory, presenting arbitrary
// physical memory topology as though it were fundamentally the line and
// word sizes specified here.  The code maps address spaces, including
// seamless management of multiple physical banks.  It also converts multi-
// beat physical memory "bursts" into single beat local memory requests
// and responses.
//
//                            * * * * * * * * * * *
//
//      WARNING          WARNING                 WARNING          WARNING
//
//   If you get an error compiling this module you might have chosen the
//   wrong version.  The "wide" variant is for use when the DDR burst size
//   is large enough to hold at least one local memory line.  The "narrow"
//   variant should be used when the DDR burst size is smaller than the
//   local memory line size.  In that case, multiple bursts must be
//   combined to form a line.
//
//                            * * * * * * * * * * *
//
// ========================================================================

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/debug_scan_service.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/ddr_sdram_device.bsh"


//
// mkLocalMem --
//   Implement local memory using DDR memory.
//
//   This module handles the case in which a local memory line is larger than
//   a burst from the DDR memory.  Multiple DDR bursts are combined to form
//   a local memory line.
//
module [CONNECTED_MODULE] mkLocalMem
    // interface:
    (LOCAL_MEM)
    provisos (Add#(a_, DDR_BURST_DATA_SZ, LOCAL_MEM_LINE_SZ),
              // Number of DDR memory bursts in a local memory line
              NumAlias#(n_BURSTS_PER_LOCAL_MEM_LINE, TDiv#(LOCAL_MEM_LINE_SZ,
                                                           DDR_BURST_DATA_SZ)),
              // Index of a DDR memory burst within a local memory line
              Alias#(t_DDR_BURST_IDX, Bit#(TLog#(n_BURSTS_PER_LOCAL_MEM_LINE))),
              Bits#(t_DDR_BURST_IDX, t_DDR_BURST_IDX_SZ),
              // Vector mapping of DDR memory bursts to a local memory line
              Alias#(t_DDR_BURSTS, Vector#(n_BURSTS_PER_LOCAL_MEM_LINE,
                                           DDR_BURST_DATA)),
              // Vector mapping of DDR memory write masks to a local memory line mask
              Alias#(t_DDR_BURSTS_MASK, Vector#(n_BURSTS_PER_LOCAL_MEM_LINE,
                                                Bit#(TMul#(FPGA_DDR_BYTES_PER_BEAT,
                                                           FPGA_DDR_BURST_LENGTH)))),
              // Number of DDR memory words per burst
              NumAlias#(n_DDR_WORDS_PER_BURST, TMul#(FPGA_DDR_WORDS_PER_BEAT,
                                                     FPGA_DDR_BURST_LENGTH)),
              // Number of local memory words per DDR burst
              NumAlias#(n_LOCAL_MEM_WORDS_PER_BURST, TDiv#(DDR_BURST_DATA_SZ,
                                                           LOCAL_MEM_WORD_SZ)));

    checkDDRMemSizesValid();

    if (valueOf(LOCAL_MEM_WORD_SZ) > valueOf(DDR_BURST_DATA_SZ))
        errorM("LOCAL_MEM_WORD must be no bigger than one DDR memory burst.");

    DEBUG_FILE debugLog <- mkDebugFile("memory_local_mem_ddr_narrow.out");

    // Merge read and write requests into a single FIFO to preserve order.
    // The DDR controller does this anyway, so we lose no performance.
    MERGE_FIFOF#(2, LOCAL_MEM_REQ) mergeReqQ <- mkMergeBypassFIFOF();

    FIFOF#(Tuple2#(LOCAL_MEM_LINE, LOCAL_MEM_LINE_MASK)) writeDataQ <- mkFIFOF();
    FIFOF#(Tuple2#(LOCAL_MEM_WORD, LOCAL_MEM_WORD_MASK)) writeWordDataQ <- mkFIFOF();

    FIFOF#(LOCAL_MEM_LINE) lineResponseQ <- mkBypassFIFOF();
    FIFOF#(LOCAL_MEM_WORD) wordResponseQ <- mkBypassFIFOF();

    // Get a handle to the DDR DRAM Controller
    LOCAL_MEM_DDR dramDriver <- mkLocalMemDDRConnection();

    //
    // ddrAddrComponents --
    //   Compute the bank and address in DDR memory space of the DDR memory
    //   burst containing the local memory address.
    //
    function Tuple2#(FPGA_DDR_ADDRESS,
                     DDR_BANK_IDX) ddrAddrComponents(LOCAL_MEM_ADDR localAddr)
        provisos (Alias#(t_DDR_ALIGNED_BURST_ADDRESS, Bit#(TSub#(DDR_BURST_ADDRESS_SZ,
                                                                 t_DDR_BURST_IDX_SZ))));
        // Get the address of the local memory line
        let local_line_addr = localMemLineAddr(localAddr);
    
        // The local memory address maps to a DDR address and bank.
        Tuple2#(t_DDR_ALIGNED_BURST_ADDRESS, DDR_BANK_IDX) ddr_addr_comp =
            unpack(local_line_addr);

        // Pad the multi-burst-aligned address to a burst address within the bank.
        t_DDR_BURST_IDX b_idx = 0;
        DDR_BURST_ADDRESS burst_addr = {tpl_1(ddr_addr_comp), b_idx};

        // Convert burst-aligned address to a full FPGA word address
        DDR_BURST_WORD_IDX w_idx = 0;
        FPGA_DDR_ADDRESS ddr_addr = {burst_addr, w_idx};

        return tuple2(ddr_addr, tpl_2(ddr_addr_comp));
    endfunction

    function FPGA_DDR_ADDRESS ddrAddr(LOCAL_MEM_ADDR addr) =
        tpl_1(ddrAddrComponents(addr));

    function DDR_BANK_IDX ddrBank(LOCAL_MEM_ADDR addr) =
        tpl_2(ddrAddrComponents(addr));


    //
    // ddrWordAddrComponents --
    //   Compute the DDR memory space address of a local memory word and
    //   the index of the local memory word among local memory words in
    //   the burst.
    //
    function Tuple2#(FPGA_DDR_ADDRESS,
                     Bit#(TLog#(n_LOCAL_MEM_WORDS_PER_BURST)))
        ddrWordAddrComponents(LOCAL_MEM_ADDR localAddr);

        // Get the index of the word within the local memory line
        let local_word_idx = localMemWordIdx(localAddr);

        // Map the index into a burst and word within the burst
        Tuple2#(t_DDR_BURST_IDX, Bit#(TLog#(n_LOCAL_MEM_WORDS_PER_BURST)))
            offset_comp = unpack(local_word_idx);

        // Get the DDR address of the start of the local memory line
        let ddr_addr = ddrAddr(localAddr);
        // Add the burst offset
        ddr_addr = ddr_addr + zeroExtend(tpl_1(offset_comp)) *
                              fromInteger(valueOf(n_DDR_WORDS_PER_BURST));

        return tuple2(ddr_addr, tpl_2(offset_comp));
    endfunction

    function FPGA_DDR_ADDRESS ddrAddrForWord(LOCAL_MEM_ADDR addr) =
        tpl_1(ddrWordAddrComponents(addr));

    function Bit#(TLog#(n_LOCAL_MEM_WORDS_PER_BURST)) wordBurstIdx(LOCAL_MEM_ADDR addr) =
        tpl_2(ddrWordAddrComponents(addr));


    //
    // Process read requests
    //

    FIFOF#(Tuple2#(Bool, LOCAL_MEM_REQ)) activeReadQ <-
        mkSizedFIFOF(valueOf(TMul#(FPGA_DDR_BANKS, FPGA_DDR_MAX_OUTSTANDING_READS)));

    Reg#(t_DDR_BURST_IDX) readBurstIdx <- mkReg(0);

    rule startReadLine (mergeReqQ.firstPortID == 0 &&&
                        mergeReqQ.first matches tagged MEM_REQ_LINE .addr);
        // Convert local memory address space to DDR memory address and bank
        let ddr_addr = ddrAddr(addr);
        let bank = ddrBank(addr);

        // Add the burst offset
        ddr_addr = ddr_addr + zeroExtend(readBurstIdx) *
                              fromInteger(valueOf(n_DDR_WORDS_PER_BURST));

        debugLog.record($format("Read Req addr=0x%h: bank=%0d, ddr_addr=0x%h (burst=%0d)", addr, bank, ddr_addr, readBurstIdx));

        //
        // Update the multi-burst counter.  The number of bursts in a local
        // memory line has already been proven to be a power of two by
        // checkDDRMemSizesValid().
        //
        // The request is popped from the incoming queue only after all
        // bursts have been requested.
        //
        Bool last_burst = (readBurstIdx == maxBound);
        if (last_burst)
        begin
            // Done with request
            mergeReqQ.deq();
        end

        readBurstIdx <= readBurstIdx + 1;

        // Request the read
        dramDriver[bank].readReq(ddr_addr);
        activeReadQ.enq(tuple2(last_burst, mergeReqQ.first));
    endrule


    //
    // startReadWord --
    //   Reading a word is much like reading a line except that the local
    //   memory word is known to fit in one DDR memory burst (a requirement).
    //
    rule startReadWord (mergeReqQ.firstPortID == 0 &&&
                        mergeReqQ.first matches tagged MEM_REQ_WORD .addr);
        mergeReqQ.deq();

        // Convert local memory address space to DDR memory address and bank
        let ddr_addr = ddrAddrForWord(addr);
        let bank = ddrBank(addr);

        debugLog.record($format("Read Req addr=0x%h: bank=%0d, ddr_addr=0x%h", addr, bank, ddr_addr));

        // Request the read
        dramDriver[bank].readReq(ddr_addr);
        activeReadQ.enq(tuple2(True, mergeReqQ.first));
    endrule


    // Count incoming beats within one burst
    Reg#(Bit#(TLog#(FPGA_DDR_BURST_LENGTH))) readBeatIdx <- mkReg(0);
    // Vector of all beats in a local memory line
    Reg#(Vector#(TMul#(n_BURSTS_PER_LOCAL_MEM_LINE,
                       FPGA_DDR_BURST_LENGTH),
                 FPGA_DDR_DUALEDGE_BEAT)) readLineBeats <- mkRegU();

    //
    // processReadLineBeats --
    //   Normal read flow.  Collect response beats from the DDR memory until
    //   a full line arrives.
    //
    rule processReadLineBeats (tpl_2(activeReadQ.first()) matches tagged MEM_REQ_LINE .addr);
        let is_last_burst = tpl_1(activeReadQ.first());

        // Retrieve a beat
        let bank = ddrBank(addr);
        let beat <- dramDriver[bank].readRsp();
        let line_val = shiftInAtN(readLineBeats, beat);
        readLineBeats <= line_val;

        debugLog.record($format("Read addr=0x%h: bank=%0d, beat=%0d, val=0x%h", addr, bank, readBeatIdx, beat));

        // All done?  Count beats.  This code depends on the number of beats
        // in a read being a power of 2.
        if (readBeatIdx == maxBound)
        begin
            // Last beat in read
            activeReadQ.deq();

            // Is this the last burst for the read?
            if (is_last_burst)
            begin
                // Convert the DDR multi-beat response into a local memory line.
                LOCAL_MEM_LINE line_data = unpack(pack(line_val));
                lineResponseQ.enq(line_data);
                debugLog.record($format("Read line addr=0x%h: resp=0x%h", addr, line_data));
            end
        end

        readBeatIdx <= readBeatIdx + 1;
    endrule


    // Vector of all beats in a local memory word
    Reg#(Vector#(FPGA_DDR_BURST_LENGTH,
                 FPGA_DDR_DUALEDGE_BEAT)) readWordBeats <- mkRegU();

    //
    // processReadWordBeats --
    //     Collect beats for one DDR memory burst and return the local memory
    //     word.
    //
    rule processReadWordBeats (tpl_2(activeReadQ.first()) matches tagged MEM_REQ_WORD .addr);
        // Retrieve a beat
        let bank = ddrBank(addr);
        let beat <- dramDriver[bank].readRsp();
        let burst_val = shiftInAtN(readWordBeats, beat);
        readWordBeats <= burst_val;

        debugLog.record($format("Read addr=0x%h: bank=%0d, beat=%0d, val=0x%h", addr, bank, readBeatIdx, beat));

        // All done?  Count beats.  This code depends on the number of beats
        // in a read being a power of 2.
        if (readBeatIdx == maxBound)
        begin
            // Last beat in read
            activeReadQ.deq();

            // Convert the DDR multi-beat response into a set of local
            // memory words.
            Vector#(n_LOCAL_MEM_WORDS_PER_BURST, LOCAL_MEM_WORD) burst_data =
                unpack(pack(burst_val));
            // Pick the requested word
            LOCAL_MEM_WORD word_data = burst_data[wordBurstIdx(addr)];

            wordResponseQ.enq(word_data);
            debugLog.record($format("Read word addr=0x%h: resp=0x%h", addr, word_data));
        end

        readBeatIdx <= readBeatIdx + 1;
    endrule


    //
    // Process write requests.  Only line-sized writes are implemented because
    // the word write methods convert their requests to masked line writes.
    //

    Vector#(FPGA_DDR_BANKS,
            FIFO#(Tuple2#(Vector#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_DUALEDGE_BEAT),
                          Vector#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_DUALEDGE_BEAT_MASK))))
        burstWriteQ <- replicateM(mkBypassFIFO());

    Reg#(t_DDR_BURST_IDX) writeBurstIdx <- mkReg(0);

    rule startWriteLine (mergeReqQ.firstPortID == 1 &&&
                         mergeReqQ.first() matches tagged MEM_REQ_LINE .addr);
        // Convert local memory address space to DDR memory address and bank
        let ddr_addr = ddrAddr(addr);
        let bank = ddrBank(addr);

        // Add the burst offset
        ddr_addr = ddr_addr + zeroExtend(writeBurstIdx) *
                              fromInteger(valueOf(n_DDR_WORDS_PER_BURST));

        // Forward one DDR memory-sized burst from the local line
        t_DDR_BURSTS ddr_bursts = unpack(pack(tpl_1(writeDataQ.first())));
        t_DDR_BURSTS_MASK ddr_bursts_mask = unpack(pack(tpl_2(writeDataQ.first())));

        let burst_data = ddr_bursts[writeBurstIdx];
        let burst_mask = ddr_bursts_mask[writeBurstIdx];

        debugLog.record($format("Write line addr=0x%h: bank=%0d, ddr_addr=0x%h (burst=%0d), val=0x%h, mask_high=0x%h", addr, bank, ddr_addr, writeBurstIdx, burst_data, burst_mask));

        Bool last_burst = (writeBurstIdx == maxBound);
        if (last_burst)
        begin
            // Done with request
            mergeReqQ.deq();
            writeDataQ.deq();
        end

        writeBurstIdx <= writeBurstIdx + 1;

        // Request the write (unless the mask disables all writes)
        if (burst_mask != 0)
        begin
            dramDriver[bank].writeReq(ddr_addr);
            burstWriteQ[bank].enq(tuple2(unpack(burst_data), unpack(burst_mask)));
        end
    endrule

    //
    // startWriteWord --
    //   Writing a word requires only writing one burst.
    //
    rule startWriteWord (mergeReqQ.firstPortID == 1 &&&
                         mergeReqQ.first() matches tagged MEM_REQ_WORD .addr);
        // Convert local memory address space to DDR memory address and bank
        let ddr_addr = ddrAddrForWord(addr);
        let bank = ddrBank(addr);

        // Generate a burst-sized vector of local memory words
        Vector#(n_LOCAL_MEM_WORDS_PER_BURST, LOCAL_MEM_WORD) burst_data =
            replicate(tpl_1(writeWordDataQ.first()));
        // Mask only the appropriate word    
        Vector#(n_LOCAL_MEM_WORDS_PER_BURST, LOCAL_MEM_WORD_MASK) burst_mask =
            unpack(0);
        burst_mask[wordBurstIdx(addr)] = tpl_2(writeWordDataQ.first());

        debugLog.record($format("Write line addr=0x%h: bank=%0d, ddr_addr=0x%h (burst=%0d), val=0x%h, mask_high=0x%h", addr, bank, ddr_addr, writeBurstIdx, burst_data, burst_mask));

        mergeReqQ.deq();
        writeWordDataQ.deq();

        // Request the write (unless the mask disables all writes)
        if (pack(burst_mask) != 0)
        begin
            dramDriver[bank].writeReq(ddr_addr);
            burstWriteQ[bank].enq(tuple2(unpack(pack(burst_data)),
                                         unpack(pack(burst_mask))));
        end
    endrule


    //
    // Forward write data to the memory
    //

    // Count outbound beats for each data queue
    Vector#(FPGA_DDR_BANKS,
            Reg#(Bit#(TLog#(FPGA_DDR_BURST_LENGTH)))) writeBeatIdx <-
        replicateM(mkReg(0));

    // There is a separate queue for each bank
    for (Integer bank = 0; bank < valueOf(FPGA_DDR_BANKS); bank = bank + 1)
    begin
        rule fwdWriteData (True);
            let beat_idx = writeBeatIdx[bank];

            // Data and mask for the full multi-beat write
            match {.data, .mask} = burstWriteQ[bank].first();

            // Map the data and mask to a vector of beats in order to pick
            // the values for the current beat.
            Vector#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_DUALEDGE_BEAT) beats =
                unpack(pack(data));
            Vector#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_DUALEDGE_BEAT_MASK) beat_masks =
                unpack(pack(mask));

            // The mask in local memory is active high.  The DDR controller is
            // also byte-sized masks, but active low.  Invert the masks.
            beat_masks = unpack(~pack(beat_masks));

            debugLog.record($format("Write bank=%0d, beat=%0d, val=0x%h, mask_low=0x%h", bank, beat_idx, beats[beat_idx], beat_masks[beat_idx]));

            dramDriver[bank].writeData(beats[beat_idx],
                                       beat_masks[beat_idx]);

            // Count beats.  This code depends on the number of beats in
            // a write being a power of 2.
            if (beat_idx == maxBound)
            begin
                // Last beat in write
                burstWriteQ[bank].deq();
            end

            writeBeatIdx[bank] <= beat_idx + 1;
        endrule
    end


    // ====================================================================
    //
    // Debug
    //
    // ====================================================================

    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    dbg_list <- addDebugScanField(dbg_list, "LM DDR Wide mergeReqQ not empty", mergeReqQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "LM DDR Wide writeDataQ not empty", writeDataQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "LM DDR Wide writeWordDataQ not empty", writeWordDataQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "LM DDR Wide activeReadQ not empty", activeReadQ.notEmpty);
    dbg_list <- addDebugScanField(dbg_list, "LM DDR Wide activeReadQ not full", activeReadQ.notFull);
    dbg_list <- addDebugScanField(dbg_list, "LM DDR Wide lineResponseQ not full", lineResponseQ.notFull);
    dbg_list <- addDebugScanField(dbg_list, "LM DDR Wide wordResponseQ not full", wordResponseQ.notFull);

    let dbgNode <- mkDebugScanNode("Local Memory (local-mem-ddr-wide.bsv)", dbg_list);


    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    //
    // Read and write request methods are predicated
    // to ensure synchronization with writes.
    //

    method Action readWordReq(LOCAL_MEM_ADDR addr);
        mergeReqQ.ports[0].enq(tagged MEM_REQ_WORD addr);
    endmethod

    method ActionValue#(LOCAL_MEM_WORD) readWordRsp();
        wordResponseQ.deq();
        return wordResponseQ.first();
    endmethod


    method Action readLineReq(LOCAL_MEM_ADDR addr);
        mergeReqQ.ports[0].enq(tagged MEM_REQ_LINE addr);
    endmethod

    method ActionValue#(LOCAL_MEM_LINE) readLineRsp();
        lineResponseQ.deq();
        return lineResponseQ.first();
    endmethod


    method Action writeWord(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data);
        mergeReqQ.ports[1].enq(tagged MEM_REQ_WORD addr);
        // Pass on data and mask indicating write everything
        writeWordDataQ.enq(tuple2(data, unpack(~0)));
    endmethod

    method Action writeLine(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data);
        mergeReqQ.ports[1].enq(tagged MEM_REQ_LINE addr);
        // Pass on data and mask indicating write everything
        writeDataQ.enq(tuple2(data, unpack(~0)));
    endmethod

    method Action writeWordMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data, LOCAL_MEM_WORD_MASK mask);
        mergeReqQ.ports[1].enq(tagged MEM_REQ_WORD addr);
        writeWordDataQ.enq(tuple2(data, mask));
    endmethod

    method Action writeLineMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data, LOCAL_MEM_LINE_MASK mask);
        mergeReqQ.ports[1].enq(tagged MEM_REQ_LINE addr);
        writeDataQ.enq(tuple2(data, mask));
    endmethod

endmodule
