
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/soft_connections.bsh"

`include "awb/dict/RINGID.bsh"


module [CONNECTED_MODULE] mkMemServices#(VIRTUAL_DEVICES vdevs)
    // interface:
        ();
    
    let centralCacheService     <- mkCentralCacheService(vdevs);
    let scratchpadMemoryService <- mkScratchpadMemoryService(vdevs);
    let sharedMemoryService     <- mkSharedMemoryService(vdevs);
    
endmodule
