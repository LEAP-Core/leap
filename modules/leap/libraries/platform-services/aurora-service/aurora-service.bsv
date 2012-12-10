//
// Copyright (C) 2008 Intel Corporation
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

import FIFOF::*;
import GetPut::*;
import Connectable::*;
import CBus::*;
import Clocks::*;
import FIFO::*;
import FixedPoint::*;
import Complex::*;

`include "asim/provides/low_level_platform_interface.bsh"
`include "asim/provides/physical_platform.bsh"
`include "asim/provides/ml605_aurora_device.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_connections.bsh"
`include "asim/provides/soft_clocks.bsh"
`include "asim/provides/clocks_device.bsh"
`include "asim/provides/fpga_components.bsh"
`include "asim/provides/librl_bsv_storage.bsh"
`include "asim/provides/librl_bsv_base.bsh"

module [CONNECTED_MODULE] mkAuroraService#(PHYSICAL_DRIVERS drivers) (); 

   AURORA_DRIVER       auroraDriver = drivers.auroraDriver;
   FIFOF#(Bit#(16)) serdes_infifo <- mkSizedBRAMFIFOF(64);
   // make soft connections to PHY
   Connection_Send#(Bit#(16)) analogRX <- mkConnection_Send("AuroraRX");
   Reg#(Bit#(40)) rxCount <- mkReg(0);
   Reg#(Bit#(40)) sampleDropped <- mkReg(0);
   Reg#(Bit#(40)) sampleSent <- mkReg(0);
   
    rule sendToSW (serdes_infifo.notFull);
      Bit#(16) dataIn <- auroraDriver.read();
      rxCount <= rxCount + 1;
      // This may be a bug Alfred will know what to do. XXX
      sampleSent <= sampleSent + 1;
      serdes_infifo.enq(dataIn);
    endrule

/* ///// ???????????
    rule dropdata (!serdes_infifo.notFull);
       Bit#(16) dataIn <- auroraDriver.read();
       rxCount <= rxCount + 1;
       // This may be a bug Alfred will know what to do. XXX
       sampleDropped <= sampleDropped + 1;
    endrule
*/
    rule toAnalog;
       serdes_infifo.deq;
       analogRX.send(unpack(truncate(serdes_infifo.first())));       
    endrule

    Connection_Receive#(Bit#(16)) analogTX <- mkConnection_Receive("AuroraTX");

    FIFOF#(Bit#(16)) serdes_send <- mkSizedFIFOF(32);  

    Reg#(Bit#(40)) txCountIn <- mkReg(0);  
    Reg#(Bit#(40)) txCount <- mkReg(0);  

    rule forwardToLL; 
      analogTX.deq();
      txCountIn <= txCountIn + 1;
      serdes_send.enq(pack(analogTX.receive));
    endrule

    rule sendToSERDESData;
      auroraDriver.write(serdes_send.first());  // Byte endian issue?
      txCount <= txCount + 1;
      serdes_send.deq();
    endrule
endmodule
