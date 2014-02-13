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

interface SYNC_PIPELINE#(parameter type t_IN, parameter type t_OUT);

    method Action operate(t_IN d);
    
    method t_OUT result();

endinterface


interface GUARDED_PIPELINE#(parameter type t_REQ, parameter type t_RSP);

    method Action makeReq(t_REQ t);
    
    method ActionValue#(t_RSP) getRsp();
    
endinterface


//
// mkGuardedPipeline --
//
// Turn a systolic pipeline that can drop responses if bluespec is not ready, into a safely wrapped,
// buffered pipeline. This uses the classic "counter and FIFO" approach.
//
module mkGuardedPipeline#(SYNC_PIPELINE#(t_IN, t_OUT) pipe)
    // interface:
        (GUARDED_PIPELINE#(t_IN, t_OUT))
    provisos
        (Bits#(t_OUT, t_OUT_SZ));

    // Buffer the responses so nothing is dropped.  Bypass FIFO has 0 cycle
    // latency for enq -> deq.  A bypass FIFO has only a single buffer slot,
    // so we chain two together in order to get two slots.  This gives us
    // single cycle read latency on BRAMs and the same buffering as a normal
    // FIFO.
    FIFO#(t_OUT)  buffer0 <- mkBypassFIFO();
    FIFOF#(t_OUT) buffer1 <- mkBypassFIFOF();

    // How much buffering is available?
    COUNTER#(2) bufferingAvailable <- mkLCounter(2);

    // enqIntoFIFO
    
    // When:   Some number of cycles after a req happens.
    // Effect: Put the response into the buffer.

    rule enqIntoFIFO (True);
        t_OUT data = pipe.result();
        buffer0.enq(data);
    endrule
    
    // Forward data between the two outgoing read buffers
    rule forwardData (True);
        let data = buffer0.first();
        buffer0.deq();
        buffer1.enq(data);
    endrule

    // put
    
    // When:   Any time that sufficient buffering is available 
    //         and the pipeline is ready.
    // Effect: Make the request and reserve the buffering spot.

    method Action makeReq(t_IN a) if (bufferingAvailable.value() > 0);
        pipe.operate(a);
        bufferingAvailable.down();
    endmethod

    // readRsp
    
    // When:   Any time there's something in the response buffer.
    // Effect: Deq the buffering and record the new space available.

    method ActionValue#(t_OUT) getRsp();
        bufferingAvailable.up();
        let v = buffer1.first();
        buffer1.deq();
        return v;
    endmethod

endmodule
