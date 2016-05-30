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

import Clocks::*;

`include "awb/provides/soft_connections_common.bsh"


// ****** Connection Functions ******


// register{Send,Recv}

// Adds a new send/recv. First try to find existing matches, 
// then either connect it or add it to the unmatched list.

module [t_CONTEXT] registerSend#(String logicalName, LOGICAL_SEND_INFO new_send) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    // See if we can find our partner.
    let recvs <- getUnmatchedRecvs();

    LOGICAL_SEND_ENTRY new_send_entry = ctHashEntry(logicalName,
                                                    new_send);
    LOGICAL_SEND_INFO_TABLE_IDX idx = ctHash(new_send_entry);
    let m_match <- findMatchingRecv(new_send_entry, recvs.tbl[idx]);

    case (m_match) matches
        tagged Invalid:   
        begin
            // No match. Add the send to the list.
            addUnmatchedSend(logicalName, new_send);
        end
        tagged Valid .recv:
        begin
            // A 1-to-1 match! Attempt to connect them.
            connect(new_send_entry, recv);
            // The receive is no longer unmatched, so remove it from the list.
            removeUnmatchedRecv(recv);
        end
    endcase

endmodule

module [t_CONTEXT] registerSendMulti#(LOGICAL_SEND_MULTI_INFO new_send) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    // Defer one to many send to the very top level.
    addUnmatchedSendMulti(new_send);

endmodule

module [t_CONTEXT] registerRecv#(String logicalName, LOGICAL_RECV_INFO new_recv) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    // See if we can find our partner.
    let sends <- getUnmatchedSends();

    LOGICAL_RECV_ENTRY new_recv_entry = ctHashEntry(logicalName,
                                                    new_recv);
    LOGICAL_RECV_INFO_TABLE_IDX idx = ctHash(new_recv_entry);
    let m_match <- findMatchingSend(new_recv_entry, sends.tbl[idx]);

    case (m_match) matches
        tagged Invalid:   
        begin
            // No match. Add the recv to the list.
            addUnmatchedRecv(logicalName, new_recv);
        end
        tagged Valid .send:
        begin
            // A match! Attempt to connect them.
            connect(send, new_recv_entry);
            // The send is no longer unmatched, so remove it from the list.
            removeUnmatchedSend(send);
        end
    endcase

endmodule

module [t_CONTEXT] registerRecvMulti#(LOGICAL_RECV_MULTI_INFO new_recv) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    // Defer many to one recvs to the very top level.
    addUnmatchedRecvMulti(new_recv);

endmodule


// BACKWARDS COMPATABILITY: Connection Chains

// These will eventually be subsumed by manyToOne/oneToMany logical connections
// that are then divorced from their physical topology. Until that day arrives
// a Logical and Physical chain is the same thing.

module [t_CONTEXT] registerChain#(LOGICAL_CHAIN_INFO link) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    messageM("Register Chain: [" + link.logicalName + "] Module:"  + link.moduleNameIncoming);

    // See what existing links are out there.
    let existing_links <- getChain(link);

    // If the platforms do not match, drop the chain.  Unless we have been 
    // asked to propagate all connections to the top level.  
    if (existing_links matches tagged Valid .latest_link)
    begin

        // There are other links already, so make sure the types
        // are consistent.
 
        // Make sure connections match or consumer is receiving it as void
        if (link.logicalType != latest_link.logicalType && link.logicalType != "" && latest_link.logicalType != "")
        begin

            // Error out
            error("ERROR: data types for Connection Chain " + link.logicalName + " do not match: \n" + 
                  "Detected existing chain type: " + latest_link.logicalType + 
                  "\nDetected new link type: " + link.logicalType + "\n");

        end
      
        // Good news! We didn't blow up.
        // Actually do the connection, with a new LOGICAL_CHAIN_INFO 
        // This lets us keep a single LOGICAL_CHAIN_INFO
        messageM("Adding Link to Chain: [" + link.logicalName + "] Module:"  + link.moduleNameIncoming);
        connectOutToIn(link.outgoing, latest_link.incoming, 0);

        // Add the new link to the list.
        putChain( LOGICAL_CHAIN_INFO{ logicalName: link.logicalName, 
                                      logicalType: link.logicalType, 
                                      moduleNameIncoming: link.moduleNameIncoming,
                                      moduleNameOutgoing: latest_link.moduleNameOutgoing,
                                      bitWidth: link.bitWidth, 
                                      incoming: link.incoming, 
                                      outgoing: latest_link.outgoing });

    end
    else
    begin

        // It's the first member of the chain, so just add it.
        messageM("Adding Initial Link for Chain: [" + link.logicalName + "]  Module:" + link.moduleNameIncoming );
        putChain(link);

    end

endmodule

//
// registerServiceClient
// Adds a new service client. 
//
module [t_CONTEXT] registerServiceClient#(LOGICAL_SERVICE_CLIENT_INFO link) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    messageM("Register Service Client: [" + link.logicalName + "] Module:"  + link.moduleName);
    
    // See what existing links are out there.
    let clients <- getUnmatchedServiceClients();
    let existing_client = List::find(primNameMatches(link.logicalName), clients);

    let servers <- getUnmatchedServiceServers();
    let existing_server = List::find(primNameMatches(link.logicalName), servers);

    // Do type checks
    if (existing_client matches tagged Valid .latest_client)
    begin
        // Make sure service connections match or consumer is receiving it as void
        if (link.logicalReqType != latest_client.logicalReqType && link.logicalReqType != "" && latest_client.logicalReqType != "")
        begin
            // Error out
            error("ERROR: request types for Connection Service " + link.logicalName + " do not match: \n" + 
                  "Detected existing client request type: " + latest_client.logicalReqType + 
                  "\nDetected new client request type: " + link.logicalReqType + "\n");
        end
        if (link.logicalRespType != latest_client.logicalRespType && link.logicalRespType != "" && latest_client.logicalRespType != "")
        begin
            // Error out
            error("ERROR: response types for Connection Service " + link.logicalName + " do not match: \n" + 
                  "Detected existing client response type: " + latest_client.logicalRespType + 
                  "\nDetected new client response type: " + link.logicalRespType + "\n");
        end
    end
    if (existing_server matches tagged Valid .server)
    begin
        // Make sure service connections match or consumer is receiving it as void
        if (link.logicalReqType != server.logicalReqType && link.logicalReqType != "" && server.logicalReqType != "")
        begin
            // Error out
            error("ERROR: request types for Connection Service " + link.logicalName + " do not match: \n" + 
                  "Detected existing server request type: " + server.logicalReqType + 
                  "\nDetected new client request type: " + link.logicalReqType + "\n");
        end
        if (link.logicalRespType != server.logicalRespType && link.logicalRespType != "" && server.logicalRespType != "")
        begin
            // Error out
            error("ERROR: response types for Connection Service " + link.logicalName + " do not match: \n" + 
                  "Detected existing server response type: " + server.logicalRespType + 
                  "\nDetected new client response type: " + link.logicalRespType + "\n");
        end
    end
    
    // Propagate connections to the top level
    messageM("Adding service client: [" + link.logicalName + "]  Module:" + link.moduleName );
    addUnmatchedServiceClient(link);

endmodule

//
// registerServiceServer
// Adds a new service server. 
//
module [t_CONTEXT] registerServiceServer#(LOGICAL_SERVICE_SERVER_INFO link) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    messageM("Register Service Server: [" + link.logicalName + "] Module:"  + link.moduleName);
    
    // See what existing links are out there.
    let clients <- getUnmatchedServiceClients();
    let existing_client = List::find(primNameMatches(link.logicalName), clients);

    let servers <- getUnmatchedServiceServers();
    let existing_server = List::find(primNameMatches(link.logicalName), servers);


    if (existing_server matches tagged Valid .server)
    begin
         // Error out
         error("ERROR: Connection Service " + link.logicalName + " server already exists!\n");
    end
    
    // Do type checks
    if (existing_client matches tagged Valid .latest_client)
    begin
        // Make sure service connections match or consumer is receiving it as void
        if (link.logicalReqType != latest_client.logicalReqType && link.logicalReqType != "" && latest_client.logicalReqType != "")
        begin
            // Error out
            error("ERROR: request types for Connection Service " + link.logicalName + " do not match: \n" + 
                  "Detected existing client request type: " + latest_client.logicalReqType + 
                  "\nDetected server request type: " + link.logicalReqType + "\n");
        end
        if (link.logicalRespType != latest_client.logicalRespType && link.logicalRespType != "" && latest_client.logicalRespType != "")
        begin
            // Error out
            error("ERROR: response types for Connection Service " + link.logicalName + " do not match: \n" + 
                  "Detected existing client response type: " + latest_client.logicalRespType + 
                  "\nDetected server response type: " + link.logicalRespType + "\n");
        end
    end
    
    // Propagate connections to the top level
    messageM("Adding service server: [" + link.logicalName + "]  Module:" + link.moduleName );
    addUnmatchedServiceServer(link);

endmodule



// findMatching{Recv/Send}

// Find the match for the given name. If there's more than one match 
// then this is a serious error that should end the world.

module [t_CONTEXT] findMatchingRecv#(LOGICAL_SEND_ENTRY send, List#(LOGICAL_RECV_ENTRY) recvs) (Maybe#(LOGICAL_RECV_ENTRY))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let exposeAllConnections <- getExposeAllConnections();

    let name = ctHashKey(send);
    let recv_matches = List::filter(nameMatches(exposeAllConnections, send), recvs);
    
    // The list should have exactly zero or one element in it....
    case (List::length(recv_matches))
        0:
        begin
            messageM("Found No ConnectionRecv named: " + name);
            return tagged Invalid;
        end
        1:
        begin
            messageM("Found ConnectionRecv named: " + name);
            return tagged Valid List::head(recv_matches);
        end
        default:
        begin
            error("ERROR: Found multiple ConnectionRecv named: " + name);
            return tagged Invalid;
        end
    endcase

endmodule

module [t_CONTEXT] findMatchingSend#(LOGICAL_RECV_ENTRY recv, List#(LOGICAL_SEND_ENTRY) sends) (Maybe#(LOGICAL_SEND_ENTRY))
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let exposeAllConnections <- getExposeAllConnections();

    let name = ctHashKey(recv);
    let send_matches = List::filter(nameMatches(exposeAllConnections, recv), sends);
    
    // The list should have exactly zero or one element in it....
    case (List::length(send_matches))
        0:
        begin
            messageM("Found No ConnectionSend named: " + name);
            return tagged Invalid;
        end
        1:
        begin
            messageM("Found ConnectionSend named: " + name);
            return tagged Valid List::head(send_matches);
        end
        default:
        begin
            error("ERROR: Found multiple ConnectionSend named: " + name);
            return tagged Invalid;
        end
    endcase

endmodule

module findMatchingServiceClient#(List#(LOGICAL_SERVICE_CLIENT_INFO) clients, 
                                  String serviceName, 
                                  String id) 
    // Interface:
    (LOGICAL_SERVICE_CLIENT_INFO);
  
    let client_matches = List::find(serviceNameIdMatches(serviceName, id), clients);
    
    // There should always be a matching client
    if (client_matches matches tagged Valid .client)
    begin
        messageM("Found ServiceClient named: " + serviceName + " with clientId: " + id);
        return client;
    end
    else
    begin
        error("ERROR: Found no ServiceClient named: " + serviceName + " with clientId: " + id);
        return ?;
    end

endmodule

module findMatchingServiceServer#(List#(LOGICAL_SERVICE_SERVER_INFO) servers, String serviceName)
    // Interface:
    (LOGICAL_SERVICE_SERVER_INFO);
  
    let server_matches = List::find(primNameMatches(serviceName), servers);
    
    // There should always be a matching server
    if (server_matches matches tagged Valid .server)
    begin
        messageM("Found ServiceServer named: " + serviceName);
        return server;
    end
    else
    begin
        error("ERROR: Found no ServiceServer named: " + serviceName);
        return ?;
    end

endmodule




// findAllMatching{Recv/Send}s

// Find all matches for the given name and remove them from the list.
// Useful for manyToOne/oneToMany connections.

function (List#(t_CONN)) findAllMatching(String name, List#(t_CONN) conns) provisos (Matchable#(t_CONN));

    let conn_matches = List::filter(primNameMatches(name), conns);
    return conn_matches;

endfunction

function (List#(t_CONN)) findAllNotMatching(String name, List#(t_CONN) conns) provisos (Matchable#(t_CONN));

    let conn_matches = List::filter(primNameDoesNotMatch(name), conns);
    return conn_matches;

endfunction


// connect

// Do the actual business of connecting a 1-to-1 send to a receive.

module [t_CONTEXT] connect#(LOGICAL_SEND_ENTRY sEntry, LOGICAL_RECV_ENTRY rEntry) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let name = ctHashKey(sEntry);
    let csend = ctHashValue(sEntry);
    let crecv = ctHashValue(rEntry);

    // Make sure connections match or consumer is receiving it as void
    if (csend.logicalType != crecv.logicalType && crecv.logicalType != "")
    begin
        error("ERROR: data types for Connection " + name + " do not match. \n" + "Detected send type: " + csend.logicalType + "\nDetected receive type: " + crecv.logicalType + "\n");
    end
    else
    begin  //Actually do the connection
        messageM("Connecting: " + name);
        connectOutToIn(csend.outgoing, crecv.incoming, 0);
    end

endmodule



// ========================================================================
//
//   Multiple sender/receiver support through shared stations.
//
//   THIS CODE IS OLD AND UNSUPPORTED.  It was part of Michael Pellauer's
//   thesis research.  He found that FPGAs have so many wires that shared
//   connections added complexity without improving either performance
//   or routing efficiency.
//
//   Code that no longer works has been commented out.
//
// ========================================================================

// Logical stations can have sends and receives associated with them.
// These functions handle that.

module [t_CONTEXT] registerSendToStation#(LOGICAL_SEND_INFO new_send, String station_name) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

//    // Get the station info.
//    let infos <- getStationInfos();
//    let st_info = findStationInfo(station_name, infos);
//    
//    // Check to see if the counterpart recv is already at this station.
//    // If so let's just make them point-to-point.
//
//    let m_match <- findMatchingRecv(new_send, st_info.registeredRecvs);
//    
//    if (m_match matches tagged Valid .recv)
//    begin
//    
//        // A match! Attempt to connect them.
//        connect(new_send, recv);
//        
//        // The send is no longer unmatched, so remove it from the list.
//        removeUnmatchedRecv(recv);
//        
//    end
//    else
//    begin
//
//        // No match. Add the send to the station's list.
//        st_info.registeredSends = List::cons(new_send, st_info.registeredSends);
//
//        // Update the registry.
//        updateStationInfo(station_name, st_info);
//
//    end

endmodule

module [t_CONTEXT] registerSendMultiToStation#(LOGICAL_SEND_MULTI_INFO new_send, String station_name) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

//    // Get the station info.
//    let infos <- getStationInfos();
//    let st_info = findStationInfo(station_name, infos);
//    
//    // Add the send to the station's list.
//    st_info.registeredSendMultis = List::cons(new_send, st_info.registeredSendMultis);
//
//    // Update the registry.
//    updateStationInfo(station_name, st_info);

endmodule

module [t_CONTEXT] registerRecvToStation#(LOGICAL_RECV_INFO new_recv, String station_name) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

//    // Get the station info.
//    let infos <- getStationInfos();
//    let st_info = findStationInfo(station_name, infos);
//    
//    // Check to see if the counterpart recv is already at this station.
//    // If so let's just make them point-to-point.
//
//    let m_match <- findMatchingSend(new_recv, st_info.registeredSends);
//    
//    if (m_match matches tagged Valid .send)
//    begin
//        
//        // A match! Attempt to connect them.
//        connect(send, new_recv);
//        
//        // The send is no longer unmatched, so remove it from the list.
//        removeUnmatchedSend(send);
//    
//    end
//    else
//    begin
//    
//        // No match. Add the recv to the station's list.
//        st_info.registeredRecvs = List::cons(new_recv, st_info.registeredRecvs);
//
//        // Update the registry.
//        updateStationInfo(station_name, st_info);
//    
//    end

endmodule

module [t_CONTEXT] registerRecvMultiToStation#(LOGICAL_RECV_MULTI_INFO new_recv, String station_name) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

//    // Get the station info.
//    let infos <- getStationInfos();
//    let st_info = findStationInfo(station_name, infos);
//    
//    // No match. Add the recv to the station's list.
//    st_info.registeredRecvMultis = List::cons(new_recv, st_info.registeredRecvMultis);
//
//    // Update the registry.
//    updateStationInfo(station_name, st_info);
    
endmodule

// Register a new logical station. Initially it has no children.
// Currently network type and station type are just strings.
// Later they could be more complex data types.

module [t_CONTEXT] registerStation#(String station_name, String network_name, String station_type) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));
    
    // Make a fresh station info.
    let new_st_info = STATION_INFO 
                      {
                           stationName:          station_name,
                           networkName:          network_name,
                           stationType:          station_type,
                           childrenNames:        List::nil,
                           registeredSends:      List::nil, 
                           registeredRecvs:      List::nil,
                           registeredSendMultis: List::nil, 
                           registeredRecvMultis: List::nil
                      };

    let st_infos <- getStationInfos();
    putStationInfos(List::cons(new_st_info, st_infos));

endmodule

// Add a child station to an existing station. IE for trees and so forth.

module [t_CONTEXT] registerChildToStation#(String parentName, String childName) ()
    provisos(Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

    let infos <- getStationInfos();
    let parent_info = findStationInfo(parentName, infos);
        
    parent_info.childrenNames = List::cons(childName, parent_info.childrenNames);
    updateStationInfo(parentName, parent_info);
    
endmodule
