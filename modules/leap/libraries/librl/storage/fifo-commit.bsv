//
// Copyright (C) 2010 Massachusetts Institute of Technology
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

import RegFile::*;
import GetPut::*;

/* This fifo operates with speculative enqueues.  The commit method
   must be called to make these enqueues visible at the dequeue side.
   Abort destroys all non-commited enqueued values. 
*/


function Get#(fifo_type) commitFifoToGet( CommitFIFO#(fifo_type,size) fifo);
  Get#(fifo_type) f = interface Get#(fifo_type);
                        method ActionValue#(fifo_type) get();
                          fifo.deq;
                          return fifo.first;
                        endmethod
                      endinterface;
  return f; 
endfunction

function Put#(fifo_type) commitFifoToPut( CommitFIFO#(fifo_type,size) fifo);
  Put#(fifo_type) f = interface Put#(fifo_type);
                        method Action put(fifo_type data);
                          fifo.enq(data);
                        endmethod
                      endinterface; 
  return f;
endfunction


// This fifo allows the partial commit of values.  Values are not seen at the output until commit is called.
// Yet another variant on the ever popular ring buffer.


interface CommitFIFO#(type data, numeric type size);
  method data first();
  method Action commit();  
  method Action abort();  
  method Action deq();
  method Action enq(data inData);
  method Bool notFull;
  method Bool notEmpty;
endinterface

