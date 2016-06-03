//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

import Clocks::*;
import Connectable::*;
import GetPut::*;
import FIFOF::*;


//============================================================================
// Helper Functions
//
// Connections can be hooked up using the standard mkConnection function
//=============================================================================


instance Connectable#(CONNECTION_OUT#(t_MSG), CONNECTION_IN#(t_MSG));

  function m#(Empty) mkConnection(CONNECTION_OUT#(t_MSG) cout, CONNECTION_IN#(t_MSG) cin)
    provisos (IsModule#(m, c));
  
    return connectOutToIn(cout, cin, 0);
    
  endfunction

endinstance

instance Connectable#(CONNECTION_IN#(t_MSG), CONNECTION_OUT#(t_MSG));

  function m#(Empty) mkConnection(CONNECTION_IN#(t_MSG) cin, CONNECTION_OUT#(t_MSG) cout)
    provisos (IsModule#(m, c));
  
    return connectOutToIn(cout, cin, 0);
    
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
  function String  getLogicalName(t val);
  function Integer getLogicalWidth(t val);
  function String  getModuleName(t val);
endtypeclass

instance Matchable#(LOGICAL_RECV_ENTRY);
  function String getLogicalName(LOGICAL_RECV_ENTRY r_entry);
    return ctHashKey(r_entry);
  endfunction

  function Integer getLogicalWidth(LOGICAL_RECV_ENTRY r_entry);
    return ctHashValue(r_entry).bitWidth;
  endfunction

  function String getModuleName(LOGICAL_RECV_ENTRY r_entry);
    return ctHashValue(r_entry).moduleName;
  endfunction
endinstance

instance Matchable#(LOGICAL_SEND_ENTRY);
  function String getLogicalName(LOGICAL_SEND_ENTRY s_entry);
    return ctHashKey(s_entry);
  endfunction

  function Integer getLogicalWidth(LOGICAL_SEND_ENTRY s_entry);
    return ctHashValue(s_entry).bitWidth;
  endfunction

  function String getModuleName(LOGICAL_SEND_ENTRY r_entry);
    return ctHashValue(r_entry).moduleName;
  endfunction
endinstance

instance Matchable#(LOGICAL_RECV_MULTI_INFO);
  function String getLogicalName(LOGICAL_RECV_MULTI_INFO rinfo);
    return rinfo.logicalName;
  endfunction

  function Integer getLogicalWidth(LOGICAL_RECV_MULTI_INFO rinfo);
    return rinfo.bitWidth;
  endfunction

  function String getModuleName(LOGICAL_RECV_MULTI_INFO rinfo);
    return rinfo.moduleName;
  endfunction
endinstance

instance Matchable#(LOGICAL_SEND_MULTI_INFO);
  function String getLogicalName(LOGICAL_SEND_MULTI_INFO sinfo);
    return sinfo.logicalName;
  endfunction

  function Integer getLogicalWidth(LOGICAL_SEND_MULTI_INFO sinfo);
    return sinfo.bitWidth;
  endfunction

  function String getModuleName(LOGICAL_SEND_MULTI_INFO sinfo);
    return sinfo.moduleName;
  endfunction
endinstance

instance Matchable#(LOGICAL_CHAIN_INFO);
  function String getLogicalName(LOGICAL_CHAIN_INFO sinfo);
    return sinfo.logicalName;
  endfunction

  function Integer getLogicalWidth(LOGICAL_CHAIN_INFO sinfo);
    return sinfo.bitWidth;
  endfunction

  function String getModuleName(LOGICAL_CHAIN_INFO sinfo); 

    // Although chains carry information about incoming and outgoing
    // modules for chain links, it is sufficient to only look at the incoming module, since all new links 
    // have the incoming and outgoing modules tagged in the same way.
    
    return sinfo.moduleNameIncoming; 
  endfunction 
endinstance

instance Matchable#(LOGICAL_SERVICE_CLIENT_INFO);
  function String getLogicalName(LOGICAL_SERVICE_CLIENT_INFO sinfo);
    return sinfo.logicalName;
  endfunction

  function Integer getLogicalWidth(LOGICAL_SERVICE_CLIENT_INFO sinfo);
    return sinfo.reqBitWidth + sinfo.respBitWidth + sinfo.clientIdBitWidth;
  endfunction

  function String getModuleName(LOGICAL_SERVICE_CLIENT_INFO sinfo);
    return sinfo.moduleName;
  endfunction
endinstance

instance Matchable#(LOGICAL_SERVICE_SERVER_INFO);
  function String getLogicalName(LOGICAL_SERVICE_SERVER_INFO sinfo);
    return sinfo.logicalName;
  endfunction

  function Integer getLogicalWidth(LOGICAL_SERVICE_SERVER_INFO sinfo);
    return sinfo.reqBitWidth + sinfo.respBitWidth + sinfo.clientIdBitWidth;
  endfunction

  function String getModuleName(LOGICAL_SERVICE_SERVER_INFO sinfo);
    return sinfo.moduleName;
  endfunction
endinstance


function Bool nameMatches(Bool exposeAllConnections, r rinfo, s sinfo)
  provisos (Matchable#(r),
            Matchable#(s));
  
  return (getLogicalName(sinfo) == getLogicalName(rinfo)) &&          
         // In the first pass of multifpga builds, we expose all connections. 
         // However connections within the same module can be joined immediately. 
         ((getModuleName(sinfo) == getModuleName(rinfo)) ||
          !exposeAllConnections);   
endfunction

function Bool nameDoesNotMatch(Bool exposeAllConnections, r rinfo, s sinfo)
  provisos (Matchable#(r),
            Matchable#(s));
  
  return !nameMatches(exposeAllConnections, rinfo,sinfo);
endfunction

function Bool primNameMatches(String rinfo, s sinfo)
  provisos (Matchable#(s));
  
  return (rinfo == getLogicalName(sinfo));
 
endfunction

function Bool primNameDoesNotMatch(String rinfo, s sinfo)
  provisos (Matchable#(s));
  
  return !primNameMatches(rinfo, sinfo);
endfunction

function Bool serviceNameIdMatches(String name, String id, LOGICAL_SERVICE_CLIENT_INFO sinfo);
    return (sinfo.logicalName == name) && (sinfo.clientId == id);
endfunction


//
// mkBufferedConnectionOut --
//   Transform a CONNECTION_OUT by adding some number of buffered FIFOs as
//   intermediate stages in order to relax timing.  A new CONNECTION_OUT is
//   returned.
//
module mkBufferedConnectionOut#(CONNECTION_OUT#(t_MSG_SIZE) cout,
                                Integer bufferStages)
    // Interface:
    (CONNECTION_OUT#(t_MSG_SIZE));

    if (bufferStages == 0)
    begin
        return cout;
    end
    else
    begin
        // Connect cout to first buffer.
        FIFOF#(Bit#(t_MSG_SIZE)) b <- mkUGFIFOF(clocked_by cout.clock,
                                                reset_by cout.reset);

        rule fromCout (cout.notEmpty && b.notFull);
            // Try to move the data
            Bit#(t_MSG_SIZE) x = cout.first();
            cout.deq();

            b.enq(x);
        endrule

        // Insert extra buffer stages
        for (Integer i = 1; i < bufferStages; i = i + 1)
        begin
            FIFOF#(Bit#(t_MSG_SIZE)) b_next <- mkUGFIFOF(clocked_by cout.clock,
                                                         reset_by cout.reset);

            rule conBuf (b.notEmpty && b_next.notFull);
                let x = b.first();
                b.deq();

                b_next.enq(x);
            endrule

            b = b_next;
        end

        method Bool notEmpty = b.notEmpty;
        method Bit#(t_MSG_SIZE) first = b.first;
        method Action deq = b.deq;
        interface Clock clock = cout.clock;
        interface Reset reset = cout.reset;
    end
endmodule


//
// mkBufferedConnectionIn --
//   Transform a CONNECTION_IN by adding some number of buffered FIFOs as
//   intermediate stages in order to relax timing.  A new CONNECTION_IN is
//   returned.
//
module mkBufferedConnectionIn#(CONNECTION_IN#(t_MSG_SIZE) cin,
                                Integer bufferStages)
    // Interface:
    (CONNECTION_IN#(t_MSG_SIZE));

    if (bufferStages == 0)
    begin
        return cin;
    end
    else
    begin
        // Connect cin to nearest buffer.
        FIFOF#(Bit#(t_MSG_SIZE)) b <- mkUGFIFOF(clocked_by cin.clock,
                                                reset_by cin.reset);

        rule cinTrySend (b.notEmpty);
            // Try to move the data
            Bit#(t_MSG_SIZE) x = b.first();
            cin.try(x);
        endrule

        rule cinSuccess (cin.success());
            // We succeeded in moving the data
            b.deq();
        endrule

        // Insert extra buffer stages
        for (Integer i = 1; i < bufferStages; i = i + 1)
        begin
            FIFOF#(Bit#(t_MSG_SIZE)) b_prev <- mkUGFIFOF(clocked_by cin.clock,
                                                         reset_by cin.reset);

            rule conBuf (b_prev.notEmpty && b.notFull);
                let x = b_prev.first();
                b_prev.deq();

                b.enq(x);
            endrule

            b = b_prev;
        end

        PulseWire enW <- mkPulseWire(clocked_by cin.clock, reset_by cin.reset);

        method Action try(Bit#(t_MSG_SIZE) d);
            if (b.notFull)
            begin
                b.enq(d);
                enW.send();
            end
        endmethod

        method Bool success() = enW;
        method Bool dequeued() = enW;
        interface Clock clock = cin.clock;
        interface Reset reset = cin.reset;
    end
endmodule


//
// connectOutToIn --
//   This is the module that actually performs the connection between two
//   physical endpoints. This is for 1-to-1 communication only.
//
//   A configurable number of buffer stages may be added to relax timing
//   between distant endpoints.
//
module connectOutToIn#(CONNECTION_OUT#(t_MSG_SIZE) cout,
                       CONNECTION_IN#(t_MSG_SIZE) cin,
                       Integer bufferStages)
    // Interface:
    ();
  
    let buf_cout <- mkBufferedConnectionOut(cout, bufferStages);

    rule trySend (buf_cout.notEmpty());
        // Try to move the data
        Bit#(t_MSG_SIZE) x = buf_cout.first();
        cin.try(x);
    endrule

    rule success (cin.success());
        // We succeeded in moving the data
        buf_cout.deq();
    endrule
endmodule


// Smart, clock-domain aware version, of the above.
// This version is not used presently, due to issues in 
// carrying clock information through the import BVI 
// version of the build tree.
module connectOutToInMulti#(CONNECTION_OUT#(t_MSG_SIZE) cout, CONNECTION_IN#(t_MSG_SIZE) cin) ();
  
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


module printSend#(LOGICAL_SEND_ENTRY entry) (String);
  match {.name, .send} = entry;
  String printStr = "Send: " + name + " " + send.moduleName + "\n";
  messageM(printStr);
  return printStr;
endmodule

module printSends#(LOGICAL_SEND_INFO_TABLE sends) (Empty);
  List::mapM(printSend, ctHashTableToList(sends));
endmodule

module printRecv#(LOGICAL_RECV_ENTRY entry) (String);
  match {.name, .recv} = entry;
  String printStr = "Recv: " + name + " " + recv.moduleName + "\n";
  messageM(printStr);
  return printStr;
endmodule

module printRecvs#(LOGICAL_RECV_INFO_TABLE recvs) (Empty);
  List::mapM(printRecv, ctHashTableToList(recvs));
endmodule

//
// Global string table.
//

module printGlobString#(Handle hdl, GLOBAL_STRING_TABLE_ENTRY entry) (Empty);
    // Tag the end of the string with a marker so newlines can be detected
    hPutStrLn(hdl, integerToString(tpl_2(entry).uid) + "," + tpl_1(entry) + "X!gLb!X");
endmodule

module printGlobStrings#(GLOBAL_STRING_TABLE tbl) (Empty);
    Handle hdl <- openFile(genPackageName + ".str", WriteMode);
    List::mapM(printGlobString(hdl), ctHashTableToList(tbl.buckets));
    hClose(hdl);
endmodule


// Functions for resizing input/output connections. 

//
// resizeConnectOut
// Exposes actual size to high-level tools.  This is necessary so that the Xilinx 
// partition optimizers can more easily see unused code. 
//
function CONNECTION_OUT#(t_MSG_SIZE) resizeConnectOut(CONNECTION_OUT#(t_MSG_SIZE) cout, NumTypeParam#(t_ACTUAL_SIZE) connectionSize)
    provisos(Add#(t_EXTRA, t_ACTUAL_SIZE, t_MSG_SIZE));

    CONNECTION_OUT#(t_MSG_SIZE) retval = interface CONNECTION_OUT;
                                             method Bit#(t_MSG_SIZE) first();
                                                 Bit#(t_MSG_SIZE) x = cout.first();   
                                                 Bit#(t_ACTUAL_SIZE) xActual = truncateNP(x);
                                                 return {?,xActual};
                                             endmethod

                                             method deq = cout.deq;
                                             method notEmpty = cout.notEmpty;
                                             interface clock = cout.clock;
                                             interface reset = cout.reset;
                                         endinterface; 

    return retval;

endfunction
