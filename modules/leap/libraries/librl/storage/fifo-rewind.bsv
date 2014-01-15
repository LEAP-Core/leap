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

import GetPut::*;
import ConfigReg::*;
import DReg::*;

`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv_base.bsh"

function Get#(fifo_type) rewindFifoToGet(RewindFIFO#(fifo_type,size) fifo);
    Get#(fifo_type) f = interface Get#(fifo_type);
                            method ActionValue#(fifo_type) get();
                                fifo.deq;
                                return fifo.first;
                            endmethod
                        endinterface;
    return f;
endfunction

function Put#(fifo_type) rewindFifoToPut(RewindFIFO#(fifo_type,size) fifo);
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

//
// This FIFO allows the partial commit of values.  Values are not seen at the
// output until commit is called.
//
// Yet another variant on the ever popular ring buffer.
//

interface RewindFIFO#(type t_DATA, numeric type t_SIZE);
    method t_DATA first();
    method Action commit();
    method Action rewind();
    method Action deq();
    method Action enq(t_DATA inData);
    method Bool notFull;
    method Bool notEmpty;
endinterface

interface RewindFIFOLevel#(type t_DATA, numeric type t_SIZE);
    method t_DATA first();
    method Action commit();
    method Action rewind();
    method Action deq();
    method Action enq(t_DATA inData);
    method Bool notFull;
    method Bool notEmpty;
    method Bool isLessThan   (Bit#(TAdd#(1, TLog#(t_SIZE))) c1) ;
    method Bool isGreaterThan(Bit#(TAdd#(1, TLog#(t_SIZE))) c1) ;
    method Bit#(TAdd#(1, TLog#(t_SIZE))) count();
endinterface

interface RewindFIFOVariableCommitLevel#(type t_DATA, numeric type t_SIZE);
    method t_DATA first();
    method Action commit(Maybe#(Bit#(TAdd#(1, TLog#(t_SIZE)))) commitAmount);
    method Action rewind();
    method Action deq();
    method Action enq(t_DATA inData);
    method Bool notFull;
    method Bool notEmpty;
    method Bool isLessThan   (Bit#(TAdd#(1, TLog#(t_SIZE))) c1) ;
    method Bool isGreaterThan(Bit#(TAdd#(1, TLog#(t_SIZE))) c1) ;
    method Bit#(TAdd#(1, TLog#(t_SIZE))) count();
endinterface


/* Note deq/enq happens logically before commit... */

//
// mkRewindFIFOVariableCommitLevel --
//   FIFO with state buffered even after deq() until committed.  The state
//   is stored in LUTRAM.
//
module mkRewindFIFOVariableCommitLevel
    // Interface:
    (RewindFIFOVariableCommitLevel#(t_DATA, t_SIZE))
    provisos(
        Bits#(t_DATA, t_DATA_SZ)
    );

    let _r <- mkRewindFIFOVariableCommitLevelImpl(False);
    return _r;
endmodule

//
// mkRewindBRAMFIFOVariableCommitLevel --
//   Same as mkRewindFIFOVariableCommitLevel but buffered state is stored
//   in block RAM.
//
module mkRewindBRAMFIFOVariableCommitLevel
    // Interface:
    (RewindFIFOVariableCommitLevel#(t_DATA, t_SIZE))
    provisos(
        Bits#(t_DATA, t_DATA_SZ)
    );

    let _r <- mkRewindFIFOVariableCommitLevelImpl(True);
    return _r;
endmodule


//
// Internal implementation of the rewind FIFO.
//
module mkRewindFIFOVariableCommitLevelImpl#(Bool useBRAM)
    // Interface:
    (RewindFIFOVariableCommitLevel#(t_DATA, t_SIZE))
    provisos(
        Bits#(t_DATA, t_DATA_SZ),
        Alias#(t_IDX, Bit#(TAdd#(1, TLog#(t_SIZE))))
    );

    //
    // Memory is such a small part of the logic that we implement either
    // LUTRAM or BRAM in the same module.  One will be NULL.
    //
    MEMORY_IFC#(t_IDX, t_DATA) memoryB = ?;
    LUTRAM#(t_IDX, t_DATA) memoryL = ?;
    if (useBRAM)
        memoryB <- mkBRAM();
    else
        memoryL <- mkLUTRAMU();

    Reg#(t_IDX)          firstPtr      <- mkConfigReg(0);
    Reg#(t_IDX)          rewindPtr     <- mkConfigReg(0);
    Reg#(t_IDX)          enqPtr        <- mkConfigReg(0);
    // Total live data in fifo (including rewind amount)
    Reg#(t_IDX)          dataCounter   <- mkReg(0);
    // Amount that has been dequeued, but subject to rewind.
    Reg#(t_IDX)          rewindCounter <- mkReg(0);
    // Enq this cycle?
    RWire#(t_DATA)       enqW          <- mkRWire;
    PulseWire            countDown     <- mkPulseWire;
    PulseWire            commitPulse   <- mkPulseWire;
    Wire#(Maybe#(t_IDX)) commitCommand <- mkDWire(tagged Invalid);
    PulseWire            rewindPulse   <- mkPulseWire;
    // Set during update phase to the value that will be in firstPtr next cycle
    Wire#(t_IDX)         nextFirstPtrW <- mkBypassWire;

    let commitDistance = fromMaybe(rewindCounter, commitCommand);

    (* fire_when_enabled, no_implicit_conditions *)
    rule updateState (True);
        // Data counter retains the true count of data in the fifo.
        // It can only be modified by enq and commit.

        Bool countUp = isValid(enqW.wget);

        if (countUp && !commitPulse) // enq
        begin
            dataCounter <= dataCounter + 1;
        end
        else if (commitPulse && !countUp) //  commit.
        begin
            dataCounter <= dataCounter - commitDistance;
        end
        else if (commitPulse && countUp) // enq +  commit.
        begin
           dataCounter <= dataCounter - commitDistance + 1;
        end


        // Rewind counter retains the count of data speculatively
        // dequeued from the fifo. It can only be modified by deq,
        // commit, and rewind.

        if (rewindPulse) // set to zero.
        begin
            rewindCounter <= 0;
        end
        else if (commitPulse && !countDown)
        begin
            rewindCounter <= rewindCounter - commitDistance;
        end
        else if (commitPulse && countDown)
        begin
            rewindCounter <= rewindCounter - commitDistance + 1;
        end
        else if (countDown)
        begin
            rewindCounter <= rewindCounter + 1;
        end

        // Enq Ptr just counts up
        if (countUp)
        begin
            enqPtr <= enqPtr + 1;
        end


        // Rewind Pointer points to the last committed location.  It can
        // only change on a commit.

        if (commitPulse)
        begin
            rewindPtr <= rewindPtr + commitDistance;
        end

        // First pointer points to the next value to be deqeued.
        // It can change on an update and on a rewind.

        let next_first_ptr = firstPtr;

        if (rewindPulse)
        begin
            next_first_ptr = rewindPtr;
        end
        else if (countDown)
        begin
            next_first_ptr = firstPtr + 1;
        end

        firstPtr <= next_first_ptr;
        nextFirstPtrW <= next_first_ptr;

        if (`DEBUG_REWIND_FIFO == 1)
        begin
            $display("RwFIFO: firstPtr: %h, rwPtr: %h, enqPtr: %h, rwCnt: %h, dataCnt: %h", firstPtr, rewindPtr, enqPtr, rewindCounter, dataCounter);
            $display("RwFIFO: countUp: %d, countDown: %d, commmitPulse: %d, rewindPulse: %d, commitDistance: %d", countUp, countDown, commitPulse, rewindPulse, commitDistance);
        end

        // some simple checks
        if ((enqPtr > rewindPtr) && (enqPtr - rewindPtr != dataCounter))
        begin
            $display("Data being dropped >, enqPtr - rewindPtr != dataCounter");
            $finish;
        end

        if (enqPtr == rewindPtr && !(dataCounter == 0 || dataCounter == fromInteger(valueof(t_SIZE))))
        begin
            $display("Data being dropped=, enqPtr - rewindPtr != dataCounter");
            $finish;
        end

        // data at head of queue + (data at tail of queue)
        if (enqPtr < rewindPtr && !({1'b0,dataCounter} == {0,enqPtr} + (fromInteger(valueof(TExp#(TAdd#(1, TLog#(t_SIZE))))) - {0,rewindPtr})))
        begin
            $display("Data being dropped<, enqPtr - rewindPtr (%d) != dataCounter (%d)", enqPtr + fromInteger(valueof(t_SIZE)) - rewindPtr, dataCounter);
            $finish;
        end

        // Same assertions about rw and first

        if ((firstPtr > rewindPtr) && (firstPtr - rewindPtr != rewindCounter))
        begin
            $display("Data being dropped >, firstPtr - rewindPtr != rewindCounter");
            $finish;
        end

        if (firstPtr == rewindPtr && !(rewindCounter == 0 || rewindCounter == fromInteger(valueof(t_SIZE))))
        begin
            $display("Data being dropped=, firstPtr - rewindPtr != rewindCounter");
            $finish;
        end

        // data at head of queue + (data at tail of queue)
        if (firstPtr < rewindPtr && !({1'b0,rewindCounter} == {0,firstPtr} + (fromInteger(valueof(TExp#(TAdd#(1, TLog#(t_SIZE))))) - {0,rewindPtr})))
        begin
            $display("Data being dropped<, firstPtr - rewindPtr != rewindCounter");
            $finish;
        end

       if (dataCounter > fromInteger(valueof(t_SIZE)))
       begin
            $display("Too much data!");
            $finish;
       end

       if (rewindCounter > fromInteger(valueof(t_SIZE)))
       begin
            $display("Too much data to be rewound!");
            $finish;
       end

       if (rewindCounter > dataCounter)
       begin
            $display("rewind counter larger than data counter!");
            $finish;
       end

       // An illegal commit distance?
       if (commitDistance > rewindCounter)
       begin
           $display("Illegal commit distance %d.  Maximum was %d", commitDistance, rewindCounter);
           $finish;
       end

    endrule

    //
    // Code specific to memory type.  These feed the first() method below.
    //
    Wire#(t_DATA) firstW <- mkWire();
    Reg#(Maybe#(t_DATA)) memBypass <- mkDReg(tagged Invalid);

    if (useBRAM)
    begin
        // BRAM operates over two cycles.  Speculatively fetch the next
        // head of the FIFO.
        (* fire_when_enabled *)
        rule fetchFirstReq (True);
            // Did enq() just write to the first pointer location?
            if (isValid(enqW.wget) && (enqPtr == nextFirstPtrW))
            begin
                // Yes -- bypass BRAM.  memBypass is a DReg and will hold its
                // value only for the next cycle.
                memBypass <= enqW.wget;
            end
            else
            begin
                // No -- request value from BRAM
                memoryB.readReq(nextFirstPtrW);
            end
        endrule

        // Consume the previous cycle's speculative fetch and, if appropriate,
        // forward it to the first() method.  The bypass has priority over
        // the BRAM.
        (* fire_when_enabled, no_implicit_conditions *)
        rule fetchFirstBypass (memBypass matches tagged Valid .data);
            if (dataCounter > rewindCounter)
            begin
                firstW <= data;
            end
        endrule

        (* fire_when_enabled *)
        rule fetchFirstRsp (! isValid(memBypass));
            let data <- memoryB.readRsp();
            if (dataCounter > rewindCounter)
            begin
                firstW <= data;
            end
        endrule
    end
    else
    begin
        // LUTRAM is easy -- read it the cycle it is consumed.
        (* fire_when_enabled *)
        rule fetchFirstL (dataCounter > rewindCounter);
            firstW <= memoryL.sub(firstPtr);
        endrule
    end

    method t_DATA first();
        return firstW;
    endmethod

    method Action commit(Maybe#(t_IDX) commitAmount); // no simultaneous rewind and commit
        commitPulse.send;
        commitCommand <= commitAmount;
    endmethod

    method Action rewind() if (!commitPulse);
        rewindPulse.send;
    endmethod

    method Action deq() if (dataCounter > rewindCounter);
        countDown.send;
    endmethod

    // issue here is what happens when we also commit...
    // commit should probably happen last.  if only we could specifiy...
    method Action enq(t_DATA inData) if (dataCounter < fromInteger(valueof(t_SIZE)));
     //   if (enqPtr == rewindPtr && dataCounter != 0)
     //   begin
     //       $display("Overwriting data");
     //       $finish;
     //   end

        enqW.wset(inData);

        // Only one of these memories will be implemented
        memoryB.write(enqPtr, inData);
        memoryL.upd(enqPtr, inData);
    endmethod


    method Bool notFull;
        return dataCounter < fromInteger(valueof(t_SIZE));
    endmethod

    method Bool notEmpty;
        return dataCounter > rewindCounter;
    endmethod

    method Bool isLessThan   (t_IDX c1);
        return (dataCounter - rewindCounter  < c1);
    endmethod

    method Bool isGreaterThan(t_IDX c1);
        return (dataCounter - rewindCounter  > c1);
    endmethod

    method t_IDX count();
        return  dataCounter - rewindCounter;
    endmethod

endmodule
