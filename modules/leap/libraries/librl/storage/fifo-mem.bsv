//
// Copyright (C) 2010 Intel Corporation
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
// FIFOs with data stored in a large memory (e.g. BRAM).
//

import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;
import SpecialFIFOs::*;

`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv_base.bsh"


//
// mkSizedBRAMFIFO --
//     BRAM version of a memory FIFO.
//
module mkSizedBRAMFIFO#(Integer nEntries)
    // Interface:
    (FIFO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));
     
    FIFOF#(t_DATA) fifof <- mkSizedBRAMFIFOF(nEntries);
    return fifofToFifo(fifof);
endmodule


//
// mkSizedBRAMFIFOF --
//     BRAM version of a memory FIFOF.
//
//     We wrote these before the Bluespec library's equivalent function was
//     available.  The brute-force conversion of an integer parameter to
//     a type was adapted from the Bluespec code, replacing our old version
//     that took a type.  Too bad Integer can't be converted to a type.
//
module mkSizedBRAMFIFOF#(Integer depth)
    // Interface:
    (FIFOF#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));
     
    let _f = ?;

    if      (depth <= 2)          begin MEMORY_IFC#(Bit#(1), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4)          begin MEMORY_IFC#(Bit#(2), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 8)          begin MEMORY_IFC#(Bit#(3), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 8) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 16)         begin MEMORY_IFC#(Bit#(4), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 16) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 32)         begin MEMORY_IFC#(Bit#(5), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 32) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 64)         begin MEMORY_IFC#(Bit#(6), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 64) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 128)        begin MEMORY_IFC#(Bit#(7), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 128) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 256)        begin MEMORY_IFC#(Bit#(8), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 256) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 512)        begin MEMORY_IFC#(Bit#(9), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 512) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 1024)       begin MEMORY_IFC#(Bit#(10), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 1024) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 2048)       begin MEMORY_IFC#(Bit#(11), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2048) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4096)       begin MEMORY_IFC#(Bit#(12), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4096) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 8192)       begin MEMORY_IFC#(Bit#(13), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 8192) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 16384)      begin MEMORY_IFC#(Bit#(14), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 16384) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 32768)      begin MEMORY_IFC#(Bit#(15), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 32768) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 65536)      begin MEMORY_IFC#(Bit#(16), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 65536) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 101072)     begin MEMORY_IFC#(Bit#(17), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 101072) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 262144)     begin MEMORY_IFC#(Bit#(18), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 262144) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 524288)     begin MEMORY_IFC#(Bit#(19), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 524288) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 1048576)    begin MEMORY_IFC#(Bit#(20), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 1048576) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 2097152)    begin MEMORY_IFC#(Bit#(21), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2097152) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4194304)    begin MEMORY_IFC#(Bit#(22), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4194304) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 8388608)    begin MEMORY_IFC#(Bit#(23), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 8388608) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 16777216)   begin MEMORY_IFC#(Bit#(24), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 16777216) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 33554432)   begin MEMORY_IFC#(Bit#(25), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 33554432) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 67108864)   begin MEMORY_IFC#(Bit#(26), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 67108864) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 134217728)  begin MEMORY_IFC#(Bit#(27), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 134217728) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 268435456)  begin MEMORY_IFC#(Bit#(28), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 268435456) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 536870912)  begin MEMORY_IFC#(Bit#(29), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 536870912) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 1073741824) begin MEMORY_IFC#(Bit#(30), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 1073741824) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 2147483648) begin MEMORY_IFC#(Bit#(31), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2147483648) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4294967296) begin MEMORY_IFC#(Bit#(32), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4294967296) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end

    return _f;
endmodule


//
// mkSizedBRAMFIFOCount --
//     BRAM version of a memory FIFOCountF.
//
module mkSizedBRAMFIFOCount
    // Interface:
    (FIFOCountIfc#(t_DATA,n_ENTRIES))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    MEMORY_IFC#(Bit#(TLog#(n_ENTRIES)), t_DATA) mem <- mkBRAMUnguarded();
    FIFOCountIfc#(t_DATA,n_ENTRIES) fifo <- mkMemoryFIFOF(mem);
    return fifo;
endmodule


//
// mkMemoryFIFOF --
//     Implement a FIFOF in the provided memory (e.g. BRAM).  
//
//     To guarantee timing, the memory must have two characteristics:
//         1.  Reads and writes are unguarded.
//         2.  Read data is available one cycle following a read request.
//
//
module mkMemoryFIFOF#(MEMORY_IFC#(Bit#(TLog#(n_ENTRIES)), t_DATA) mem)
    // Interface:
    (FIFOCountIfc#(t_DATA, n_ENTRIES))
    provisos (Bits#(t_DATA, t_DATA_SZ));
    
    Reg#(FUNC_FIFO_IDX#(n_ENTRIES)) state <- mkReg(funcFIFO_IDX_Init());


    //
    // updateState --
    //     Combine deq and enq requests into an update of the FIFO state.
    //     Also fetch the value that could be returned by first() in the
    //     next cycle.
    RWire#(t_DATA) enqData <- mkRWire();
    PulseWire deqReq <- mkPulseWire();
    PulseWire clearReq <- mkPulseWire();
    
    Reg#(Maybe#(t_DATA)) bypassFirstVal <- mkReg(tagged Invalid);

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule updateState;
        FUNC_FIFO_IDX#(n_ENTRIES) new_state = state;
        Bool made_mem_req = False;
        
        // DEQ requested?
        if (deqReq)
        begin
            new_state = funcFIFO_IDX_UGdeq(new_state);
        end

        // After DEQ does the FIFO have more entries?  If yes, request the
        // value of the next entry.  It will be consumed by firstFromMem.
        if (funcFIFO_IDX_notEmpty(new_state))
        begin
            mem.readReq(funcFIFO_IDX_UGfirst(new_state));
            made_mem_req = True;
        end

        Maybe#(t_DATA) bypass_first = tagged Invalid;

        if (enqData.wget() matches tagged Valid .data)
        begin
            match {.s, .idx} = funcFIFO_IDX_UGenq(new_state);
            new_state = s;
            mem.write(idx, data);

            if (! made_mem_req)
            begin
                // No memory request is being issued this cycle either because
                // the FIFO was empty or is now empty following a deq.
                // Pass the new data directly to next cycle's first().
                bypass_first = tagged Valid data;
            end
        end

        //Clear takes precendent
        if(clearReq)
        begin
            new_state = funcFIFO_IDX_Init();
            bypass_first = tagged Invalid;
        end

        bypassFirstVal <= bypass_first;
        state <= new_state;
    endrule


    //
    // The value for the first() method must be requested the previous cycle
    // since memory reads are two phases.  The value comes from the updateState
    // rule either as a bypass or as a memory read response.
    //
    RWire#(t_DATA) firstVal <- mkRWire();

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule firstFromBypass (bypassFirstVal matches tagged Valid .val);
        firstVal.wset(val);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule firstFromMemRsp (! isValid(bypassFirstVal) &&
                          funcFIFO_IDX_notEmpty(state));
        let v <- mem.readRsp();
        firstVal.wset(v);
    endrule


    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action enq(t_DATA data) if (funcFIFO_IDX_notFull(state));
        enqData.wset(data);
    endmethod

    method t_DATA first() if (firstVal.wget() matches tagged Valid .val);
        return val;
    endmethod

    method Action deq() if (firstVal.wget() matches tagged Valid .val);
        deqReq.send();
    endmethod

    method Action clear();
        clearReq.send();
    endmethod

    method Bool notEmpty();
        return funcFIFO_IDX_notEmpty(state);
    endmethod

    method Bool notFull();
        return funcFIFO_IDX_notFull(state);
    endmethod

    method UInt#(TLog#(TAdd#(n_ENTRIES,1))) count();
        return unpack(funcFIFO_IDX_numBusySlots(state));
    endmethod

endmodule


module mkSizedLUTRAMFIFOFUG#(NumTypeParam#(t_DEPTH) dummy) 
  //
  //interface:
              (FIFOF#(data_T))
  provisos
          (Bits#(data_T, data_SZ));

  LUTRAM#(Bit#(TLog#(t_DEPTH)), data_T) rs <- mkLUTRAMU();
  
  COUNTER#(TLog#(t_DEPTH)) head <- mkLCounter(0);
  COUNTER#(TLog#(t_DEPTH)) tail <- mkLCounter(0);

  Bool full  = head.value() == (tail.value() + 1);
  Bool empty = head.value() == tail.value();
    
  method Action enq(data_T d);
  
    rs.upd(tail.value(), d);
    tail.up();
   
  endmethod  
  
  method data_T first();
    
    return rs.sub(head.value());
  
  endmethod   
  
  method Action deq();
  
    head.up();
    
  endmethod

  method Action clear();
  
    tail.setC(0);
    head.setC(0);
    
  endmethod

  method Bool notEmpty();
    return !empty;
  endmethod
  
  method Bool notFull();
    return !full;
  endmethod

endmodule


module mkSizedLUTRAMFIFOF#(NumTypeParam#(t_DEPTH) dummy) 
    //
    //interface:
              (FIFOF#(data_T))
    provisos
          (Bits#(data_T, data_SZ));

    let q <- mkSizedLUTRAMFIFOFUG(dummy);
    
    method Action enq(data_T d) if (q.notFull);

        q.enq(d);   

    endmethod  
  
    method data_T first() if (q.notEmpty);

        return q.first();     

    endmethod   
  
    method Action deq() if (q.notEmpty);
  
        q.deq();
    
    endmethod

    method clear = q.clear;
  
    method notEmpty = q.notEmpty;
  
    method notFull = q.notFull;

endmodule


module mkSizedLUTRAMFIFO#(NumTypeParam#(t_DETPH) dummy) (FIFO#(data_T))
  provisos
          (Bits#(data_T, data_SZ));

    let q <- mkSizedLUTRAMFIFOF(dummy);
    return fifofToFifo(q);

endmodule
