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

import FIFOF::*;


//
// Miscellaneous memory modules.
//

//
// mkSlowMemory --
//   Very large BRAMs can be slow and timing becomes tight when incoming
//   values are computed in the same cycle or outgoing values are used
//   in logic in the exit cycle.  If bufBefore is True this wrapper adds
//   a buffer stage at each end of the pipeline.  If bufBefore is False
//   only the output is buffered.
//
module [m] mkSlowMemory#(MEMORY_IFC#(t_ADDR, t_DATA) mem, Bool bufBefore)
    // Interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bounded#(t_ADDR),
              IsModule#(m, a__));
    
    // Shared read request and write queue
    FIFOF#(Tuple2#(Maybe#(t_ADDR), Maybe#(Tuple2#(t_ADDR, t_DATA)))) reqQ = ?;
    if (bufBefore)
    begin
        reqQ <- mkFIFOF();
    end

    FIFOF#(t_DATA) readRspQ <- mkFIFOF();
    RWire#(t_ADDR) readReqW <- mkRWire();
    RWire#(Tuple2#(t_ADDR, t_DATA)) writeW <- mkRWire();

    rule fwdReadRsp (True);
        let rsp <- mem.readRsp();
        readRspQ.enq(rsp);
    endrule

    if (bufBefore)
    begin
        rule fwdReq (True);
            match {.m_r_addr, .m_w_req} = reqQ.first();
            reqQ.deq();

            if (m_r_addr matches tagged Valid .r_addr)
            begin
                mem.readReq(r_addr);
            end

            if (m_w_req matches tagged Valid {.w_addr, .w_data})
            begin
                mem.write(w_addr, w_data);
            end
        endrule

        (* fire_when_enabled *)
        rule genReq (True);
            reqQ.enq(tuple2(readReqW.wget, writeW.wget));
        endrule
    end


    method Action readReq(t_ADDR addr) if (! bufBefore || reqQ.notFull);
        if (bufBefore)
        begin
            // Buffering input requests.  Write the request wire, which will
            // trigger an enq to the buffer FIFO.
            readReqW.wset(addr);
        end
        else
        begin
            // Not buffering.  Send request directly to memory.
            mem.readReq(addr);
        end
    endmethod

    method ActionValue#(t_DATA) readRsp();
        let data = readRspQ.first();
        readRspQ.deq();

        return data;
    endmethod

    method Action write(t_ADDR addr, t_DATA data) if (! bufBefore || reqQ.notFull);
        if (bufBefore)
        begin
            // Buffering input requests.  Write the request wire, which will
            // trigger an enq to the buffer FIFO.
            writeW.wset(tuple2(addr, data));
        end
        else
        begin
            // Not buffering.  Send request directly to memory.
            mem.write(addr, data);
        end
    endmethod

    method Bool notFull = (bufBefore ? reqQ.notFull : mem.notFull);
    method Bool writeNotFull = (bufBefore ? reqQ.notFull : mem.writeNotFull);
    method Bool notEmpty = readRspQ.notEmpty;
    method t_DATA peek = readRspQ.first;
endmodule


//
// mkSlowMemoryM --
//   Equivalent of mkSlowMemory() but takes a function that can instantiate
//   a base memory to wrap.
//
module [m] mkSlowMemoryM#(function m#(MEMORY_IFC#(t_ADDR, t_DATA)) memImpl,
                          Bool bufBefore)
    // Interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bounded#(t_ADDR),
              IsModule#(m, a__));

    let _m <- memImpl();
    let _s <- mkSlowMemory(_m, bufBefore);
    return _s;
endmodule


