import Clocks::*;

`include "asim/provides/soft_connections_common.bsh"

// ****** Connection Functions ******


// register{Send,Recv}

// Adds a new send/recv. First try to find existing matches, 
// then either connect it or add it to the unmatched list.

module [t_CONTEXT] registerSend#(LOGICAL_SEND_INFO new_send) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // See if we can find our partner.
    let recvs <- getUnmatchedRecvs();
    let m_match <- findMatchingRecv(new_send, recvs);

    case (m_match) matches
        tagged Invalid:   
        begin

            // No match. Add the send to the list.
            addUnmatchedSend(new_send);

        end
        tagged Valid .recv:
        begin

            // A 1-to-1 match! Attempt to connect them.
            connect(new_send, recv);

            // The receive is no longer unmatched, so remove it from the list.
            removeUnmatchedRecv(recv);

        end
    endcase

endmodule

module [t_CONTEXT] registerSendMulti#(LOGICAL_SEND_MULTI_INFO new_send) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Defer one to many send to the very top level.
    addUnmatchedSendMulti(new_send);

endmodule

module [t_CONTEXT] registerRecv#(LOGICAL_RECV_INFO new_recv) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // See if we can find our partner.
    let sends <- getUnmatchedSends();
    let m_match <- findMatchingSend(new_recv, sends);

    case (m_match) matches
        tagged Invalid:   
        begin

            // No match. Add the recv to the list.
            addUnmatchedRecv(new_recv);

        end
        tagged Valid .send:
        begin

            // A match! Attempt to connect them.
            connect(send, new_recv);

            // The send is no longer unmatched, so remove it from the list.
            removeUnmatchedSend(send);

        end
    endcase

endmodule

module [t_CONTEXT] registerRecvMulti#(LOGICAL_RECV_MULTI_INFO new_recv) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Defer many to one recvs to the very top level.
    addUnmatchedRecvMulti(new_recv);

endmodule


// BACKWARDS COMPATABILITY: Connection Chains

// These will eventually be subsumed by manyToOne/oneToMany logical connections
// that are then divorced from their physical topology. Until that day arrives
// a Logical and Physical chain is the same thing.

module [t_CONTEXT] registerChain#(LOGICAL_CHAIN_INFO new_link) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // See what existing links are out there.
    let idx = new_link.logicalIdx;
    let existing_links <- getChain(idx);

    if (List::isNull(existing_links))
    begin

        // It's the only member of the chain, so just add it.
        messageM("Adding Initial Link for Chain: [" + integerToString(idx) + "]");
        putChain(idx, List::cons(new_link, existing_links));

    end
    else
    begin

        // There are other links already, so make sure the types
        // are consistent.
        let latest_link = List::head(existing_links);
   
        // Make sure connections match or consumer is receiving it as void
        if (new_link.logicalType != latest_link.logicalType && new_link.logicalType != "" && latest_link.logicalType != "")
        begin

            // Error out
            messageM("Detected existing chain type: " + latest_link.logicalType);
            messageM("Detected new link type: " + new_link.logicalType);
            error("ERROR: data types for Connection Chain #" + integerToString(idx) + " do not match.");

        end
        else
        begin  
           
            // Actually do the connection
            messageM("Adding Link to Chain: [" + integerToString(idx) + "]");
            connectOutToIn(new_link.outgoing, latest_link.incoming);

        end

        // Add the new link to the list.
        putChain(idx, List::cons(new_link, existing_links));

    end

endmodule

// Logical stations can have sends and receives associated with them.
// These functions handle that.

module [t_CONTEXT] registerSendToStation#(LOGICAL_SEND_INFO new_send, String station_name) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Get the station info.
    let infos <- getStationInfos();
    let st_info = findStationInfo(station_name, infos);
    
    // Check to see if the counterpart recv is already at this station.
    // If so let's just make them point-to-point.

    let m_match <- findMatchingRecv(new_send, st_info.registeredRecvs);
    
    if (m_match matches tagged Valid .recv)
    begin
    
        // A match! Attempt to connect them.
        connect(new_send, recv);
        
        // The send is no longer unmatched, so remove it from the list.
        removeUnmatchedRecv(recv);
        
    end
    else
    begin

        // No match. Add the send to the station's list.
        st_info.registeredSends = List::cons(new_send, st_info.registeredSends);

        // Update the registry.
        updateStationInfo(station_name, st_info);

    end

endmodule

module [t_CONTEXT] registerSendMultiToStation#(LOGICAL_SEND_MULTI_INFO new_send, String station_name) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Get the station info.
    let infos <- getStationInfos();
    let st_info = findStationInfo(station_name, infos);
    
    // Add the send to the station's list.
    st_info.registeredSendMultis = List::cons(new_send, st_info.registeredSendMultis);

    // Update the registry.
    updateStationInfo(station_name, st_info);

endmodule

module [t_CONTEXT] registerRecvToStation#(LOGICAL_RECV_INFO new_recv, String station_name) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Get the station info.
    let infos <- getStationInfos();
    let st_info = findStationInfo(station_name, infos);
    
    // Check to see if the counterpart recv is already at this station.
    // If so let's just make them point-to-point.

    let m_match <- findMatchingSend(new_recv, st_info.registeredSends);
    
    if (m_match matches tagged Valid .send)
    begin
        
        // A match! Attempt to connect them.
        connect(send, new_recv);
        
        // The send is no longer unmatched, so remove it from the list.
        removeUnmatchedSend(send);
    
    end
    else
    begin
    
        // No match. Add the recv to the station's list.
        st_info.registeredRecvs = List::cons(new_recv, st_info.registeredRecvs);

        // Update the registry.
        updateStationInfo(station_name, st_info);
    
    end

endmodule

module [t_CONTEXT] registerRecvMultiToStation#(LOGICAL_RECV_MULTI_INFO new_recv, String station_name) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Get the station info.
    let infos <- getStationInfos();
    let st_info = findStationInfo(station_name, infos);
    
    // No match. Add the recv to the station's list.
    st_info.registeredRecvMultis = List::cons(new_recv, st_info.registeredRecvMultis);

    // Update the registry.
    updateStationInfo(station_name, st_info);
    
endmodule

// Register a new logical station. Initially it has now children.
// Currently network type and station type are just strings.
// Later they could be more complex data types.

module [t_CONTEXT] registerStation#(String station_name, String network_name, String station_type) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
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
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let infos <- getStationInfos();
    let parent_info = findStationInfo(parentName, infos);
        
    parent_info.childrenNames = List::cons(childName, parent_info.childrenNames);
    
    updateStationInfo(parentName, parent_info);
    
endmodule

// findMatching{Recv/Send}

// Find the match for the given name. If there's more than one match 
// then this is a serious error that should end the world.

module [t_CONTEXT] findMatchingRecv#(LOGICAL_SEND_INFO send, List#(LOGICAL_RECV_INFO) recvs) (Maybe#(LOGICAL_RECV_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

  let recv_matches = List::filter(nameMatches(send), recvs);
  
  
  // The list should have exactly zero or one element in it....

  case (List::length(recv_matches))
      0:
      begin
          messageM("Found No ConnectionRecv named: " + send.logicalName);
          return tagged Invalid;

      end
      1:
      begin
          messageM("Found ConnectionRecv named: " + send.logicalName);
          return tagged Valid List::head(recv_matches);

      end
      default:
      begin

          error("ERROR: Found multiple ConnectionRecv named: " + send.logicalName);
          return tagged Invalid;

      end
  endcase

endmodule

module [t_CONTEXT] findMatchingSend#(LOGICAL_RECV_INFO recv, List#(LOGICAL_SEND_INFO) sends) (Maybe#(LOGICAL_SEND_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

  let send_matches = List::filter(nameMatches(recv), sends);
  
  // The list should have exactly zero or one element in it....

  case (List::length(send_matches))
      0:
      begin

          return tagged Invalid;

      end
      1:
      begin

          return tagged Valid List::head(send_matches);

      end
      default:
      begin

          error("ERROR: Found multiple ConnectionSend named: " + recv.logicalName);
          return tagged Invalid;

      end
  endcase

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

module [t_CONTEXT] connect#(LOGICAL_SEND_INFO csend, LOGICAL_RECV_INFO crecv) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Make sure connections match or consumer is receiving it as void
    if (csend.logicalType != crecv.logicalType && crecv.logicalType != "")
    begin

        messageM("Detected send type: " + csend.logicalType);
        messageM("Detected receive type: " + crecv.logicalType);
        error("ERROR: data types for Connection " + csend.logicalName + " do not match.");

    end
    else
    begin  //Actually do the connection
  
        messageM("Connecting: " + csend.logicalName);
        connectOutToIn(csend.outgoing, crecv.incoming);

    end

endmodule



