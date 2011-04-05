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

//Re-bury connections which have been exposed at synthesis boundaries

typedef Tuple3#(String, String, Integer) ConMap;

// The leap-connect script generates a surrogate using the ConMap tuple.
// Add this information back is as normal connections, except that their
// info actually points at the WITH_CONNECTIONS vector rather than the 
// original connection.

module [CONNECTED_MODULE] addConnections#(WITH_CONNECTIONS#(t_NUM_IN, t_NUM_OUT, t_IFC) mod, List#(ConMap) sends, List#(ConMap) recs) (t_IFC);
   
    // Add Sends
    let nSends = length(sends);
    for (Integer x = 0; x < nSends; x = x + 1)
    begin
      match {.nm, .contype, .idx} = sends[x];
      let inf = LOGICAL_SEND_INFO {logicalName: nm, logicalType: contype, optional: False, outgoing: mod.outgoing[idx]};
      registerSend(inf);
    end

    // Add Recvs
    let nRecs = length(recs);
    for (Integer x = 0; x < nRecs; x = x + 1)
    begin
      match {.nm, .contype, .idx} = recs[x];
      let inf = LOGICAL_RECV_INFO {logicalName:nm, logicalType: contype, optional: False, incoming: mod.incoming[idx]};
      registerRecv(inf);
    end

    // Add Chains
    for (Integer x = 0; x < valueof(CON_NUM_CHAINS); x = x + 1)
    begin
     // Collect up our info.
     let info = 
         LOGICAL_CHAIN_INFO 
         {
             logicalIdx: x, 
             logicalType: "", 
             incoming: mod.chains[x].incoming,
             outgoing: mod.chains[x].outgoing
         };

     // Register the chain
     registerChain(info);
    end

    return mod.device;

endmodule
