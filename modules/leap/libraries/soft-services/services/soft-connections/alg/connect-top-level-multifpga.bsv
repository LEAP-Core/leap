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

`include "awb/provides/physical_platform_utils.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_interconnect.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_connections_alg.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"


// instatiateWithConnections
// Connect all remaining connections at the top-level. 
// This includes all one-to-many and many-to-one connections,
// and all shared interconnects.

// For backwards compatability we also still handle chains.
// Called at the top level, very similar to with connections now...
module finalizeSoftConnection#(LOGICAL_CONNECTION_INFO info) (Empty);

  Clock clk <- exposeCurrentClock();

  String errorStr = "";

  // Backwards compatability: Connect all chains in the resulting context.
  connectChains(clk, info.chains); 

  // Connect all broadcasts in the resulting context.
  match {.unmatched_sends, .unmatched_recvs} <- connectMulticasts(clk, info);

  // Connect all trees in the resulting context.
  // Eventually more physical interconnects will be supported.
  connectStationsTree(clk, info);

  // Error out if there are dangling connections
  // however, "model" where this is called may be on another FPGA.  So, unmatched things 
  // are acceptable - the generated 
  Bool error_occurred = False;
  // Final Dangling sends
  for (Integer x = 0; x < List::length(unmatched_sends); x = x + 1)
  begin
    let cur = unmatched_sends[x];
  
    // clear out leftovers from model top level 
    if(cur.computePlatform != fpgaPlatformName)
      begin
	let newStr <- printSend(cur);
        errorStr = "Dropping: " + newStr + errorStr;	
      end
    else if(cur.computePlatform == fpgaPlatformName && `IGNORE_PLATFORM_MISMATCH == 1)
      begin
        // In this case we should display the unmatched connection
        printDanglingSend(x,cur);
	let newStr <- printSend(cur);
        errorStr = "Matched Send: " + newStr + errorStr;	
      end
    else if (!cur.optional)
      begin
        messageM("ERROR: Unmatched logical send: ");
	let newStr <- printSend(cur);
        errorStr = "ERROR: Unmatched logical send" + integerToString(x) + ": " + newStr + errorStr;	
        error_occurred = True;
      end
  end

  // Final Dangling recvs
  for (Integer x = 0; x < List::length(unmatched_recvs); x = x + 1)
  begin
    let cur = unmatched_recvs[x];
    messageM("Working on: " + fpgaPlatformName);
    // clear out leftovers from model top level 
    if(cur.computePlatform != fpgaPlatformName)
      begin
        messageM("Top Level Dropping Recv: ");
	let newStr <- printRecv(cur);		 
        errorStr = "Dropping Top Level: " + newStr + errorStr; 
      end
    else if(cur.computePlatform == fpgaPlatformName && `IGNORE_PLATFORM_MISMATCH == 1)
      begin
        // In this case we should display the unmatched connection
        printDanglingRecv(x,cur);
	let newStr <- printRecv(cur);		 
        errorStr = "Matched Recv: " + newStr + errorStr; 
      end
    else if (!cur.optional)
      begin
        messageM("ERROR: Unmatched logical receive: ");
	let newStr <- printRecv(cur);		 
        errorStr = "ERROR: Unmatched logical receive " + integerToString(x) + ": " + newStr + errorStr; 
        error_occurred = True;
      end
  end

  // Emit the global string table
  printGlobStrings(info.globalStrings);

  if (error_occurred)
    error("\nError: Unmatched logical connections at top level. \n" + errorStr);

endmodule


// connectChains

// Backwards Compatability: Connection Chains

module connectChains#(Clock c, List#(LOGICAL_CHAIN_INFO) chains) ();

    for (Integer x = 0; x < length(chains); x = x + 1)
      begin		
        // Iterate through the chains.
        let chn = chains[x];
        if(`CLOSE_CHAINS == 1)
          begin
            messageM("Closing Chain: [" + chn.logicalName + "]");
            connectOutToIn(chn.outgoing, chn.incoming);
          end
        else
          begin
            printChain(x,chn);
          end
      end
    
endmodule
