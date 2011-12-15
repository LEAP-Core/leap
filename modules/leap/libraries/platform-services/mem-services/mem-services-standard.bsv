`include "awb/provides/central_cache_service.bsh"
`include "awb/provides/scratchpad_memory_service.bsh"
`include "awb/provides/shared_memory_service.bsh"
`include "awb/provides/librl_bsv_base.bsh"

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/soft_connections.bsh"

`include "awb/dict/RINGID.bsh"


module [CONNECTED_MODULE] mkMemServices#(VIRTUAL_DEVICES vdevs)
    // interface:
        ();
    
    let centralCacheService     <- mkCentralCacheService();
    let scratchpadMemoryService <- mkScratchpadMemoryService(centralCacheService);
    let sharedMemoryService     <- mkSharedMemoryService();
    
endmodule
