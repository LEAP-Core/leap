import FIFOF::*;
import Clocks::*;
import ModuleContext::*;
import HList::*;

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/physical_interconnect.bsh"
`include "asim/provides/soft_connections_common.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_services_lib.bsh"


// instatiateWithConnections
// Connect all remaining connections at the top-level. 
// This includes all one-to-many and many-to-one connections,
// and all shared interconnects.

// For backwards compatability we also still handle chains.

module finalizeSoftConnection#(LOGICAL_CONNECTION_INFO info) (Empty);

  Clock clk <- exposeCurrentClock();

  // Backwards compatability: Connect all chains in the resulting context.
  connectChains(clk, info.chains); 

  // Connect all broadcasts in the resulting context.
  match {.unmatched_sends, .unmatched_recvs} <- connectMulticasts(clk, info);

  // Connect all trees in the resulting context.
  // Eventually more physical interconnects will be supported.
  connectStationsTree(clk, info);

  // Error out if there are dangling connections
  Bool error_occurred = False;
  // Final Dangling sends
  for (Integer x = 0; x < List::length(unmatched_sends); x = x + 1)
  begin
    let cur = unmatched_sends[x];
    if (!cur.optional)
      begin
        messageM("ERROR: Unmatched logical send: " +  cur.logicalName);
        error_occurred = True;
      end
  end

  // Final Dangling recvs
  for (Integer x = 0; x < List::length(unmatched_recvs); x = x + 1)
  begin
    let cur = unmatched_recvs[x];
    if (!cur.optional)
      begin
        messageM("ERROR: Unmatched logical receive: " + cur.logicalName);
        error_occurred = True;
      end
  end

  if (error_occurred)
    error("Error: Unmatched logical connections at top level.");

endmodule


// connectChains

// Backwards Compatability: Connection Chains

module connectChains#(Clock c, Vector#(CON_NUM_CHAINS, List#(LOGICAL_CHAIN_INFO)) chains) ();

    for (Integer x = 0; x < valueof(CON_NUM_CHAINS); x = x + 1)
    begin
		
        // Iterate through the chains.
        let chn = chains[x];
        
        // Close non-nil chains off.
        if (!List::isNull(chn))
        begin

            let latest_link = List::head(chn);
            let earliest_link = List::last(chn);
            // This is the reverse of the non-top level way, because we are
            // closing the chain.
            messageM("Closing Chain: [" + integerToString(x) + "]");
            connectOutToIn(earliest_link.outgoing, latest_link.incoming);

        end
        else
        begin
            messageM("Skipping Empty Chain: [" + integerToString(x) + "].");
        end

    end
    
endmodule
