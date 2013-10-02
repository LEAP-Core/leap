//
// Copyright (C) 2013 MIT
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
