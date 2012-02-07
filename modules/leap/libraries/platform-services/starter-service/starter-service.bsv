
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/starter_device.bsh"

`include "awb/provides/soft_connections.bsh"


module [CONNECTED_MODULE] mkStarterService#(VIRTUAL_DEVICES vdevs)
    // interface:
        ();
    
    let starter = vdevs.starter;
    
    // ====================================================================
    //
    // Starter connections.
    //
    // ====================================================================


    Connection_Send#(Bool) linkStarterStartRun <- mkConnectionSendOptional("vdev_starter_start_run");
    Connection_Receive#(Bit#(8)) linkStarterFinishRun <- mkConnectionRecvOptional("vdev_starter_finish_run");

    rule sendStarterStartRun (True);
        
        starter.acceptRequest_Start();
        linkStarterStartRun.send(?);
        
    endrule

    rule sendStarterFinishRun (True);
        
        let exit_code = linkStarterFinishRun.receive();
        linkStarterFinishRun.deq();
        starter.makeRequest_End(exit_code);
        
    endrule


endmodule
