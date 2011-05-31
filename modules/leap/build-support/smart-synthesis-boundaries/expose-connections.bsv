//
// Copyright (C) 2008 Massachusetts Institute of Technology
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

import FIFOF::*;
import ModuleContext::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_connections_alg.bsh"

// Instantiate a module with connections exposed via "messageM".
// This will be parsed by the "leap-connect" script and passed to the
// instantiator of t_IFC via a generated "surrogate" module.

// Note: This MUST be of module type [Module].

module [Module] instantiateSmartBoundary#(CONNECTED_MODULE#(t_IFC) m) 
    // interface:
    (WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_IFC));

    let ctx = freshContext;

    // Gotta set the initial soft reset to an actual reset line 
    // in order to keep things happy.
    let rst <- exposeCurrentReset();
    ctx.softReset = rst;
    let clk <- exposeCurrentClock();

    match {.new_context, .m2} <- runWithContext(ctx, m);

    // TODO: leap-connect doesn't know about multicasts or stations yet.
    // Therefore for now we just connect them at every synthesis boundary
    // as if it were the toplevel.

    // In the future leap-connect will know about these and we'll do something
    // different - more akin to how Chains are today.

    // Until then this allows them to work within a synthesis boundary, but not
    // across synthesis boundaries.
    match {.new_context2, .m4} <- runWithContext(new_context, connectMulticasts(clk));

    match {.final_context, .m5} <- runWithContext(new_context2, connectStationsTree(clk));

    let x <- toWithConnections(new_context, m2);
    return x;

endmodule

// Connect soft connections as normal, but dangling connections are not an error
// Instead they're exposed as a WITH_CONNECTIONS interface and messages are entered
// into the compilation log recording their address index.
// Connection Chains are not "tied off" but exposed as head and tail


module [Module] toWithConnections#(LOGICAL_CONNECTION_INFO ctx, t_IFC i)       (WITH_CONNECTIONS#(t_NUM_OUT, t_NUM_IN, t_IFC));

    let outs     <- exposeDanglingSends(ctx.unmatchedSends);
    let ins      <- exposeDanglingRecvs(ctx.unmatchedRecvs);

    Vector#(CON_NUM_CHAINS, PHYSICAL_CONNECTION_INOUT) chns = newVector();

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
          chns[x] = (interface PHYSICAL_CONNECTION_INOUT;
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
          chns[x] = (interface PHYSICAL_CONNECTION_INOUT;
                         interface incoming = latest_link.incoming;
                         interface outgoing = earliest_link.outgoing;
                     endinterface);

       end
    end

    interface outgoing = outs;
    interface incoming = ins;
    interface chains = chns;
    interface device = i;

endmodule  


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
      messageM("Dangling Send {" + cur.logicalType + "} [" + integerToString(cur_out) +  "]: " + cur.logicalName);
      res[cur_out] = cur.outgoing;
      cur_out = cur_out + 1;
    end

    // Zero out unused dangling sends
    for (Integer x = cur_out; x < valueOf(n); x = x + 1)
      res[x] = PHYSICAL_CONNECTION_OUT{clock:noClock,reset:noReset}; // XXX this line reads like black magic.

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
      messageM("Dangling Rec {" + cur.logicalType + "} [" + integerToString(cur_in) + "]: " + cur.logicalName);
      res[cur_in] = cur.incoming;
      cur_in = cur_in + 1;
    end

    //Zero out unused dangling recvs
    for (Integer x = cur_in; x < valueOf(n); x = x + 1)
      res[x] = PHYSICAL_CONNECTION_IN{clock:noClock,reset:noReset}; // XXX This line reads like black magic.

    return res;

endmodule
  
  

//If there are no links then it's just a pass-through queue

module mkPassThrough
    //interface:
                (PHYSICAL_CONNECTION_INOUT);

    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    FIFOF#(PHYSICAL_CONNECTION_DATA) passQ <- mkFIFOF();
    PulseWire enW <- mkPulseWire();

    interface PHYSICAL_CONNECTION_IN incoming;

      method Action try(PHYSICAL_CONNECTION_DATA d);
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
    interface PHYSICAL_CONNECTION_OUT outgoing;

      method Bool notEmpty() = passQ.notEmpty();
      method PHYSICAL_CONNECTION_DATA first() = passQ.first();
      method Action deq() = passQ.deq();

      interface Clock clock = localClock;
      interface Reset reset = localReset; 

    endinterface

endmodule
