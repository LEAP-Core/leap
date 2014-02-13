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

`include "awb/provides/librl_bsv_base.bsh"


// tree-helper.bsv

// Convenient helper functions for the tree network.


// mkEmptyRoot

// Rather than have a special case for the root node, it's easier to just 
// wrap the root in something that drops all incoming requests.
// Note that these requests should only originate from multicasts.

module mkEmptyRoot#(PHYSICAL_STATION st) ();

    rule dropInc (st.outgoing.notEmpty());
        st.outgoing.deq();
    endrule

endmodule

// checkConnectionTypes

// When connecting two logical connections, test if they were originally the same type.

module checkConnectionTypes#(LOGICAL_SEND_ENTRY sEntry, LOGICAL_RECV_ENTRY rEntry) ();

    let name = ctHashKey(sEntry);
    let send_info = ctHashValue(sEntry);
    let recv_info = ctHashValue(rEntry);

    if (send_info.logicalType != recv_info.logicalType)
    begin
        messageM("Mismatched types for connection " + name); 
        messageM("        Send type: " + send_info.logicalType);
        messageM("     Receive type: " + recv_info.logicalType);
        return error("Connection type error.");
    end

endmodule


// checkMultiConnectionTypes

// When we find two listeners to the same multicast, make sure they are the same type.

module checkMultiConnectionTypes#(LOGICAL_RECV_ENTRY rEntry1, LOGICAL_RECV_ENTRY rEntry2) ();

    let name = ctHashKey(rEntry1);
    let recv_info1 = ctHashValue(rEntry1);
    let recv_info2 = ctHashValue(rEntry2);

    if (recv_info1.logicalType != recv_info2.logicalType)
    begin
        messageM("Inconsistent types for one-to-many connection " + name);
        messageM("       First type: " + recv_info1.logicalType);
        messageM("      Second type: " + recv_info2.logicalType);
        return error("Connection type error.");
    end

endmodule


// Printing Functions

// Various functions for printing debugging information

module printStationInfo#(PHYSICAL_STATION_INFO info) ();

    messageM("Outgoing Info:");

    for (Integer x = 0; x < length(info.outgoingInfo); x = x + 1)
    begin
        let sendInfo = info.outgoingInfo[x];
        // messageM(sendInfo.logicalName);
    
    end

    messageM("Incoming Info:");

    for (Integer x = 0; x < length(info.incomingInfo); x = x + 1)
    begin
        let recvInfo = info.incomingInfo[x];
        // messageM(recvInfo.logicalName);
    
    end

    messageM("From Parent:");

    for (Integer x = 0; x < length(info.routingTable.fromParent); x = x + 1)
    begin
        let parentInfo = info.routingTable.fromParent[x];
        printRoutingDecision(parentInfo);
    
    end

    messageM("From Children:");

    if (length(info.routingTable.fromChild) == 0)
        messageM("<NIL>");

    for (Integer x = 0; x < length(info.routingTable.fromChild); x = x + 1)
    begin
        messageM("From Child:");
        let childInfo = info.routingTable.fromChild[x];
        if (length(childInfo) == 0)
            messageM("<NIL>");
        for (Integer y = 0; y < length(childInfo); y = y + 1)
        begin
            printRoutingDecision(childInfo[y]);
        end
    
    end

    messageM("From Multi:");

    if (length(info.routingTable.fromMulti) == 0)
        messageM("<NIL>");

    for (Integer x = 0; x < length(info.routingTable.fromMulti); x = x + 1)
    begin
        let multiInfo = info.routingTable.fromMulti[x];
        printMulticastInfo(multiInfo);
    
    end
endmodule

module printMulticastInfo#(MULTICAST_INFO info) ();

    messageM("Children Need:");

    for (Integer x = 0; x < length(info.childrenNeed); x = x + 1)
    begin
        case (info.childrenNeed[x]) matches
            tagged Invalid: messageM("N");
            tagged Valid .d: messageM("Y " + bitToString(d));
        endcase
    end
    
    if (info.parentNeed matches tagged Valid .d)
    begin
        messageM("Parent Needs " + bitToString(d));
    end

endmodule

module printRoutingDecision#(ROUTING_DECISION r) ();

    case (r) matches
        tagged ROUTE_parent .d: messageM("ToParent " + bitToString(d));
        tagged ROUTE_child {.c, .d}: messageM("ToChild " + bitToString(c) + " " + bitToString(d));
        tagged ROUTE_multicast .midx: messageM("Multi " + bitToString(midx));
    endcase

endmodule
