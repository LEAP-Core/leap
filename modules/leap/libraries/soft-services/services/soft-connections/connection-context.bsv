//
// Copyright (C) 2011 Intel Corporation
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

import ModuleContext::*;

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
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
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.synthesisBoundaryPlatform;

endmodule

module [t_CONTEXT] getSynthesisBoundaryPlatformID (Integer)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.synthesisBoundaryPlatformID;

endmodule

module [t_CONTEXT] getUnmatchedSends (List#(LOGICAL_SEND_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedSends;

endmodule


module [t_CONTEXT] printUnmatchedSends (Empty)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- getUnmatchedSends();
    printSends(m);

endmodule

module [t_CONTEXT] getUnmatchedRecvs (List#(LOGICAL_RECV_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedRecvs;

endmodule

module [t_CONTEXT] printUnmatchedRecvs (Empty)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- getUnmatchedRecvs();
    printRecvs(m);

endmodule


module [t_CONTEXT] getUnmatchedSendMultis (List#(LOGICAL_SEND_MULTI_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedSendMultis;

endmodule

module [t_CONTEXT] getUnmatchedRecvMultis (List#(LOGICAL_RECV_MULTI_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.unmatchedRecvMultis;

endmodule

module [t_CONTEXT] getStationInfos (List#(STATION_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.stations;

endmodule

module [t_CONTEXT] getStationStack (List#(STATION))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.stationStack;

endmodule

module [t_CONTEXT] getRootStationName (String)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.rootStationName;

endmodule

module [t_CONTEXT] getSoftReset (Reset)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.softReset;

endmodule

// BACKWARDS COMPATABILITY: Connection Chains

module [t_CONTEXT] getChain#(LOGICAL_CHAIN_INFO descriptor) (Maybe#(LOGICAL_CHAIN_INFO))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    
    return List::find(nameMatches(descriptor),ctxt.chains);

endmodule

// ****** Mutators *******

// These update the field to the given value.



module [t_CONTEXT] putSynthesisBoundaryPlatform#(String new_name) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.synthesisBoundaryPlatform = new_name;
    putContext(ctxt);

endmodule

module [t_CONTEXT] putSynthesisBoundaryPlatformID#(Integer new_id) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.synthesisBoundaryPlatformID = new_id;
    putContext(ctxt);

endmodule

// putUnmatchedSends

module [t_CONTEXT] putUnmatchedSends#(List#(LOGICAL_SEND_INFO) new_sends) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedSends = new_sends;
    putContext(ctxt);

endmodule


// putUnmatchedRecvs

module [t_CONTEXT] putUnmatchedRecvs#(List#(LOGICAL_RECV_INFO) new_recvs) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedRecvs = new_recvs;
    putContext(ctxt);

endmodule

// putUnmatchedSendMultis

module [t_CONTEXT] putUnmatchedSendMultis#(List#(LOGICAL_SEND_MULTI_INFO) new_sends) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedSendMultis = new_sends;
    putContext(ctxt);

endmodule


// putUnmatchedRecvMultis

module [t_CONTEXT] putUnmatchedRecvMultis#(List#(LOGICAL_RECV_MULTI_INFO) new_recvs) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.unmatchedRecvMultis = new_recvs;
    putContext(ctxt);

endmodule

// putStations

module [t_CONTEXT] putStationInfos#(List#(STATION_INFO) new_stations) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.stations = new_stations;
    putContext(ctxt);

endmodule

// putStationStack

module [t_CONTEXT] putStationStack#(List#(STATION) new_stations) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.stationStack = new_stations;
    putContext(ctxt);

endmodule

// putRootStationName

module [t_CONTEXT] putRootStationName#(String new_root) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.rootStationName = new_root;
    putContext(ctxt);

endmodule

// putSoftReset

module [t_CONTEXT] putSoftReset#(Reset new_reset) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.softReset = new_reset;
    putContext(ctxt);

endmodule

// putChain

module [t_CONTEXT] putChain#(LOGICAL_CHAIN_INFO chain) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.chains = List::cons(chain,List::filter(nameDoesNotMatch(chain),ctxt.chains));
    putContext(ctxt);

endmodule

// ****** Non-Primitive Mutators ******


// addUnmatchedSend/Recv

// Add a new send/recv to the list.

module [t_CONTEXT] addUnmatchedSend#(LOGICAL_SEND_INFO new_send) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

   let sends <- getUnmatchedSends();
   putUnmatchedSends(List::cons(new_send, sends));

endmodule

module [t_CONTEXT] addUnmatchedRecv#(LOGICAL_RECV_INFO new_recv) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

   let recvs <- getUnmatchedRecvs();
   putUnmatchedRecvs(List::cons(new_recv, recvs));

endmodule

module [t_CONTEXT] addUnmatchedSendMulti#(LOGICAL_SEND_MULTI_INFO new_send) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

   let sends <- getUnmatchedSendMultis();
   putUnmatchedSendMultis(List::cons(new_send, sends));

endmodule

module [t_CONTEXT] addUnmatchedRecvMulti#(LOGICAL_RECV_MULTI_INFO new_recv) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

   let recvs <- getUnmatchedRecvMultis();
   putUnmatchedRecvMultis(List::cons(new_recv, recvs));

endmodule

// removeUnmatchedSend/Recv

// Remove an unmatched send/recv (usually because it's been matched). 

// Use strong == here.  

module [t_CONTEXT] removeUnmatchedSend#(LOGICAL_SEND_INFO send) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

  messageM("Try to remove send" + send.logicalName);
  let sends <- getUnmatchedSends();
  let new_sends = List::filter(nameDoesNotMatch(send), sends);
  putUnmatchedSends(new_sends);

endmodule

module [t_CONTEXT] removeUnmatchedRecv#(LOGICAL_RECV_INFO recv) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

  messageM("Try to remove recv " + recv.logicalName);
  let recvs <- getUnmatchedRecvs();
  let new_recvs = List::filter(nameDoesNotMatch(recv), recvs);
  putUnmatchedRecvs(new_recvs);

endmodule

module [t_CONTEXT] removeUnmatchedSendMulti#(String sname) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

  let sends <- getUnmatchedSendMultis();
  let new_sends = List::filter(primNameDoesNotMatch(sname), sends);
  putUnmatchedSendMultis(new_sends);

endmodule

module [t_CONTEXT] removeUnmatchedRecvMulti#(String rname) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

  let recvs <- getUnmatchedRecvMultis();
  let new_recvs = List::filter(primNameDoesNotMatch(rname), recvs);
  putUnmatchedRecvMultis(new_recvs);

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
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
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
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let ss <- getStationStack();
    putStationStack(List::cons(s,ss));

endmodule

module [t_CONTEXT] popStation ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
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
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
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
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
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
