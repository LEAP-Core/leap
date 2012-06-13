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

// The actual instatiation of a physical send. For efficiency contains an 
// unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this may guard the FIFO as appropriate.


import FIFOF::*;
import FIFO::*;

//`include "awb/provides/physical_platform.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"

typedef struct {
  Bit#(16) stamp;
  t_MSG payload;
} TimestampedValue#(type t_MSG) deriving (Bits,Eq);

typedef 8 TestFIFODepth;


/* 
// Probably need to pull the parameters out of the context
module [t_CONTEXT] mkAdjustableFIFOUG#(String name, Bool guarded) (FIFO#(t_MSG));
     let fifo <- mkSizedLUTRAMFIFOFUG(valueof(TestFIFODepth));
     Reg#(Bit#(16)) current <- mkReg(0);
     // I'm too lazy to implement a lutram count fifo.. 
     COUNTER#(TLog#(TestFIFODepth)) count <- mkLCounter(0);     
     COUNTER#(TLog#(t_DEPTH)) head <- mkLCounter(0);
     GLOBAL_STRING_UID tag <- getGlobalStringUID(name + "_LATENCY_TEST");
     Param#(SizeOf#(GLOBAL_STRING_UID)) idExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_ID,paramNode);
     Param#(16) delayExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_DELAY,paramNode);
     Param#(TLog#(t_DEPTH)) depthExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_DEPTH,paramNode);

     let delay = (idExternal == tag)?delayExternal:0;
     let depth = (idExternal == tag)?depthExternal:`CON_BUFFERING;

     rule tickCurrent;
         current <= current + 1;
     endrule

     method first();
         return fifo.first.payload;
     endmethod

     method Action deq();
         fifo.deq; 
         count.down;
     endmethod

     method Action enq(t_MSG value);
         count.up();
         fifo.enq(TimestampedValue{stamp: current, payload: value});
     endmethod


     method Bool notEmpty = fifo.notEmpty && (delay < abs(fifo.first.stamp - current));   
     method Bool notFull = fifo.notFull && (count.value != depth);

endmodule
*/



interface SCFIFOF#(type t_MSG);
    interface FIFOF#(t_MSG) fifo;
    interface CONNECTION_LATENCY_CONTROL control;
endinterface 

// Probably need to pull the parameters out of the context
module mkSCFIFOFUG (SCFIFOF#(t_MSG))
provisos( Bits#(t_MSG, t_MSG_sz)//,
          /*Add#(16, b__, a__)*/ ); //??

     NumTypeParam#(TExp#(SizeOf#(LATENCY_FIFO_DEPTH))) sizeParam = ?;
     let fifoMem <- mkSizedLUTRAMFIFOFUG(sizeParam);
     Reg#(Bit#(16)) current <- mkReg(0);
     // I'm too lazy to implement a lutram count fifo.. 
     COUNTER#(SizeOf#(LATENCY_FIFO_DEPTH)) count <- mkLCounter(0);     
     Reg#(Bool) enable <- mkReg(False);
     Reg#(LATENCY_FIFO_DELAY) delayExternal <- mkReg(0);
     Reg#(LATENCY_FIFO_DEPTH) depthExternal <- mkReg(`CON_BUFFERING);

     let delay = (enable)?delayExternal:0;
     let depth = (enable)?depthExternal:`CON_BUFFERING;

     Int#(SizeOf#(LATENCY_FIFO_DELAY)) stampDelta = unpack(abs(current-fifoMem.first.stamp));

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

         endmethod

         method Action enq(t_MSG value);
             count.up();
             fifoMem.enq(TimestampedValue{stamp: current, payload: value});
         endmethod


         method Bool notEmpty = fifoMem.notEmpty && (delay < pack(abs(stampDelta)));   
         method Bool notFull = fifoMem.notFull && (count.value < depth);

    endinterface

    interface CONNECTION_LATENCY_CONTROL control;

        method setControl = enable._write();

        method setDelay = delayExternal._write();
 
        method setDepth = depthExternal._write();

    endinterface

endmodule