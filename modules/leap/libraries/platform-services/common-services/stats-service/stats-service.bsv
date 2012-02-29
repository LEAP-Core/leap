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
`include "awb/dict/STATS.bsh"


module [CONNECTED_MODULE] mkStatsService
    // interface:
    ();

    // ****** State Elements ******

    // Communication link to the Stats themselves
    Connection_Chain#(STAT_DATA) chain <- mkConnection_Chain(`RINGID_STATS);

    // Communication to/from software
    ClientStub_STATS clientStub <- mkClientStub_STATS();
    ServerStub_STATS serverStub <- mkServerStub_STATS();

    // ****** Rules ******

    //
    // Rules receiving incoming commands
    //
    rule beginVectorLengths (True);
        let dummy <- serverStub.acceptRequest_GetVectorLengths();
        chain.sendToNext(ST_GET_LENGTH);
    endrule

    rule beginDump (True);
        let dummy <- serverStub.acceptRequest_DumpStats();
        chain.sendToNext(ST_DUMP);
    endrule

    rule beginReset (True);
        let dummy <- serverStub.acceptRequest_Reset();
        chain.sendToNext(ST_RESET);
    endrule

    rule beginToggle (True);
        let dummy <- serverStub.acceptRequest_Toggle();
        chain.sendToNext(ST_TOGGLE);
    endrule


    //
    // processResp --
    //
    //     Process responses returning on the statistics ring.
    //
    rule processResp (True);
        let st <- chain.recvFromPrev();

        case (st) matches
            tagged ST_VAL .stinfo: // A stat to dump
                clientStub.makeRequest_ReportStat(zeroExtend(stinfo.statID),
                                                  stinfo.index,
                                                  zeroExtend(stinfo.value));

            tagged ST_LENGTH .stinfo: // A stat vector length
                clientStub.makeRequest_SetVectorLength(zeroExtend(stinfo.statID),
                                                       stinfo.length,
                                                       zeroExtend(pack(stinfo.buildArray)));

            tagged ST_GET_LENGTH:  // We're done getting lengths
                serverStub.sendResponse_GetVectorLengths(0);

            tagged ST_DUMP:  // We're done dumping
                serverStub.sendResponse_DumpStats(0);

            tagged ST_RESET:  // We're done reseting
                serverStub.sendResponse_Reset(0);

            tagged ST_TOGGLE:  // We're done toggling
                serverStub.sendResponse_Toggle(0);
        endcase
    endrule
endmodule
