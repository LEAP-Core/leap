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
// Miscellaneous memory modules.
//

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
