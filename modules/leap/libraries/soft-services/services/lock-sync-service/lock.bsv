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
// Lock service implementation. 
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
// The maximum number of associated lock nodes
//
typedef 32 N_LOCK_NODES;

//
// Lock node port number. 
//
typedef Bit#(TMax#(TLog#(N_LOCK_NODES),1)) LOCK_PORT_NUM;

//
// Lock request
//
typedef struct
{
    LOCK_PORT_NUM       requester;
    t_LOCK_ID           lockId;
}
LOCK_REQ_MSG#(type t_LOCK_ID)
    deriving(Bits, Eq);

//
// Lock service interface.
//
interface LOCK_IFC#(type t_LOCK_ID);
    // Issue a request to get access to a certain lock 
    method Action acquireLockReq(t_LOCK_ID id);
    // Retrun a response when a lock is available to use
    method ActionValue#(t_LOCK_ID) lockResp();
    // Release a certain lock
    method Action releaseLock(t_LOCK_ID id);
    method Bool respNotEmpty();
    method Bool reqNotFull();
endinterface

//
// Lock state 
//
typedef enum
{
    LOCK_STATE_NOT_OWN    = 0,
    LOCK_STATE_OWN_IDLE   = 1,
    LOCK_STATE_OWN_IN_USE = 2,
    LOCK_STATE_WAIT       = 3
}
LOCK_STATE
    deriving (Eq, Bits);

//
// Lock entry
//
typedef struct
{
    LOCK_STATE             state;
    Maybe#(LOCK_PORT_NUM)  fwdId;
}
LOCK_ENTRY
    deriving(Bits, Eq);

