//
// Copyright (C) 2009 Intel Corporation
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


import FIFO::*;

`include "awb/rrr/server_stub_DEBUG_SCAN.bsh"
`include "awb/rrr/client_stub_DEBUG_SCAN.bsh"
`include "awb/dict/PARAMS_DEBUG_SCAN_SERVICE.bsh"
`include "awb/provides/dynamic_parameters_service.bsh"


module [CONNECTED_MODULE] mkDebugScanService
    // interface:
    ();

    // ****** State Elements ******

    // Communication to/from our SW via RRR
    ClientStub_DEBUG_SCAN clientStub <- mkClientStub_DEBUG_SCAN();
    ServerStub_DEBUG_SCAN serverStub <- mkServerStub_DEBUG_SCAN();

    // Communication link to the scan nodes themselves.  We have two links:
    // Ring 0 is the primary ring on the master FPGA.  Ring G is all other FPGAs.
    // This way we at least get status out of ring 0 if the network is broken
    // on a multi-FPGA configuration.
    CONNECTION_CHAIN#(DEBUG_SCAN_DATA) chain0 <- mkConnectionChain("DebugScanRing_0");
    CONNECTION_CHAIN#(DEBUG_SCAN_DATA) chainG <- mkConnectionChain("DebugScanRing_G");
    
    // Dead man's timeout.  Set the parameter to a cycle count interval when
    // debug scan's will be initiated automatically.  This is useful when
    // the host to FPGA channel becomes deadlocked but not the FPGA to host.
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();
    Param#(40) deadLinkTimeout <-
        mkDynamicParameter(`PARAMS_DEBUG_SCAN_SERVICE_DEBUG_SCAN_DEADLINK_TIMEOUT,
                           paramNode);

    Reg#(Bit#(40)) timeout <- mkReg(0);
    FIFO#(Bool) swRequestedScan <- mkFIFO();
    Reg#(Bool) deadLinkDumping <- mkReg(False);

    // ****** Rules ******
  
    //
    // processRRRCheck --
    //     Check that RRR allows I/O in both directions.  For bugs where I/O
    //     is so broken that debug scan doesn't complete, this check lets us
    //     rule out RRR problems.
    //
    rule processRRRCheck (True);
        let v <- serverStub.acceptRequest_CheckRRR();
        serverStub.sendResponse_CheckRRR(v);
    endrule

    //
    // processReq --
    //     Receive a command requesting a scan dump.
    //
    rule processReq (True);
        let dummy <- serverStub.acceptRequest_Scan();

        // There is only one command:  start a scan
        chain0.sendToNext(tagged DS_DUMP);
        swRequestedScan.enq(True);
    endrule

    //
    // Done fires when software confirms all dump data has been received.
    // At that point it is safe to return from the Scan() request.
    //
    (* descending_urgency = "done, processRRRCheck" *)
    rule done (True);
        let dummy <- clientStub.getResponse_Done();
        serverStub.sendResponse_Scan(0);
    endrule

    //
    // processResp0 --
    //
    // Process a response from an individual scan node on the master chain.
    //  
    (* conservative_implicit_conditions *)
    rule processResp0 (True);
        let ds <- chain0.recvFromPrev();

        case (ds) matches
            // A value to dump
            tagged DS_VAL .v:
            begin
                clientStub.makeRequest_Send(v, 0);
            end

            tagged DS_VAL_LAST .v:
            begin
                clientStub.makeRequest_Send(v, 1);
            end

            // Command came all the way around the loop.  Start dumping on the
            // slave FPGAs.
            tagged DS_DUMP:
            begin
                chainG.sendToNext(tagged DS_DUMP);
            end
        endcase
    endrule

    //
    // processRespG --
    //
    // Process a response from an individual scan node on the global slave chain.
    //  
    (* descending_urgency = "processRespG, processResp0" *)
    (* conservative_implicit_conditions *)
    rule processRespG (True);
        let ds <- chainG.recvFromPrev();

        case (ds) matches
            // A value to dump
            tagged DS_VAL .v:
            begin
                clientStub.makeRequest_Send(v, 0);
            end

            tagged DS_VAL_LAST .v:
            begin
                clientStub.makeRequest_Send(v, 1);
            end

            // Command came all the way around the loop.  Done.
            tagged DS_DUMP:
            begin
                if (swRequestedScan.first())
                begin
                    clientStub.makeRequest_Done(?);
                end
                else
                begin
                    deadLinkDumping <= False;
                end

                swRequestedScan.deq();
            end
        endcase
    endrule

    
    //
    // Rules for automatic dumping using timers
    //
    (* no_implicit_conditions, fire_when_enabled *)
    rule timeoutCnt (timeout != 0);
        timeout <= timeout - 1;
    endrule

    (* descending_urgency = "processReq, timeoutTriggerScan" *)
    (* descending_urgency = "processRespG, timeoutTriggerScan" *)
    rule timeoutTriggerScan ((timeout == 0) &&
                             (deadLinkTimeout != 0) &&
                             ! deadLinkDumping);
        chain0.sendToNext(tagged DS_DUMP);
        swRequestedScan.enq(False);
        timeout <= deadLinkTimeout;
        deadLinkDumping <= True;
    endrule
endmodule
