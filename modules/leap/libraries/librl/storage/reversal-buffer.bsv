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

import RegFile::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;

// here ctrl_t represents a count as to the number of data that are rolling through th pipeline.

interface ReversalBuffer#(type data_t, type ctrl_t, numeric type reversal_granularity);
    interface Put#(Tuple2#(ctrl_t,data_t))   inputData;
    interface Get#(Tuple2#(ctrl_t,data_t))   outputData;
endinterface

typedef enum {
    WriteUp, // 0 -> reversalGranularity
    WriteDown // reversalGranularity -> 0
} WriteDirection deriving (Eq,Bits);


typeclass ReversalBufferCtrl #(type a);
    function Bool isLast(a x);
    function Bool isData(a x);
endtypeclass

instance ReversalBufferCtrl#(Bool);
    function Bool isLast(Bool x); 
        return x; 
    endfunction 

    function Bool isData(Bool x); 
        return !x; 
    endfunction 
endinstance

typedef enum {
    Data,
    Flush,
    SendLast
} ReversalBufferState deriving (Bits,Eq);

// There's probably a fair bit of optimization that can be done here.  
// Perhaps some rainy day, I'll come back to it.
module mkReversalBuffer#(String str) (ReversalBuffer#(data_t, ctrl_t, reversal_granularity))
    provisos(
        Bits#(data_t, data_size),
        Bits#(ctrl_t, ctrl_size),
	ReversalBufferCtrl#(ctrl_t),
        Log#(reversal_granularity, log_reversal_granularity_minus),
        Add#(log_reversal_granularity_minus, 1, log_reversal_granularity), // XXX This isn't what we wanted to have. This is Log#(n+1) - 1. It's okay for powers of two
        Add#(log_reversal_granularity_minus, aaa, data_size),
        Add#(log_reversal_granularity, xxx,  data_size)         
    );

    // Keeping all the excess ctrl_t around is probably not necessary and 
    // should be fixed at some point
    RegFile#(Bit#(log_reversal_granularity_minus),Tuple2#(ctrl_t,data_t)) rfile <- mkRegFileWCF(0,fromInteger(valueof(reversal_granularity) - 1));  

    // Module state
    FIFO#(Tuple2#(ctrl_t,data_t))                      inQ <- mkLFIFO; 
    Reg#(WriteDirection) writeDirection                    <- mkReg(WriteUp);
    FIFO#(Tuple2#(ctrl_t,data_t)) outfifo                  <- mkFIFO;
    Reg#(Bit#(log_reversal_granularity)) writeCount        <- mkReg(fromInteger(valueof(reversal_granularity)));  
    Reg#(Bit#(log_reversal_granularity_minus)) kBitsBottom <- mkReg(0);  
    Reg#(Bool) readLast                                    <- mkReg(False);
    Reg#(ReversalBufferState) state                        <- mkReg(Data);      

    match {.ctrl, .nextData} = inQ.first;
  
    Reg#(Bit#(32)) dataIn  <- mkReg(0);
    Reg#(Bit#(32)) dataOut <- mkReg(0);
    Reg#(Bit#(32)) lastIn  <- mkReg(0);
    Reg#(Bit#(32)) lastOut <- mkReg(0);


    Bit#(log_reversal_granularity) writeCountNext =  writeCount - 1;
    Bit#(log_reversal_granularity_minus) addr = (writeDirection == WriteUp)?truncate(~(writeCount - 1)):
									  truncate( (writeCount - 1));

    rule readLastSet(state == Flush);
        if(`DEBUG_REVBUF == 1)
        begin
            $display("%s: Read last: count: %d returning Data: %h: read from: %d",str, writeCount,rfile.sub(addr), addr);
        end

        outfifo.enq(rfile.sub(addr));
        if(readLast && (writeCountNext == 0))
        begin
           readLast <= False;
           writeDirection <= (writeDirection == WriteUp) ? WriteDown : WriteUp;
           writeCount <= zeroExtend(kBitsBottom); 
        end
        else if(writeCountNext == 0) // done with the flush
        begin
            if(`DEBUG_REVBUF == 1)
            begin
                $display("%s: Completing buffer!",str);
            end

            readLast <= False;
            writeCount <= fromInteger(valueof(reversal_granularity));
            state <= SendLast;
        end
        else
        begin
            writeCount <= writeCountNext;
        end
  endrule
  
 
    // Need one last rule to spit out the Last Token...
    // Can assert isLast here...
    rule handleLast(state == SendLast);
        if(`DEBUG_REVBUF == 1)
        begin  
            $display("%s: sending last", str);
        end

        state <= Data;
        inQ.deq;
        outfifo.enq(inQ.first);
    endrule

    // due to the write down, we are getting slightly screwed on edge cases...

    rule handleInputLast(state == Data && isLast(ctrl));
        if(isLast(ctrl))
        begin
            if(`DEBUG_REVBUF == 1)
            begin
                $display("%s: Got Last",str);
            end

            let remainder = fromInteger(valueOf(reversal_granularity)) - writeCount;
            kBitsBottom <= truncate(remainder);
            if(!readLast && writeCount == fromInteger(valueOf(reversal_granularity))) // Inexplicably no data...
            begin
                state <= SendLast;
            end
            else if(!readLast)
            begin
                state<=Flush;
                // kBitsBottom can be calculated based on WriteCount
                writeDirection <= (writeDirection == WriteUp) ? WriteDown : WriteUp;
                writeCount <= (writeCount == fromInteger(valueOf(reversal_granularity))) ? fromInteger(valueOf(reversal_granularity)): remainder; 
                readLast <= False;
            end
            else if(writeCount == fromInteger(valueOf(reversal_granularity)))
            begin
                state<=Flush;
                // kBitsBottom can be calculated based on WriteCount
                //writeDirection <= (writeDirection == WriteUp) ? WriteUp : WriteUp; //Already did this...
                writeCount <= (writeCount == fromInteger(valueOf(reversal_granularity))) ? fromInteger(valueOf(reversal_granularity)): remainder; 
                readLast <= False;
            end
            else
            begin
                state <= Flush;
                //writeCount <= writeCountNext;
            end
        end   
    endrule

    rule handle_input(state == Data && isData(ctrl));
        inQ.deq;
        // Since reading is incrementing our count, we can only finish at an appropriate time
        // unless we're at the end of packet condition.  The rule will handle this condition.
  
        if(writeCountNext == 0)   
        begin
            writeDirection <= (writeDirection == WriteUp) ? WriteDown : WriteUp;
            writeCount <= fromInteger(valueof(reversal_granularity));
            readLast <= True;
            // We should somehow update the write count;
        end
        else
        begin
            writeCount <= writeCountNext;
        end 

        if(`DEBUG_REVBUF == 1)
        begin
            $display("%s: Got Data: %h Wrote to: %d", str,  nextData, addr);
        end

        rfile.upd(addr, inQ.first);

        if(readLast)
        begin
            if(`DEBUG_REVBUF == 1)
            begin
                $display("%s: Pushing Data: %h read from: %d",str, rfile.sub(addr), addr);
            end

            outfifo.enq(rfile.sub(addr));
        end
    endrule 
    
    interface Put inputData;
        method Action put(Tuple2#(ctrl_t,data_t) value);
            let lastInNext = lastIn;
            let dataInNext = dataIn;
 
            if(!isLast(tpl_1(value)))
            begin
                dataInNext = dataIn + 1;
            end
            else
            begin
                lastInNext = lastIn + 1;
            end

            dataIn <= dataInNext;
            lastIn <= lastInNext;

            if(`DEBUG_REVBUF == 1)
            begin
                $display("%s: DataIn: %d LastIn: %d", str , dataInNext, lastInNext);
            end

            inQ.enq(value);
        endmethod
    endinterface

    interface Get outputData;
        method ActionValue#(Tuple2#(ctrl_t,data_t)) get();
            match {.ctrl, .data} = outfifo.first;
      	    let lastOutNext = lastOut;
      	    let dataOutNext = dataOut;
      	    if(!isLast(ctrl))
            begin
		dataOutNext = dataOut + 1;
            end
      	    else
            begin
                lastOutNext = lastOut + 1;
            end

	    dataOut <= dataOutNext;
      	    lastOut <= lastOutNext;

      	    if(`DEBUG_REVBUF == 1)
            begin
                $display("%s: DataOut: %d LastOut: %d Returning Data: %d, %h ",str, dataOutNext, lastOutNext, ctrl, data);
            end

	    outfifo.deq;
            return outfifo.first();
        endmethod
    endinterface

endmodule























