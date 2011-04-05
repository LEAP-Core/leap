
import Vector::*;
import ModuleContext::*;
import List::*;
import HList::*;
import FIFOF::*;

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/physical_interconnect.bsh"
`include "asim/provides/soft_connections_common.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"




// Connect soft connections as normal, but dangling connections are not an error
// Instead they're exposed as a WithConnections interface and messages are entered
// into the compilation log recording their address index.
// Connection Chains are not "tied off" but exposed as head and tail

//toWithConnections :: [ConnectionData] -> Module WithConnections


module toWithConnections#(LOGICAL_CONNECTION_INFO ctx)       (WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_NUM_IN_MULTI, t_NUM_MULTI));

    let outs      <- exposeDanglingSends(ctx.unmatchedSends);
    let ins       <- exposeDanglingRecvs(ctx.unmatchedRecvs);
    let outMultis <- exposeDanglingSendMultis(ctx.unmatchedSendMultis);
    let inMultis  <- exposeDanglingRecvMultis(ctx.unmatchedRecvMultis);

    Vector#(CON_NUM_CHAINS, PHYSICAL_CHAIN) chns = newVector();

    // For every chain, we must expose it to the next level.
    for (Integer x = 0; x < valueof(CON_NUM_CHAINS); x = x + 1)
    begin
       let links = ctx.chains[x];
       if (List::isNull(links))
       begin

          // If a particular chain is empty for this synthesis boundary
          // make a dummy link that is just a pass-through.
          messageM("Exposing Chain: [" + integerToString(x) + "] as Pass-Through.");
          let dummy <- mkPassThrough();
          chns[x] = (interface PHYSICAL_CHAIN;
                         interface incoming = dummy.incoming;
                         interface outgoing = dummy.outgoing;
                     endinterface);

       end
       else
       begin

          // For non-empty chains, we connect to the head of the first link
          // and the tail of the last link. (These could be the same link if
          // there was only one.)
          messageM("Exposing Chain: [" + integerToString(x) + "]");
          let latest_link = List::head(links);
          let earliest_link = List::last(links);
          chns[x] = (interface PHYSICAL_CHAIN;
                         interface incoming = latest_link.incoming;
                         interface outgoing = earliest_link.outgoing;
                     endinterface);

       end
    end

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
                 chains: Vector::replicate(tagged Nil),
                 stations: tagged Nil,
                 stationStack: tagged Nil,
                 rootStationName: "InvalidRootStation",
                 softReset: sReset
             };
    endmodule

    module finalizeServiceContext#(LOGICAL_CONNECTION_INFO m) (Empty);

       let finalModule <- finalizeSoftConnection(m);   

    endmodule

endinstance

instance SYNTHESIZABLE_SOFT_SERVICE#(LOGICAL_CONNECTION_INFO, WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_NUM_IN_MULTI, t_NUM_MULTI));

    module exposeServiceContext#(LOGICAL_CONNECTION_INFO ctx) (WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_NUM_IN_MULTI, t_NUM_MULTI));

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

// Expose dangling sends to other synthesis boundaries via compilation messages

// exposeDangingSends :: [LOGICAL_SEND_INFO] -> Module [PHYSICAL_CONNECTION_OUT]

module exposeDanglingSends#(List#(LOGICAL_SEND_INFO) dsends) (Vector#(n, PHYSICAL_CONNECTION_OUT));

  Vector#(n, PHYSICAL_CONNECTION_OUT) res = newVector();
  Integer cur_out = 0;

  // Output a compilation message and tie it to the next free outport
  for (Integer x = 0; x < length(dsends); x = x + 1)
  begin
    if (cur_out >= valueof(n))
      error("ERROR: Too many dangling Send Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_OUT parameter to WithConnections.");

    let cur = dsends[x];
    let opt = (cur.optional) ? "True" : "False";
    messageM("Dangling Send {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]:" + cur.logicalName + ":" + cur.computePlatform + ":" + opt);
    res[cur_out] = cur.outgoing;
    cur_out = cur_out + 1;
  end
  
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

// Expose dangling receives to other synthesis boundaries via compilation messages

// exposeDangingRecvs :: [LOGICAL_RECV_INFO] -> Module [PHYSICAL_CONNECTION_IN]

module exposeDanglingRecvs#(List#(LOGICAL_RECV_INFO) drecvs) (Vector#(n, PHYSICAL_CONNECTION_IN));

  Vector#(n, PHYSICAL_CONNECTION_IN) res = newVector();
  Integer cur_in = 0;
  
  //Output a compilation message and tie it to the next free inport
  for (Integer x = 0; x < length(drecvs); x = x + 1)
  begin
    if (cur_in >= valueof(n))
      error("ERROR: Too many dangling Receive Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_IN parameter to WithConnections.");

    let cur = drecvs[x];
    let opt = (cur.optional) ? "True" : "False";
    messageM("Dangling Recv {" + cur.logicalType + "} [" + integerToString(cur_in) + "]:" + cur.logicalName+ ":" + cur.computePlatform + ":" + opt);
    res[cur_in] = cur.incoming;
    cur_in = cur_in + 1;
  end
  
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
    if (cur_out >= valueof(n))
      error("ERROR: Too many dangling SendMulti Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_OUT_MULTI parameter to WithConnections.");

    let cur = dsends[x];
    messageM("Dangling SendMulti {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]:" + cur.logicalName + ":" + cur.computePlatform);
    res[cur_out] = cur.outgoing;
    cur_out = cur_out + 1;
  end
  
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
    if (cur_in >= valueof(n))
      error("ERROR: Too many dangling Receive Multi Connections (max " + integerToString(valueof(n)) + "). Increase the t_NUM_IN_MULTI parameter to WithConnections.");

    let cur = drecvs[x];
    messageM("Dangling RecvMulti {" + cur.logicalType + "} [" + integerToString(cur_in) + "]:" + cur.logicalName+ ":" + cur.computePlatform);
    res[cur_in] = cur.incoming;
    cur_in = cur_in + 1;
  end
  
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

  FIFOF#(PHYSICAL_CHAIN_DATA) passQ <- mkFIFOF();
  PulseWire enW <- mkPulseWire();
  
  interface PHYSICAL_CHAIN_IN incoming;

    method Action try(PHYSICAL_CHAIN_DATA d);
      passQ.enq(d);
      enW.send();
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
