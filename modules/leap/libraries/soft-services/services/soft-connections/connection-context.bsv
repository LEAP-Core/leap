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

import ModuleContext::*;

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections_common.bsh"

// ****** Connection Context Support Functions ******

// These are Bluespec modules just to work with ModuleContext.
// By most definitions they should be thought of as functions.

// Modules with empty interfaces are like C++ functions that return
// void. They only have a side effect on the context.

// Otherwise the "interface" of the module is actually the return
// type of the function.

// ****** Accessors ******

// These just access the specified field.

module [t_CONTEXT] getSynthesisBoundaryPlatform (String)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.synthesisBoundaryPlatform;

endmodule

module [t_CONTEXT] getSynthesisBoundaryPlatformID (Integer)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.synthesisBoundaryPlatformID;

endmodule

module [t_CONTEXT] getSynthesisBoundaryID (Integer)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.synthesisBoundaryID;

endmodule

module [t_CONTEXT] getSynthesisBoundaryName (String)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.synthesisBoundaryName;

endmodule

module [t_CONTEXT] getUnmatchedSends (LOGICAL_SEND_INFO_TABLE)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedSends;

endmodule


module [t_CONTEXT] printUnmatchedSends (Empty)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let m <- getUnmatchedSends();
    printSends(m);

endmodule

module [t_CONTEXT] getUnmatchedRecvs (LOGICAL_RECV_INFO_TABLE)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedRecvs;

endmodule

module [t_CONTEXT] printUnmatchedRecvs (Empty)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let m <- getUnmatchedRecvs();
    printRecvs(m);

endmodule


