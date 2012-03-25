//
// Copyright (C) 2009 Massachusetts Institute of Technology
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

`include "awb/rrr/client_stub_STATS.bsh"
`include "awb/rrr/server_stub_STATS.bsh"


module [CONNECTED_MODULE] mkStatsService
    // interface:
    ();

    // ****** State Elements ******

    // Communication link to the Stats themselves
    CONNECTION_CHAIN#(STAT_DATA) chain <- mkConnectionChain("StatsRing");

    // Communication to/from software
    ClientStub_STATS clientStub <- mkClientStub_STATS();
    ServerStub_STATS serverStub <- mkServerStub_STATS();

    // ****** Rules ******

    //
    // Rules receiving incoming commands
    //
    rule beginInit (True);
        let dummy <- serverStub.acceptRequest_DoInit();
        chain.sendToNext(ST_INIT);
    endrule

    rule beginDump (True);
        let dummy <- serverStub.acceptRequest_DumpStats();
        chain.sendToNext(ST_DUMP);
    endrule

    rule beginEnable (True);
        let dummy <- serverStub.acceptRequest_Enable();
        chain.sendToNext(ST_ENABLE);
    endrule

    rule beginDisable (True);
        let dummy <- serverStub.acceptRequest_Disable();
        chain.sendToNext(ST_DISABLE);
    endrule


    //
    // processResp --
    //
    //     Process responses returning on the statistics ring.
    //
    rule processResp (True);
        let st <- chain.recvFromPrev();

        case (st) matches
            tagged ST_VAL .stinfo:
                // A stat to dump
                clientStub.makeRequest_ReportStat(zeroExtend(stinfo.desc),
                                                  zeroExtend(stinfo.index),
                                                  zeroExtend(stinfo.value));

            tagged ST_INIT_RSP .node_desc:
                // Describe a node
                clientStub.makeRequest_NodeInfo(zeroExtend(node_desc));

            //
            // Signal completion of requests to software...
            //

            tagged ST_INIT:
                serverStub.sendResponse_DoInit(0);

            tagged ST_DUMP:
                serverStub.sendResponse_DumpStats(0);

            tagged ST_ENABLE:
                serverStub.sendResponse_Enable(0);

            tagged ST_DISABLE:
                serverStub.sendResponse_Disable(0);
        endcase
    endrule
endmodule
