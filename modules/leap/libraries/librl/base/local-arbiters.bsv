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
// LOCAL_ARBITER is an arbiter suitable for inclusion within a single rule.
// The standard Bluespec arbiter interface necessitates wires and, consequently,
// separation of rules for triggering requests and receiving grants.
//

interface LOCAL_ARBITER#(numeric type nCLIENTS);
    // If the value of "fixed" is True, the current grant is locked and not
    // updated again until "fixed" goes False.
    method ActionValue#(Maybe#(UInt#(TLog#(nCLIENTS)))) arbitrate(Vector#(nCLIENTS, Bool) req,
                                                                  Bool fixed);
    //
    // Separate the arbitrate method into two methods: arbitrateNoUpd and update.
    // These two methods are for clients who want to control when to update the 
    // arbitration state.
    //
    // arbitrateNoUpd: return the winner and the new arbitration state without updating it
    method ActionValue#(Tuple2#(Maybe#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS)), LOCAL_ARBITER_OPAQUE#(nCLIENTS)))
        arbitrateNoUpd(LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS) req, Bool fixed);
    //
    // update: update the arbitration state with the new state returned by the 
    // arbitrateNoUpd() call
    //
    method Action update(LOCAL_ARBITER_OPAQUE#(nCLIENTS) stateUpdate);

endinterface

// Index of a single arbiter client
typedef UInt#(TLog#(nCLIENTS))  LOCAL_ARBITER_CLIENT_IDX#(numeric type nCLIENTS);

// Bit mask of all an arbiter's clients -- one bit per client.
typedef Vector#(nCLIENTS, Bool) LOCAL_ARBITER_CLIENT_MASK#(numeric type nCLIENTS);

// Abiter's internal, persistent, state
typedef struct
{
    LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS) priorityIdx;
}
LOCAL_ARBITER_OPAQUE#(numeric type nCLIENTS)
    deriving (Eq, Bits);


//
// localArbiterPickWinner --
//     Pick a winner given a set of requests and the current arbitration state.
//
//     This implementation uses vector functions instead of the loops found
//     in the Bluespec arbiter example.  Performance of the compiler in complex
//     cases is much improved using this style.
//
function Maybe#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS)) localArbiterPickWinner(
    LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS) req,
    LOCAL_ARBITER_OPAQUE#(nCLIENTS) state);

    //
    // Clear the low priority portion of the request
    //
    function Bool maskOnlyHighPriority(Integer idx) = (fromInteger(idx) >= state.priorityIdx);
    let high_priority_mask = map(maskOnlyHighPriority, genVector());
    let high_priority_req = zipWith( \&& , req, high_priority_mask);

    //
    // Pick a winner
    //
    Maybe#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS)) winner;
    if (findElem(True, high_priority_req) matches tagged Valid .idx)
        winner = tagged Valid idx;
    else
        winner = findElem(True, req);

    return winner;
endfunction


//
// localArbiterFunc --
//     Implementation of a local arbiter using a function.  This is the algorithm
//     used in mkLocalArbiter() below, but made available as a function so that
//     clients may manage their own storage.  A client instantiating a large
//     number of arbiters might use this in order to manage storage of
//     state efficiently.
//
function Tuple2#(Maybe#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS)),
                 LOCAL_ARBITER_OPAQUE#(nCLIENTS))
    localArbiterFunc(LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS) req,
                     Bool fixed,
                     LOCAL_ARBITER_OPAQUE#(nCLIENTS) state);

    let n_clients = valueOf(nCLIENTS);

    let winner = localArbiterPickWinner(req, state);

    // If a grant was given, update the priority index so that client now has
    // lowest priority.
    let state_upd = state;
    if (! fixed &&& winner matches tagged Valid .idx)
    begin
        state_upd.priorityIdx = (idx == fromInteger(n_clients - 1)) ? 0 : idx + 1;
    end

    return tuple2(winner, state_upd);
endfunction


