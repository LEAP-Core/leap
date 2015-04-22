import Vector::*;
import FIFO::*;

`include "awb/provides/umf.bsh"
`include "awb/provides/librl_bsv_base.bsh"

// Demarshaller

// A de-marshaller takes n input "chunks" and produces one larger value.
// Chunks are received starting from the MS chunk and ending with the LS chunk

// Overall RRR service-stub flow control primarily lives in this code.
// The stub itself initiates a demarshalling sequence by calling "start"
// and passing in the number of chunks after which the demarshaller should
// activate the output. The demarshaller will not accept a new start
// request until the previous sequence has been read out. The stub itself
// does not have to explicitly maintain any other flow-control related
// state.

// types
typedef enum
{
    STATE_idle,
    STATE_queueing
}
RRR_DEMARSHALLER_STATE
    deriving(Bits, Eq);

// interface
interface RRR_DEMARSHALLER#(parameter type in_T, parameter type out_T);
    
    // start a demarshalling sequence
    method Action start(UMF_MSG_LENGTH nchunks);
        
    // insert a chunk
    method Action insert(in_T chunk);
        
    // read the whole completed value and delete it
    method ActionValue#(out_T) readAndDelete();

    // read the whole completed value
    method out_T peek();


    // Below method are for debugging. 

    // lists current state of demarshaller 
    method RRR_DEMARSHALLER_STATE getState();

    // Lists wheter marshaller has data.
    method Bool notEmpty();

endinterface

// module
module mkRRRDemarshaller
    // interface:
        (RRR_DEMARSHALLER#(in_T, Vector#(n_CHUNKS,in_T)))
    provisos
        (Bits#(in_T, in_SZ));
    
    // =============== state ================
    
    // shift register we fill up as chunks come in.
    Reg#(Vector#(n_CHUNKS, in_T))chunks <- mkRegU();
    
    // number of chunks remaining in current sequence
    Reg#(UMF_MSG_LENGTH) chunksRemaining <- mkReg(0);
    
    // demarshaller state
    Reg#(RRR_DEMARSHALLER_STATE) state <- mkReg(STATE_idle);
    
    // =============== methods ===============
    
    // start a demarshalling sequence
    method Action start(UMF_MSG_LENGTH nchunks) if (state == STATE_idle);
        
        // initialize number of chunks in sequence
        chunksRemaining <= nchunks;
        state <= STATE_queueing;
        
    endmethod
    
    // add the chunk to the first place in the vector and
    // shift the other elements.
    method Action insert(in_T chunk) if (state == STATE_queueing &&
                                         chunksRemaining != 0);
    
        chunks <= shiftInAt0(chunks, chunk); 
        
        // decrement chunks remaining
        chunksRemaining <= chunksRemaining - 1;

    endmethod
    
    // return the entire vector
    method ActionValue#(Vector#(n_CHUNKS,in_T)) readAndDelete() if (state == STATE_queueing &&
                                                                    chunksRemaining == 0);

        // switch to idle state
        state <= STATE_idle;

        return chunks;

    endmethod

    // return the entire vector
    method Vector#(n_CHUNKS,in_T) peek() if (state == STATE_queueing &&
                                             chunksRemaining == 0);

        return chunks;
    endmethod

    // Just return state.
    method getState = state;

    // returns wether we have a complete data in the demarshaller.
    method notEmpty = (state == STATE_queueing && chunksRemaining == 0);

endmodule
