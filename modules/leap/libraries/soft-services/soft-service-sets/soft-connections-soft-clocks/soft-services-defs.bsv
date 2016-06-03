import HList::*;
import ModuleContext::*;

`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_clocks_lib.bsh"

typedef HList2#(LOGICAL_CONNECTION_INFO, LOGICAL_CLOCK_INFO) SOFT_SERVICES_CONTEXT;

typedef Tuple3#(WITH_CONNECTIONS#(t_NUM_IN, 
                                  t_NUM_OUT, 
                                  t_NUM_IN_MULTI, 
                                  t_NUM_OUT_MULTI, 
                                  t_NUM_CHAINS, 
                                  t_NUM_SERVICE_CLIENTS, 
                                  t_NUM_SERVICE_SERVERS), 
                Empty, 
                Empty) SOFT_SERVICES_INTERMEDIATE#(numeric type t_NUM_IN, 
                                                   numeric type t_NUM_OUT, 
                                                   numeric type t_NUM_IN_MULTI, 
                                                   numeric type t_NUM_OUT_MULTI, 
                                                   numeric type t_NUM_CHAINS, 
                                                   numeric type t_NUM_SERVICE_CLIENTS,
                                                   numeric type t_NUM_SERVICE_SERVERS);

typedef WITH_SERVICES#(SOFT_SERVICES_INTERMEDIATE#(t_NUM_IN, 
                                                   t_NUM_OUT, 
                                                   t_NUM_IN_MULTI, 
                                                   t_NUM_OUT_MULTI, 
                                                   t_NUM_CHAINS, 
                                                   t_NUM_SERVICE_CLIENTS, 
                                                   t_NUM_SERVICE_SERVERS), module_ifc) SOFT_SERVICES_SYNTHESIS_BOUNDARY#(numeric type t_NUM_IN, 
                                                                                                                         numeric type t_NUM_OUT, 
                                                                                                                         numeric type t_NUM_IN_MULTI, 
                                                                                                                         numeric type t_NUM_OUT_MULTI, 
                                                                                                                         numeric type t_NUM_CHAINS, 
                                                                                                                         numeric type t_NUM_SERVICE_CLIENTS,
                                                                                                                         numeric type t_NUM_SERVICE_SERVERS,
                                                                                                                         type module_ifc);

typedef ModuleContext#(SOFT_SERVICES_CONTEXT) SOFT_SERVICES_MODULE;

// Backwards compatability
typedef SOFT_SERVICES_MODULE SoftServicesModule;
typedef SOFT_SERVICES_CONTEXT SoftServicesContext;
typedef WITH_SERVICES#(SOFT_SERVICES_INTERMEDIATE#(nI, nO, 0, 0, nC, 0, 0), Empty) SoftServicesSynthesisInterface#(parameter numeric type nI, parameter numeric type nO, parameter numeric type nC);

