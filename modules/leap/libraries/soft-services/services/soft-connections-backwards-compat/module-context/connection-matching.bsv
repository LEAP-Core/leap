import Clocks::*;
// ****** Connection Functions ******


// register{Send,Recv}

// Adds a new send/recv. First try to find existing matches, 
// then either connect it or add it to the unmatched list.

module [CONNECTED_MODULE] registerSend#(LOGICAL_SEND_INFO new_send) ();

    // See if we can find our partner.
    let recvs <- getUnmatchedRecvs();
    let m_match <- findMatchingRecv(new_send.logicalName, recvs);

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
            removeUnmatchedRecv(recv.logicalName);

        end
    endcase

endmodule

module [CONNECTED_MODULE] registerSendMulti#(LOGICAL_SEND_MULTI_INFO new_send) ();

    // Defer one to many send to the very top level.
    addUnmatchedSendMulti(new_send);

endmodule

module [CONNECTED_MODULE] registerRecv#(LOGICAL_RECV_INFO new_recv) ();

    // See if we can find our partner.
    let sends <- getUnmatchedSends();
    let m_match <- findMatchingSend(new_recv.logicalName, sends);

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
            removeUnmatchedSend(send.logicalName);

        end
    endcase

endmodule

module [CONNECTED_MODULE] registerRecvMulti#(LOGICAL_RECV_MULTI_INFO new_recv) ();

    // Defer many to one recvs to the very top level.
    addUnmatchedRecvMulti(new_recv);

endmodule

// BACKWARDS COMPATABILITY: Connection Chains

// These will eventually be subsumed by manyToOne/oneToMany logical connections
// that are then divorced from their physical topology. Until that day arrives
// a Logical and Physical chain is the same thing.

module [CONNECTED_MODULE] registerChain#(LOGICAL_CHAIN_INFO new_link) ();

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

module [CONNECTED_MODULE] registerSendToStation#(LOGICAL_SEND_INFO new_send, String station_name) ();

    // Get the station info.
    let st_info <- findStationInfo(station_name);
    
    // Check to see if the counterpart recv is already at this station.
    // If so let's just make them point-to-point.

    let m_match <- findMatchingRecv(new_send.logicalName, st_info.registeredRecvs);
    
    if (m_match matches tagged Valid .recv)
    begin
    
        // A match! Attempt to connect them.
        connect(new_send, recv);
        
        // The recv is no longer unmatched, so remove it from the list.
        st_info.registeredRecvs = List::filter(recvNameDoesNotMatch(new_send.logicalName), st_info.registeredRecvs);

        // Update the registry.
        updateStationInfo(station_name, st_info);
        
    end
    else
    begin

        // No match. Add the send to the station's list.
        st_info.registeredSends = List::cons(new_send, st_info.registeredSends);

        // Update the registry.
        updateStationInfo(station_name, st_info);

    end

endmodule


module [CONNECTED_MODULE] registerSendMultiToStation#(LOGICAL_SEND_MULTI_INFO new_send, String station_name) ();

    // Get the station info.
    let st_info <- findStationInfo(station_name);
    
    // Add the send to the station's list.
    st_info.registeredSendMultis = List::cons(new_send, st_info.registeredSendMultis);

    // Update the registry.
    updateStationInfo(station_name, st_info);

endmodule


module [CONNECTED_MODULE] registerRecvToStation#(LOGICAL_RECV_INFO new_recv, String station_name) ();

    // Get the station info.
    let st_info <- findStationInfo(station_name);
    
    // Check to see if the counterpart recv is already at this station.
    // If so let's just make them point-to-point.

    let m_match <- findMatchingSend(new_recv.logicalName, st_info.registeredSends);
    
    if (m_match matches tagged Valid .send)
    begin
        
        // A match! Attempt to connect them.
        connect(send, new_recv);
        
        // The send is no longer unmatched, so remove it from the list.
        st_info.registeredSends = List::filter(sendNameDoesNotMatch(new_recv.logicalName), st_info.registeredSends);

        // Update the registry.
        updateStationInfo(station_name, st_info);
    
    end
    else
    begin
    
        // No match. Add the recv to the station's list.
        st_info.registeredRecvs = List::cons(new_recv, st_info.registeredRecvs);

        // Update the registry.
        updateStationInfo(station_name, st_info);
    
    end

endmodule


module [CONNECTED_MODULE] registerRecvMultiToStation#(LOGICAL_RECV_MULTI_INFO new_recv, String station_name) ();

    // Get the station info.
    let st_info <- findStationInfo(station_name);
    
    // No match. Add the recv to the station's list.
    st_info.registeredRecvMultis = List::cons(new_recv, st_info.registeredRecvMultis);

    // Update the registry.
    updateStationInfo(station_name, st_info);
    
endmodule


