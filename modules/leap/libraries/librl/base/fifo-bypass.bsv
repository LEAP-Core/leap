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

// Preserves Bluespec's old BypassFIFO implementation.  In new
// versions of the compiler, they changed the semantics in a way that
// breaks legacy leap code.


import Vector::*;
import FIFOLevel::*;
import FIFO::*;
import FIFOF::*;
import RevertingVirtualReg::*;




// ================================================================
// 1-element "bypass FIFO".
// It's a 1-element FIFO (register with Valid/Invalid tag bit), where
//   - if full, can only deq, cannot enq, leaving it empty
//   - if empty, can
//     - either just enq, leaving it full
//     - or enq and deq simultaneously (logically: enq before deq), leaving it empty

module mkBypassFIFO (FIFO#(a))
   provisos (Bits#(a,sa));

   // STATE ----------------

   Reg#(Maybe#(a))   taggedReg <- mkReg (tagged Invalid); // the FIFO
   RWire#(a)         rw_enq    <- mkRWire;                // enq method signal
   PulseWire         pw_deq    <- mkPulseWire;            // deq method signal

   Bool enq_ok = (! isValid (taggedReg));
   Bool deq_ok = (isValid (taggedReg) || isValid (rw_enq.wget));

   // RULES ----------------

   rule rule_enq (rw_enq.wget matches tagged Valid .v &&& (! pw_deq));
     taggedReg <= tagged Valid v;
   endrule

   rule rule_deq (pw_deq);
     taggedReg <= tagged Invalid;
   endrule

   // INTERFACE ----------------

   method Action enq(v) if (enq_ok);
      rw_enq.wset(v);
   endmethod

   method Action deq() if (deq_ok);
      pw_deq.send ();
   endmethod

   method first() if (deq_ok);
      return (rw_enq.wget matches tagged Valid .v
              ? v
              : fromMaybe (?, taggedReg));
   endmethod

   method Action clear();
      taggedReg <= tagged Invalid;
   endmethod

endmodule


module mkBypassFIFOF (FIFOF#(a))
   provisos (Bits#(a,sa));

   // STATE ----------------

   Reg#(Maybe#(a))   taggedReg <- mkReg (tagged Invalid); // the FIFO
   RWire#(a)         rw_enq    <- mkRWire;                // enq method signal
   PulseWire         pw_deq    <- mkPulseWire;            // deq method signal

   Bool enq_ok = (! isValid (taggedReg));
   Bool deq_ok = (isValid (taggedReg) || isValid (rw_enq.wget));

   // RULES ----------------

   rule rule_enq (rw_enq.wget matches tagged Valid .v &&& (! pw_deq));
     taggedReg <= tagged Valid v;
   endrule

   rule rule_deq (pw_deq);
     taggedReg <= tagged Invalid;
   endrule

   // INTERFACE ----------------

   method Action enq(v) if (enq_ok);
      rw_enq.wset(v);
   endmethod

   method Action deq() if (deq_ok);
      pw_deq.send ();
   endmethod

   method first() if (deq_ok);
      return (rw_enq.wget matches tagged Valid .v
              ? v
              : fromMaybe (?, taggedReg));
   endmethod

   method notFull ();
      return enq_ok;
   endmethod

   method notEmpty ();
      return deq_ok;
   endmethod


   method Action clear();
      taggedReg <= tagged Invalid;
   endmethod

endmodule

