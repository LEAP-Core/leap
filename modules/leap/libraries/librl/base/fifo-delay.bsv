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
// Delay FIFO is useful for simulation and probably not useful for hardware.
// It imposes a delay of at least N cycles for messages flowing through the
// FIFO.  This may be useful for emulating hardware with latency (e.g. SDRAM).
//

// Note that the delay fifo is used only in software.  If it is ever
// used in hardware, if should be implemented using the SRL-based shift 
// register.

module [m] mkDelayFIFOF#(NumTypeParam#(n_DELAY_CYCLES) _p)
    // Interface:
    (FIFOF#(t_DATA))
    provisos (IsModule#(m, m__),
              Bits#(t_DATA, t_DATA_SZ));
    
    Integer nDelayCycles = valueOf(n_DELAY_CYCLES);
    
    // Buffer where messages are stored
    Reg#(Vector#(TAdd#(n_DELAY_CYCLES, 1), Maybe#(t_DATA))) buffer <-
        mkReg(replicate(tagged Invalid));

    // Signals
    RWire#(t_DATA) doEnq <- mkRWire();
    PulseWire doDeq <- mkPulseWire();
    PulseWire doClear <- mkPulseWire();

    //
    // Bubble values down and handle enq/deq.
    //
    (* fire_when_enabled, no_implicit_conditions *)
    rule bubble (True);
        Vector#(TAdd#(n_DELAY_CYCLES, 1), Maybe#(t_DATA)) b = buffer;
        
        //
        // Update based on method calls
        //

        if (doDeq)
        begin
            b[0] = tagged Invalid;
        end

        if (doEnq.wget() matches tagged Valid .val)
        begin
            b[nDelayCycles] = tagged Valid val;
        end

        if (doClear)
        begin
            b = replicate(tagged Invalid);
        end

        //
        // Values flow at most one slot per cycle.
        //
        for (Integer i = 0; i < nDelayCycles; i = i + 1)
        begin
            if (! isValid(b[i]))
            begin
                b[i] = b[i + 1];
                b[i + 1] = tagged Invalid;
            end
        end

        buffer <= b;
    endrule


    function Bool isNotFull() = ! isValid(buffer[nDelayCycles]);
    function Bool isNotEmpty() = isValid(buffer[0]);

    method Action enq(t_DATA val) if (isNotFull());
        doEnq.wset(val);
    endmethod

    method Action deq() if (isNotEmpty());
        doDeq.send();
    endmethod

    method t_DATA first() if (isNotEmpty());
        return validValue(buffer[0]);
    endmethod

    method Action clear;
        doClear.send();
    endmethod

    method Bool notFull = isNotFull();
    method Bool notEmpty = isNotEmpty();
endmodule
