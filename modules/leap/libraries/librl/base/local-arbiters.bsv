//
// Copyright (C) 2011 Intel Corporation
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
// LOCAL_ARBITER is an arbiter suitable for inclusion within a single rule.
// The standard Bluespec arbiter interface necessitates wires and, consequently,
// separation of rules for triggering requests and receiving grants.
//

interface LOCAL_ARBITER#(numeric type nCLIENTS);
    method ActionValue#(Maybe#(UInt#(TLog#(nCLIENTS)))) arbitrate(Vector#(nCLIENTS, Bool) req);
endinterface


//
// mkLocalArbiter --
//   A fair round robin arbiter with changing priorities, inspired by the
//   Bluespec mkArbiter().  If the value of "fixed" is True, the current
//   grant is locked and not updated again until "fixed" goes False.
//
//   This implementation uses vector functions instead of the loops found
//   in the Bluespec example.  Performance of the compiler in complex cases
//   is much improved using this stle.
//
module mkLocalArbiter#(Bool fixed)
    // Interface:
    (LOCAL_ARBITER#(nCLIENTS))
    provisos (Alias#(Vector#(nCLIENTS, Bool), t_CLIENT_MASK),
              Alias#(UInt#(TLog#(nCLIENTS)), t_CLIENT_IDX));

    let n_clients = valueOf(nCLIENTS);

    // Initially, priority is given to client 0
    Reg#(t_CLIENT_IDX) priorityIdx <- mkReg(0);

    method ActionValue#(Maybe#(t_CLIENT_IDX)) arbitrate(t_CLIENT_MASK req);
        //
        // Clear the low priority portion of the request
        //
        function Bool maskOnlyHighPriority(Integer idx) = (fromInteger(idx) >= priorityIdx);
        t_CLIENT_MASK high_priority_mask = map(maskOnlyHighPriority, genVector());
        t_CLIENT_MASK high_priority_req = zipWith( \&& , req, high_priority_mask);
    
        //
        // Pick a winner
        //
        Maybe#(t_CLIENT_IDX) winner;
        if (findElem(True, high_priority_req) matches tagged Valid .idx)
            winner = tagged Valid idx;
        else
            winner = findElem(True, req);

        // If a grant was given, update the priority index so that client now has
        // lowest priority.
        if (! fixed &&& winner matches tagged Valid .idx)
        begin
            priorityIdx <= (idx == fromInteger(n_clients - 1)) ? 0 : idx + 1;
        end

        return winner;
    endmethod
endmodule


//
// mkLocalRandomArbiter --
//   Nearly identical to mkLocalArbiter() except the highest priority index
//   is chosen randomly.
//
module mkLocalRandomArbiter#(Bool fixed)
    // Interface:
    (LOCAL_ARBITER#(nCLIENTS))
    provisos (Alias#(Vector#(nCLIENTS, Bool), t_CLIENT_MASK),
              Alias#(UInt#(TLog#(nCLIENTS)), t_CLIENT_IDX));

    // Initially, priority is given to client 0
    Reg#(t_CLIENT_IDX) priorityIdx <- mkReg(0);

    // LFSR for generating the next starting priority index
    LFSR#(Bit#(TLog#(nCLIENTS))) lfsr <- mkLFSR();

    method ActionValue#(Maybe#(t_CLIENT_IDX)) arbitrate(t_CLIENT_MASK req);
        //
        // Clear the low priority portion of the request
        //
        function Bool maskOnlyHighPriority(Integer idx) = (fromInteger(idx) >= priorityIdx);
        t_CLIENT_MASK high_priority_mask = map(maskOnlyHighPriority, genVector());
        t_CLIENT_MASK high_priority_req = zipWith( \&& , req, high_priority_mask);
    
        //
        // Pick a winner
        //
        Maybe#(t_CLIENT_IDX) winner;
        if (findElem(True, high_priority_req) matches tagged Valid .idx)
            winner = tagged Valid idx;
        else
            winner = findElem(True, req);

        // Always run the LFSR to avoid timing dependence on the search result
        if (! fixed)
        begin
            priorityIdx <= unpack(lfsr.value());
        end
        lfsr.next();

        return winner;
    endmethod
endmodule
