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
import Vector::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/common_services.bsh"

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
//    provisos(Add#(TMax#(TLog#(a__), 1), b__, 12));
    List#(CONNECTION_LATENCY_INFO) info <- getConnectionLatencyInfo();
    let synth_plat_uid <- getSynthesisBoundaryPlatformID();
    let synth_local_uid <- getSynthesisBoundaryID();

    //  Unfortunately the stats vector requires a concrete vector length
    //  Probably it could be rewritten not to require this, but it would not 
    //  be a good use of time. Instead, I will fill in the last vector with 
    //  some garbage names... 
    function genNames(Integer i);
        String s = "XXX Garbage Stat " + integerToString(i) + integerToString(synth_plat_uid)+ integerToString(synth_local_uid);
        return statName(s,s);
    endfunction

    Vector#(16,STAT_ID) baseID = genWith(genNames);
    Vector#(16,STAT_ID) tempID = baseID;
    Vector#(16,function Bool f()) incrs = replicate(?);

    Integer index = 0;

    if (`CON_LATENCY_ENABLE != 0)
    begin
        while (info matches tagged Nil ? False : True)
        begin
            let elem = List::head(info);
            messageM("LATENCY: " + elem.sendName);

            let id = statName(elem.sendName + "_SENT_"+ integerToString(synth_plat_uid)+ integerToString(synth_local_uid), elem.sendName + "_SENT_" + integerToString(synth_plat_uid)+ integerToString(synth_local_uid));

            tempID[index] = id;
            incrs[index] = elem.control.incrStat;
            if(index + 1 == 16)
            begin
                index = 0;
                STAT_ID ids[16] = vectorToArray(tempID);
                STAT_VECTOR#(16) stats <- mkStatCounter_Vector(ids);
                tempID = baseID;
                for(Integer i = 0; i < 16; i = i + 1)
                begin 
                    rule doIncr(incrs[i]);
                        stats.incr(fromInteger(i));                       
                    endrule
                end     
                
                tempID = baseID;
                incrs = replicate(?);   
            end
            else 
            begin
                index = index + 1; 
            end

            // Set up a parameter node for every soft connection
            PARAMETER_NODE paramNode <- mkDynamicParameterNode();
            GLOBAL_STRING_UID tag <- getGlobalStringUID(elem.sendName + "_LATENCY_TEST");
            Param#(SizeOf#(GLOBAL_STRING_UID)) idExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_ID,paramNode);
            Param#(1) inverseTest <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_INVERSE_TEST,paramNode);
            Param#(SizeOf#(LATENCY_FIFO_DELAY_CONTAINER)) delayExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_DELAY,paramNode);
            //Param#(SizeOf#(LATENCY_FIFO_DEPTH_CONTAINER)) depthExternal <- mkDynamicParameter(`PARAMS_SOFT_CONNECTIONS_LATENCY_DELTA_DEPTH,paramNode);

            rule driveIface(((idExternal == tag) &&  !unpack(inverseTest)) ||
                            ((idExternal != tag) &&  unpack(inverseTest)));
                elem.control.setControl(True);
                elem.control.setDelay(delayExternal);
                //elem.control.setDepth(depthExternal);
            endrule

            info = List::tail(info);
        end

        // We have some stats left over...
        if(index != 0)
        begin 
            STAT_ID ids[16] = vectorToArray(tempID);
            STAT_VECTOR#(16) stats <- mkStatCounter_Vector(ids);
            tempID = baseID;
            for(Integer i = 0; i < index; i = i + 1)
            begin 
                rule doIncr(incrs[i]);
                    stats.incr(fromInteger(i));                       
                endrule
            end     
        end
    end
endmodule
