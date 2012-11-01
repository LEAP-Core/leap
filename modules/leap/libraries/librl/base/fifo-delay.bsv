//
// Copyright (C) 2012 Intel Corporation
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

//
// Delay FIFO is useful for simulation and probably not useful for hardware.
// It imposes a delay of at least N cycles for messages flowing through the
// FIFO.  This may be useful for emulating hardware with latency (e.g. SDRAM).
//

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
