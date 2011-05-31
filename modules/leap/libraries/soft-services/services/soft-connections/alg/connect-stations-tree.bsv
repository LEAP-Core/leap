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

import List::*;
import FIFOF::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_interconnect.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"

`include "awb/provides/soft_connections_common.bsh"

// connectStationsTree

// Find the root station, then connect all of its children together,
// building the routing tables as we go.

module connectStationsTree#(Clock c, LOGICAL_CONNECTION_INFO info) ();

    let root_name = info.rootStationName;
    List#(STATION_INFO) sts = getParentlessStations(info.stations);
    /* NOTE: THIS SEEMS LIKE NONSENSE
    // First of all, all parentless stations become
    // children of the actual root.
    while (!List::isNull(sts))
    begin
        let cur = List::head(sts);
        sts = List::tail(sts);
        if (cur.stationName != root_name)
            registerChildToStation(root_name, cur.stationName);
    end
    */
    
    // Now, see if there's an actual tree to connect.
    if (root_name != "InvalidRootStation")
    begin
        let root_info = findStationInfo(root_name, info.stations);
        let soft_reset = info.softReset;
        // Recursively connect all the stations together in a tree.
        match {.r, .r_info} <- mkStationTree(root_info, info, clocked_by c, reset_by soft_reset);
        // Add an empty root that drops everything routed to it.
        // This allows the existing root node to not be a special case
        // whe it comes to routing broadcasts and the like.
        mkEmptyRoot(r, clocked_by c, reset_by soft_reset);    
    end
    
endmodule


// mkStationTree

// Convert a logical station into a physical tree node. Return that node, along with a set of info
// describing all connections attached it, and all of its children. These infos allow us to build
// a routing table at each node.

module mkStationTree#(STATION_INFO st_info, LOGICAL_CONNECTION_INFO info) (Tuple2#(PHYSICAL_STATION, PHYSICAL_STATION_INFO));

    // Examine the current node's children.
    List#(String) children = st_info.childrenNames;
    if (List::isNull(children))
    begin
        // Current node is s a leaf.
        let phys_station_info <- initRoutingTableLeaf(st_info.registeredRecvs, st_info.registeredSends, st_info.registeredRecvMultis, st_info.registeredSendMultis);
        messageM("Creating Physical Station: " + st_info.stationName + "(Leaf).");
        for (Integer x = 0; x < List::length(st_info.registeredRecvs); x = x + 1)
        begin
            messageM("    Registering Recv: " + st_info.registeredRecvs[x].logicalName);
        end
        for (Integer x = 0; x < List::length(st_info.registeredSends); x = x + 1)
        begin
            messageM("    Registering Send: " + st_info.registeredSends[x].logicalName);
        end
        for (Integer x = 0; x < List::length(st_info.registeredRecvMultis); x = x + 1)
        begin
            messageM("    Registering Recv Multi: " + st_info.registeredRecvMultis[x].logicalName);
        end
        for (Integer x = 0; x < List::length(st_info.registeredSendMultis); x = x + 1)
        begin
            messageM("    Registering Send Multi: " + st_info.registeredSendMultis[x].logicalName);
        end
        printStationInfo(phys_station_info);
        // Make wrappers for the sends and receives to make them look like mini-stations.
        // This simplifies the code since there's only one type of thing to deal with.
        let wrappers <- mkConnStationWrappers(st_info.registeredRecvs, st_info.registeredSends, st_info.registeredRecvMultis, st_info.registeredSendMultis);
        // Instantiate a physical station based on the routing table and the wrappers.
        let m <- mkPhysicalStation(wrappers, phys_station_info.routingTable);
        return tuple2(m, phys_station_info);
    end
    else
    begin
        // Current node is not a leaf.
        
        // Make some lists for recursing down to our children.
        List#(PHYSICAL_STATION) phys_children = List::nil;
        List#(PHYSICAL_STATION_INFO) phys_children_info = List::nil;

        // Recursively deal with every child.
        while (!List::isNull(children))
        begin
            let cur_child = List::head(children);
            children = List::tail(children);

            let child_info = findStationInfo(cur_child, info.stations);
            match {.c, .c_info} <- mkStationTree(child_info, info);
            phys_children = List::cons(c, phys_children);
            phys_children_info = List::cons(c_info, phys_children_info);
        end

        messageM("Creating Physical Station: " + st_info.stationName);

        for (Integer x = 0; x < List::length(st_info.childrenNames); x = x + 1)
        begin
            messageM("    Registering Child: " + st_info.childrenNames[x]);
        end

        for (Integer x = 0; x < List::length(st_info.registeredRecvs); x = x + 1)
        begin
            messageM("    Registering Recv: " + st_info.registeredRecvs[x].logicalName);
            let recv_info = 
                PHYSICAL_STATION_INFO
                {
                    outgoingInfo: List::nil,
                    incomingInfo: List::cons(st_info.registeredRecvs[x], List::nil),
                    outgoingMultiInfo: List::nil,
                    incomingMultiInfo: List::nil,
                    routingTable: ?
                };
            phys_children_info = List::cons(recv_info, phys_children_info);
            let wrapper <- mkRecvStationWrapper(st_info.registeredRecvs[x].incoming);
            phys_children = List::cons(wrapper, phys_children);
        end

        for (Integer x = 0; x < List::length(st_info.registeredSends); x = x + 1)
        begin
            messageM("    Registering Send: " + st_info.registeredSends[x].logicalName);
            let send_info = 
                PHYSICAL_STATION_INFO
                {
                    outgoingInfo: List::cons(st_info.registeredSends[x], List::nil),
                    incomingInfo: List::nil,
                    outgoingMultiInfo: List::nil,
                    incomingMultiInfo: List::nil,
                    routingTable: ?
                };
            phys_children_info = List::cons(send_info, phys_children_info);
            let wrapper <- mkSendStationWrapper(st_info.registeredSends[x].outgoing);
            phys_children = List::cons(wrapper, phys_children);
        end

        for (Integer x = 0; x < List::length(st_info.registeredRecvMultis); x = x + 1)
        begin
            messageM("    Registering Recv Multi: " + st_info.registeredRecvMultis[x].logicalName);
            let recv_info = 
                PHYSICAL_STATION_INFO
                {
                    outgoingInfo: List::nil,
                    incomingInfo: List::nil,
                    outgoingMultiInfo: List::nil,
                    incomingMultiInfo: List::cons(st_info.registeredRecvMultis[x], List::nil),
                    routingTable: ?
                };
            phys_children_info = List::cons(recv_info, phys_children_info);
            let wrapper <- mkRecvMultiStationWrapper(st_info.registeredRecvMultis[x].incoming);
            phys_children = List::cons(wrapper, phys_children);
        end

        for (Integer x = 0; x < List::length(st_info.registeredSendMultis); x = x + 1)
        begin
            messageM("    Registering Send Multi: " + st_info.registeredSendMultis[x].logicalName);
            let send_info = 
                PHYSICAL_STATION_INFO
                {
                    outgoingInfo: List::nil,
                    incomingInfo: List::nil,
                    outgoingMultiInfo: List::cons(st_info.registeredSendMultis[x], List::nil),
                    incomingMultiInfo: List::nil,
                    routingTable: ?
                };
            phys_children_info = List::cons(send_info, phys_children_info);
            let wrapper <- mkSendMultiStationWrapper(st_info.registeredSendMultis[x].outgoing);
            phys_children = List::cons(wrapper, phys_children);
        end

        // Restore the list to the original indices.
        phys_children = List::reverse(phys_children);
        phys_children_info = List::reverse(phys_children_info);        

        // Based on all of our children, make a routing table for this node.
        let phys_station_info <- initRoutingTable(phys_children_info);
        printStationInfo(phys_station_info);
        // Make a physical station for this node, including FIFOs and whatnot.
        let m <- mkPhysicalStation(phys_children, phys_station_info.routingTable);
        return tuple2(m, phys_station_info);

    end
    
endmodule

// Helper function to find parentless stations that are not connected
// to the root. (Perhaps because of synthesis boundaries.)

function Bool isParentlessStation(List#(STATION_INFO) sts, STATION_INFO st);

    if (List::isNull(sts)) 
        return True;
    else
    begin
        let cur = List::head(sts);
        List#(String) childs = cur.childrenNames;
        Bool found = False;
        while (!List::isNull(childs))
        begin
            let cur_child = List::head(childs);
            childs = List::tail(childs);
            if (st.stationName == cur_child)
                found = True;
        end
        return found ? False : isParentlessStation(List::tail(sts), st);
    end

endfunction

// Helper function to filter for all parentless stations.

function List#(STATION_INFO) getParentlessStations(List#(STATION_INFO) sts);

    return List::filter(isParentlessStation(sts), sts);

endfunction
