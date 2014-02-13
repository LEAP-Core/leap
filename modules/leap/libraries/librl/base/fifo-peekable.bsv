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


//
// PEEKABLE_FIFO is a FIFO that enables peeking an arbitrary object
// in the FIFO.
//

interface PEEKABLE_FIFOF#(type t_DATA, numeric type n_ENTRIES);
    method Action enq(t_DATA val);
    method Action deq();
    method t_DATA first();
    method Action clear();
    method Maybe#(t_DATA) peekElem(Bit#(TLog#(n_ENTRIES)) idx);
    method Bool notEmpty();
    method Bool notFull();
endinterface


//
// mkPeekableFIFO --
//   A peekable FIFO that enables peeking an arbitrary object in the FIFO.  
//

module mkPeekableFIFOF
    // Interface:
    (PEEKABLE_FIFOF#(t_DATA, n_ENTRIES))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    Reg#(FUNC_FIFO#(t_DATA, n_ENTRIES)) fifo <- mkReg(funcFIFO_Init());

    //
    // updateState --
    //     Combine deq and enq requests into an update of the FIFO state.
    //
    RWire#(t_DATA) enqData <- mkRWire();
    PulseWire deqReq <- mkPulseWire();
    PulseWire clearReq <- mkPulseWire();
    
    (* fire_when_enabled, no_implicit_conditions *)
    rule updateState (True);
        FUNC_FIFO#(t_DATA, n_ENTRIES) new_fifo_state = fifo;

        // DEQ requested?
        if (deqReq)
        begin
            new_fifo_state = funcFIFO_UGdeq(new_fifo_state);
        end

        // ENQ requested?
        if (enqData.wget() matches tagged Valid .data)
        begin
            new_fifo_state = funcFIFO_UGenq(new_fifo_state, data);
        end

        if(clearReq)
        begin
            new_fifo_state = funcFIFO_Init();
        end

        fifo <= new_fifo_state;

    endrule

    
    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action enq(t_DATA data) if (funcFIFO_notFull(fifo));
        enqData.wset(data);
    endmethod

    method Action deq() if (funcFIFO_notEmpty(fifo));
        deqReq.send();
    endmethod
    
    method t_DATA first() if (funcFIFO_notEmpty(fifo));
        return funcFIFO_UGfirst(fifo);
    endmethod

    method Action clear();
        clearReq.send();
    endmethod

    method Maybe#(t_DATA) peekElem(Bit#(TLog#(n_ENTRIES)) idx);
        return funcFIFO_peek(fifo, idx);
    endmethod

    method Bool notEmpty();
        return funcFIFO_notEmpty(fifo);
    endmethod

    method Bool notFull();
        return funcFIFO_notFull(fifo);
    endmethod

endmodule