//
// mkWriteBeforeReadMemory --
//   LEAP's Xilinx BRAM implementation is configured as read before write
//   on the write port.  When Xilinx multi-ported BRAM ports are synchronous
//   and the writing port is read-first, the value read on a read port is the
//   old value even when the read and write ports target the same memory
//   location. (See e.g. UG473, "Conflict Avoidance" in Block RAM Resources.)
//
//   This module turns a memory into write-before by monitoring the addresses
//   and bypassing writes to read responses when addresses conflict.
//
module [m] mkWriteBeforeReadMemory#(MEMORY_IFC#(t_ADDR, t_DATA) mem)
    // Interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bounded#(t_ADDR),
              IsModule#(m, a__));
    
    RWire#(t_ADDR) readAddr <- mkRWire();
    RWire#(t_ADDR) writeAddr <- mkRWire();
    RWire#(t_DATA) writeData <- mkRWire();
    
    FIFOF#(Maybe#(t_DATA)) bypassWriteQ <- mkUGFIFOF();
    
    //
    // checkBypassing --
    //   Monitor read and write addresses.  When the same, forward write
    //   data to the read response port.
    //
    (* no_implicit_conditions, fire_when_enabled *)
    rule checkBypassing (readAddr.wget() matches tagged Valid .r);
        if (writeAddr.wget() matches tagged Valid .w &&& pack(w) == pack(r))
            bypassWriteQ.enq(writeData.wget());
        else
            bypassWriteQ.enq(tagged Invalid);
    endrule

    method Action readReq(t_ADDR addr) if (bypassWriteQ.notFull);
        mem.readReq(addr);
        readAddr.wset(addr);
    endmethod

    method ActionValue#(t_DATA) readRsp() if (bypassWriteQ.notEmpty);
        let resp_mem <- mem.readRsp();

        let resp_bypass = bypassWriteQ.first();
        bypassWriteQ.deq();

        return (isValid(resp_bypass) ? validValue(resp_bypass) : resp_mem);
    endmethod

    method Action write(t_ADDR addr, t_DATA data);
        mem.write(addr, data);
        writeAddr.wset(addr);
        writeData.wset(data);
    endmethod

    method Bool notFull = mem.notFull && bypassWriteQ.notFull;
    method Bool notEmpty = mem.notEmpty && bypassWriteQ.notEmpty;
    method Bool writeNotFull = mem.writeNotFull;
    method t_DATA peek = error("mkCachePrefetchLearnerMemory.peek() not implemented");
endmodule



// ========================================================================
//
//  Memory wrappers that combine equivalent reads into single requests.
//
// ========================================================================
    
//
// mkMemReadBypassWrapper --
//   Monitor read requests and combine a series of requests for the same
//   address into a single read.
//
module [m] mkMemReadBypassWrapper#(
    MEMORY_IFC#(t_ADDR, t_DATA) mem,
    Integer maxReadsPerPort)
    // Interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              IsModule#(m, a__));

    // The read bypass code is implemented in a multi-reader interface.
    let _mem_multi <- mkMemIfcToMultiMemIfc(mem);

    // Wrap with the read bypassing code.
    _mem_multi <- mkMemReadBypassWrapperMultiRead(_mem_multi, maxReadsPerPort);

    // Downgrade the multi reader interface to the usual interface.
    let _mem <- mkMultiMemIfcToMemIfc(_mem_multi);

    return _mem;
endmodule

module [m] mkMemReadBypassWrapperM#(
    function m#(MEMORY_IFC#(t_ADDR, t_DATA)) memImpl,
    Integer maxReadsPerPort)
    // Interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              IsModule#(m, a__));

    let _mem <- memImpl();
    _mem <- mkMemReadBypassWrapper(_mem, maxReadsPerPort);

    return _mem;
endmodule


//
// mkMemReadBypassWrapperMultiRead --
//   Monitor read requests and combine a series of requests for the same
//   address into a single read.
//
module [m] mkMemReadBypassWrapperMultiRead#(
    MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) mem,
    Integer maxReadsPerPort)
    // Interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              IsModule#(m, a__));

    // The read bypass code is implemented in a masked write interface.
    // Wrap the incoming memory with a dummy mask argument.
    MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_ADDR, t_DATA, Bit#(1)) _mem_masked <-
        mkMultiReadMemIfcToMultiReadMaskedWriteIfc(mem);

    // Wrap with the read bypassing code.
    _mem_masked <- mkMemReadBypassWrapperMultiReadMaskedWrite(_mem_masked, maxReadsPerPort);

    // Downgrade the masked write interface to the usual interface.
    let _mem <- mkMultiReadMaskedWriteIfcToMultiReadMemIfc(_mem_masked);

    return _mem;
endmodule
    

module [m] mkMemReadBypassWrapperMultiReadM#(
    function m#(MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA)) memImpl,
    Integer maxReadsPerPort)
    // Interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              IsModule#(m, a__));

    let _mem <- memImpl();
    _mem <- mkMemReadBypassWrapperMultiRead(_mem, maxReadsPerPort);

    return _mem;
endmodule


