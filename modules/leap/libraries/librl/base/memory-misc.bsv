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
