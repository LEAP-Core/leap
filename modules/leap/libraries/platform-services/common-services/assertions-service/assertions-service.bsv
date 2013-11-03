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

import FIFO::*;
import Vector::*;
import GetPut::*;
import Connectable::*;


`include "awb/rrr/client_stub_ASSERTIONS.bsh"
`include "awb/rrr/service_ids.bsh"
`include "awb/dict/ASSERTIONS.bsh"


module [CONNECTED_MODULE] mkAssertionsService
    // interface:
        ();

    // Communication to our RRR server
    ClientStub_ASSERTIONS clientStub <- mkClientStub_ASSERTIONS();
  
    //
    // Cycle counter.
    //
    Reg#(Bit#(64)) fpgaCC <- mkReg(0);

    (* fire_when_enabled, no_implicit_conditions *)
    rule countCC (True);
        fpgaCC <= fpgaCC + 1;
    endrule


    // ========================================================================
    //
    //   String-based assertions.
    //
    // ========================================================================

    // Communication link to the rest of the Assertion checkers
    CONNECTION_CHAIN#(ASSERTION_STR_RING_DATA) chainStr <-
        mkConnectionChain("AssertStrRing");
  
    DEMARSHALLER#(ASSERTION_STR_RING_DATA, ASSERTION_STR_DATA) assertQ <-
        mkSimpleDemarshaller();

    // Demarshall the incoming data stream, making it available as assertQ.
    mkConnection(toGet(chainStr), toPut(assertQ));

    //
    // processStrResp --
    //   Process the next response from an individual assertion checker.
    //   Pass assertions on to software.
    //
    rule processStrResp (True);
        let ast = assertQ.first();
        assertQ.deq();

        clientStub.makeRequest_AssertStr(fpgaCC,
                                         zeroExtend(pack(ast.suid)),
                                         zeroExtend(pack(ast.severity)));
    endrule

    // ========================================================================
    //
    //   Dictionary-based assertions.
    //
    // ========================================================================

    // Communication link to the rest of the Assertion checkers
    Connection_Chain#(ASSERTION_DATA) chainDict <- mkConnection_Chain(`RINGID_ASSERTS);
  
    rule processDictResp (True);
        let ast <- chainDict.recvFromPrev();
        clientStub.makeRequest_AssertDict(fpgaCC,
                                          zeroExtend(pack(ast.baseID)),
                                          zeroExtend(pack(ast.assertions)));
    endrule

endmodule
