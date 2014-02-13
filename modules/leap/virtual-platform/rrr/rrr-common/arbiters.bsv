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

import Vector::*;
import FIFO::*;

// Arbiters

// An arbiter takes a bit-vector of n Requests and returns a bit-vector
// of n Grant signals.

// interface
interface ARBITER#(numeric type bits_T);

    // arbitrate
    method Maybe#(UInt#(TLog#(bits_T))) arbitrate(Bit#(bits_T) request);

endinterface

// === static priority arbiter ===

module mkStaticArbiter
    // interface:
        (ARBITER#(bits_T))
    provisos (Log#(bits_T, TLog#(bits_T)));
    
    method Maybe#(UInt#(TLog#(bits_T))) arbitrate(Bit#(bits_T) request);
        
        Vector#(bits_T, Bit#(1)) req_v = unpack(request);
        return findElem(1, req_v);

    endmethod
    
endmodule

// 
// Wrapper for RR arbiter - with size 1, we can simply build a static 
// arbiter.
//
module mkRoundRobinArbiter
    // interface:
    (ARBITER#(bits_T))
    provisos (Log#(bits_T, TLog#(bits_T)));
    ARBITER#(bits_T) arbiter = ?;
    if(valueof(bits_T) < 2) 
      begin
        arbiter <- mkStaticArbiter();
      end
    else
      begin 
        arbiter <- mkRoundRobinArbiterMultiBit();
      end

    return arbiter;
endmodule

//
// Round-robin arbiter
//
module mkRoundRobinArbiterMultiBit
    // interface:
    (ARBITER#(bits_T))
    provisos (Log#(bits_T, TLog#(bits_T)));

    Reg#(Bit#(bits_T)) curPrio <- mkReg(1);
    Reg#(Bit#(bits_T)) curPrioMask <- mkReg(0);
    
    (* fire_when_enabled *)
    rule rotate_priority (True);
        // Rotate priority mask every cycle
        Bit#(bits_T) prioNext = truncate({curPrio, curPrio} >> 1); 
        curPrio <= prioNext;
        curPrioMask <= prioNext - 1; // need to break the carry chain for large bit sizes
    endrule

    //
    // Choose the request closest to the right of the choice bit
    //
    method Maybe#(UInt#(TLog#(bits_T))) arbitrate(Bit#(bits_T) request);
        // prio_mask now has bits set only to the right of choice point
        let r = curPrioMask & request;

        // If no requests set to the right then use the whole request mask
        if (r == 0)
        begin
            r = request;
        end

        // Pick the highest bit set
        Maybe#(UInt#(TLog#(bits_T))) pick = tagged Invalid;
        for (Integer x = 0; x < valueOf(bits_T); x = x + 1)
        begin
            if (r[x] == 1)
            begin
                pick = tagged Valid fromInteger(x);
            end
        end

        return pick;
    endmethod
endmodule
