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
// Functions implementing a FIFO that can be stored in any type of storage,
// including BRAM and LUTRAM.
//
// The functions implement the standard methods available on either unguarded
// or guarded FIFOs.  The functional implementation is stateless.  Functions
// that update the FIFO (enq and deq) take a FIFO state as an input and return
// the updated FIFO state.  It is the caller's responsibility to manage
// loading and storing the state to a memory.
//
// These functions DO NOT behave exactly like a standard FIFO.  Updating the
// FIFO from different rules in the same cycle will not work.  Similarly,
// calling the enq function followed by deq within a single rule will
// forward the data immediately, within a single cycle.
//

import Vector::*;
import FIFOLevel::*;
import FIFO::*;
import FIFOF::*;

// ========================================================================
// ========================================================================
//
//   First implementation:  full FIFO in a struct.
//
// ========================================================================
// ========================================================================

//
// FUNC_FIFO --
//     Base data type.  The oldest entry is always in slot 0 of the data
//     vector.  Values are shifted as entries are dequeued.  Shifting
//     is generally less expensive than the indexing that would be required
//     of a ring buffer.
//
typedef struct
{
    Vector#(n_ENTRIES, t_DATA) data;
    Bit#(TLog#(TAdd#(n_ENTRIES, 1))) activeEntries;
}
FUNC_FIFO#(type t_DATA, numeric type n_ENTRIES)
    deriving (Eq, Bits);


//
// funcFIFO_Init --
//     Initialize a FIFO.
//
function FUNC_FIFO#(t_DATA, n_ENTRIES) funcFIFO_Init();
    return FUNC_FIFO { data: newVector(),
                       activeEntries: 0 };
endfunction


// ========================================================================
//
//   Queries
//
// ========================================================================

//
// funcFIFO_notEmpty
//
function Bool funcFIFO_notEmpty(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo);
    return fifo.activeEntries != 0;
endfunction


//
// funcFIFO_notFull
//
function Bool funcFIFO_notFull(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo);
    return fifo.activeEntries < fromInteger(valueOf(n_ENTRIES));
endfunction


//
// funcFIFO_numBusySlots
//
function Bit#(TLog#(TAdd#(n_ENTRIES, 1))) funcFIFO_numBusySlots(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo);
    return fifo.activeEntries;
endfunction


// ========================================================================
//
//   Unguarded updates
//
// ========================================================================

//
// funcFIFO_UGfirst
//
function t_DATA funcFIFO_UGfirst(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo);
    return fifo.data[0];
endfunction


//
// funcFIFO_UGdeq
//
function FUNC_FIFO#(t_DATA, n_ENTRIES) funcFIFO_UGdeq(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo);
    fifo.data = shiftInAtN(fifo.data, ?);
    fifo.activeEntries = fifo.activeEntries - 1;

    return fifo;
endfunction


//
// funcFIFO_UGenq
//
function FUNC_FIFO#(t_DATA, n_ENTRIES) funcFIFO_UGenq(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo,
                                                      t_DATA val);
    fifo.data[fifo.activeEntries] = val;
    fifo.activeEntries = fifo.activeEntries + 1;
    
    return fifo;
endfunction


// ========================================================================
//
//   Guarded updates
//
// ========================================================================

//
// funcFIFO_first
//
function t_DATA funcFIFO_first(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo);
    return when (funcFIFO_notEmpty(fifo), funcFIFO_UGfirst(fifo));
endfunction


//
// funcFIFO_deq
//
function FUNC_FIFO#(t_DATA, n_ENTRIES) funcFIFO_deq(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo);
    return when (funcFIFO_notEmpty(fifo), funcFIFO_UGdeq(fifo));
endfunction


//
// funcFIFO_enq
//
function FUNC_FIFO#(t_DATA, n_ENTRIES) funcFIFO_enq(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo,
                                                    t_DATA val);
    return when (funcFIFO_notFull(fifo), funcFIFO_UGenq(fifo, val));
endfunction


// ========================================================================
//
//   Non-FIFO data access for callers that need to access an arbitrary
//   object in the buffer.
//
// ========================================================================

//
// funcFIFO_peek --
//     Read data in a specific slot.
//
function Maybe#(t_DATA) funcFIFO_peek(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo,
                                      Bit#(TLog#(n_ENTRIES)) idx);
    if (fifo.activeEntries > zeroExtendNP(idx))
        return tagged Valid fifo.data[idx];
    else
        return tagged Invalid;
endfunction


//
// funcFIFO_poke --
//     Write data to a specific slot.
//
function FUNC_FIFO#(t_DATA, n_ENTRIES) funcFIFO_poke(FUNC_FIFO#(t_DATA, n_ENTRIES) fifo,
                                                     Bit#(TLog#(n_ENTRIES)) idx,
                                                     t_DATA value);
    fifo.data[idx] = value;
    return fifo;
endfunction





// ========================================================================
// ========================================================================
//
//   Second implementation:  struct holds only the metadata for a FIFO.
//       The full data must be managed outside the functions.  Functions
//       return the index that must be read/written to complete the
//       operation.
//
// ========================================================================
// ========================================================================

//
// FUNC_FIFO_IDX --
//     Base data type for the FIFO index manages the oldest and newest
//     pointers.
//
typedef struct
{
    Bit#(TLog#(n_ENTRIES)) idxOldest;
    Bit#(TLog#(n_ENTRIES)) idxNextNew;
    Bool notEmpty;
}
FUNC_FIFO_IDX#(numeric type n_ENTRIES)
    deriving (Eq, Bits);


