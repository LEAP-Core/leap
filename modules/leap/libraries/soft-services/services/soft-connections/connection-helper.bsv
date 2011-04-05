import Clocks::*;
import Connectable::*;

// ****** Helper Functions ******

// Connections can be hooked up using the standard mkConnection function

instance Connectable#(CONNECTION_OUT#(t_MSG), CONNECTION_IN#(t_MSG));

  function m#(Empty) mkConnection(CONNECTION_OUT#(t_MSG) cout, CONNECTION_IN#(t_MSG) cin)
    provisos (IsModule#(m, c));
  
    return connectOutToIn(cout, cin);
    
  endfunction

endinstance

instance Connectable#(CONNECTION_IN#(t_MSG), CONNECTION_OUT#(t_MSG));

  function m#(Empty) mkConnection(CONNECTION_IN#(t_MSG) cin, CONNECTION_OUT#(t_MSG) cout)
    provisos (IsModule#(m, c));
  
    return connectOutToIn(cout, cin);
    
  endfunction

endinstance

// InOut pairs like Servers and Clients can also be connected.

instance Connectable#(PHYSICAL_CONNECTION_INOUT, PHYSICAL_CONNECTION_INOUT);

  function m#(Empty) mkConnection(PHYSICAL_CONNECTION_INOUT c1, PHYSICAL_CONNECTION_INOUT c2)
    provisos (IsModule#(m, c));
  
    return connectInOutToInOut(c1, c2);
    
  endfunction

endinstance

module connectInOutToInOut#(PHYSICAL_CONNECTION_INOUT inout1, PHYSICAL_CONNECTION_INOUT inout2) ();

  mkConnection(inout1.outgoing, inout2.incoming);
  mkConnection(inout2.outgoing, inout1.incoming);

endmodule

// {send,recv}NameMatches

// Does the send/recv's name match the param
// In this world, not matching a logical platform is also a non-match
// and must be handled at the top level

typeclass Matchable#(type t);
  function String getLogicalName(t val);
  function String getComputePlatform(t val);
endtypeclass

instance Matchable#(LOGICAL_RECV_INFO);
  function String getLogicalName(LOGICAL_RECV_INFO rinfo);
    return rinfo.logicalName;
  endfunction

  function String getComputePlatform(LOGICAL_RECV_INFO rinfo);
    return rinfo.computePlatform;
  endfunction
endinstance

instance Matchable#(LOGICAL_SEND_INFO);
  function String getLogicalName(LOGICAL_SEND_INFO sinfo);
    return sinfo.logicalName;
  endfunction

  function String getComputePlatform(LOGICAL_SEND_INFO sinfo);
    return sinfo.computePlatform;
  endfunction
endinstance

instance Matchable#(LOGICAL_RECV_MULTI_INFO);
  function String getLogicalName(LOGICAL_RECV_MULTI_INFO rinfo);
    return rinfo.logicalName;
  endfunction

  function String getComputePlatform(LOGICAL_RECV_MULTI_INFO rinfo);
    return rinfo.computePlatform;
  endfunction
endinstance

instance Matchable#(LOGICAL_SEND_MULTI_INFO);
  function String getLogicalName(LOGICAL_SEND_MULTI_INFO sinfo);
    return sinfo.logicalName;
  endfunction

  function String getComputePlatform(LOGICAL_SEND_MULTI_INFO sinfo);
    return sinfo.computePlatform;
  endfunction
endinstance

function Bool nameMatches(r rinfo, s sinfo)
  provisos (Matchable#(r),
            Matchable#(s));
  
  return (getLogicalName(sinfo) == getLogicalName(rinfo)) && 
         (getComputePlatform(sinfo) == getComputePlatform(rinfo));
 
endfunction

function Bool nameDoesNotMatch(r rinfo, s sinfo)
  provisos (Matchable#(r),
            Matchable#(s));
  
  return !nameMatches(rinfo,sinfo);
endfunction

function Bool primNameMatches(String rinfo, s sinfo)
  provisos (Matchable#(s));
  
  return (rinfo == getLogicalName(sinfo));
 
endfunction

function Bool primNameDoesNotMatch(String rinfo, s sinfo)
  provisos (Matchable#(s));
  
  return !primNameMatches(rinfo, sinfo);
endfunction

// connectOutToIn

// This is the module that actually performs the connection between two
// physical endpoints. This is for 1-to-1 communication only.

module connectOutToIn#(CONNECTION_OUT#(t_MSG_SIZE) cout, CONNECTION_IN#(t_MSG_SIZE) cin) ();
  
  if(sameFamily(cin.clock,cout.clock))
  begin
      rule trySend (cout.notEmpty());
          // Try to move the data
          Bit#(t_MSG_SIZE) x = cout.first();
          cin.try(x);
      endrule

      rule success (cin.success());
          // We succeeded in moving the data
          cout.deq();
    
      endrule
  end
  else
  begin

      messageM("CrossDomain@ Found");

      // choose a size large enough to cover latency of fifo
      let domainFIFO <- mkSyncFIFO(8,
                                   cout.clock, 
                                   cout.reset,
                                   cin.clock);

      rule receive (cout.notEmpty() && domainFIFO.notFull());
          Bit#(t_MSG_SIZE) x = cout.first();
          domainFIFO.enq(x);
          cout.deq();
      endrule
  
      rule trySend (domainFIFO.notEmpty());
          cin.try(domainFIFO.first());
      endrule

      rule succeedSend(cin.success());
          domainFIFO.deq();
      endrule
  end

endmodule


module printSend#(LOGICAL_SEND_INFO send) (Empty);
  messageM("Send: " + send.logicalName + " " + send.computePlatform);
endmodule

module printSends#(List#(LOGICAL_SEND_INFO) sends) (Empty);
  for (Integer x = 0; x < length(sends); x = x + 1)
    begin
      printSend(sends[x]);
    end
endmodule

module printRecv#(LOGICAL_RECV_INFO recv) (Empty);
  messageM("Recv: " + recv.logicalName + " " + recv.computePlatform);
endmodule

module printRecvs#(List#(LOGICAL_RECV_INFO) recvs) (Empty);
  for (Integer x = 0; x < length(recvs); x = x + 1)
    begin
      printRecv(recvs[x]);
    end
endmodule

