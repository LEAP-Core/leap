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

import GetPut::*;
import Connectable::*;

`include "awb/rrr/client_stub_STATS.bsh"
`include "awb/rrr/server_stub_STATS.bsh"

//
// Commands that may be passed to the Command port in hardware.  This
// enumeration must match the C++ equivalent.
//
typedef enum
{
    STATS_SERVER_CMD_INIT,
    STATS_SERVER_CMD_DUMP,
    STATS_SERVER_CMD_ENABLE,
    STATS_SERVER_CMD_DISABLE
}
STATS_SERVER_COMMAND
    deriving (Bits, Eq);


module [CONNECTED_MODULE] mkStatsService
    // interface:
    ();

    // ****** State Elements ******

    // Communication link to the Stats themselves
    GP_MARSHALLED_CHAIN#(STATS_MAR_CHAIN_DATA, STAT_DATA) chainGP <-
        mkGPMarshalledConnectionChain("StatsRing");
    let chainGet = tpl_1(chainGP).get;
    let chainPut = tpl_2(chainGP).put;

    // Communication to/from software
    ClientStub_STATS clientStub <- mkClientStub_STATS();
    ServerStub_STATS serverStub <- mkServerStub_STATS();

    // ****** Rules ******

    //
    // Rules receiving incoming commands
    //
    rule acceptCommand (True);
        let cmd <- serverStub.acceptRequest_Command();

        case (unpack(truncate(cmd)))
            STATS_SERVER_CMD_INIT:    chainPut(ST_INIT);
            STATS_SERVER_CMD_DUMP:    chainPut(ST_DUMP);
            STATS_SERVER_CMD_ENABLE:  chainPut(ST_ENABLE);
            STATS_SERVER_CMD_DISABLE: chainPut(ST_DISABLE);
        endcase
    endrule


    //
    // processResp --
    //
    //     Process responses returning on the statistics ring.
    //
    rule processResp (True);
        let st <- chainGet();

        case (st) matches
            tagged ST_VAL .stinfo:
                // A stat to dump
            begin
                clientStub.makeRequest_ReportStat(zeroExtend(stinfo.desc),
                                                  zeroExtend(stinfo.index),
                                                  zeroExtend(stinfo.value));
            end

            tagged ST_INIT_RSP .node_desc:
            begin
                // Describe a node
                clientStub.makeRequest_NodeInfo(zeroExtend(node_desc));
            end

            //
            // Signal completion of requests to software...
            //

            tagged ST_INIT:
            begin
                clientStub.makeRequest_Ack(zeroExtend(pack(STATS_SERVER_CMD_INIT)));
            end

            tagged ST_DUMP:
            begin
                clientStub.makeRequest_Ack(zeroExtend(pack(STATS_SERVER_CMD_DUMP)));
            end

            tagged ST_ENABLE:
            begin
                clientStub.makeRequest_Ack(zeroExtend(pack(STATS_SERVER_CMD_ENABLE)));
            end

            tagged ST_DISABLE:
            begin
                clientStub.makeRequest_Ack(zeroExtend(pack(STATS_SERVER_CMD_DISABLE)));
            end
        endcase
    endrule
endmodule