interface CommitFIFOLevel#(type data, numeric type size);
  method data first();
  method Action commit();  
  method Action abort();  
  method Action deq();
  method Action enq(data inData);
  method Bool notFull;
  method Bool notEmpty;

  // These are a little confusing, since they measure the number of data
  // including speculative data
  method Bool isLessThan   ( Bit#(TAdd#(1,TLog#(size))) c1 ) ;
  method Bool isGreaterThan( Bit#(TAdd#(1,TLog#(size))) c1 ) ;
  method Bit#(TAdd#(1,TLog#(size))) count();
endinterface

module mkCommitFIFOLevel (CommitFIFOLevel#(data,size))
   provisos(
     Bits#(data, dataSz)
   );

  RegFile#(Bit#(TAdd#(1,TLog#(size))),data) memory <- mkRegFile(0,fromInteger(valueof(size))); 

  Reg#(Bit#(TAdd#(1,TLog#(size)))) firstPtr      <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) commitPtr     <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) enqPtr        <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) dataCounter   <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) commitCounter <- mkReg(0);
  PulseWire           countUp       <- mkPulseWire;
  PulseWire           countDown     <- mkPulseWire;
  PulseWire           commitPulse   <- mkPulseWire;
  PulseWire           abortPulse    <- mkPulseWire;

  rule toggle;
    // adjust data counter
    if(countDown && !commitPulse) // don't care about count up, unless we also commit.
      begin
        dataCounter <= dataCounter - 1;
      end  
    else if(!countDown && commitPulse && !countUp)
      begin
        dataCounter <= dataCounter + commitCounter;
      end 
    else if(!countDown && commitPulse && countUp)
      begin
        dataCounter <= dataCounter + commitCounter + 1;
      end 
    else if(countDown && commitPulse && !countUp)
      begin
        dataCounter <= dataCounter + commitCounter - 1;
      end 
    else if(countDown && commitPulse && countUp)
      begin
        dataCounter <= dataCounter + commitCounter;
      end 

    if(commitPulse)
      begin
        commitCounter <= 0;
      end
    else if(abortPulse)
      begin
        commitCounter <= 0;
      end
    else if(!commitPulse && countUp)
      begin
        commitCounter <= commitCounter + 1;
      end

    if(commitPulse)
      begin
        if(countUp)
          begin
            enqPtr <= (enqPtr + 1 == fromInteger(valueof(size)))?0:enqPtr+1;  
          end
      end
    else if(abortPulse)
      begin
        enqPtr <= commitPtr;
      end
    else if(countUp)
      begin
        enqPtr <= (enqPtr + 1 == fromInteger(valueof(size)))?0:enqPtr+1;  
      end
   
    if(commitPulse && countUp)
      begin
        commitPtr <= (enqPtr + 1 == fromInteger(valueof(size)))?0:enqPtr+1; 
      end
    else if(commitPulse && !countUp)
      begin
        commitPtr <= enqPtr;
      end

  endrule

  method data first() if(dataCounter > 0);
    return memory.sub(firstPtr);
  endmethod

  method Action commit();  
    commitPulse.send;
  endmethod

  method Action abort();  
    abortPulse.send;
  endmethod

  method Action deq() if(dataCounter > 0);
    firstPtr <= (firstPtr + 1 == fromInteger(valueof(size)))?0:firstPtr+1;
    countDown.send;
  endmethod

  // issue here is what happens when we also commit... 
  // commit should probably happen last.  if only we could specifiy...
  method Action enq(data inData) if(dataCounter + commitCounter < fromInteger(valueof(size)));
    countUp.send;
    memory.upd(enqPtr,inData);  
  endmethod


  method Bool notFull;
   return dataCounter + commitCounter < fromInteger(valueof(size));
  endmethod

  method Bool notEmpty;
    return dataCounter > 0;
  endmethod

  method Bool isLessThan   ( Bit#(TAdd#(1,TLog#(size))) c1 );
    return ( dataCounter + commitCounter  < c1 );
  endmethod

  method Bool isGreaterThan( Bit#(TAdd#(1,TLog#(size))) c1 );
   return ( dataCounter + commitCounter  > c1 );   
  endmethod

  method Bit#(TAdd#(1,TLog#(size))) count();
    return dataCounter + commitCounter;
  endmethod

endmodule


module mkCommitFIFO (CommitFIFO#(data,size))
   provisos(
     Bits#(data, dataSz)
   );

  CommitFIFOLevel#(data,size) fifo <- mkCommitFIFOLevel(); 

  method first = fifo.first;
  method commit = fifo.commit;  
  method abort = fifo.abort;  
  method deq = fifo.deq;
  method enq = fifo.enq;
  method notFull = fifo.notFull;
  method notEmpty = fifo.notEmpty; 

endmodule


module mkCommitFIFOLevelUG (CommitFIFOLevel#(data,size))
   provisos(
     Bits#(data, dataSz)
   );

  RegFile#(Bit#(TAdd#(1,TLog#(size))),data) memory <- mkRegFile(0,fromInteger(valueof(size))); 

  Reg#(Bit#(TAdd#(1,TLog#(size)))) firstPtr      <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) commitPtr     <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) enqPtr        <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) dataCounter   <- mkReg(0);
  Reg#(Bit#(TAdd#(1,TLog#(size)))) commitCounter <- mkReg(0);
  PulseWire           countUp       <- mkPulseWire;
  PulseWire           countDown     <- mkPulseWire;
  PulseWire           commitPulse   <- mkPulseWire;
  PulseWire           abortPulse    <- mkPulseWire;

  rule toggle;
    // adjust data counter
    if(countDown && !commitPulse) // don't care about count up, unless we also commit.
      begin
        dataCounter <= dataCounter - 1;
      end  
    else if(!countDown && commitPulse && !countUp)
      begin
        dataCounter <= dataCounter + commitCounter;
      end 
    else if(!countDown && commitPulse && countUp)
      begin
        dataCounter <= dataCounter + commitCounter + 1;
      end 
    else if(countDown && commitPulse && !countUp)
      begin
        dataCounter <= dataCounter + commitCounter - 1;
      end 
    else if(countDown && commitPulse && countUp)
      begin
        dataCounter <= dataCounter + commitCounter;
      end 

    if(commitPulse)
      begin
        commitCounter <= 0;
      end
    else if(abortPulse)
      begin
        commitCounter <= 0;
      end
    else if(!commitPulse && countUp)
      begin
        commitCounter <= commitCounter + 1;
      end

    if(commitPulse)
      begin
        if(countUp)
          begin
            enqPtr <= (enqPtr + 1 == fromInteger(valueof(size)))?0:enqPtr+1;  
          end
      end
    else if(abortPulse)
      begin
        enqPtr <= commitPtr;
      end
    else if(countUp)
      begin
        enqPtr <= (enqPtr + 1 == fromInteger(valueof(size)))?0:enqPtr+1;  
      end
   
    if(commitPulse && countUp)
      begin
        commitPtr <= (enqPtr + 1 == fromInteger(valueof(size)))?0:enqPtr+1; 
      end
    else if(commitPulse && !countUp)
      begin
        commitPtr <= enqPtr;
      end

  endrule

  method data first() if(dataCounter > 0);
    return memory.sub(firstPtr);
  endmethod

  method Action commit();  
    commitPulse.send;
  endmethod

  method Action abort();  
    abortPulse.send;
  endmethod

  method Action deq() if(dataCounter > 0);
    firstPtr <= (firstPtr + 1 == fromInteger(valueof(size)))?0:firstPtr+1;
    countDown.send;
  endmethod

  // You asked for it, you got it...
  method Action enq(data inData);
    countUp.send;
    memory.upd(enqPtr,inData);  
  endmethod


  method Bool notFull;
   return dataCounter + commitCounter < fromInteger(valueof(size));
  endmethod

  method Bool notEmpty;
    return dataCounter > 0;
  endmethod

  method Bool isLessThan   ( Bit#(TAdd#(1,TLog#(size))) c1 );
    return ( dataCounter + commitCounter  < c1 );
  endmethod

  method Bool isGreaterThan( Bit#(TAdd#(1,TLog#(size))) c1 );
   return ( dataCounter + commitCounter  > c1 );   
  endmethod

  method Bit#(TAdd#(1,TLog#(size))) count();
    return dataCounter + commitCounter;
  endmethod

endmodule


module mkCommitFIFOUG (CommitFIFO#(data,size))
   provisos(
     Bits#(data, dataSz)
   );

  CommitFIFOLevel#(data,size) fifo <- mkCommitFIFOLevelUG(); 

  method first = fifo.first;
  method commit = fifo.commit;  
  method abort = fifo.abort;  
  method deq = fifo.deq;
  method enq = fifo.enq;
  method notFull = fifo.notFull;
  method notEmpty = fifo.notEmpty; 

endmodule