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
typedef `CON_CWIDTH PHYSICAL_DATA_SIZE;
typedef Bit#(PHYSICAL_DATA_SIZE) PHYSICAL_CONNECTION_DATA;
typedef Bit#(TSub#(`CON_CWIDTH, 32)) PHYSICAL_CONNECTION_PAYLOAD;

// Data types for routing multicast connections and performing logical broadcasts.
typedef `CONNECTION_IDX_SIZE CONNECTION_IDX_SIZE;
typedef Bit#(CONNECTION_IDX_SIZE) CONNECTION_IDX;

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
    String computePlatform;
    Bool optional;
    PHYSICAL_CONNECTION_OUT outgoing;
} 
    LOGICAL_SEND_INFO;

// Data about unmatched logical receive connections
typedef struct 
{
    String logicalName;
    String logicalType;
    String computePlatform;
    Bool optional;
    PHYSICAL_CONNECTION_IN incoming;
} 
    LOGICAL_RECV_INFO;

// Data about unmatched logical send multicast connections
typedef struct 
{
    String logicalName;
    String logicalType;
    String computePlatform;
    PHYSICAL_CONNECTION_OUT_MULTI outgoing;
} 
    LOGICAL_SEND_MULTI_INFO;

// Data about unmatched logical receive multicast connections
typedef struct 
{
    String logicalName;
    String logicalType;
    String computePlatform;
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
typedef `CON_CHAIN_CWIDTH CHAIN_DATA_SIZE;
typedef Bit#(CHAIN_DATA_SIZE) PHYSICAL_CHAIN_DATA;

typedef CONNECTION_IN#(CHAIN_DATA_SIZE)  PHYSICAL_CHAIN_IN;
typedef CONNECTION_OUT#(CHAIN_DATA_SIZE) PHYSICAL_CHAIN_OUT;
typedef CONNECTION_INOUT#(CHAIN_DATA_SIZE, CHAIN_DATA_SIZE) PHYSICAL_CHAIN;

typedef struct 
{
    Integer logicalIdx;
    String  logicalType;
    PHYSICAL_CHAIN_IN  incoming;
    PHYSICAL_CHAIN_OUT outgoing;
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
