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
  String errorStr = "";
  // Final Dangling sends
  for (Integer x = 0; x < List::length(unmatched_sends); x = x + 1)
  begin
    let cur = unmatched_sends[x];
    let cur_name = ctHashKey(cur);
    let cur_entry = ctHashValue(cur);
    if (!cur_entry.optional)
      begin
        messageM("ERROR: Unmatched logical send: " +  cur_name);
	let newStr <- printSend(cur);
        errorStr = "Unmatched Send: " + newStr + errorStr;	
        error_occurred = True;
      end
  end

  // Final Dangling recvs
  for (Integer x = 0; x < List::length(unmatched_recvs); x = x + 1)
  begin
    let cur = unmatched_recvs[x];
    let cur_name = ctHashKey(cur);
    let cur_entry = ctHashValue(cur);
    if (!cur_entry.optional)
      begin
        messageM("ERROR: Unmatched logical receive: " + cur_name);
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