//
// mkMemReadBypassWrapperMultiReadMaskedWrite --
//   Monitor read requests and combine a series of requests for the same
//   address into a single read.
//
module [m] mkMemReadBypassWrapperMultiReadMaskedWrite#(
    MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_ADDR, t_DATA, t_MASK) mem,
    Integer maxReadsPerPort)
    // Interface:
    (MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_ADDR, t_DATA, t_MASK))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_MASK, t_MASK_SZ),
              IsModule#(m, a__));

    // addrMatchQ indicates whether to repeat the last value or return a
    // new response.
    Vector#(n_READERS, FIFOF#(Bool)) addrMatchQ <- replicateM(mkSizedFIFOF(maxReadsPerPort));
    Vector#(n_READERS, Array#(Reg#(Maybe#(t_ADDR)))) lastAddr <- replicateM(mkCReg(2, tagged Invalid));
    Vector#(n_READERS, Reg#(t_DATA)) lastValue <- replicateM(mkRegU());

    Vector#(n_READERS, RWire#(t_DATA)) nextValueW <- replicateM(mkRWire);
    Vector#(n_READERS, PulseWire) didReadRspW <- replicateM(mkPulseWire);


    //
    // Monitor writes and invalidate the address being matched if needed.
    // The invalidation is done at the beginning of the cycle following
    // a write instead of at the end of the write's cycle in order to
    // avoid creating a timing path between readReq and write methods.
    //
    FIFOF#(t_ADDR) invalQ <- mkFIFOF();

    (* fire_when_enabled *)
    rule doInval (invalQ.notEmpty);
        let addr = invalQ.first();
        invalQ.deq();

        for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
        begin
            if (lastAddr[p][0] matches tagged Valid .a &&& pack(a) == pack(addr))
            begin
                lastAddr[p][0] <= tagged Invalid;
            end
        end
    endrule


    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        //
        // Compute the next value on each port in this rule instead of in
        // the method in case callers of the method use no_implicit_conditions,
        // in which case the lack of a cache read response could cause
        // a deadlock.
        //
        rule nextValue (True);
            let repeat_prev = addrMatchQ[p].first();

            if (repeat_prev)
            begin
                // Forward the repeated value
                nextValueW[p].wset(lastValue[p]);
            end
            else
            begin
                // Use the next read response from the managed memory
                let v = mem.readPorts[p].peek();
                lastValue[p] <= v;
                nextValueW[p].wset(v);
            end
        endrule

        //
        // doDeq consumes deq requests from readRsp and consumes incoming
        // responses.  It is in a rule for the same reason as nextValue above.
        //
        (* fire_when_enabled *)
        rule doDeq (didReadRspW[p]);
            let repeat_prev = addrMatchQ[p].first();
            addrMatchQ[p].deq();

            if (! repeat_prev)
            begin
                let dummy <- mem.readPorts[p].readRsp();
            end
        endrule


        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr);
                    // Look for back-to-back reads from the same address
                    if (lastAddr[p][1] matches tagged Valid .a &&& pack(a) == pack(addr))
                    begin
                        // Found a repeat.  Don't do the load.
                        addrMatchQ[p].enq(True);
                    end
                    else
                    begin
                        // New address.
                        mem.readPorts[p].readReq(addr);
                        addrMatchQ[p].enq(False);
                        lastAddr[p][1] <= tagged Valid addr;
                    end
                endmethod

                method ActionValue#(t_DATA) readRsp() if (nextValueW[p].wget() matches tagged Valid .v);
                    didReadRspW[p].send();
                    return v;
                endmethod

                method t_DATA peek() if (nextValueW[p].wget() matches tagged Valid .v);
                    return v;
                endmethod

                method Bool notEmpty = isValid(nextValueW[p].wget);
                method Bool notFull = mem.readPorts[p].notFull && addrMatchQ[p].notFull;
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val, t_MASK mask);
        mem.write(addr, val, mask);

        // Invalidate last read address if it matches.  For timing, the
        // invalidation happens at the beginning of the next cycle, before
        // reads are checked.
        invalQ.enq(addr);
    endmethod

    method Bool writeNotFull = mem.writeNotFull;
endmodule

module [m] mkMemReadBypassWrapperMultiReadMaskedWriteM#(
    function m#(MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_ADDR, t_DATA, t_MASK)) memImpl,
    Integer maxReadsPerPort)
    // Interface:
    (MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_ADDR, t_DATA, t_MASK))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_MASK, t_MASK_SZ),
              IsModule#(m, a__));

    let _mem <- memImpl();
    _mem <- mkMemReadBypassWrapperMultiReadMaskedWrite(_mem, maxReadsPerPort);

    return _mem;
endmodule
