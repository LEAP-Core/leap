
`include "awb/rrr/client_stub_STARTER_SERVICE.bsh"
`include "awb/rrr/server_stub_STARTER_SERVICE.bsh"

`include "awb/provides/soft_connections.bsh"


module [CONNECTED_MODULE] mkStarterService
    // interface:
        ();
    
    ClientStub_STARTER_SERVICE client_stub <- mkClientStub_STARTER_SERVICE;
    ServerStub_STARTER_SERVICE server_stub <- mkServerStub_STARTER_SERVICE;

    
    // ====================================================================
    //
    // Starter connections.
    //
    // ====================================================================


    Connection_Send#(Bool) linkStarterStartRun <- mkConnectionSendOptional("vdev_starter_start_run");
    Connection_Receive#(Bit#(8)) linkStarterFinishRun <- mkConnectionRecvOptional("vdev_starter_finish_run");

    rule sendStarterStartRun (True);
        
        let val <- server_stub.acceptRequest_Start();
        linkStarterStartRun.send(?);
        
    endrule

    rule sendStarterFinishRun (True);
        
        let exit_code = linkStarterFinishRun.receive();
        linkStarterFinishRun.deq();
        client_stub.makeRequest_End(exit_code);
        
    endrule


endmodule
