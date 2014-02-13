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
