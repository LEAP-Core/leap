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
// Extensions to GetPut interfaces.
//

import GetPut::*;
import FIFO::*;



//
// MULTIPORT_GET_PUT --
//   A vector of get and put ports used by multi-ported Get/Put modules.
//
interface MULTIPORT_GET_PUT#(numeric type n_PORTS, type t_PUT_DATA, type t_GET_DATA);
    interface Vector#(n_PORTS, Put#(t_PUT_DATA)) putPorts;
    interface Vector#(n_PORTS, Get#(t_GET_DATA)) getPorts;
endinterface

//
// mkSizedMultiPortedGetPut --
//   Wrap a single-ported Get and Put pair with a multi-ported interface.
//   The client assumes that there is exactly one get() triggered in
//   response to every put().  Each get() response is returned on the port
//   of the corresponding put() that triggered the response.
//
//   Scheduling of each port is independent of all other ports.
//
module mkSizedMultiPortedGetPut#(Integer nActiveRequests,
                                 Put#(t_PUT_DATA) putObj,
                                 Get#(t_GET_DATA) getObj)
    // Interface:
    (MULTIPORT_GET_PUT#(n_PORTS, t_PUT_DATA, t_GET_DATA))
    provisos (Bits#(t_PUT_DATA, t_PUT_DATA_SZ),
              Bits#(t_GET_DATA, t_GET_DATA_SZ));

    // Track the order of requests.
    FIFO#(Bit#(TLog#(n_PORTS))) orderQ <- mkSizedFIFO(nActiveRequests);

    // Responses are forwarded to port-specific response queues based on
    // orderQ.
    Vector#(n_PORTS, FIFO#(t_GET_DATA)) respQ <- replicateM(mkFIFO);

    //
    // routeResponses --
    //   Receive responses from getObj and route them to the correct output
    //   ports.
    //
    rule routeResponses (True);
        let p = orderQ.first();
        orderQ.deq();

        let v <- getObj.get();

        respQ[p].enq(v);
    endrule

    // Funnel all request ports into a single queue.
    MERGE_FIFOF#(n_PORTS, t_PUT_DATA) reqQ <- mkMergeFIFOF();

    //
    // fwdRequests --
    //   Send requests to putObj and record the port from which each request
    //   originated.
    //
    rule fwdRequests (True);
        orderQ.enq(reqQ.firstPortID);

        let v = reqQ.first();
        reqQ.deq();

        putObj.put(v);
    endrule


    Vector#(n_PORTS, Put#(t_PUT_DATA)) putPortsLocal = newVector();
    Vector#(n_PORTS, Get#(t_GET_DATA)) getPortsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_PORTS); p = p + 1)
    begin
        putPortsLocal[p] = (
            interface Put;
                method Action put(t_PUT_DATA v);
                    reqQ.ports[p].enq(v);
                endmethod
            endinterface
        );

        getPortsLocal[p] = (
            interface Get;
                method ActionValue#(t_GET_DATA) get();
                    let v = respQ[p].first();
                    respQ[p].deq();

                    return v;
                endmethod
            endinterface
        );
    end

    interface putPorts = putPortsLocal;
    interface getPorts = getPortsLocal;
endmodule