module [t_CONTEXT] getUnmatchedSendMultis (List#(LOGICAL_SEND_MULTI_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedSendMultis;

endmodule

module [t_CONTEXT] getUnmatchedRecvMultis (List#(LOGICAL_RECV_MULTI_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedRecvMultis;

endmodule

module [t_CONTEXT] getStationInfos (List#(STATION_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.stations;

endmodule

module [t_CONTEXT] getStationStack (List#(STATION))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.stationStack;

endmodule

module [t_CONTEXT] getRootStationName (String)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.rootStationName;

endmodule

module [t_CONTEXT] getSoftReset (Reset)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.softReset;

endmodule

// BACKWARDS COMPATABILITY: Connection Chains

module [t_CONTEXT] getChain#(LOGICAL_CHAIN_INFO descriptor) (Maybe#(LOGICAL_CHAIN_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return List::find(nameMatches(False, descriptor),ctxt.chains);

endmodule

module [t_CONTEXT] getExposeAllConnections (Bool)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.exposeAllConnections;

endmodule

// Service clients and servers

module [t_CONTEXT] getUnmatchedServiceClients (List#(LOGICAL_SERVICE_CLIENT_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedServiceClients;

endmodule

module [t_CONTEXT] getUnmatchedServiceServers (List#(LOGICAL_SERVICE_SERVER_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedServiceServers;

endmodule


// ****** Mutators *******

// These update the field to the given value.

module [t_CONTEXT] putSynthesisBoundaryPlatform#(String new_name) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.synthesisBoundaryPlatform = new_name;
    putContext(ctxt);
endmodule

module [t_CONTEXT] putSynthesisBoundaryPlatformID#(Integer new_id) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.synthesisBoundaryPlatformID = new_id;
    putContext(ctxt);

endmodule

module [t_CONTEXT] putSynthesisBoundaryID#(Integer new_id) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.synthesisBoundaryID = new_id;
    putContext(ctxt);

endmodule

module [t_CONTEXT] putSynthesisBoundaryName#(String new_name) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.synthesisBoundaryName = new_name;
    putContext(ctxt);

endmodule

// putUnmatchedSends

module [t_CONTEXT] putUnmatchedSends#(LOGICAL_SEND_INFO_TABLE new_sends) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedSends = new_sends;
    putContext(ctxt);

endmodule


// putUnmatchedRecvs

module [t_CONTEXT] putUnmatchedRecvs#(LOGICAL_RECV_INFO_TABLE new_recvs) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedRecvs = new_recvs;
    putContext(ctxt);

endmodule

// putUnmatchedSendMultis

module [t_CONTEXT] putUnmatchedSendMultis#(List#(LOGICAL_SEND_MULTI_INFO) new_sends) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedSendMultis = new_sends;
    putContext(ctxt);

endmodule


// putUnmatchedRecvMultis

module [t_CONTEXT] putUnmatchedRecvMultis#(List#(LOGICAL_RECV_MULTI_INFO) new_recvs) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedRecvMultis = new_recvs;
    putContext(ctxt);

endmodule

// putStations

module [t_CONTEXT] putStationInfos#(List#(STATION_INFO) new_stations) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.stations = new_stations;
    putContext(ctxt);

endmodule

// putStationStack

module [t_CONTEXT] putStationStack#(List#(STATION) new_stations) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.stationStack = new_stations;
    putContext(ctxt);

endmodule

// putRootStationName

module [t_CONTEXT] putRootStationName#(String new_root) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.rootStationName = new_root;
    putContext(ctxt);

endmodule

// putSoftReset

module [t_CONTEXT] putSoftReset#(Reset new_reset) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.softReset = new_reset;
    putContext(ctxt);

endmodule

// putChain

module [t_CONTEXT] putChain#(LOGICAL_CHAIN_INFO chain) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.chains = List::cons(chain,List::filter(nameDoesNotMatch(False, chain),ctxt.chains));
    putContext(ctxt);

endmodule

module [t_CONTEXT] putExposeAllConnections#(Bool exposeAllConnections) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.exposeAllConnections = exposeAllConnections;
    putContext(ctxt);

endmodule

// putServiceClient

module [t_CONTEXT] putUnmatchedServiceClients#(List#(LOGICAL_SERVICE_CLIENT_INFO) new_clients) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedServiceClients = new_clients;
    putContext(ctxt);

endmodule

// putServiceServer

module [t_CONTEXT] putUnmatchedServiceServers#(List#(LOGICAL_SERVICE_SERVER_INFO) new_servers) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedServiceServers = new_servers;
    putContext(ctxt);

endmodule

// ****** Non-Primitive Mutators ******

// addUnmatchedSend/Recv

// Add a new send/recv to the list.

module [t_CONTEXT] addUnmatchedSend#(String logicalName, LOGICAL_SEND_INFO new_send) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let sends <- getUnmatchedSends();
    putUnmatchedSends(ctHashTableInsert(sends, logicalName, new_send));

endmodule

module [t_CONTEXT] addUnmatchedRecv#(String logicalName, LOGICAL_RECV_INFO new_recv) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let recvs <- getUnmatchedRecvs();
    putUnmatchedRecvs(ctHashTableInsert(recvs, logicalName, new_recv));

endmodule

module [t_CONTEXT] addUnmatchedSendMulti#(LOGICAL_SEND_MULTI_INFO new_send) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let sends <- getUnmatchedSendMultis();
    putUnmatchedSendMultis(List::cons(new_send, sends));

endmodule

module [t_CONTEXT] addUnmatchedRecvMulti#(LOGICAL_RECV_MULTI_INFO new_recv) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let recvs <- getUnmatchedRecvMultis();
    putUnmatchedRecvMultis(List::cons(new_recv, recvs));

endmodule

module [t_CONTEXT] addUnmatchedServiceClient#(LOGICAL_SERVICE_CLIENT_INFO new_client) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let clients <- getUnmatchedServiceClients();
    putUnmatchedServiceClients(List::cons(new_client,clients));

endmodule

module [t_CONTEXT] addUnmatchedServiceServer#(LOGICAL_SERVICE_SERVER_INFO new_server) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let servers <- getUnmatchedServiceServers();
    putUnmatchedServiceServers(List::cons(new_server,servers));

endmodule

// removeUnmatchedSend/Recv

// Remove an unmatched send/recv (usually because it's been matched). 

// Use strong == here.  

module [t_CONTEXT] removeUnmatchedSend#(LOGICAL_SEND_ENTRY send) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let sends <- getUnmatchedSends();

    // Remove entry from the hash table
    LOGICAL_SEND_INFO_TABLE_IDX idx = ctHash(ctHashKey(send));
    sends.tbl[idx] = List::filter(nameDoesNotMatch(False,send), sends.tbl[idx]);

    putUnmatchedSends(sends);

endmodule

module [t_CONTEXT] removeUnmatchedRecv#(LOGICAL_RECV_ENTRY recv) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let recvs <- getUnmatchedRecvs();

    // Remove entry from the hash table
    LOGICAL_RECV_INFO_TABLE_IDX idx = ctHash(ctHashKey(recv));
    recvs.tbl[idx] = List::filter(nameDoesNotMatch(False,recv), recvs.tbl[idx]);

    putUnmatchedRecvs(recvs);

endmodule

module [t_CONTEXT] removeUnmatchedSendMulti#(String sname) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let sends <- getUnmatchedSendMultis();
    let new_sends = List::filter(primNameDoesNotMatch(sname), sends);
    putUnmatchedSendMultis(new_sends);

endmodule

module [t_CONTEXT] removeUnmatchedRecvMulti#(String rname) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let recvs <- getUnmatchedRecvMultis();
    let new_recvs = List::filter(primNameDoesNotMatch(rname), recvs);
    putUnmatchedRecvMultis(new_recvs);

endmodule

module [t_CONTEXT] removeUnmatchedServiceClient#(LOGICAL_SERVICE_CLIENT_INFO client) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let clients <- getUnmatchedServiceClients();

    function Tuple2#(Bool, List#(LOGICAL_SERVICE_CLIENT_INFO)) removeNameAndIdMatchClient(String name, 
                                                                                          String id, 
                                                                                          Tuple2#(Bool, List#(LOGICAL_SERVICE_CLIENT_INFO)) tup,
                                                                                          LOGICAL_SERVICE_CLIENT_INFO c);
        match {.is_matched, .rest_clients} = tup;
        let new_list_1 = rest_clients;
        let new_list_2 = List::replicate(1, c);
        if (is_matched) // Already found the matched client before
        begin
            return tuple2(is_matched, List::append(new_list_1, new_list_2));
        end
        else if (serviceNameIdMatches(name, id, c)) // The matched client is found and should be removed (do not append)
        begin
            return tuple2(True, new_list_1);
        end
        else
        begin
            return tuple2(False, List::append(new_list_1, new_list_2));
        end
    endfunction
    
    // Remove the first matched service client (there might be multiple matched clients if clientId is "undefined")
    match {.matched, .new_clients} = List::foldl(removeNameAndIdMatchClient(client.logicalName, client.clientId), 
                                                 tuple2(False, tagged Nil), 
                                                 clients);
    
    putUnmatchedServiceClients(new_clients);

endmodule

module [t_CONTEXT] removeUnmatchedServiceServer#(LOGICAL_SERVICE_SERVER_INFO server) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let servers <- getUnmatchedServiceServers();
    let new_servers = List::filter(primNameDoesNotMatch(server.logicalName), servers);
    putUnmatchedServiceServers(new_servers);

endmodule

// findStationInfo

// Find the info associated with a a station name (or error).

function STATION_INFO findStationInfo(String station_name, List#(STATION_INFO) st_infos);

    Bool found = False;
    STATION_INFO res = ?;

    while (!List::isNull(st_infos) && !found)
    begin
        STATION_INFO cur = List::head(st_infos);
        if (cur.stationName == station_name)
        begin
            found = True;
            res = cur;
        end
        st_infos = List::tail(st_infos);
    end

    if (found)
      return res;
    else
      return error("Could not find a Station named " + station_name);

endfunction

// updateStationInfo

// Update a given station's info to the new values.

module [t_CONTEXT] updateStationInfo#(String station_name, STATION_INFO new_info) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    List#(STATION_INFO) st_infos <- getStationInfos();
    List#(STATION_INFO) new_infos = List::nil;
    Bool found = False;

    while (!found && !List::isNull(st_infos))
    begin
        STATION_INFO cur = List::head(st_infos);
        if (cur.stationName == station_name)
        begin
            new_infos = List::append(List::tail(st_infos), List::cons(new_info, new_infos));
            found = True;
        end
        else
        begin
            new_infos = List::cons(cur, new_infos);
        end
        st_infos = List::tail(st_infos);
    end
    
    if (found)
        putStationInfos(new_infos);
    else
        return error("Could not find a Station named " + station_name);

endmodule

// We arrange logical stations into a stack.
// These functions manipulate the stack.

module [t_CONTEXT] pushStation#(STATION s) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let ss <- getStationStack();
    putStationStack(List::cons(s,ss));

endmodule

module [t_CONTEXT] popStation ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let ss <- getStationStack();
    case (ss) matches
        tagged Nil:
        begin
            error("popStation() called on empty station stack.");
        end
        default:
        begin
            putStationStack(List::tail(ss));
        end
    endcase

endmodule

module [t_CONTEXT] getCurrentStation (STATION)
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let ss <- getStationStack();
    return case (ss) matches
               tagged Nil:
               begin
                   return error("getCurrentStation() called on empty station stack.");
               end
               default:
               begin
                   return (List::head(ss));
               end
           endcase;

endmodule

module [t_CONTEXT] getCurrentStationM (Maybe#(STATION))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let ss <- getStationStack();
    return case (ss) matches
               tagged Nil:
               begin
                   return tagged Invalid;
               end
               default:
               begin
                   return tagged Valid (List::head(ss));
               end
           endcase;

endmodule


// ========================================================================
//
// Debug info
//
// ========================================================================

module [t_CONTEXT] getConnectionDebugInfo (List#(CONNECTION_DEBUG_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.debugInfo;

endmodule


module [t_CONTEXT] addConnectionDebugInfo#(CONNECTION_DEBUG_INFO dbg_info) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.debugInfo = List::cons(dbg_info, ctxt.debugInfo);
    putContext(ctxt);

endmodule

// ========================================================================
//
// Latency control info
//
// ========================================================================

module [t_CONTEXT] getConnectionLatencyInfo (List#(CONNECTION_LATENCY_INFO))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.latencyInfo;

endmodule


module [t_CONTEXT] addConnectionLatencyInfo#(CONNECTION_LATENCY_INFO dbg_info) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.latencyInfo = List::cons(dbg_info, ctxt.latencyInfo);
    putContext(ctxt);

endmodule
