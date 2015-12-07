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
import FIFO::*;

//`include "awb/provides/physical_platform.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"

typedef struct {
  LATENCY_FIFO_DELAY_CONTAINER stamp;
  t_MSG payload;
} TimestampedValue#(type t_MSG) deriving (Bits,Eq);


interface SCFIFOF#(type t_MSG);
    interface FIFOF#(t_MSG) fifo;
    interface CONNECTION_LATENCY_CONTROL control;
endinterface 

// The actual instatiation of a physical send. For efficiency contains an 
// unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this may guard the FIFO as appropriate.

module mkSCFIFOFUG (SCFIFOF#(t_MSG))
    provisos( Bits#(t_MSG, t_MSG_sz) );
    
    let m <- mkSCSizedFIFOFUG(`CON_BUFFERING);  
    return m;
endmodule

// Probably need to pull the parameters out of the context
module mkSCSizedFIFOFUG#(Integer depthParam)
    // interface:
    (SCFIFOF#(t_MSG))
    provisos(Bits#(t_MSG, t_MSG_sz));

    NumTypeParam#(LATENCY_FIFO_DEPTH) sizeParam = ?;
    let fifoMem <- mkUGSizedFIFOF(depthParam);
    Reg#(LATENCY_FIFO_DELAY_CONTAINER) current <- mkReg(0);
    // I'm too lazy to implement a lutram count fifo.. 
    COUNTER#(SizeOf#(LATENCY_FIFO_DEPTH_CONTAINER)) count <- mkLCounter(0);     
    Reg#(Bool) enable <- mkReg(False);
    
    if (depthParam > valueOf(LATENCY_FIFO_DEPTH))
    begin
        error("LATENCY_FIFO_DEPTH is not big enough: need to be set to at least " + integerToString(depthParam));
    end
    
    Reg#(LATENCY_FIFO_DELAY_CONTAINER) delayExternal <- mkReg(0);
    Reg#(LATENCY_FIFO_DEPTH_CONTAINER) depthExternal <- mkReg(fromInteger(depthParam));

    PulseWire statIncr <- mkPulseWire();

    let delay = (enable)? delayExternal : 0;
    let depth = (enable)? depthExternal : fromInteger(depthParam);

    Int#(SizeOf#(LATENCY_FIFO_DELAY_CONTAINER)) stampDelta = unpack(abs(current-fifoMem.first.stamp));

    rule tickCurrent;
        current <= current + 1;
    endrule

    interface FIFOF fifo;

        method first();
            return fifoMem.first.payload;
        endmethod

        method Action deq();
            fifoMem.deq; 
            count.down;
            statIncr.send;
        endmethod

        method Action enq(t_MSG value);
            count.up();
            fifoMem.enq(TimestampedValue{stamp: current, payload: value});
        endmethod

        method Bool notEmpty = fifoMem.notEmpty && (delay < pack(abs(stampDelta)));   

        method Bool notFull = fifoMem.notFull && (count.value <= depth);

        method Action clear(); 
            fifoMem.clear();
            count.setC(0);   
        endmethod

    endinterface

    interface CONNECTION_LATENCY_CONTROL control;

        method setControl = enable._write();

        method setDelay = delayExternal._write();
 
        method setDepth = depthExternal._write();

        method incrStat = statIncr._read();

    endinterface

endmodule

// ========================================================================
//
// Guarded latency FIFOs. 
//
// ========================================================================

module mkSCFIFOF (SCFIFOF#(t_MSG))
    provisos( Bits#(t_MSG, t_MSG_sz) );
    
    let m <- mkSCSizedFIFOF(`CON_BUFFERING);  
    return m;
endmodule


module mkSCSizedFIFOF#(Integer depth)
    // interface:
    (SCFIFOF#(t_MSG))
    provisos(Bits#(t_MSG, t_MSG_sz));

    let m <- mkSCSizedFIFOFUG(depth);  
    
    interface FIFOF fifo;
        method first() if (m.fifo.notEmpty);
            return m.fifo.first();
        endmethod
        method Action deq() if (m.fifo.notEmpty);
            m.fifo.deq();
        endmethod
        method Action enq(t_MSG value) if (m.fifo.notFull);
            m.fifo.enq(value);
        endmethod
        method Bool notEmpty = m.fifo.notEmpty;
        method Bool notFull = m.fifo.notFull;
        method Action clear(); 
            m.fifo.clear();
        endmethod
    endinterface

    interface CONNECTION_LATENCY_CONTROL control = m.control;

endmodule