//
// funcFIFO_IDX_Init --
//     Initialize a FIFO.
//
function FUNC_FIFO_IDX#(n_ENTRIES) funcFIFO_IDX_Init();
    return FUNC_FIFO_IDX { idxOldest: 0,
                           idxNextNew: 0,
                           notEmpty: False };
endfunction


// ========================================================================
//
//   Queries
//
// ========================================================================

//
// funcFIFO_IDX_notEmpty
//
function Bool funcFIFO_IDX_notEmpty(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    return fifo.notEmpty;
endfunction


//
// funcFIFO_IDX_notFull
//
function Bool funcFIFO_IDX_notFull(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    return (fifo.idxOldest != fifo.idxNextNew) || ! fifo.notEmpty;
endfunction


//
// funcFIFO_IDX_numBusySlots
//
function Bit#(TLog#(TAdd#(n_ENTRIES, 1))) funcFIFO_IDX_numBusySlots(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    Bit#(TLog#(TAdd#(n_ENTRIES, 1))) n_busy;

    if (fifo.idxOldest == fifo.idxNextNew)
    begin
        n_busy = funcFIFO_IDX_notEmpty(fifo) ? fromInteger(valueOf(n_ENTRIES)) : 0;
    end
    else if (fifo.idxOldest < fifo.idxNextNew)
    begin
        n_busy = zeroExtendNP(fifo.idxNextNew - fifo.idxOldest);
    end
    else
    begin
        n_busy = fromInteger(valueOf(n_ENTRIES)) - zeroExtendNP(fifo.idxOldest - fifo.idxNextNew);
    end

    return n_busy;
endfunction


// ========================================================================
//
//   Unguarded updates
//
// ========================================================================

//
// funcFIFO_IDX_UGfirst
//
function Bit#(TLog#(n_ENTRIES)) funcFIFO_IDX_UGfirst(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    return fifo.idxOldest;
endfunction


//
// funcFIFO_IDX_UGdeq
//
function FUNC_FIFO_IDX#(n_ENTRIES) funcFIFO_IDX_UGdeq(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    if (fifo.idxOldest == fromInteger(valueOf(TSub#(n_ENTRIES, 1))))
        fifo.idxOldest = 0;
    else
        fifo.idxOldest = fifo.idxOldest + 1;

    fifo.notEmpty = (fifo.idxOldest != fifo.idxNextNew);

    return fifo;
endfunction


//
// funcFIFO_IDX_UGenq --
//   Returns a tuple.  The first entry is the updated FIFO state.  The second is
//   the index to which the value should be written (by the caller).
//
function Tuple2#(FUNC_FIFO_IDX#(n_ENTRIES),
                 Bit#(TLog#(n_ENTRIES))) funcFIFO_IDX_UGenq(FUNC_FIFO_IDX#(n_ENTRIES) fifo);

    let enq_idx = fifo.idxNextNew;
    fifo.notEmpty = True;
    
    if (fifo.idxNextNew == fromInteger(valueOf(TSub#(n_ENTRIES, 1))))
        fifo.idxNextNew = 0;
    else
        fifo.idxNextNew = fifo.idxNextNew + 1;

    return tuple2(fifo, enq_idx);
endfunction


// ========================================================================
//
//   Guarded updates
//
// ========================================================================

//
// funcFIFO_IDX_first
//
function Bit#(TLog#(n_ENTRIES)) funcFIFO_IDX_first(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    return when (funcFIFO_IDX_notEmpty(fifo), funcFIFO_IDX_UGfirst(fifo));
endfunction


//
// funcFIFO_IDX_deq
//
function FUNC_FIFO_IDX#(n_ENTRIES) funcFIFO_IDX_deq(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    return when (funcFIFO_IDX_notEmpty(fifo), funcFIFO_IDX_UGdeq(fifo));
endfunction


//
// funcFIFO_IDX_enq
//
function Tuple2#(FUNC_FIFO_IDX#(n_ENTRIES),
                 Bit#(TLog#(n_ENTRIES))) funcFIFO_IDX_enq(FUNC_FIFO_IDX#(n_ENTRIES) fifo);
    return when (funcFIFO_IDX_notFull(fifo), funcFIFO_IDX_UGenq(fifo));
endfunction


// ========================================================================
//
//   Non-FIFO data access for callers that need to access an arbitrary
//   object in the buffer.
//
// ========================================================================

//
// funcFIFO_IDX_index --
//     Compute the index of a particular position in the FIFO.
//
function Maybe#(Bit#(TLog#(n_ENTRIES))) funcFIFO_IDX_index(FUNC_FIFO_IDX#(n_ENTRIES) fifo,
                                                           Bit#(TLog#(n_ENTRIES)) idx);
    let active_slots = funcFIFO_IDX_numBusySlots(fifo);
    if (zeroExtendNP(idx) >= active_slots)
    begin
        return tagged Invalid;
    end
    else
    begin
        Bit#(TLog#(TAdd#(n_ENTRIES, 1))) s = zeroExtendNP(idx);
        s = s + zeroExtendNP(fifo.idxOldest);
        s = s % fromInteger(valueOf(n_ENTRIES));
        return tagged Valid truncateNP(s);
    end
endfunction

//
// fifoCountToFifof --
//     Compute the index of a particular position in the FIFO.
//
function FIFOF#(t_DATA) fifoCountToFifof (FIFOCountIfc#(t_DATA,n_ENTRIES) old_fifo);

   FIFOF#(t_DATA) new_fifo = interface FIFOF#(t_DATA);
                               method enq      = old_fifo.enq;
                               method deq      = old_fifo.deq;
                               method first    = old_fifo.first;
                               method notEmpty = old_fifo.notEmpty;
                               method notFull  = old_fifo.notFull;
                               method clear    = old_fifo.clear;
                             endinterface;

  return new_fifo;
endfunction
