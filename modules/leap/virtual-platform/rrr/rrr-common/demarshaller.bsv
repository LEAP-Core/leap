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
STATE
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

endinterface

// module
module mkRRRDemarshaller
    // interface:
        (RRR_DEMARSHALLER#(in_T, out_T))
    provisos
        (Bits#(in_T, in_SZ),
         Bits#(out_T, out_SZ),
         Div#(out_SZ, in_SZ, n_CHUNKS));
    
    // =============== state ================
    
    // shift register we fill up as chunks come in.
    Reg#(Vector#(n_CHUNKS, Bit#(in_SZ))) chunks <- mkRegU();
    
    // number of chunks remaining in current sequence
    Reg#(UMF_MSG_LENGTH) chunksRemaining <- mkReg(0);
    
    // demarshaller state
    Reg#(STATE) state <- mkReg(STATE_idle);
    
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
    
        // newer chunks are closer to the LSB.
        chunks <= shiftInAt0(chunks, pack(chunk));
        
        // decrement chunks remaining
        chunksRemaining <= chunksRemaining - 1;
        
    endmethod
    
    // return the entire vector
    method ActionValue#(out_T) readAndDelete() if (state == STATE_queueing &&
                                                   chunksRemaining == 0);

        // switch to idle state
        state <= STATE_idle;

        // return
        Bit#(out_SZ) final_val = truncateNP(pack(chunks));
        return unpack(final_val);

    endmethod

    // return the entire vector
    method out_T peek() if (state == STATE_queueing &&
                            chunksRemaining == 0);

        Bit#(out_SZ) final_val = truncateNP(pack(chunks));
        return unpack(final_val);

    endmethod

endmodule
