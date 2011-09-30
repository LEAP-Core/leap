`include "asim/provides/librl_bsv_base.bsh"

import FIFOF::*;

interface TriggeredStreamCaptureFIFOF#(type data_t);
  interface FIFOF#(data_t) fifof;
  method Action trigger();
endinterface

// We collect a number of samples past the trigger.
module mkTriggeredStreamCaptureFIFOF#(Integer streamSize) (TriggeredStreamCaptureFIFOF#(data_t))
  provisos(Bits#(data_t, data_sz));

  FIFOF#(data_t) fifoStore <- mkSizedFIFOF(streamSize + 1);
  Reg#(State) state <- mkReg(Filling);
  Reg#(Bit#(32)) elementCount <- mkReg(0);  
  PulseWire deqPulse <- mkPulseWire;
  PulseWire triggerPulse <- mkPulseWire;

  if(streamSize > 4000000000)
    begin
      error("Unsupported stream size in triggered fifo");
    end

  rule cycle (deqPulse && state == Filling);
    fifoStore.deq;
    if(`DEBUG_STREAM_CAPTURE_FIFO == 1) 
      begin
        $display("TrigFIFO: Droppin Data");
      end
  endrule

  rule setTrigger(triggerPulse);
    if(`DEBUG_STREAM_CAPTURE_FIFO == 1) 
      begin
        $display("TrigFIFO: setting trigger");
      end
    state <= Draining;
  endrule

  rule setFilling (!fifoStore.notEmpty && state == Draining); 
    state <= Filling; 
    elementCount <= 0;
  endrule
  

  interface FIFOF fifof;
    method data_t first() if(state == Draining);
      return fifoStore.first;
    endmethod

    method Action deq() if(state == Draining);
      fifoStore.deq; 
    endmethod

    method Action enq(data_t data) if(state == Filling); 
      if(elementCount <  fromInteger(streamSize)) 
        begin
          elementCount <= elementCount + 1;
        end
      else // need to deq
        begin
          deqPulse.send;
        end
      fifoStore.enq(data);
    endmethod

    method notEmpty = fifoStore.notEmpty;

    method Bool notFull();
      return fifoStore.notFull && (elementCount < fromInteger(streamSize));
    endmethod

    method Action clear; // This method needs some fixing
      fifoStore.clear;
      elementCount <= 0;
      state <= Filling;
    endmethod
  endinterface

  method Action trigger();
   if(elementCount == fromInteger(streamSize) && state != Draining)
     begin
       triggerPulse.send;
     end
  endmethod
endmodule