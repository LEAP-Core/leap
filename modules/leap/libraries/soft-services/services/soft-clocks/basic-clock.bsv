//
// Copyright (C) 2010 Massachusetts Institute of Technology
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

import Clocks::*;
import ModuleContext::*;

`include "asim/provides/fpga_components.bsh"
`include "asim/provides/clocks_device.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_clocks_lib.bsh"

instance SOFT_SERVICE#(LOGICAL_CLOCK_INFO);

    module initializeServiceContext (LOGICAL_CLOCK_INFO);

        let clock <- exposeCurrentClock();
        let reset <- exposeCurrentReset();

        return LOGICAL_CLOCK_INFO {clk: clock, rst: reset};

    endmodule
    
    module finalizeServiceContext#(LOGICAL_CLOCK_INFO info) (Empty);
        // Currently nothing to do here.
    endmodule

endinstance

instance SYNTHESIZABLE_SOFT_SERVICE#(LOGICAL_CLOCK_INFO, Empty);

    module exposeServiceContext#(LOGICAL_CLOCK_INFO info) (Empty);
        // Currently nothing to do here.
    endmodule

endinstance


module [t_CONTEXT] mkSoftClock#(Integer outputFreq) (UserClock)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CLOCK_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

   // Get a reference to the known clock
   LOGICAL_CLOCK_INFO modelClock <- getContext();
   let returnClock <- mkUserClockFromFrequency(`MODEL_CLOCK_FREQ,
                                               outputFreq,
                                               clocked_by modelClock.clk, 
                                               reset_by modelClock.rst);
   return returnClock;
endmodule