//
// mkLockNode -- 
//     Instantiate a lock node in a specific lock group. 
// Inside the same lock group, lock nodes are connected on rings and share a 
// set of locks. 
//
module [CONNECTED_MODULE] mkLockNode#(Integer lockGroupID, Bool isMasterNode)
    // interface:
    (LOCK_IFC#(t_LOCK_ID))
    provisos (Bits#(t_LOCK_ID, t_LOCK_ID_SZ),
              Alias#(LOCK_REQ_MSG#(t_LOCK_ID), t_LOCK_REQ));

    DEBUG_FILE debugLog <- mkDebugFileNull(""); 
    
    let lock <- mkLockNodeDebug(lockGroupID, isMasterNode, debugLog);

    return lock;
endmodule

//
// mkLockNodeDebug -- 
//     Instantiate a lock node in a specific lock group. 
// 
// This is the module used for debugging.  Debug file is passed in as an argument 
// for simplicity. 
//
// Current implementation is suitable for the case where there is a small number of locks. 
// If there is a large number of locks, it requries another kind of implementation. 
//
module [CONNECTED_MODULE] mkLockNodeDebug#(Integer lockGroupID, Bool isMasterNode, DEBUG_FILE debugLog)
    // interface:
    (LOCK_IFC#(t_LOCK_ID))
    provisos (Bits#(t_LOCK_ID, t_LOCK_ID_SZ),
              NumAlias#(TExp#(t_LOCK_ID_SZ), n_LOCKS),
              Alias#(LOCK_REQ_MSG#(t_LOCK_ID), t_LOCK_REQ));

    
    // =======================================================================
    //
    // Lock status information is stored on every distributed lock node.
    // The master node owns all the locks initially. 
    //
    // =======================================================================
    
    let initState = (isMasterNode)? LOCK_STATE_OWN_IDLE : LOCK_STATE_NOT_OWN;
   
    // Use a vector of registers to store lock status information
    // This implementation is suitable for a small number of locks
    Vector#(n_LOCKS, Reg#(LOCK_ENTRY)) lockMem <- replicateM( mkReg( LOCK_ENTRY{ state: initState, 
                                                                                 fwdId: tagged Invalid } ));
    
    // LUTRAM#(t_LOCK_ID, LOCK_ENTRY) lockMem <- mkLUTRAM(LOCK_ENTRY{ state: initState, fwdId: tagged Invalid });
    
    
    // =======================================================================
    //
    // Lock nodes are connected via rings. 
    //
    // Two rings are required to avoid deadlocks: one for requests, 
    // one for responses.
    //
    // =======================================================================

    // Broadcast ring for request
    CONNECTION_CHAIN#(t_LOCK_REQ) link_lock_req <- mkConnectionChain("Lock_group_" + integerToString(lockGroupID) + "_Req");
    
    // Addressable ring (self-enumeration) for response
    CONNECTION_ADDR_RING#(LOCK_PORT_NUM, t_LOCK_ID) link_lock_resp <- (isMasterNode)?
        mkConnectionTokenRingNode("Lock_group_" + integerToString(lockGroupID) + "_Resp", 0) :
        mkConnectionTokenRingDynNode("Lock_group_" + integerToString(lockGroupID) + "_Resp");

    
    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    Reg#(Bool) initialized          <- mkReg(isMasterNode);
    Reg#(LOCK_PORT_NUM) myPort      <- mkReg(0);
    FIFOF#(t_LOCK_ID) lockReqQ      <- mkFIFOF();
    FIFOF#(t_LOCK_ID) lockRespQ     <- mkBypassFIFOF();
    RWire#(t_LOCK_ID) releaseLockId <- mkRWire();
    
    FIFOF#(Tuple2#(LOCK_PORT_NUM, t_LOCK_ID)) respToNetworkQ  <- mkSizedBypassFIFOF(valueOf(n_LOCKS));

    Reg#(Bool) reqArb           <- mkReg(False); // False: local request has higher priority
                                                 // True: network request has higher priority

    if (isMasterNode == False)
    begin
        // Assign the port number got from request ring's self-enumeration to the response ring
        rule doInit (!initialized);
            initialized <= True;
            let port_num = link_lock_resp.nodeID();
            myPort <= port_num;
            debugLog.record($format("Lock node port ID = %0d", port_num));
        endrule
    end

    // =======================================================================
    //
    // Acquire lock (send requests)
    //
    // =======================================================================

    rule acquireLock (initialized && ( !reqArb || !link_lock_req.recvNotEmpty()));
        let lock_id = lockReqQ.first();
        lockReqQ.deq();
        let e = lockMem[pack(lock_id)];
        let new_entry = e;

        // state can only be LOCK_STATE_OWN_IDLE or LOCK_STATE_NOT_OWN 
        if (e.state == LOCK_STATE_OWN_IDLE)
        begin
            lockRespQ.enq(lock_id);
            new_entry.state = LOCK_STATE_OWN_IN_USE;
            debugLog.record($format("    acquireLock: lock (id = 0x%x) is available, send local response", lock_id));
        end
        else if (e.state == LOCK_STATE_NOT_OWN)
        begin
            t_LOCK_REQ req = LOCK_REQ_MSG { requester: myPort,
                                            lockId: lock_id };
            link_lock_req.sendToNext(req); 
            debugLog.record($format("    acquireLock: lock (id = 0x%x) is not available, send request on the ring", lock_id));
        end
        
        lockMem[pack(lock_id)] <= new_entry;
        reqArb <= True;
    endrule


    // =======================================================================
    //
    // Receive response 
    //
    // =======================================================================

    rule recvLockResp (True);
        let lock_id = link_lock_resp.first();
        link_lock_resp.deq();
        lockRespQ.enq(lock_id);
        debugLog.record($format("    recvLockResp: lock (id = 0x%x) is available, send local response", lock_id));
        let e = lockMem[pack(lock_id)];
        lockMem[pack(lock_id)] <= LOCK_ENTRY{ state: LOCK_STATE_OWN_IN_USE, fwdId: e.fwdId }; 
    endrule

    // =======================================================================
    //
    // Release lock
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule returnLock (releaseLockId.wget() matches tagged Valid .id);
        let e = lockMem[pack(id)];
        let new_entry = e;
        if (e.fwdId matches tagged Valid .f_id)
        begin
            respToNetworkQ.enq(tuple2(f_id, id)); 
            debugLog.record($format("    releaseLock: lock (id = 0x%x) is available, send network response to node id = 0x%x", id, f_id));
            new_entry.state = LOCK_STATE_NOT_OWN;
            new_entry.fwdId = tagged Invalid;
        end
        else // no need to forward lock
        begin
            new_entry.state = LOCK_STATE_OWN_IDLE;
            debugLog.record($format("    releaseLock: lock (id = 0x%x) is available, return to idle state", id));
        end
        lockMem[pack(id)] <= new_entry;
    endrule
    
    // =======================================================================
    //
    // Snoop network lock requests 
    //
    // =======================================================================
   
    (* descending_urgency = "returnLock, recvLockResp, acquireLock, snoopLockReq" *)
    rule snoopLockReq (reqArb || !lockRespQ.notEmpty());
        let req <- link_lock_req.recvFromPrev();
        let e = lockMem[pack(req.lockId)];
        let new_entry = e;

        if (e.state == LOCK_STATE_OWN_IDLE && !isValid(e.fwdId))
        begin
            respToNetworkQ.enq(tuple2(req.requester, req.lockId)); 
            debugLog.record($format("    snoopLockReq: lock (id = 0x%x) is available, send network response to node id = 0x%x", 
                            req.lockId, req.requester));
            new_entry.state = LOCK_STATE_NOT_OWN;
        end
        else if (e.state != LOCK_STATE_NOT_OWN && !isValid(e.fwdId))
        begin
            new_entry.fwdId = tagged Valid req.requester;
            debugLog.record($format("    snoopLockReq: lock (id = 0x%x) is not available, record forward id = 0x%x", 
                            req.lockId, req.requester));
        end
        else // forward request on the ring
        begin
            link_lock_req.sendToNext(req);
            debugLog.record($format("    snoopLockReq: forward lock request (lock id = 0x%x, node id = 0x%x)", 
                            req.lockId, req.requester));
        end

        lockMem[pack(req.lockId)] <= new_entry;
        reqArb <= False;
    endrule
    
    // =======================================================================
    //
    // Send responses
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule sendRespToNetwork (True);
        match {.n_id, .l_id} = respToNetworkQ.first();
        respToNetworkQ.deq();
        link_lock_resp.enq(n_id, l_id);
        debugLog.record($format("    sendRespToNetwork: lock id = 0x%x, node id = 0x%x ", n_id, l_id));
    endrule
    
    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    method Action acquireLockReq(t_LOCK_ID id);
        lockReqQ.enq(id);
        debugLog.record($format("Acquire lock request: lock id = 0x%x", id));
    endmethod

    method ActionValue#(t_LOCK_ID) lockResp();
        let r = lockRespQ.first();
        lockRespQ.deq();
        return r;
    endmethod

    method Action releaseLock (t_LOCK_ID id) if (respToNetworkQ.notFull());
        releaseLockId.wset(id);
        debugLog.record($format("Release lock: lock id = 0x%x", id));
    endmethod

    method Bool respNotEmpty();
        return lockRespQ.notEmpty();
    endmethod
    
    method Bool reqNotFull();
        return lockReqQ.notFull();
    endmethod

endmodule

