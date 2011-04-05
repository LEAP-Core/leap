import ModuleContext::*;
import Connectable::*;
import Vector::*;
import Clocks::*;

`include "asim/provides/soft_connections_common.bsh"


//------------------ Connection Information ----------------------//
//                                                                //
// We gather information about each module's connections using the//
// ModuleContext library. The connections are then hooked together//
// using this info with the algorithms in connections.bsv         //
//                                                                //
//----------------------------------------------------------------//

typedef SOFT_SERVICES_MODULE CONNECTED_MODULE;

