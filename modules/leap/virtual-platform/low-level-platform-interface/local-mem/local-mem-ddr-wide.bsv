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
import List::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/ddr_sdram_device.bsh"


//
// mkLocalMem --
//   Implement local memory using DDR memory.  The DDR memory has line sizes
//   large enough to hold a single local memory line.
//
module mkLocalMem#(PHYSICAL_DRIVERS drivers)
    // interface:
    (LOCAL_MEM)
    provisos (Add#(a_, LOCAL_MEM_LINE_SZ, DDR_BURST_DATA_SZ),
              // Number of local memory lines in a DDR memory burst
              NumAlias#(n_LOCAL_MEM_LINES_PER_BURST, TDiv#(DDR_BURST_DATA_SZ,
                                                           LOCAL_MEM_LINE_SZ)),
              // Index of a local memory line within a DDR memory burst
              Alias#(t_LOCAL_MEM_LINE_IDX, Bit#(TLog#(n_LOCAL_MEM_LINES_PER_BURST))),
              // Vector mapping of local memory lines to a DDR memory burst
              Alias#(t_LOCAL_MEM_LINES, Vector#(n_LOCAL_MEM_LINES_PER_BURST,
                                                LOCAL_MEM_LINE)),
              // Vector mapping of local memory write masks to a DDR memory burst
              Alias#(t_LOCAL_MEM_MASKS, Vector#(n_LOCAL_MEM_LINES_PER_BURST,
                                                LOCAL_MEM_LINE_MASK)));

    checkDDRMemSizesValid();

    DEBUG_FILE debugLog <- mkDebugFile("memory_local_mem_ddr_wide.out");

    // Merge read and write requests into a single FIFO to preserve order.
    // The DDR controller does this anyway, so we lose no performance.
    MERGE_FIFOF#(2, LOCAL_MEM_REQ) mergeReqQ <- mkMergeBypassFIFOF();
    FIFOF#(Tuple2#(LOCAL_MEM_LINE, LOCAL_MEM_LINE_MASK)) writeDataQ <- mkBypassFIFOF();

    FIFOF#(LOCAL_MEM_LINE) lineResponseQ <- mkBypassFIFOF();
    FIFOF#(LOCAL_MEM_WORD) wordResponseQ <- mkBypassFIFOF();

    // Get a handle to the DDR DRAM Controller
    Vector#(FPGA_DDR_BANKS, DDR_DRIVER) dramDriver = drivers.ddrDriver;

    //
    // ddrAddrComponents --
    //   Compute the bank and address in DDR memory space of the DDR memory
    //   burst containing the local memory address.  Also compute the index
    //   of the local memory line within the DDR memory burst.
    //
    function Tuple3#(FPGA_DDR_ADDRESS,
                     DDR_BANK_IDX,
                     t_LOCAL_MEM_LINE_IDX) ddrAddrComponents(LOCAL_MEM_ADDR localAddr);
        // Get the address of the local memory line
        let local_line_addr = localMemLineAddr(localAddr);
    
        // The local memory address maps to a DDR address, a DDR bank and the
        // index of the local memory line within a DDR burst.
        Tuple3#(DDR_BURST_ADDRESS, DDR_BANK_IDX, t_LOCAL_MEM_LINE_IDX) ddr_addr_comp =
            unpack(local_line_addr);

        // Convert burst-aligned address to a full FPGA word address
        DDR_BURST_WORD_IDX w_idx = 0;
        FPGA_DDR_ADDRESS ddr_addr = {tpl_1(ddr_addr_comp), w_idx};

        return tuple3(ddr_addr, tpl_2(ddr_addr_comp), tpl_3(ddr_addr_comp));
    endfunction

    function FPGA_DDR_ADDRESS ddrAddr(LOCAL_MEM_ADDR addr) =
        tpl_1(ddrAddrComponents(addr));

    function DDR_BANK_IDX ddrBank(LOCAL_MEM_ADDR addr) =
        tpl_2(ddrAddrComponents(addr));

    function t_LOCAL_MEM_LINE_IDX ddrBurstIdx(LOCAL_MEM_ADDR addr) =
        tpl_3(ddrAddrComponents(addr));


    //
    // Process read requests
    //

    FIFOF#(Tuple2#(Bool, LOCAL_MEM_REQ)) activeReadQ <-
        mkSizedFIFOF(valueOf(TMul#(FPGA_DDR_BANKS, FPGA_DDR_MAX_OUTSTANDING_READS)));

    Reg#(Maybe#(Tuple2#(DDR_BANK_IDX, FPGA_DDR_ADDRESS))) lastReadAddr <-
        mkReg(tagged Invalid);

    rule startRead (mergeReqQ.firstPortID == 0);
        LOCAL_MEM_ADDR addr = case (mergeReqQ.first()) matches
                                  tagged MEM_REQ_LINE .a: a;
                                  tagged MEM_REQ_WORD .a: a;
                              endcase;
        mergeReqQ.deq();

        // Convert local memory address space to DDR memory address and bank
        let ddr_addr = ddrAddr(addr);
        let bank = ddrBank(addr);

        debugLog.record($format("Read Req addr=0x%h: bank=%0d, ddr_addr=0x%h", addr, bank, ddr_addr));

        // Request the read
        if (lastReadAddr matches tagged Valid {.last_bank, .last_ddr_addr} &&&
            last_bank == bank &&&
            last_ddr_addr == ddr_addr)
        begin
            // Last read was the same DDR memory line.  Reuse the response.
            activeReadQ.enq(tuple2(True, mergeReqQ.first));
        end
        else
        begin
            // Different address than last read.  Load the memory.
            dramDriver[bank].readReq(ddr_addr);
            activeReadQ.enq(tuple2(False, mergeReqQ.first));
        end

        // Remember the read address in case it is requested again as the
        // next read.
        lastReadAddr <= tagged Valid tuple2(bank, ddr_addr);
    endrule


    Reg#(Bit#(TLog#(FPGA_DDR_BURST_LENGTH))) readBeatIdx <- mkReg(0);
    Reg#(Vector#(FPGA_DDR_BURST_LENGTH, FPGA_DDR_DUALEDGE_BEAT)) readBeats <-
        mkRegU();

    function Bool isRepeatRead = tpl_1(activeReadQ.first);

    //
    // processReadBeats --
    //   Normal read flow.  Collect response beats from the DDR memory until
    //   a full line arrives.
    //
    rule processReadBeats (! isRepeatRead());
        let req = tpl_2(activeReadQ.first());

        LOCAL_MEM_ADDR addr =
            case (req) matches
                tagged MEM_REQ_LINE .a: a;
                tagged MEM_REQ_WORD .a: a;
            endcase;

        // Word sized read?
        Maybe#(LOCAL_MEM_WORD_IDX) w_idx =
            case (req) matches
                tagged MEM_REQ_LINE .a: tagged Invalid;
                tagged MEM_REQ_WORD .a: tagged Valid localMemWordIdx(a);
            endcase;

        // Retrieve a beat
        let bank = ddrBank(addr);
        let beat <- dramDriver[bank].readRsp();
        let line_val = shiftInAtN(readBeats, beat);
        readBeats <= line_val;

        debugLog.record($format("Read addr=0x%h: bank=%0d, beat=%0d, val=0x%h", addr, bank, readBeatIdx, beat));

        // All done?  Count beats.  This code depends on the number of beats
        // in a read being a power of 2.
        if (readBeatIdx == maxBound)
        begin
            // Last beat in read
            activeReadQ.deq();

            // Convert the DDR multi-beat response into a collection of local
            // memory lines.
            t_LOCAL_MEM_LINES ddr_burst = unpack(pack(line_val));

            // Select the desired local memory line from the response
            let idx = ddrBurstIdx(addr);
            LOCAL_MEM_LINE line_data = ddr_burst[idx];

            if (w_idx matches tagged Valid .w)
            begin
                // Select the desired word from the local memory line
                Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD) words = unpack(line_data);
                wordResponseQ.enq(words[w]);
                debugLog.record($format("Read word addr=0x%h: resp=0x%h", addr, words[w]));
            end
            else
            begin
                lineResponseQ.enq(line_data);
                debugLog.record($format("Read line addr=0x%h: resp=0x%h", addr, line_data));
            end
        end

        readBeatIdx <= readBeatIdx + 1;
    endrule

    //
    // processRepeatRead --
    //   Handle a read requested from the same DDR memory line as the previous
    //   read.  Use the local line buffer collected from the last read.
    //
    rule processRepeatRead (isRepeatRead());
        let req = tpl_2(activeReadQ.first());

        LOCAL_MEM_ADDR addr =
            case (req) matches
                tagged MEM_REQ_LINE .a: a;
                tagged MEM_REQ_WORD .a: a;
            endcase;

        // Word sized read?
        Maybe#(LOCAL_MEM_WORD_IDX) w_idx =
            case (req) matches
                tagged MEM_REQ_LINE .a: tagged Invalid;
                tagged MEM_REQ_WORD .a: tagged Valid localMemWordIdx(a);
            endcase;

        activeReadQ.deq();

        // Convert the DDR multi-beat response into a collection of local
        // memory lines.
        t_LOCAL_MEM_LINES ddr_burst = unpack(pack(readBeats));

        // Select the desired local memory line from the response
        let idx = ddrBurstIdx(addr);
        LOCAL_MEM_LINE line_data = ddr_burst[idx];

        if (w_idx matches tagged Valid .w)
        begin
            // Select the desired word from the local memory line
            Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD) words = unpack(line_data);
            wordResponseQ.enq(words[w]);
            debugLog.record($format("Read word (hit) addr=0x%h: resp=0x%h", addr, words[w]));
        end
        else
        begin
            lineResponseQ.enq(line_data);
            debugLog.record($format("Read line (hit) addr=0x%h: resp=0x%h", addr, line_data));
        end
    endrule


    //
    // Process write requests.  Only line-sized writes are implemented because
    // the word write methods convert their requests to masked line writes.
    //

    Vector#(FPGA_DDR_BANKS,
            FIFO#(Tuple2#(t_LOCAL_MEM_LINES,
                          t_LOCAL_MEM_MASKS))) burstWriteQ <- replicateM(mkLFIFO());

    rule startWriteLine (mergeReqQ.firstPortID == 1 &&&
                         mergeReqQ.first() matches tagged MEM_REQ_LINE .addr);
        mergeReqQ.deq();

        // Convert local memory address space to DDR memory address and bank
        let ddr_addr = ddrAddr(addr);
        let bank = ddrBank(addr);

        // Request the write
        dramDriver[bank].writeReq(ddr_addr);

        // Construct the full data burst.  If the burst is larger than a local
        // memory line we simply replicate the line through the burst.  The
        // masks, computed below, will cause the correct portion to be written.
        let idx = ddrBurstIdx(addr);
        t_LOCAL_MEM_LINES ddr_burst = replicate(tpl_1(writeDataQ.first()));

        // Mask of bytes to write, active high
        t_LOCAL_MEM_MASKS ddr_masks = unpack(0);
        ddr_masks[idx] = tpl_2(writeDataQ.first());

        debugLog.record($format("Write line addr=0x%h: bank=%0d, ddr_addr=0x%h, val=0x%h, mask_high=0x%h", addr, bank, ddr_addr, ddr_burst, ddr_masks));

        // Forward write data to the DDR controller
        burstWriteQ[bank].enq(tuple2(ddr_burst, ddr_masks));
        writeDataQ.deq();

        // Invalidate the last read line cache if the write is to the same
        // address.
        if (lastReadAddr matches tagged Valid {.read_bank, .read_ddr_addr} &&&
            read_bank == bank &&&
            read_ddr_addr == ddr_addr)
        begin
            lastReadAddr <= tagged Invalid;
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
                debugLog.record($format("Write line done"));
            end

            writeBeatIdx[bank] <= beat_idx + 1;
        endrule
    end


    // ====================================================================
    //
    // Debug
    //
    // ====================================================================

    //
    // Soft connections for a debug scan node are not allowed in the platform.
    // Export debug scan state.  A node will be created by the local memory
    // platform interface.
    //
    List#(Tuple2#(String, Bool)) ds_data = List::nil;
    ds_data = List::cons(tuple2("LM DDR Wide mergeReqQ not empty", mergeReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("LM DDR Wide mergeReqQ not full", mergeReqQ.ports[0].notFull), ds_data);
    ds_data = List::cons(tuple2("LM DDR Wide writeDataQ not empty", writeDataQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("LM DDR Wide writeDataQ not full", writeDataQ.notFull), ds_data);
    ds_data = List::cons(tuple2("LM DDR Wide activeReadQ not empty", activeReadQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("LM DDR Wide activeReadQ not full", activeReadQ.notFull), ds_data);
    ds_data = List::cons(tuple2("LM DDR Wide lineResponseQ not full", lineResponseQ.notFull), ds_data);
    ds_data = List::cons(tuple2("LM DDR Wide wordResponseQ not full", wordResponseQ.notFull), ds_data);

    // Collect debug scan state for physical memory controllers
    for (Integer b = 0; b < valueOf(FPGA_DDR_BANKS); b = b + 1)
    begin
        ds_data = List::append(ds_data, dramDriver[b].debugScanState());
    end

    let debugScanData = ds_data;


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
        // Convert word write to a masked line write
        let w_idx = localMemWordIdx(addr);
    
        // Replicate the word and let the mask sort it out
        Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD) line_data = replicate(data);

        // Mask just the requested word
        LOCAL_MEM_LINE_MASK line_mask = replicate(replicate(False));
        line_mask[w_idx] = replicate(True);

        mergeReqQ.ports[1].enq(tagged MEM_REQ_LINE addr);
        writeDataQ.enq(tuple2(pack(line_data), line_mask));
    endmethod

    method Action writeLine(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data);
        mergeReqQ.ports[1].enq(tagged MEM_REQ_LINE addr);
        // Pass on data and mask indicating write everything
        writeDataQ.enq(tuple2(data, unpack(~0)));
    endmethod

    method Action writeWordMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data, LOCAL_MEM_WORD_MASK mask);
        // Convert word write to a masked line write
        let w_idx = localMemWordIdx(addr);
    
        // Replicate the word and let the mask sort it out
        Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD) line_data = replicate(data);

        // Mask just the requested word
        LOCAL_MEM_LINE_MASK line_mask = replicate(replicate(False));
        line_mask[w_idx] = mask;

        mergeReqQ.ports[1].enq(tagged MEM_REQ_LINE addr);
        writeDataQ.enq(tuple2(pack(line_data), line_mask));
    endmethod

    method Action writeLineMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data, LOCAL_MEM_LINE_MASK mask);
        mergeReqQ.ports[1].enq(tagged MEM_REQ_LINE addr);
        writeDataQ.enq(tuple2(data, mask));
    endmethod

    method List#(Tuple2#(String, Bool)) debugScanState();
        return debugScanData;
    endmethod
endmodule
