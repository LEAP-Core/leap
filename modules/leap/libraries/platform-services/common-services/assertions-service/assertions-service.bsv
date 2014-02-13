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
