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

import DefaultValue::*;
import Vector::*;
import ModuleContext::*;
import List::*;
import HList::*;
import FIFOF::*;


`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_interconnect.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_connections_alg.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"


// Connect soft connections as normal, but dangling connections are not an error
// Instead they're exposed as a WithConnections interface and messages are entered
// into the compilation log recording their address index.
// Connection Chains are not "tied off" but exposed as head and tail

//toWithConnections :: [ConnectionData] -> Module WithConnections


module toWithConnections#(LOGICAL_CONNECTION_INFO ctx)       (WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_NUM_IN_MULTI, t_NUM_MULTI, t_NUM_CHAINS));

    let outs      <- exposeDanglingSends(ctx, ?);
    let ins       <- exposeDanglingRecvs(ctx, ?);
    let outMultis <- exposeDanglingSendMultis(ctx);
    let inMultis  <- exposeDanglingRecvMultis(ctx);
    let chns      <- exposeChains(ctx);

    interface outgoing = outs;
    interface incoming = ins;
    interface outgoingMultis = outMultis;
    interface incomingMultis = inMultis;
    interface chains = chns;
  
endmodule  

instance SOFT_SERVICE#(LOGICAL_CONNECTION_INFO);

    module initializeServiceContext (LOGICAL_CONNECTION_INFO); 
        let sReset <- exposeCurrentReset();
        return LOGICAL_CONNECTION_INFO 
             {
                 globalStrings: defaultValue,
                 unmatchedSends: defaultValue,
                 unmatchedRecvs: defaultValue,
                 unmatchedSendMultis: tagged Nil,
                 unmatchedRecvMultis: tagged Nil,
                 chains: tagged Nil,
                 stations: tagged Nil,
                 stationStack: tagged Nil,
                 debugInfo: tagged Nil,
                 latencyInfo: tagged Nil,
                 synthesisBoundaryPlatform: "Deprecated",
                 synthesisBoundaryPlatformID: -1,
                 synthesisBoundaryID: 0,
                 synthesisBoundaryName: "UNASSIGNED",
                 exposeAllConnections: False,
                 rootStationName: "InvalidRootStation",
                 remappingFunction: connectionNameNullRemap,
                 softReset: sReset
             };
    endmodule

    module finalizeServiceContext#(LOGICAL_CONNECTION_INFO m) (Empty);

       let finalModule <- finalizeSoftConnection(m);   

    endmodule

endinstance

instance SYNTHESIZABLE_SOFT_SERVICE#(LOGICAL_CONNECTION_INFO, WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_NUM_IN_MULTI, t_NUM_MULTI,t_NUM_CHAINS));

    module exposeServiceContext#(LOGICAL_CONNECTION_INFO ctx) (WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_NUM_IN_MULTI, t_NUM_MULTI, t_NUM_CHAINS));

        let rst <- exposeCurrentReset();
        let clk <- exposeCurrentClock();

        // TODO: leap-connect doesn't know about multicasts or stations yet.
        // Therefore for now we just connect them at every synthesis boundary
        // as if it were the toplevel.

        // In the future leap-connect will know about these and we'll do something
        // different - more akin to how Chains are today.

        // Until then this allows them to work within a synthesis boundary, but not
        // across synthesis boundaries.
        connectMulticasts(clk, ctx);
        connectStationsTree(clk, ctx);

        let x <- toWithConnections(ctx);

        // Emit the global string table
        printGlobStrings(ctx.globalStrings);

        return x;

    endmodule

endinstance

// We should refactor this code
module printDanglingSend#(Integer cur_out, LOGICAL_SEND_ENTRY cur) (Empty);
    let name = ctHashKey(cur);
    let cur_val = ctHashValue(cur);
    let opt = (cur_val.optional) ? "True" : "False";
    messageM("Dangling Send {" + cur_val.logicalType + "} [" + integerToString(cur_out) +  "]:" + name + ":" + opt + ":" + integerToString(cur_val.bitWidth) + ":" + cur_val.moduleName + ":None" );
endmodule

module printDanglingRecv#(Integer cur_out, LOGICAL_RECV_ENTRY cur) (Empty);
    let name = ctHashKey(cur);
    let cur_val = ctHashValue(cur);
    let opt = (cur_val.optional) ? "True" : "False";
    messageM("Dangling Recv {" + cur_val.logicalType + "} [" + integerToString(cur_out) + "]:" + name + ":" + opt + ":" + integerToString(cur_val.bitWidth) + ":" + cur_val.moduleName+ ":None" );
endmodule


// Expose dangling sends to other synthesis boundaries via compilation messages

// exposeDangingSends :: [LOGICAL_SEND_INFO] -> Module [PHYSICAL_CONNECTION_OUT]

module exposeDanglingSends#(LOGICAL_CONNECTION_INFO ctx, String platform) (Vector#(n, PHYSICAL_CONNECTION_OUT));

    Vector#(n, PHYSICAL_CONNECTION_OUT) res = newVector();
    Integer cur_out = 0;
    List#(LOGICAL_SEND_ENTRY) dsends = ctHashTableToList(ctx.unmatchedSends);

    // Output a compilation message and tie it to the next free outport
    while (! List::isNull(dsends))
    begin
        let cur = List::head(dsends);
        let name = ctHashKey(cur);
        let cur_val = ctHashValue(cur);
        dsends = List::tail(dsends);
        printDanglingSend(cur_out,cur);
        res[cur_out] = cur_val.outgoing;
        cur_out = cur_out + 1;
    end

    // We can now squash connections
    if (cur_out > valueof(n))
    begin
        error("ERROR: Too many dangling Send Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_OUT parameter to WithConnections.");
    end

    // Zero out unused dangling sends
    for (Integer x = cur_out; x < valueOf(n); x = x + 1)
    begin
      res[x] = (interface PHYSICAL_CONNECTION_OUT
                    interface clock = noClock;
                    interface reset = noReset;
                    method Action deq() = noAction;
                    method PHYSICAL_CONNECTION_DATA first() = 0;
                    method Bool notEmpty() = False;
                 endinterface);
    end

    return res;

endmodule


// Expose dangling receives to other synthesis boundaries via compilation messages

// exposeDangingRecvs :: [LOGICAL_RECV_INFO] -> Module [PHYSICAL_CONNECTION_IN]

module exposeDanglingRecvs#(LOGICAL_CONNECTION_INFO ctx, String platform) (Vector#(n, PHYSICAL_CONNECTION_IN));

    Vector#(n, PHYSICAL_CONNECTION_IN) res = newVector();
    Integer cur_in = 0;
    List#(LOGICAL_RECV_ENTRY) drecvs = ctHashTableToList(ctx.unmatchedRecvs);

    // Output a compilation message and tie it to the next free inport
    while (! List::isNull(drecvs))
    begin
        let cur = List::head(drecvs);
        let name = ctHashKey(cur);
        let cur_val = ctHashValue(cur);
        drecvs = List::tail(drecvs);
        printDanglingRecv(cur_in,cur);
        res[cur_in] = cur_val.incoming;
        cur_in = cur_in + 1;
    end

    // We can now squash connections
    if (cur_in > valueof(n))
    begin
       error("ERROR: Too many dangling Receive Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_IN parameter to WithConnections.");
    end


    //Zero out unused dangling recvs
    for (Integer x = cur_in; x < valueOf(n); x = x + 1)
    begin
        res[x] = (interface PHYSICAL_CONNECTION_IN
                     interface clock = noClock;
                     interface reset = noReset;
                     method Bool success() = False;
                     method Action try(PHYSICAL_CONNECTION_DATA d) = noAction;
                     method Bool dequeued = False;
                   endinterface);
    end

    return res;

endmodule
  

module exposeDanglingSendMultis#(LOGICAL_CONNECTION_INFO ctx) (Vector#(n, PHYSICAL_CONNECTION_OUT_MULTI));

    Vector#(n, PHYSICAL_CONNECTION_OUT_MULTI) res = newVector();
    Integer cur_out = 0;
    List#(LOGICAL_SEND_MULTI_INFO) dsends = ctx.unmatchedSendMultis;

    // Output a compilation message and tie it to the next free outport
    while(!List::isNull(dsends))
    begin
        let cur = List::head(dsends);
        dsends = List::tail(dsends);
        messageM("Dangling SendMulti {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]:" + cur.logicalName );
        res[cur_out] = cur.outgoing;
        cur_out = cur_out + 1;
    end

    if (cur_out > valueof(n))
    begin
        error("ERROR: Too many dangling SendMulti Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_OUT_MULTI parameter to WithConnections.");
    end


    // Zero out unused dangling send multis
    for (Integer x = cur_out; x < valueOf(n); x = x + 1)
    begin
        res[x] = (interface PHYSICAL_CONNECTION_OUT_MULTI
                      interface clock = noClock;
                      interface reset = noReset;
                      method Action deq() = noAction;
                      method Tuple2#(CONNECTION_TAG, PHYSICAL_CONNECTION_DATA) first() = tuple2(tagged CONNECTION_ROUTED 0, 0);
                      method Bool notEmpty() = False;
                   endinterface);
    end

    return res;

endmodule

module exposeDanglingRecvMultis#(LOGICAL_CONNECTION_INFO ctx) (Vector#(n, PHYSICAL_CONNECTION_IN_MULTI));

    Vector#(n, PHYSICAL_CONNECTION_IN_MULTI) res = newVector();
    Integer cur_in = 0;
    List#(LOGICAL_RECV_MULTI_INFO) drecvs = ctx.unmatchedRecvMultis;

    // Output a compilation message and tie it to the next free inport
    while (!List::isNull(drecvs))
    begin
        let cur = List::head(drecvs);
        drecvs = List::tail(drecvs);
        messageM("Dangling RecvMulti {" + cur.logicalType + "} [" + integerToString(cur_in) + "]:" + cur.logicalName);
        res[cur_in] = cur.incoming;
        cur_in = cur_in + 1;
    end

    if (cur_in > valueof(n))
    begin
        error("ERROR: Too many dangling Receive Multi Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_IN_MULTI parameter to WithConnections.");
    end

    // Zero out unused dangling recv multis
    for (Integer x = cur_in; x < valueOf(n); x = x + 1)
    begin
        res[x] = (interface PHYSICAL_CONNECTION_IN_MULTI
                     interface clock = noClock;
                     interface reset = noReset;
                     method Bool success() = False;
                     method Action try(CONNECTION_IDX x, PHYSICAL_CONNECTION_DATA d) = noAction;
                   endinterface);
    end

    return res;

endmodule
  
// make the printout similar to connections.  this may assist in parsing later.
module printChain#(Integer cur_out, LOGICAL_CHAIN_INFO cur) (Empty);
    messageM("Dangling Chain {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]:" + cur.logicalName + ":False:" + integerToString(cur.bitWidth) + ":" + cur.moduleNameIncoming+ ":" + cur.moduleNameOutgoing);
endmodule

module exposeChains#(LOGICAL_CONNECTION_INFO ctx) (Vector#(n, PHYSICAL_CHAIN));

    Vector#(n, PHYSICAL_CHAIN) chns = newVector();
    List#(LOGICAL_CHAIN_INFO) chains = ctx.chains;
    //messageM("In expose Chains");    
    Integer cur_chain = 0;
    // For every chain, we must expose it to the next level.
    while (!List::isNull(chains))
    begin
        let chain = List::head(chains);
        chains = List::tail(chains);
        // For non-empty chains, we connect to the head of the first link
        // and the tail of the last link. (These could be the same link if
        // there was only one.)
        //Drop chain if not used
        printChain(cur_chain, chain);
        chns[cur_chain] = (interface PHYSICAL_CHAIN;
                               interface incoming = chain.incoming;
                               interface outgoing = chain.outgoing;
                           endinterface);
        cur_chain = cur_chain + 1;
    end


    for (Integer x = cur_chain; x < valueOf(n); x = x + 1)
    begin  

        let null_in = (interface PHYSICAL_CHAIN_IN
                           interface clock = noClock;
                           interface reset = noReset;
                           method Bool success() = False;
                           method Bool dequeued() = False;
                           method Action try(PHYSICAL_CHAIN_DATA d) = noAction;
                       endinterface);

        let null_out = (interface PHYSICAL_CHAIN_OUT
                            interface clock = noClock;
                            interface reset = noReset;
                            method Action deq() = noAction;
                            method PHYSICAL_CHAIN_DATA first = 0;
                            method Bool notEmpty() = False;
                       endinterface);

       chns[x] = (interface PHYSICAL_CHAIN;
                      interface incoming = null_in;
                      interface outgoing = null_out;
                  endinterface); 
     end	       

    return chns;
endmodule
