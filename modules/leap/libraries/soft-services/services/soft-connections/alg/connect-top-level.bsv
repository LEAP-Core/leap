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

import FIFOF::*;
import Clocks::*;
import ModuleContext::*;
import HList::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_interconnect.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"


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

  // Emit the global string table
  printGlobStrings(info.globalStrings);

  if (error_occurred)
    error("Error: Unmatched logical connections at top level.");

endmodule


// connectChains

// connectChains

// Backwards Compatability: Connection Chains

module connectChains#(Clock c, List#(LOGICAL_CHAIN_INFO) chains) ();

    for (Integer x = 0; x < length(chains); x = x + 1)
      begin		
        // Iterate through the chains.
        let chn = chains[x];
        messageM("Closing Chain: [" + chn.logicalName + "]");
        connectOutToIn(chn.outgoing, chn.incoming);
      end			     
endmodule
