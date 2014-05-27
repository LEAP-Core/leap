`include "awb/provides/librl_bsv_base.bsh"

import FIFOF::*;

module mkStreamCaptureFIFOF#(Integer fifoSz) (FIFOF#(data_t))
  provisos(Bits#(data_t, data_sz),
           Literal#(data_t)); // required by bramfifo

  FIFOF#(data_t) fifo <- mkSizedBRAMFIFOF(fifoSz);
  Reg#(State) state <- mkReg(Filling);
   
  rule setState (!fifo.notFull && state != Draining); 
    state <= Draining; 
  endrule

  rule setFilling (!fifo.notEmpty && state != Filling); 
    state <= Filling; 
  endrule
  

  method data_t first() if(state == Draining);
    return fifo.first;
  endmethod

  method Action deq() if(state == Draining);
    fifo.deq; 
  endmethod

  method Action enq(data_t data) if(state == Filling); 
    fifo.enq(data);
  endmethod

  method notEmpty = fifo.notEmpty && state == Draining;
  method notFull = fifo.notFull && state == Filling;
  method Action clear;
    fifo.clear;
    state <= Filling;
  endmethod
endmodule