// Register a new logical station. Initially it has no children.
// Currently network type and station type are just strings.
// Later they could be more complex data types.

module [CONNECTED_MODULE] registerStation#(String station_name, String network_name, String station_type) ();
    
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

module [CONNECTED_MODULE] registerChildToStation#(String parentName, String childName) ();

    let parent_info <- findStationInfo(parentName);
        
    parent_info.childrenNames = List::cons(childName, parent_info.childrenNames);
    
    updateStationInfo(parentName, parent_info);
    
endmodule

// findMatching{Recv/Send}

// Find the match for the given name. If there's more than one match 
// then this is a serious error that should end the world.

module [CONNECTED_MODULE] findMatchingRecv#(String sname, List#(LOGICAL_RECV_INFO) recvs) (Maybe#(LOGICAL_RECV_INFO));

  let recv_matches = List::filter(recvNameMatches(sname), recvs);
  

  // The list should have exactly zero or one element in it....

  case (List::length(recv_matches))
      0:
      begin

          return tagged Invalid;

      end
      1:
      begin

          return tagged Valid List::head(recv_matches);

      end
      default:
      begin

          error("ERROR: Found multiple ConnectionRecv named: " + sname);
          return tagged Invalid;

      end
  endcase

endmodule

module [CONNECTED_MODULE] findMatchingSend#(String rname, List#(LOGICAL_SEND_INFO) sends) (Maybe#(LOGICAL_SEND_INFO));

  let send_matches = List::filter(sendNameMatches(rname), sends);
  
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

          error("ERROR: Found multiple ConnectionSend named: " + rname);
          return tagged Invalid;

      end
  endcase

endmodule

// findAllMatching{Recv/Send}s

// Find all matches for the given name and remove them from the list.
// Useful for manyToOne/oneToMany connections.

module [CONNECTED_MODULE] findAllMatchingRecvs#(String sname) (List#(LOGICAL_RECV_INFO));

  let recvs <- getUnmatchedRecvs();

  let recv_matches = List::filter(recvNameMatches(sname), recvs);
  let remaining = List::filter(recvNameDoesNotMatch(sname), recvs);
  putUnmatchedRecvs(remaining);

  return recv_matches;

endmodule

module [CONNECTED_MODULE] findAllMatchingSends#(String rname) (List#(LOGICAL_SEND_INFO));

  let sends <- getUnmatchedSends();

  let send_matches = List::filter(sendNameMatches(rname), sends);
  let remaining = List::filter(sendNameDoesNotMatch(rname), sends);
  putUnmatchedSends(remaining);

  return send_matches;

endmodule


module [CONNECTED_MODULE] findAllMatchingRecvMultis#(String sname) (List#(LOGICAL_RECV_MULTI_INFO));

  let recvs <- getUnmatchedRecvMultis();

  let recv_matches = List::filter(recvMultiNameMatches(sname), recvs);
  let remaining = List::filter(recvMultiNameDoesNotMatch(sname), recvs);
  putUnmatchedRecvMultis(remaining);

  return recv_matches;

endmodule

module [CONNECTED_MODULE] findAllMatchingSendMultis#(String rname) (List#(LOGICAL_SEND_MULTI_INFO));

  let sends <- getUnmatchedSendMultis();

  let send_matches = List::filter(sendMultiNameMatches(rname), sends);
  let remaining = List::filter(sendMultiNameDoesNotMatch(rname), sends);
  putUnmatchedSendMultis(remaining);

  return send_matches;

endmodule

// connect

// Do the actual business of connecting a 1-to-1 send to a receive.

module [CONNECTED_MODULE] connect#(LOGICAL_SEND_INFO csend, LOGICAL_RECV_INFO crecv) ();

   
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


// connectOutToIn

// This is the module that actually performs the connection between two
// physical endpoints. This is for 1-to-1 communication only.

module connectOutToIn#(PHYSICAL_CONNECTION_OUT cout, PHYSICAL_CONNECTION_IN cin) ();
  
  if(sameFamily(cin.clock,cout.clock))
  begin
      rule trySend (cout.notEmpty());
          // Try to move the data
          let x = cout.first();
          cin.try(x);
      endrule

      rule success (cin.success());
          // We succeeded in moving the data
          cout.deq();
    
      endrule
  end
  else
  begin

      messageM("CrossDomain@ Found");

      // choose a size large enough to cover latency of fifo
      let domainFIFO <- mkSyncFIFO(8,
                                   cout.clock, 
                                   cout.reset,
                                   cin.clock);

      rule receive (cout.notEmpty() && domainFIFO.notFull());
          let x = cout.first();
          domainFIFO.enq(x);
          cout.deq();
      endrule
  
      rule trySend (domainFIFO.notEmpty());
          cin.try(domainFIFO.first());
      endrule

      rule succeedSend(cin.success());
          domainFIFO.deq();
      endrule
  end

endmodule
