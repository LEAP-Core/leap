///
// Copyright (C) 2013 MIT
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

//
// Synchronization service implementation. 
//

// Library imports.

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;

// Project foundation imports.

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/fpga_components.bsh"


//
// The maximum number of associated synchronization nodes
//
typedef 64 N_SYNC_NODES;

//
// Sync node port number. 
//
typedef Bit#(TMax#(TLog#(N_SYNC_NODES),1)) SYNC_PORT_NUM;

//
// Synchronization Message
//
typedef struct
{
    SYNC_PORT_NUM    sender;
    t_SYNC_ID        syncId;
}
SYNC_MSG#(type t_SYNC_ID)
    deriving(Bits, Eq);

//
// Synchronization Broadcast Message from Controller
//
typedef union tagged
{
    Bool       SYNC_INIT_DONE;
    t_SYNC_ID  SYNC_BARRIER_DONE;
}
SYNC_BCAST_MSG#(type t_SYNC_ID)
    deriving(Bits, Eq);

//
// Synchronization service interface.
//
interface SYNC_SERVICE_IFC;
    // Return true if the synchronization service is initialized
    method Bool initialized();
    // Set the synchronization barrier 
    // Only the controller/master node can set the barrier
    method Action setSyncBarrier(Bit#(N_SYNC_NODES) barrier);
    // Notify the synchronization controller that the current node has reached
    // the synchronization point
    method Action signalSyncReached();
    // Wait for synchronization 
    // This method can only be fired when the synchronization is complete
    method Action waitForSync();
    // This method is only used for the master synchronization node
    // Return true if all slave synchronization nodes have reached 
    // the synchronization point
    method Bool othersSyncAllReached();
endinterface

interface SYNC_IFC;
    method Action setSyncBarrier(Bit#(N_SYNC_NODES) barrier);
    method Action signalSyncReached();
    method Action waitForSync();
    method Bool othersSyncAllReached();
endinterface

interface SYNC_SERVICE_MULTI_SYNC_IFC#(numeric type n_SYNCS);
    interface Vector#(n_SYNCS, SYNC_IFC) syncPorts;
    // Return true if the synchronization service is initialized
    method Bool initialized();
endinterface

//
// mkSyncNode -- 
//     Instantiate a synchronization node in a specific synchronization group.
//
module [CONNECTED_MODULE] mkSyncNode#(Integer syncGroupID, Bool isMasterNode)
    // interface:
    (SYNC_SERVICE_IFC);

    SYNC_SERVICE_MULTI_SYNC_IFC#(1) syncNode <- mkMultiSyncNode(syncGroupID, isMasterNode); 
    
    method Bool initialized() = syncNode.initialized();
    method Action setSyncBarrier(Bit#(N_SYNC_NODES) barrier) = syncNode.syncPorts[0].setSyncBarrier(barrier);
    method Action signalSyncReached() = syncNode.syncPorts[0].signalSyncReached();
    method Action waitForSync() = syncNode.syncPorts[0].waitForSync();
    method Bool othersSyncAllReached() = syncNode.syncPorts[0].othersSyncAllReached();
endmodule

//
// mkMultiSyncNode --
//     Instantiate a synchronization node with multiple synchronization points
// in a specific synchronization group. 
//
module [CONNECTED_MODULE] mkMultiSyncNode#(Integer syncGroupID, Bool isMasterNode)
    // interface:
    (SYNC_SERVICE_MULTI_SYNC_IFC#(n_SYNCS))
    provisos (Add#(1, extraBits, n_SYNCS),
              Add#(extra, TMax#(TLog#(n_SYNCS), 1), TMax#(1, TMax#(TLog#(n_SYNCS), 1))));

    SYNC_SERVICE_MULTI_SYNC_IFC#(n_SYNCS) syncNode <- (isMasterNode)? 
        mkMultiSyncNodeMaster(syncGroupID) : mkMultiSyncNodeSlave(syncGroupID);
    
    return syncNode;
endmodule


//
// mkMultiSyncNodeMaster --
//     Instantiate a master synchronization node with multiple synchronization points
// in a specific synchronization group. The master node contains the synchronization
// controller. 
//
module [CONNECTED_MODULE] mkMultiSyncNodeMaster#(Integer syncGroupID)
    // interface:
    (SYNC_SERVICE_MULTI_SYNC_IFC#(n_SYNCS))
    provisos (NumAlias#(TMax#(TLog#(n_SYNCS), 1), t_SYNC_ID_SZ),
              Add#(1, extraBits, n_SYNCS),
              Alias#(Bit#(t_SYNC_ID_SZ), t_SYNC_ID),
              Alias#(SYNC_MSG#(t_SYNC_ID), t_SYNC_MSG),
              Alias#(SYNC_BCAST_MSG#(t_SYNC_ID), t_SYNC_BCAST_MSG),
              Bits#(t_SYNC_BCAST_MSG, t_SYNC_BCAST_MSG_SZ),
              Bits#(t_SYNC_MSG, t_SYNC_MSG_SZ));

    // =======================================================================
    //
    // Synchronization nodes are connected via rings. 
    //
    // Two rings are used: one for done signals (send to controller),
    // the other one for broadcasting initialization and synchronization 
    // messages (from the controller)
    //
    // =======================================================================

    // Broadcast ring for synchronization message
    CONNECTION_CHAIN#(t_SYNC_BCAST_MSG) link_sync_broadcast <- mkConnectionChain("Sync_group_" + integerToString(syncGroupID) + "_broadcast");
    
    // Addressable ring (self-enumeration) for sync signal report
    CONNECTION_ADDR_RING#(SYNC_PORT_NUM, t_SYNC_MSG) link_sync_signal_report <-
        mkConnectionTokenRingNode("Sync_group_" + integerToString(syncGroupID) + "_signal_report", 0);
    
    
    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    Reg#(Bool)        initDone     <- mkReg(False);
    FIFOF#(t_SYNC_ID) doneSignalQ  <- mkFIFOF();
    
    Vector#(n_SYNCS, Reg#(Bool))               barrierInitialized  <- replicateM(mkReg(False));
    Vector#(n_SYNCS, Reg#(Bit#(N_SYNC_NODES)))  barrierInitValues  <- replicateM(mkReg(0));
    Vector#(n_SYNCS, Reg#(Vector#(N_SYNC_NODES, Bool)))  barriers  <- replicateM(mkReg(unpack(0)));
    Vector#(n_SYNCS, FIFOF#(Bool))                     syncRespQs  <- replicateM(mkBypassFIFOF());

    // Finish initialization when all barriers are initialized
    rule checkBarrierInit (!initDone && fold(\&& , readVReg(barrierInitialized)));
        initDone <= True;
        for(Integer p = 0; p < valueOf(n_SYNCS); p = p + 1)
        begin
            barriers[p] <= unpack(barrierInitValues[p]);
        end
        // Broadcast initialization signal
        link_sync_broadcast.sendToNext(tagged SYNC_INIT_DONE True);
    endrule

    // =======================================================================
    //
    // Manage synchronization signals and broadcast synchronization signal
    //
    // =======================================================================

    rule setLocalSyncSignal (doneSignalQ.notEmpty());
        let s = doneSignalQ.first();
        doneSignalQ.deq();
        let barrier = barriers[pack(s)];
        barrier[0] = False;
        
        if (link_sync_signal_report.notEmpty())
        begin
            let m = link_sync_signal_report.first();
            if (s == m.syncId)
            begin
                link_sync_signal_report.deq();
                barrier[pack(m.sender)] = False;
            end
        end
        if (!fold(\|| , barrier)) 
        begin
            barriers[pack(s)] <= unpack(barrierInitValues[pack(s)]);
            link_sync_broadcast.sendToNext(tagged SYNC_BARRIER_DONE s);
            syncRespQs[pack(s)].enq(True);
        end
        else
        begin
            barriers[pack(s)] <= barrier;
        end
    endrule

    (* descending_urgency = "checkBarrierInit, setLocalSyncSignal, setRemoteSyncSignal" *)
    rule setRemoteSyncSignal (initDone);
        let m = link_sync_signal_report.first();
        let barrier = barriers[pack(m.syncId)];
        link_sync_signal_report.deq();
        barrier[pack(m.sender)] = False;
        if (!fold(\|| , barrier)) 
        begin
            barriers[pack(m.syncId)] <= unpack(barrierInitValues[pack(m.syncId)]);
            link_sync_broadcast.sendToNext(tagged SYNC_BARRIER_DONE m.syncId);
            syncRespQs[pack(m.syncId)].enq(True);
        end
        else
        begin
            barriers[pack(m.syncId)] <= barrier;
        end
    endrule
    
    
    // =======================================================================
    //
    // Drop broadcast messages
    //
    // =======================================================================

    (* fire_when_enabled *)
    rule dropBroadcastMsg (True);
        let msg <- link_sync_broadcast.recvFromPrev();
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    Vector#(n_SYNCS, SYNC_IFC) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_SYNCS); p = p + 1)
    begin
        portsLocal[p] =
            interface SYNC_IFC;
                method Action setSyncBarrier(Bit#(N_SYNC_NODES) barrier) if (!fold(\&& , readVReg(barrierInitialized)));
                    barrierInitValues[p] <= barrier;
                    barrierInitialized[p] <= True;
                endmethod
                
                method Action signalSyncReached() if (initDone);
                    doneSignalQ.enq(fromInteger(p));
                endmethod

                method Action waitForSync() if (syncRespQs[p].notEmpty());
                    syncRespQs[p].deq();
                endmethod

                method Bool othersSyncAllReached();
                    let barrier = barriers[p];
                    barrier[0] = False;
                    return (!fold(\|| , barrier));
                endmethod 
            endinterface;
    end

    interface syncPorts = portsLocal;

    method Bool initialized() = (initDone == True);

endmodule

//
// mkMultiSyncNodeSlave --
//     Instantiate a slave synchronization node with multiple synchronization points
// in a specific synchronization group.
//
module [CONNECTED_MODULE] mkMultiSyncNodeSlave#(Integer syncGroupID)
    // interface:
    (SYNC_SERVICE_MULTI_SYNC_IFC#(n_SYNCS))
    provisos (NumAlias#(TMax#(TLog#(n_SYNCS), 1), t_SYNC_ID_SZ),
              Add#(1, extraBits, n_SYNCS),
              Alias#(Bit#(t_SYNC_ID_SZ), t_SYNC_ID),
              Alias#(SYNC_MSG#(t_SYNC_ID), t_SYNC_MSG),
              Alias#(SYNC_BCAST_MSG#(t_SYNC_ID), t_SYNC_BCAST_MSG),
              Bits#(t_SYNC_BCAST_MSG, t_SYNC_BCAST_MSG_SZ),
              Bits#(t_SYNC_MSG, t_SYNC_MSG_SZ));

    // =======================================================================
    //
    // Synchronization nodes are connected via rings. 
    //
    // Two rings are used: one for done signals (send to controller),
    // the other one for broadcasting initialization and synchronization 
    // messages (from the controller)
    //
    // =======================================================================

    // Broadcast ring for synchronization message
    CONNECTION_CHAIN#(t_SYNC_BCAST_MSG) link_sync_broadcast <- mkConnectionChain("Sync_group_" + integerToString(syncGroupID) + "_broadcast");
    
    // Addressable ring (self-enumeration) for sync signal report
    CONNECTION_ADDR_RING#(SYNC_PORT_NUM, t_SYNC_MSG) link_sync_signal_report <-
        mkConnectionTokenRingDynNode("Sync_group_" + integerToString(syncGroupID) + "_signal_report");
    
    
    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    Reg#(Bool)                      initDone     <- mkReg(False);
    Reg#(Bool)                      portInitDone <- mkReg(False); 
    Reg#(SYNC_PORT_NUM)             myPort       <- mkReg(0);
    FIFOF#(t_SYNC_ID)               doneSignalQ  <- mkBypassFIFOF();
    Vector#(n_SYNCS, FIFOF#(Bool))  syncRespQs   <- replicateM(mkBypassFIFOF());

    (* fire_when_enabled *)
    rule portInit (!portInitDone);
        portInitDone <= True;
        let port_num = link_sync_signal_report.nodeID();
        myPort <= port_num;
    endrule
   
    // Receive and forward initialization message
    (* fire_when_enabled *)
    rule recvInit (!initDone);
        initDone <= True;
        let msg <- link_sync_broadcast.recvFromPrev();
        link_sync_broadcast.sendToNext(msg);
    endrule

    // =======================================================================
    //
    // Send out done signals to the synchronization controller
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule sendDoneSignal (True);
        let s = doneSignalQ.first();
        doneSignalQ.deq();
        link_sync_signal_report.enq( 0, SYNC_MSG { sender: myPort, syncId: s } );
    endrule


    // =======================================================================
    //
    // Receive broadcast synchronization signal
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule recvSyncSignal (initDone && portInitDone);
        let msg <- link_sync_broadcast.recvFromPrev();
        if (msg matches tagged SYNC_BARRIER_DONE .s)
        begin
            syncRespQs[pack(s)].enq(True);
        end
        link_sync_broadcast.sendToNext(msg);
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    Vector#(n_SYNCS, SYNC_IFC) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_SYNCS); p = p + 1)
    begin
        portsLocal[p] =
            interface SYNC_IFC;
                method Action setSyncBarrier(Bit#(N_SYNC_NODES) barrier);
                    noAction;
                endmethod
                
                method Action signalSyncReached() if (initDone && portInitDone);
                    doneSignalQ.enq(fromInteger(p));
                endmethod

                method Action waitForSync() if (syncRespQs[p].notEmpty());
                    syncRespQs[p].deq();
                endmethod

                method Bool othersSyncAllReached() = False;
            endinterface;
    end

    interface syncPorts = portsLocal;

    method Bool initialized() = ((initDone == True) && (portInitDone == True));

endmodule
