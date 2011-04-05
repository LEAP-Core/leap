import ModuleContext::*;
import Connectable::*;
import Vector::*;
import Clocks::*;

//------------------ Connection Information ----------------------//
//                                                                //
// We gather information about each module's connections using the//
// ModuleContext library. The connections are then hooked together//
// using this info with the algorithms in connections.bsv         //
//                                                                //
//----------------------------------------------------------------//

// The data type that is sent in connections
typedef Bit#(`CON_CWIDTH) PHYSICAL_CONNECTION_DATA;
typedef Bit#(TSub#(`CON_CWIDTH, 32)) PHYSICAL_CONNECTION_PAYLOAD;

// Data types for routing multicast connections and performing logical broadcasts.
typedef `CONNECTION_IDX_SIZE CONNECTION_IDX_SIZE;
typedef Bit#(CONNECTION_IDX_SIZE)CONNECTION_IDX;

typedef union tagged
{
   CONNECTION_IDX CONNECTION_ROUTED; // Route a message to a particular dst.
   void CONNECTION_BROADCAST;        // Send a message to all dsts.
}
CONNECTION_TAG deriving (Eq, Bits);

// A physical incoming connection
interface PHYSICAL_CONNECTION_IN;

  method Action try(PHYSICAL_CONNECTION_DATA d);
  method Bool   success();
  interface Clock clock;
  interface Reset reset;

endinterface

// A physical outgoing connection
interface PHYSICAL_CONNECTION_OUT;

  method Bool notEmpty();
  method PHYSICAL_CONNECTION_DATA first();
  method Action deq();
  interface Clock clock;
  interface Reset reset;

endinterface


// A bi-directional connection.
interface PHYSICAL_CONNECTION_INOUT;

  interface PHYSICAL_CONNECTION_IN  incoming;
  interface PHYSICAL_CONNECTION_OUT outgoing;

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

// Data about unmatched logical send connections
typedef struct 
{
    String logicalName;
    String logicalType;
    Bool optional;
    PHYSICAL_CONNECTION_OUT outgoing;
} 
    LOGICAL_SEND_INFO;

// Data about unmatched logical receive connections
typedef struct 
{
    String logicalName;
    String logicalType;
    Bool optional;
    PHYSICAL_CONNECTION_IN incoming;
} 
    LOGICAL_RECV_INFO;

// Data about unmatched logical send multicast connections
typedef struct 
{
    String logicalName;
    String logicalType;
    PHYSICAL_CONNECTION_OUT_MULTI outgoing;
} 
    LOGICAL_SEND_MULTI_INFO;

// Data about unmatched logical receive multicast connections
typedef struct 
{
    String logicalName;
    String logicalType;
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
    
// BACKWARDS COMPATABILITY: Data about connection chains
typedef `CON_NUMCHAINS CON_NUM_CHAINS;

typedef struct 
{
    Integer logicalIdx;
    String  logicalType;
    PHYSICAL_CONNECTION_IN  incoming;
    PHYSICAL_CONNECTION_OUT outgoing;
} 
    LOGICAL_CHAIN_INFO;


// The context our connected modules operate on.
typedef struct
{
    List#(LOGICAL_SEND_INFO) unmatchedSends;
    List#(LOGICAL_RECV_INFO) unmatchedRecvs;
    List#(LOGICAL_SEND_MULTI_INFO) unmatchedSendMultis;
    List#(LOGICAL_RECV_MULTI_INFO) unmatchedRecvMultis;
    Vector#(CON_NUM_CHAINS, List#(LOGICAL_CHAIN_INFO)) chains; // BACKWARDS COMPATABILITY: connection chains
    List#(STATION_INFO) stations;
    List#(STATION) stationStack;
    String rootStationName;
    Reset softReset;
}
    LOGICAL_CONNECTION_INFO;

// A connected Module is a Bluespec module which uses Soft Connections
typedef ModuleContext#(LOGICAL_CONNECTION_INFO) CONNECTED_MODULE;

