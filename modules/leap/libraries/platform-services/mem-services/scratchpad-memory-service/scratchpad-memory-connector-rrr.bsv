//
// Copyright (C) 2011 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//


import Arbiter::*;

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/DEBUG_SCAN_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/rrr/service_ids.bsh"
`include "awb/rrr/client_stub_SCRATCHPAD_MEMORY.bsh"
`include "awb/rrr/server_stub_SCRATCHPAD_MEMORY.bsh"



module [CONNECTED_MODULE] mkScratchpadConnector#(SCRATCHPAD_MEMORY_VDEV vdev) (Empty);

    ClientStub_SCRATCHPAD_MEMORY scratchpad_rrr <- mkClientStub_SCRATCHPAD_MEMORY(); 

    Connection_TokenRing#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_RING_REQ) link_mem_req <- mkConnectionTokenRingNode("ScratchpadGlobalReq", 0);

    Connection_TokenRing#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <- mkConnectionTokenRingNode("ScratchpadGlobalResp", 0);

    Reg#(Bit#(32)) reqCount <- mkReg(0);
    Reg#(Bit#(32)) respCount <- mkReg(0);
 
    FIFO#(SCRATCHPAD_PORT_NUM) tags <- mkSizedFIFO(32); // How many outstanding reqs do we want?

    function Action sendReq(SCRATCHPAD_RRR_REQ req, SCRATCHPAD_PORT_NUM num);
      action
      case (req) matches
        tagged StoreWordReq .storeWordReq:
            begin
              scratchpad_rrr.makeRequest_StoreWord(storeWordReq.byteMask,
                                                   storeWordReq.addr,
                                                   storeWordReq.data);
            end
        tagged StoreLineReq .storeLineReq:
           begin
             scratchpad_rrr.makeRequest_StoreLine(storeLineReq.byteMask,
                                                  storeLineReq.addr,
                                                  storeLineReq.data0,
                                                  storeLineReq.data1,
                                                  storeLineReq.data2,
                                                  storeLineReq.data3);
           end

        tagged LoadLineReq .loadLineReq:
           begin
             scratchpad_rrr.makeRequest_LoadLine(loadLineReq.addr);
             tags.enq(num);
           end

        tagged InitRegionReq .initRegionReq:
           begin
             scratchpad_rrr.makeRequest_InitRegion(initRegionReq.regionID, 
                                                   initRegionReq.regionEndIdx);
           end  
      endcase
      endaction
    endfunction

    rule eatReqLocal;
      let req <- vdev.rrrReq();
      sendReq(req,0);
      $display("Scratchpad store 0 sent a req %d", reqCount+1);
      reqCount <= reqCount + 1;      
    endrule
 
    rule eatRespLocal(tags.first == 0);
      tags.deq;
      let r <- scratchpad_rrr.getResponse_LoadLine();
      vdev.loadLineResp(SCRATCHPAD_RRR_LOAD_LINE_RESP{data0:r.data0,
                                                      data1:r.data1,
                                                      data2:r.data2,
                                                      data3:r.data3});
      $display("Scratchpad store 0 got a resp %d", respCount+1);
      respCount <= respCount + 1;
    endrule

    // Also handle non-local requests
    rule eatReqNonLocal;
      let req = link_mem_req.first();
      link_mem_req.deq();
      sendReq(req.req,req.portID);
      $display("Scratchpad store got a non-local req %d", req.portID);
    endrule

    rule eatRespNonLocal(tags.first != 0);
      tags.deq;
      $display("Scratchpad load serviced non-local resp %d", tags.first);
      let r <- scratchpad_rrr.getResponse_LoadLine();
      link_mem_rsp.enq(tags.first,SCRATCHPAD_RRR_LOAD_LINE_RESP{data0:r.data0,
                                                      data1:r.data1,
                                                      data2:r.data2,
                                                      data3:r.data3});
    endrule

endmodule
