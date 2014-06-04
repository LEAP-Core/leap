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

import ConfigReg::*;

//
// The standard Bluespec "mkCounter" does not support simultaneous up/down
// calls.  This code, taken mostly from the Bluespec documentation does.
//
// The interface is extended with a few methods:
//   - isZero is True iff the counter's value was 0 at the start of a cycle.
//
interface COUNTER#(numeric type nBits);
    // The value at the beginning of the FPGA cycle.
    method Bit#(nBits) value();

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

    Wire#(Bit#(nBits)) upByW   <- mkUnsafeDWire(0);
    Wire#(Bit#(nBits)) downByW <- mkUnsafeDWire(0);
    RWire#(Bit#(nBits)) setcCalledW <- mkUnsafeRWire();

    (* fire_when_enabled, no_implicit_conditions *)
    rule updateCounter;
        Bit#(nBits) new_value;

        if (setcCalledW.wget() matches tagged Valid .v)
            new_value = v + upByW - downByW;
        else
            new_value = ctr + upByW - downByW;

        ctr <= new_value;
        zero <= (new_value == 0);
    endrule

    method Bit#(nBits) value();
        return ctr;
    endmethod

    method Action up();
        upByW <= 1;
    endmethod

    method Action upBy(Bit#(nBits) c);
        upByW <= c;
    endmethod

    method Action down();
        downByW <= 1;
    endmethod

    method Action downBy(Bit#(nBits) c);
        downByW <= c;
    endmethod

    method Action setC(Bit#(nBits) newVal);
        setcCalledW.wset(newVal);
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