//
// mkLocalArbiter --
//   A fair round robin arbiter with changing priorities, inspired by the
//   Bluespec mkArbiter().
//
module mkLocalArbiter
    // Interface:
    (LOCAL_ARBITER#(nCLIENTS))
    provisos (Alias#(LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS), t_CLIENT_MASK),
              Alias#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS), t_CLIENT_IDX));

    // Initially, priority is given to client 0
    Reg#(LOCAL_ARBITER_OPAQUE#(nCLIENTS)) state <- mkReg(unpack(0));

    method ActionValue#(Maybe#(t_CLIENT_IDX)) arbitrate(t_CLIENT_MASK req, Bool fixed);
        match {.winner, .state_upd} = localArbiterFunc(req, fixed, state);
        state <= state_upd;

        return winner;
    endmethod

    method ActionValue#(Tuple2#(Maybe#(t_CLIENT_IDX), LOCAL_ARBITER_OPAQUE#(nCLIENTS))) arbitrateNoUpd(t_CLIENT_MASK req, Bool fixed);
        return localArbiterFunc(req, fixed, state);
    endmethod

    method Action update(LOCAL_ARBITER_OPAQUE#(nCLIENTS) stateUpdate);
        state <= stateUpdate;
    endmethod

endmodule


//
// mkLocalRandomArbiter --
//   Nearly identical to mkLocalArbiter() except the highest priority index
//   is chosen randomly.
//
module mkLocalRandomArbiter
    // Interface:
    (LOCAL_ARBITER#(nCLIENTS))
    provisos (Alias#(LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS), t_CLIENT_MASK),
              Alias#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS), t_CLIENT_IDX));

    // Initially, priority is given to client 0
    Reg#(LOCAL_ARBITER_OPAQUE#(nCLIENTS)) state <- mkReg(unpack(0));

    // LFSR for generating the next starting priority index.  Add a few bits
    // to add to the pattern.
    LFSR#(Bit#(TAdd#(3, TLog#(nCLIENTS)))) lfsr <- mkLFSR();

    method ActionValue#(Maybe#(t_CLIENT_IDX)) arbitrate(t_CLIENT_MASK req, Bool fixed);
        let winner = localArbiterPickWinner(req, state);

        if (! fixed)
        begin
            t_CLIENT_IDX next_idx = truncate(unpack(lfsr.value()));

            // Is the truncated LFSR value larger than nCLIENTS?  (Only happens
            // when the number of clients isn't a power of 2.
            if (next_idx > fromInteger(valueOf(TSub#(nCLIENTS, 1))))
            begin
                // This is unfair if the number of clients isn't a power of 2.
                next_idx = ~next_idx;
            end

            state.priorityIdx <= next_idx;
        end

        // Always run the LFSR to avoid timing dependence on the search result
        lfsr.next();

        return winner;
    endmethod

    method ActionValue#(Tuple2#(Maybe#(t_CLIENT_IDX), LOCAL_ARBITER_OPAQUE#(nCLIENTS))) arbitrateNoUpd(t_CLIENT_MASK req, Bool fixed);
        let winner = localArbiterPickWinner(req, state);
        let state_update = state;

        if (! fixed)
        begin
            t_CLIENT_IDX next_idx = truncate(unpack(lfsr.value()));

            // Is the truncated LFSR value larger than nCLIENTS?  (Only happens
            // when the number of clients isn't a power of 2.
            if (next_idx > fromInteger(valueOf(TSub#(nCLIENTS, 1))))
            begin
                // This is unfair if the number of clients isn't a power of 2.
                next_idx = ~next_idx;
            end

            state_update.priorityIdx = next_idx;
        end

        // Always run the LFSR to avoid timing dependence on the search result
        lfsr.next();
   
        return tuple2(winner, state_update);
    endmethod

    method Action update(LOCAL_ARBITER_OPAQUE#(nCLIENTS) stateUpdate);
        state <= stateUpdate;
    endmethod

endmodule
