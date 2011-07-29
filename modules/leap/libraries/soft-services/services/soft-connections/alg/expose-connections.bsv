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

import Vector::*;
import ModuleContext::*;
import List::*;
import HList::*;
import FIFOF::*;


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

    let outs      <- exposeDanglingSends(ctx.unmatchedSends, ?);
    let ins       <- exposeDanglingRecvs(ctx.unmatchedRecvs, ?);
    let outMultis <- exposeDanglingSendMultis(ctx.unmatchedSendMultis);
    let inMultis  <- exposeDanglingRecvMultis(ctx.unmatchedRecvMultis);
    let chns      <- exposeChains(ctx.chains);

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
                 unmatchedSends: tagged Nil,
                 unmatchedRecvs: tagged Nil,
                 unmatchedSendMultis: tagged Nil,
                 unmatchedRecvMultis: tagged Nil,
                 chains: tagged Nil,
                 stations: tagged Nil,
                 stationStack: tagged Nil,
                 synthesisBoundaryPlatform: `MULTI_FPGA_PLATFORM,
                 rootStationName: "InvalidRootStation",
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
        return x;

    endmodule

endinstance

module printDanglingSend#(Integer cur_out, LOGICAL_SEND_INFO cur) (Empty);
  let opt = (cur.optional) ? "True" : "False";
  messageM("Dangling Send {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]:" + cur.logicalName + ":" + cur.computePlatform + ":" + opt + ":" + integerToString(cur.bitWidth));
endmodule

// Expose dangling sends to other synthesis boundaries via compilation messages

// exposeDangingSends :: [LOGICAL_SEND_INFO] -> Module [PHYSICAL_CONNECTION_OUT]

module exposeDanglingSends#(List#(LOGICAL_SEND_INFO) dsends, String platform) (Vector#(n, PHYSICAL_CONNECTION_OUT));

  Vector#(n, PHYSICAL_CONNECTION_OUT) res = newVector();
  Integer cur_out = 0;

  // Output a compilation message and tie it to the next free outport
  for (Integer x = 0; x < length(dsends); x = x + 1)
  begin
    let cur = dsends[x];    
    // Squash connections not from this FPGA Platform
    if(cur.computePlatform == `MULTI_FPGA_PLATFORM)
      begin
        printDanglingSend(cur_out,cur);
        res[cur_out] = cur.outgoing;
        cur_out = cur_out + 1;
      end
    else
      begin
        messageM("Dropping Send" + cur.logicalName + " should be on " + cur.computePlatform + " and we are compiling " + `MULTI_FPGA_PLATFORM);
      end
  end

  // We can now squash connections
  if (cur_out > valueof(n))
    error("ERROR: Too many dangling Send Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_OUT parameter to WithConnections.");
  
  // Zero out unused dangling sends
  for (Integer x = cur_out; x < valueOf(n); x = x + 1)
    res[x] = (interface PHYSICAL_CONNECTION_OUT
                  interface clock = noClock;
                  interface reset = noReset;
                  method Action deq() = noAction;
                  method PHYSICAL_CONNECTION_DATA first() = 0;
                  method Bool notEmpty() = False;
               endinterface);
  
  return res;
  
endmodule

module printDanglingRecv#(Integer cur_out, LOGICAL_RECV_INFO cur) (Empty);
    let opt = (cur.optional) ? "True" : "False";
    messageM("Dangling Recv {" + cur.logicalType + "} [" + integerToString(cur_out) + "]:" + cur.logicalName+ ":" + cur.computePlatform + ":" + opt + ":" + integerToString(cur.bitWidth));
endmodule

// Expose dangling receives to other synthesis boundaries via compilation messages

// exposeDangingRecvs :: [LOGICAL_RECV_INFO] -> Module [PHYSICAL_CONNECTION_IN]

module exposeDanglingRecvs#(List#(LOGICAL_RECV_INFO) drecvs, String platform) (Vector#(n, PHYSICAL_CONNECTION_IN));

  Vector#(n, PHYSICAL_CONNECTION_IN) res = newVector();
  Integer cur_in = 0;
  
  //Output a compilation message and tie it to the next free inport
  for (Integer x = 0; x < length(drecvs); x = x + 1)
  begin
    
    let cur = drecvs[x];
    // Squash non-local connections
    if(cur.computePlatform == `MULTI_FPGA_PLATFORM)
      begin
        printDanglingRecv(cur_in,cur);
        res[cur_in] = cur.incoming;
        cur_in = cur_in + 1;
      end
    else
      begin
        messageM("Dropping Recv" + cur.logicalName + " should be on " + cur.computePlatform + " and we are compiling " + `MULTI_FPGA_PLATFORM);
      end
  end

  // We can now squash connections
  if (cur_in > valueof(n))
     error("ERROR: Too many dangling Receive Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_IN parameter to WithConnections.");

  
  //Zero out unused dangling recvs
  for (Integer x = cur_in; x < valueOf(n); x = x + 1)
    res[x] = (interface PHYSICAL_CONNECTION_IN
                 interface clock = noClock;
                 interface reset = noReset;
                 method Bool success() = False;
                 method Action try(PHYSICAL_CONNECTION_DATA d) = noAction;
               endinterface);
  
  return res;

endmodule
  

module exposeDanglingSendMultis#(List#(LOGICAL_SEND_MULTI_INFO) dsends) (Vector#(n, PHYSICAL_CONNECTION_OUT_MULTI));

  Vector#(n, PHYSICAL_CONNECTION_OUT_MULTI) res = newVector();
  Integer cur_out = 0;

  // Output a compilation message and tie it to the next free outport
  for (Integer x = 0; x < length(dsends); x = x + 1)
  begin
    let cur = dsends[x];
    messageM("Dangling SendMulti {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]:" + cur.logicalName + ":" + cur.computePlatform );
    res[cur_out] = cur.outgoing;
    cur_out = cur_out + 1;
  end

    if (cur_out > valueof(n))
      error("ERROR: Too many dangling SendMulti Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_OUT_MULTI parameter to WithConnections.");


  
  // Zero out unused dangling send multis
  for (Integer x = cur_out; x < valueOf(n); x = x + 1)
    res[x] = (interface PHYSICAL_CONNECTION_OUT_MULTI
                  interface clock = noClock;
                  interface reset = noReset;
                  method Action deq() = noAction;
                  method Tuple2#(CONNECTION_TAG, PHYSICAL_CONNECTION_DATA) first() = tuple2(tagged CONNECTION_ROUTED 0, 0);
                  method Bool notEmpty() = False;
               endinterface);
  
  return res;
  
endmodule

module exposeDanglingRecvMultis#(List#(LOGICAL_RECV_MULTI_INFO) drecvs) (Vector#(n, PHYSICAL_CONNECTION_IN_MULTI));

  Vector#(n, PHYSICAL_CONNECTION_IN_MULTI) res = newVector();
  Integer cur_in = 0;
  
  // Output a compilation message and tie it to the next free inport
  for (Integer x = 0; x < length(drecvs); x = x + 1)
  begin
    let cur = drecvs[x];
    messageM("Dangling RecvMulti {" + cur.logicalType + "} [" + integerToString(cur_in) + "]:" + cur.logicalName+ ":" + cur.computePlatform);
    res[cur_in] = cur.incoming;
    cur_in = cur_in + 1;
  end

  if (cur_in > valueof(n))
    error("ERROR: Too many dangling Receive Multi Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_IN_MULTI parameter to WithConnections.");


  
  // Zero out unused dangling recv multis
  for (Integer x = cur_in; x < valueOf(n); x = x + 1)
    res[x] = (interface PHYSICAL_CONNECTION_IN_MULTI
                 interface clock = noClock;
                 interface reset = noReset;
                 method Bool success() = False;
                 method Action try(CONNECTION_IDX x, PHYSICAL_CONNECTION_DATA d) = noAction;
               endinterface);
  
  return res;

endmodule
  

//If there are no links then it's just a pass-through queue
module mkPassThrough
    //interface:
                (PHYSICAL_CHAIN);

  // Local Clock and reset
  Clock localClock <- exposeCurrentClock();
  Reset localReset <- exposeCurrentReset();

  FIFOF#(PHYSICAL_CHAIN_DATA) passQ <- mkUGFIFOF();
  PulseWire enW <- mkPulseWire();
  
  interface PHYSICAL_CHAIN_IN incoming;

    method Action try(PHYSICAL_CHAIN_DATA d);
      if (passQ.notFull())
      begin
        passQ.enq(d);
        enW.send();
      end
    endmethod

    method Bool   success();
      return enW;
    endmethod

    interface Clock clock = localClock;
    interface Reset reset = localReset; 

  endinterface

  // A physical outgoing connection
  interface PHYSICAL_CHAIN_OUT outgoing;

    method Bool notEmpty() = passQ.notEmpty();
    method PHYSICAL_CHAIN_DATA first() = passQ.first();
    method Action deq() = passQ.deq();

    interface Clock clock = localClock;
    interface Reset reset = localReset; 

  endinterface

endmodule

// make the printout similar to connections.  this may assist in parsing later.
module printChain#(Integer cur_out, LOGICAL_CHAIN_INFO cur) (Empty);
  messageM("Dangling Chain {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]:" + cur.logicalName + ":" + cur.computePlatform + ":False:" + integerToString(cur.bitWidth));
endmodule

module exposeChains#(List#(LOGICAL_CHAIN_INFO) chains) (Vector#(n, PHYSICAL_CHAIN));

    Vector#(n, PHYSICAL_CHAIN) chns = newVector();
    messageM("In expose Chains");    
    Integer cur_chain = 0;
    // For every chain, we must expose it to the next level.
    for (Integer x = 0; x < length(chains); x = x + 1)
    begin
       let chain = chains[x];
       cur_chain = cur_chain + 1;
       // For non-empty chains, we connect to the head of the first link
       // and the tail of the last link. (These could be the same link if
       // there was only one.)
       printChain(x,chain);
       chns[x] = (interface PHYSICAL_CHAIN;
                    interface incoming = chain.incoming;
                    interface outgoing = chain.outgoing;
                  endinterface);

    end


  for (Integer x = cur_chain; x < valueOf(n); x = x + 1)
    begin  
     let null_in = interface PHYSICAL_CHAIN_IN
                 interface clock = noClock;
                 interface reset = noReset;
                 method Bool success() = False;
                 method Action try(PHYSICAL_CHAIN_DATA d) = noAction;
               endinterface;

      let null_out = interface PHYSICAL_CHAIN_OUT
                  interface clock = noClock;
                  interface reset = noReset;
                  method Action deq() = noAction;
                  method PHYSICAL_CHAIN_DATA first = 0;
                  method Bool notEmpty() = False;
               endinterface;

      chns[x] = (interface PHYSICAL_CHAIN;
                    interface incoming = null_in;
                    interface outgoing = null_out;
                  endinterface); 
    end	       
    
   return chns;
endmodule