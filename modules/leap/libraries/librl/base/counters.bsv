//
// Copyright (C) 2008 Intel Corporation
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

import ConfigReg::*;

//
// The standard Bluespec "mkCounter" does not support simultaneous up/down
// calls.  This code, taken mostly from the Bluespec documentation does.
//
// The interface is extended with a few methods:
//   - updatedValue returns the value after up/down/etc. have been applied.
//   - isZero is True iff the counter's value was 0 at the start of a cycle.
//
interface COUNTER#(numeric type nBits);
    // The value at the beginning of the FPGA cycle.
    method Bit#(nBits) value();
    // The value at the end of the FPGA cycle, updated by calls to up/down/set.
    method Bit#(nBits) updatedValue();

    method Action up();
    method Action upBy(Bit#(nBits) c);

    method Action down();
    method Action downBy(Bit#(nBits) c);

    method Action setC(Bit#(nBits) newVal);

    // Is value() zero?
    method Bool isZero();
endinterface: COUNTER


module mkLCounter#(Bit#(nBits) initialValue)
    // interface:
        (COUNTER#(nBits));

    // Counter value
    Reg#(Bit#(nBits)) ctr <- mkConfigReg(initialValue);
    // Is counter 0?
    Reg#(Bool) zero <- mkConfigReg(initialValue == 0);

    Wire#(Bit#(nBits)) up_by   <- mkUnsafeDWire(0);
    Wire#(Bit#(nBits)) down_by <- mkUnsafeDWire(0);
    RWire#(Bit#(nBits)) setc_called <- mkUnsafeRWire();

    function newValue();
        Bit#(nBits) new_value;

        if (setc_called.wget() matches tagged Valid .v)
            new_value = v + up_by - down_by;
        else
            new_value = ctr + up_by - down_by;

        return new_value;
    endfunction

    (* fire_when_enabled, no_implicit_conditions *)
    rule updateCounter;
        let new_value = newValue();
        ctr <= new_value;
        zero <= (new_value == 0);
    endrule

    method Bit#(nBits) value();
        return ctr;
    endmethod

    method Bit#(nBits) updatedValue();
        return newValue();
    endmethod

    method Action up();
        up_by <= 1;
    endmethod

    method Action upBy(Bit#(nBits) c);
        up_by <= c;
    endmethod

    method Action down();
        down_by <= 1;
    endmethod

    method Action downBy(Bit#(nBits) c);
        down_by <= c;
    endmethod

    method Action setC(Bit#(nBits) newVal);
        setc_called.wset(newVal);
    endmethod

    method Bool isZero();
        return zero;
    endmethod
endmodule: mkLCounter


//
// COUNTER_Z used to be a separate interface and implementation.  It is now
// common with the standard counter.  This code is left for compatibility.
//
typedef COUNTER#(nBits) COUNTER_Z#(numeric type nBits);


module mkLCounter_Z#(Bit#(nBits) initialValue)
    // interface:
        (COUNTER_Z#(nBits));

    let c <- mkLCounter(initialValue);
    return c;

endmodule: mkLCounter_Z
