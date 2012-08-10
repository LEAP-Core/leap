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
// MERCHANTABILITYS or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

import Connectable::*;
import Vector::*;
import Clocks::*;
import FIFO::*;

//------------------ Connection Information ----------------------//
//                                                                //
// We gather information about each module's connections using the//
// ModuleContext library. The connections are then hooked together//
// using this info with the algorithms in connections.bsv         //
//                                                                //
//----------------------------------------------------------------//

// The data type that is sent in connections
typedef `CON_CWIDTH PHYSICAL_DATA_SIZE;
typedef Bit#(PHYSICAL_DATA_SIZE) PHYSICAL_CONNECTION_DATA;
typedef Bit#(TSub#(`CON_CWIDTH, 32)) PHYSICAL_CONNECTION_PAYLOAD;

// Data types for routing multicast connections and performing logical broadcasts.
typedef `CONNECTION_IDX_SIZE CONNECTION_IDX_SIZE;
typedef Bit#(CONNECTION_IDX_SIZE) CONNECTION_IDX;
typedef function m#(FIFO#(Bit#(PHYSICAL_DATA_SIZE))) f() CONNECTION_BUFFER_CONSTRUCTOR#(type m);



typedef union tagged
{
   CONNECTION_IDX CONNECTION_ROUTED; // Route a message to a particular dst.
   void CONNECTION_BROADCAST;        // Send a message to all dsts.
}
CONNECTION_TAG deriving (Eq, Bits);

// A physical incoming connection
interface CONNECTION_IN#(numeric type t_MSG_SIZE);

  method Action try(Bit#(t_MSG_SIZE) d);
  method Bool   success();
  method Bool   dequeued();
  interface Clock clock;
  interface Reset reset;

endinterface

typedef CONNECTION_IN#(PHYSICAL_DATA_SIZE) PHYSICAL_CONNECTION_IN;

// A physical outgoing connection
interface CONNECTION_OUT#(numeric type t_MSG_SIZE);
  method Bool notEmpty();
  method Bit#(t_MSG_SIZE) first();
  method Action deq();
  interface Clock clock;
  interface Reset reset;

endinterface

typedef CONNECTION_OUT#(PHYSICAL_DATA_SIZE) PHYSICAL_CONNECTION_OUT;

// A bi-directional connection.
interface CONNECTION_INOUT#(numeric type t_IN_SIZE, numeric type t_OUT_SIZE);

  interface CONNECTION_IN#(t_IN_SIZE)   incoming;
  interface CONNECTION_OUT#(t_OUT_SIZE) outgoing;

endinterface

typedef CONNECTION_INOUT#(PHYSICAL_DATA_SIZE, PHYSICAL_DATA_SIZE) PHYSICAL_CONNECTION_INOUT;

// The basic sending half of a connection.

interface PHYSICAL_SEND#(type t_MSG);
  
  method Action send(t_MSG data);
  method Bool notFull();  
  method Bool dequeued();  

endinterface

typeclass ToPhysicalSend#(type t_IFC, type t_MSG)
    dependencies (t_IFC determines t_MSG);
    // Convert original type to physical send.
    module mkPhysicalSend#(t_IFC ifc) (PHYSICAL_SEND#(t_MSG));

endtypeclass

interface PHYSICAL_SEND_MULTI#(type t_MSG);

    method Action broadcast(t_MSG msg);
    method Action sendTo(CONNECTION_IDX dst, t_MSG msg);
    method Bool   notFull();
    method Bool   dequeued();

endinterface




// Phsyical incoming connection capable of multicast.
interface PHYSICAL_CONNECTION_IN_MULTI;

  method Action try(CONNECTION_IDX tag, PHYSICAL_CONNECTION_DATA d);
  method Bool   success();
  interface Clock clock;
  interface Reset reset;

endinterface

// Physical outgoing connection capable of multicast.
interface PHYSICAL_CONNECTION_OUT_MULTI;

  method Bool notEmpty();
  method Tuple2#(CONNECTION_TAG, PHYSICAL_CONNECTION_DATA) first();
  method Action deq();
  interface Clock clock;
  interface Reset reset;

endinterface

// A bi-directional multicast connection.
interface PHYSICAL_CONNECTION_INOUT_MULTI;

  interface PHYSICAL_CONNECTION_IN_MULTI  incoming;
  interface PHYSICAL_CONNECTION_OUT_MULTI outgoing;

endinterface

// A logical station is just a name.
interface STATION;

    method String name();

endinterface


// A physical station just looks like two FIFOFs.
interface PHYSICAL_STATION;

  method Bool notEmpty();
  method Tuple2#(CONNECTION_TAG, PHYSICAL_CONNECTION_DATA) first();
  method Action deq();
  
  method Action enq(CONNECTION_TAG tag, PHYSICAL_CONNECTION_DATA d);

endinterface

// Global string table entry

typedef struct
{
    Integer uid;
}
    GLOBAL_STRING_TABLE_ENTRY;

// The global string table is an association list of strings and entries.
typedef Tuple2#(String, GLOBAL_STRING_TABLE_ENTRY) GLOBAL_STRING_TABLE;

// Data about unmatched logical send connections
typedef struct 
{
    String logicalName;
    String logicalType;
    String computePlatform;
    String moduleName;
    Bool optional;
    Integer bitWidth;
    PHYSICAL_CONNECTION_OUT outgoing;
} 
    LOGICAL_SEND_INFO;

// Data about unmatched logical receive connections
typedef struct 
{
    String logicalName;
    String logicalType;
    String computePlatform;
    String moduleName;
    Bool optional;
    Integer bitWidth;
    PHYSICAL_CONNECTION_IN incoming;
} 
    LOGICAL_RECV_INFO;

// Data about unmatched logical send multicast connections
typedef struct 
{
    String logicalName;
    String logicalType;
    String computePlatform;
    Integer bitWidth;
    PHYSICAL_CONNECTION_OUT_MULTI outgoing;
} 
    LOGICAL_SEND_MULTI_INFO;

// Data about unmatched logical receive multicast connections
typedef struct 
{
    String logicalName;
    String logicalType;
    String computePlatform;
    Integer bitWidth;
    PHYSICAL_CONNECTION_IN_MULTI incoming;
} 
    LOGICAL_RECV_MULTI_INFO;

// Data about stations.
typedef struct
{
    String stationName;
    String networkName;
    String stationType;
    List#(String) childrenNames;
    List#(LOGICAL_SEND_INFO) registeredSends;
    List#(LOGICAL_RECV_INFO) registeredRecvs;
    List#(LOGICAL_SEND_MULTI_INFO) registeredSendMultis;
    List#(LOGICAL_RECV_MULTI_INFO) registeredRecvMultis;
}
    STATION_INFO;
    

// ========================================================================
//
// Debug state for soft connection FIFOs.  These are collected internally
// and emitted late, by a separate module not involved in soft connection
// creation.  The debug code itself depends on soft connections, so would
// cause a dependence loop if the connection debug info were generated
// in-line.
//
// ========================================================================

interface PHYSICAL_CONNECTION_DEBUG_STATE;
    method Bool notEmpty();
    method Bool notFull();
endinterface

typedef struct
{
    String sendName;
    PHYSICAL_CONNECTION_DEBUG_STATE state;
}
    CONNECTION_DEBUG_INFO;


// ========================================================================
//
// Latency control.  Permits us to toggle the buffering an latency of the 
// softconnections at runtime as a test fixture.
//
// ========================================================================


typedef 256 LATENCY_FIFO_DELAY;
typedef Bit#(TAdd#(1,TLog#(LATENCY_FIFO_DELAY))) LATENCY_FIFO_DELAY_CONTAINER;

typedef 2 LATENCY_FIFO_DEPTH;
typedef Bit#(TAdd#(1,TLog#(LATENCY_FIFO_DEPTH))) LATENCY_FIFO_DEPTH_CONTAINER;

interface CONNECTION_LATENCY_CONTROL;

    method Action setControl(Bool enable);
    method Action setDelay(LATENCY_FIFO_DELAY_CONTAINER delay);
    method Action setDepth(LATENCY_FIFO_DEPTH_CONTAINER depth);
    method Bool   incrStat();

endinterface

typedef struct
{
    String sendName;
    CONNECTION_LATENCY_CONTROL control;
}
    CONNECTION_LATENCY_INFO;

// ========================================================================
//
// BACKWARDS COMPATABILITY: Data about connection chains
//
// ========================================================================

typedef `CON_NUMCHAINS CON_NUM_CHAINS;
typedef `CON_CWIDTH CHAIN_DATA_SIZE;
typedef Bit#(CHAIN_DATA_SIZE) PHYSICAL_CHAIN_DATA;

typedef CONNECTION_IN#(CHAIN_DATA_SIZE)  PHYSICAL_CHAIN_IN;

typedef CONNECTION_OUT#(CHAIN_DATA_SIZE) PHYSICAL_CHAIN_OUT;
typedef CONNECTION_INOUT#(CHAIN_DATA_SIZE, CHAIN_DATA_SIZE) PHYSICAL_CHAIN;

typedef struct 
{
    String  logicalName;
    String  logicalType;
    String  computePlatform;
    String  moduleNameIncoming;
    String  moduleNameOutgoing;
    Integer bitWidth;
    PHYSICAL_CHAIN_IN  incoming;
    PHYSICAL_CHAIN_OUT outgoing;
} 
    LOGICAL_CHAIN_INFO;


// ========================================================================
//
// The context our connected modules operate on.
//
// ========================================================================

typedef struct
{
    List#(GLOBAL_STRING_TABLE) globalStrings;
    List#(LOGICAL_SEND_INFO) unmatchedSends;
    List#(LOGICAL_RECV_INFO) unmatchedRecvs;
    List#(LOGICAL_SEND_MULTI_INFO) unmatchedSendMultis;
    List#(LOGICAL_RECV_MULTI_INFO) unmatchedRecvMultis;
    List#(LOGICAL_CHAIN_INFO) chains;     // BACKWARDS COMPATABILITY: connection chains
    List#(STATION_INFO) stations;
    List#(STATION) stationStack;
    List#(CONNECTION_DEBUG_INFO) debugInfo;
    List#(CONNECTION_LATENCY_INFO) latencyInfo;
    String synthesisBoundaryPlatform;
    Integer synthesisBoundaryPlatformID;  // UID for a given FPGA
    Integer synthesisBoundaryID;          // UID a synthesis boundary within a single platform
    String synthesisBoundaryName;
    String rootStationName;
    Reset softReset;
}
    LOGICAL_CONNECTION_INFO;
