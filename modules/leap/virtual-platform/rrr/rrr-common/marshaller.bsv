import Vector::*;
import FIFO::*;

`include "awb/provides/umf.bsh"

// RRR_MARSHALLER

// A marshaller takes one larger value and breaks it into a stream of n output chunks.
// Chunks are sent out starting from the LS chunk and ending with the MS chunk

interface RRR_MARSHALLER#(parameter type in_T, parameter type out_T);

    // Enq a new value
    method Action enq(in_T val, UMF_MSG_LENGTH num_chunks);

    // Look the next chunk.
    method out_T  first();

    // Deq the the chunk.
    method Action deq();

    method Bool notEmpty();
endinterface

module mkRRRMarshaller
    // interface:
        (RRR_MARSHALLER#(in_T, out_T))
    provisos
        (Bits#(in_T, in_SZ),
         Bits#(out_T, out_SZ),
         Div#(in_SZ, out_SZ, k__));

    // The number of chunks in the current message being marshalled
    // (this can be smaller than the absolute maximum because
    //  multiple methods can share a marshaller)
    Reg#(UMF_MSG_LENGTH) numChunks <- mkReg(0);
    
    // A vector to store the current chunks we're marshalling
    Reg#(Vector#(k__, Bit#(out_SZ))) chunks <- mkReg(Vector::replicate(0));
    
    // Are we done with the current value?
    Reg#(Bool) done <- mkReg(True);

    // enq
    
    // Add the chunk to the first place in the vector and
    // shift the other elements. Also set the max number of chunks
    // for the next operation.
    
    method Action enq(in_T val, UMF_MSG_LENGTH num_chunks) if (done);
    
        chunks <= toChunks(val);
        
        // assign numChunks
        numChunks <= num_chunks;
        
        // switch to dequeuing mode only if we have > 0 chunks
        if (num_chunks != 0)
        begin
            done <= False;
        end
      
    endmethod
    
    // first
    
    // Return the next chunk
    
    method out_T first() if (!done);
    
        Bit#(out_SZ) final_value = chunks[0];
      
        return unpack(final_value);
    
    endmethod
    
    // deq
    
    // Increment the index.
    
    method Action deq() if (!done);
    
        Bit#(out_SZ) dummy = ?;

        chunks <= shiftInAtN(chunks, dummy);
        done <= (numChunks == 1);
        numChunks <= numChunks - 1;
    
    endmethod

    // notEmpty

    method Bool notEmpty();
        return ! done;    
    endmethod
endmodule
