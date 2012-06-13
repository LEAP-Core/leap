//
// Copyright (C) 2012 Intel Corporation
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

import List::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/dynamic_parameters_service.bsh"
`include "awb/dict/PARAMS_SOFT_CONNECTIONS.bsh"


//
// Global strings have two parts:  a component guaranteed constant within a
// given synthesis boundary and a component representing a given string
// within a single synthesis boundary.  In the debug scan messages here
// the synthesis boundary UID is sent only once.
//

//
// mkSoftConnectionDebugInfo --
//     Generate debug scan data for every soft connection FIFO.
//
module [CONNECTED_MODULE] mkSoftConnectionLatencyInfo (Empty);
    List#(CONNECTION_LATENCY_INFO) info <- getConnectionLatencyInfo();

    if (`CON_LATENCY_ENABLE != 0)
    begin
        while (info matches tagged Nil ? False : True)
        begin
            let elem = List::head(info);
            messageM("LATENCY: " + elem.sendName);
            // Set up a parameter node for every soft connection
            PARAMETER_NODE paramNode <- mkDynamicParameterNode();
            GLOBAL_STRING_UID tag <- getGlobalStringUID(elem.sendName + "_LATENCY_TEST");
            Param#(SizeOf#(GLOBAL_STRING_UID)) idExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_ID,paramNode);
            Param#(1) inverseTest <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_INVERSE_TEST,paramNode);
            Param#(SizeOf#(LATENCY_FIFO_DELAY)) delayExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_DELAY,paramNode);
            Param#(SizeOf#(LATENCY_FIFO_DEPTH)) depthExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_DEPTH,paramNode);

            rule driveIface(((idExternal == tag) &&  !unpack(inverseTest)) ||
                            ((idExternal != tag) &&  unpack(inverseTest)));
                elem.control.setControl(True);
                elem.control.setDelay(delayExternal);
                elem.control.setDepth(depthExternal);
            endrule

            info = List::tail(info);
        end
    end
endmodule
