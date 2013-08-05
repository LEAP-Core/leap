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

function Get#(fifo_type) rewindFifoToGet( RewindFIFO#(fifo_type,size) fifo);
    Get#(fifo_type) f = interface Get#(fifo_type);
                            method ActionValue#(fifo_type) get();
                                fifo.deq;
                                return fifo.first;
                            endmethod
                        endinterface;
    return f; 
endfunction

function Put#(fifo_type) rewindFifoToPut( RewindFIFO#(fifo_type,size) fifo);
    Put#(fifo_type) f = interface Put#(fifo_type);
                            method Action put(fifo_type data);
                                fifo.enq(data);
                            endmethod
                        endinterface; 
    return f;
endfunction


instance ToPut#(RewindFIFO#(fifo_type,size), fifo_type);
    function toPut = rewindFifoToPut;
endinstance

instance ToGet#(RewindFIFO#(fifo_type,size), fifo_type);
    function toGet = rewindFifoToGet;
endinstance

// This fifo allows the partial commit of values.  Values are not seen at the output until commit is called.
// Yet another variant on the ever popular ring buffer.

interface RewindFIFO#(type data, numeric type size);
    method data first();
    method Action commit();  
    method Action rewind();  
    method Action deq();
    method Action enq(data inData);
    method Bool notFull;
    method Bool notEmpty;
endinterface

interface RewindFIFOLevel#(type data, numeric type size);
    method data first();
    method Action commit();  
    method Action rewind();  
    method Action deq();
    method Action enq(data inData);
    method Bool notFull;
    method Bool notEmpty;
    method Bool isLessThan   ( Bit#(TAdd#(1,TLog#(size))) c1 ) ;
    method Bool isGreaterThan( Bit#(TAdd#(1,TLog#(size))) c1 ) ;
    method Bit#(TAdd#(1,TLog#(size))) count();
endinterface

interface RewindFIFOVariableCommitLevel#(type data, numeric type size);
    method data first();
    method Action commit(Maybe#(Bit#(TAdd#(1,TLog#(size)))) commitAmount);  
    method Action rewind();  
    method Action deq();
    method Action enq(data inData);
    method Bool notFull;
    method Bool notEmpty;
    method Bool isLessThan   ( Bit#(TAdd#(1,TLog#(size))) c1 ) ;
    method Bool isGreaterThan( Bit#(TAdd#(1,TLog#(size))) c1 ) ;
    method Bit#(TAdd#(1,TLog#(size))) count();
endinterface


/* Note deq/enq happens logically before commit... */
module mkRewindFIFOVariableCommitLevel (RewindFIFOVariableCommitLevel#(data,size))
    provisos(
        Bits#(data, dataSz)
    );

    RegFile#(Bit#(TAdd#(1,TLog#(size))),data) memory <- mkRegFileFull(); 

    Reg#(Bit#(TAdd#(1,TLog#(size))))            firstPtr      <- mkReg(0);
    Reg#(Bit#(TAdd#(1,TLog#(size))))            rewindPtr     <- mkReg(0); 
    Reg#(Bit#(TAdd#(1,TLog#(size))))            enqPtr        <- mkReg(0); 
    Reg#(Bit#(TAdd#(1,TLog#(size))))            dataCounter   <- mkReg(0); // Total live data in fifo (including rewind amount)
    Reg#(Bit#(TAdd#(1,TLog#(size))))            rewindCounter <- mkReg(0); // amount that has been dequeued, but subject to rewind.
    PulseWire                                   countUp       <- mkPulseWire;
    PulseWire                                   countDown     <- mkPulseWire;
    PulseWire                                   commitPulse   <- mkPulseWire;
    Wire#(Maybe#(Bit#(TAdd#(1,TLog#(size)))))   commitCommand <- mkDWire(tagged Invalid);
    PulseWire                                   rewindPulse   <- mkPulseWire;

    let commitDistance = fromMaybe(rewindCounter, commitCommand);

    rule toggle;
       
        // Data counter retains the true count of data in the fifo.
        // It can only be modified by enq and commit.  
          
        if(countUp && !commitPulse) // enq
        begin
            dataCounter <= dataCounter + 1;
        end  
        else if(commitPulse && !countUp) //  commit.
        begin
            dataCounter <= dataCounter - commitDistance;
        end 
        else if(commitPulse && countUp) // enq +  commit.
        begin
           dataCounter <= dataCounter - commitDistance + 1;
        end 


        // Rewind counter retains the count of data speculatively
        // dequeued from the fifo. It can only be modified by deq, 
        // commit, and rewind.

        if(rewindPulse) // set to zero.
        begin
            rewindCounter <= 0;
        end
        else if(commitPulse && !countDown)
        begin
            rewindCounter <= rewindCounter - commitDistance; 
        end
        else if(commitPulse && countDown)
        begin
            rewindCounter <= rewindCounter - commitDistance + 1; 
        end
        else if(countDown)
        begin
            rewindCounter <= rewindCounter + 1;
        end

        // Enq Ptr just counts up
        if(countUp)
        begin
            enqPtr <= enqPtr + 1;  
        end


        // Rewind Pointer points to the last committed location.  It can 
        // only change on a commit.     

        if(commitPulse)
        begin
            rewindPtr <= rewindPtr + commitDistance;  
        end

        // First pointer points to the next value to be deqeued.  
        // It can change on an update and on a rewind. 
 
        if(rewindPulse)
        begin
            firstPtr <= rewindPtr;
        end
        else if(countDown)
        begin
            firstPtr <= firstPtr + 1;
        end

        if(`DEBUG_REWIND_FIFO == 1)
        begin
            $display("RwFIFO: firstPtr: %h, rwPtr: %h, enqPtr: %h, rwCnt: %h, dataCnt: %h", firstPtr, rewindPtr, enqPtr, rewindCounter, dataCounter);
            $display("RwFIFO: countUp: %d, countDown: %d, commmitPulse: %d, rewindPulse: %d, commitDistance: %d", countUp, countDown, commitPulse, rewindPulse, commitDistance);
        end

        // some simple checks
        if((enqPtr > rewindPtr) && (enqPtr - rewindPtr != dataCounter))
        begin
            $display("Data being dropped >, enqPtr - rewindPtr != dataCounter");
            $finish;
        end 

        if(enqPtr == rewindPtr && !(dataCounter == 0 || dataCounter == fromInteger(valueof(size))))
        begin
            $display("Data being dropped=, enqPtr - rewindPtr != dataCounter");
            $finish;
        end

        // data at head of queue + (data at tail of queue) 
        if(enqPtr < rewindPtr && !({1'b0,dataCounter} == {0,enqPtr} + (fromInteger(valueof(TExp#(TAdd#(1,TLog#(size))))) - {0,rewindPtr})))
        begin
            $display("Data being dropped<, enqPtr - rewindPtr (%d) != dataCounter (%d)", enqPtr + fromInteger(valueof(size)) - rewindPtr, dataCounter);
            $finish;
        end

        // Same assertions about rw and first

        if((firstPtr > rewindPtr) && (firstPtr - rewindPtr != rewindCounter))
        begin
            $display("Data being dropped >, firstPtr - rewindPtr != rewindCounter");
            $finish;
        end 

        if(firstPtr == rewindPtr && !(rewindCounter == 0 || rewindCounter == fromInteger(valueof(size))))
        begin
            $display("Data being dropped=, firstPtr - rewindPtr != rewindCounter");
            $finish;
        end

        // data at head of queue + (data at tail of queue)    
        if(firstPtr < rewindPtr && !({1'b0,rewindCounter} == {0,firstPtr} + (fromInteger(valueof(TExp#(TAdd#(1,TLog#(size))))) - {0,rewindPtr})))
        begin
            $display("Data being dropped<, firstPtr - rewindPtr != rewindCounter");
            $finish;
        end

       if(dataCounter > fromInteger(valueof(size)))
       begin
            $display("Too much data!");
            $finish;           
       end

       if(rewindCounter > fromInteger(valueof(size)))
       begin
            $display("Too much data to be rewound!");
            $finish;           
       end

       if(rewindCounter > dataCounter)
       begin
            $display("rewind counter larger than data counter!");
            $finish;           
       end

       // An illegal commit distance?
       if(commitDistance > rewindCounter)
       begin
           $display("Illegal commit distance %d.  Maximum was %d", commitDistance, rewindCounter);
           $finish;
       end

    endrule

    method data first() if(dataCounter > rewindCounter);
        return memory.sub(firstPtr);
    endmethod

    method Action commit(Maybe#(Bit#(TAdd#(1,TLog#(size)))) commitAmount); // no simultaneous rewind and commit  
        commitPulse.send;
        commitCommand <= commitAmount;
    endmethod

    method Action rewind() if(!commitPulse);  
        rewindPulse.send;
    endmethod

    method Action deq() if(dataCounter > rewindCounter);
        countDown.send;
    endmethod

    // issue here is what happens when we also commit... 
    // commit should probably happen last.  if only we could specifiy...
    method Action enq(data inData) if(dataCounter < fromInteger(valueof(size)));
     //   if(enqPtr == rewindPtr && dataCounter != 0)
     //   begin
     //       $display("Overwriting data");
     //       $finish;
     //   end

        countUp.send;
        memory.upd(enqPtr,inData);  
    endmethod


    method Bool notFull;
        return dataCounter < fromInteger(valueof(size));
    endmethod

    method Bool notEmpty;
        return dataCounter > rewindCounter;
    endmethod

    method Bool isLessThan   ( Bit#(TAdd#(1,TLog#(size))) c1 );
        return ( dataCounter - rewindCounter  < c1 );
    endmethod

    method Bool isGreaterThan( Bit#(TAdd#(1,TLog#(size))) c1 );
        return ( dataCounter - rewindCounter  > c1 );   
    endmethod

    method Bit#(TAdd#(1,TLog#(size))) count();
        return  dataCounter - rewindCounter;
    endmethod

endmodule