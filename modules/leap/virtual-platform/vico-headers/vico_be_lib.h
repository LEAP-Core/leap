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

#ifndef _VICO_BE_LIB_
#define _VICO_BE_LIB_

// Interface with HW side

namespace ViCo {
namespace SCE_MI_Ex {
 class Parameters;
}

namespace BE_Lib {

struct InitArgs {
 uint32_t self_size;
 const char* target;  // <data> part from attach_control (<mode>[:<data>[:<arg>]]) Can be NULL
 const char* args;    // <arg>  part from attach_control (<mode>[:<data>[:<arg>]]) Can be NULL

 const void* hello_pkt;
 size_t hello_pkt_size;

};

// Scatter-getter list
struct SGList {
 SGList* next;
 union {
  void* buffer;
  size_t main_mem_shift;
 };
 size_t size;
};

enum DMA_Status {
 DMAS_Run        = 0x00000001,
 DMAS_Error      = 0x00000002,
 DMAS_Interrupt  = 0x00000004
};

enum DMA_Mode {
 DMAM_Write       = 0x00000001,
 DMAM_AddrIsShift = 0x00000002   // Pointer is SG list really are shifts in 'main memory image'
};

struct DMA_StatusRet {
 uint32_t self_size;
 uint32_t status;
 uint64_t processed_size;
 uint32_t error_code;
};

struct SCE_MI_HdrDecoder {
 virtual ~SCE_MI_HdrDecoder() {}
 // SCE-MI pkt header encode/decode

 virtual size_t get_size() const =0;
 virtual size_t hdr_write(void* dst, size_t port_idx, size_t data_size, size_t &align) =0;
 virtual size_t hdr_read(const void* src, size_t &port_idx, size_t &data_size, size_t &align) =0;
 // sce_mi_hdr_(read|write) returns size of Pkt header.
 // sizeof of underlying buffer for sce_mi_hdr_read.src should be not less than sce_mi_hdr_get_size()
 //  if real packet is shorten than sce_mi_hdr_get_size() than rest of packet image will be undefined
};

struct Interface {
 virtual ~Interface() {}
 virtual void shutdown() =0;
 
 // Access registers (BAR)
 // section - is a register cluster index (BAR number)
 // addr - shift in cluster (in bytes)
 virtual uint64_t reg_read(uint64_t section, uint64_t addr, size_t size) =0;
 virtual void     reg_write(uint64_t section, uint64_t addr, size_t size, uint64_t data) =0;
 virtual void*    reg_dmi(uint64_t section) =0;

 // SCE-MI support
 virtual SGList*  sce_mi_exch(SGList* to_send) =0; // Send & recv packets (returns received packets)
 virtual void     sce_mi_free_sglist(SGList*) =0; // Free SG list, returned by sce_mi_exch call
 virtual bool     sce_mi_get_rdy(int ch_id) =0;

 virtual const char* sce_mi_hdr_def() =0;

 // DMA support
 virtual void     dma_set_info(int dma_chn, int index, uint64_t data) =0;
 virtual uint64_t dma_get_info(int dma_chn, int index) =0;
 virtual void     dma_run(SGList* data, int dma_chn, uint64_t addr, uint32_t mode) =0;
 virtual uint32_t dma_status(int dma_chn, bool reset_dma_status, DMA_StatusRet* ret_status=NULL) =0;
  // DMA end of op delivered via Callbacks::irq call

 // Main memory access
 virtual void*    main_mem_dmi(size_t &mem_size)=0;
 virtual void     main_mem_exch(uint64_t mem_addr, void* buf, size_t size, bool is_write) =0;

 // Master/Slave negotiation process support
 virtual void     on_sig_hierarchy(const void* cfg_pkt, size_t pkt_size) =0; // connected driver send us a config request (hello) packet

 // Initialization
 virtual bool     init_set_params(ViCo::SCE_MI_Ex::Parameters& params)=0;
 virtual bool     init_activate() =0;
  // Return error flag
};
/* Config section (setup through init_set_params)

sce_mi.pkt_rdy (type=bit) addr: section=x, bit_shift=x, bit_stride=x

dma.engaged (type=bit)    addr: section=x, bit_shift=x, bit_stride=x

cpu.isrun (type=bit)      addr: section=x, bit_shift=x
cpu.ticks (type=word)     addr: section=x, shift=x, size=x (4/8)

*/





enum CB_IRQ_Source {
 CIS_SCE_MI_Data, // Data available in one of output pipes
 CIS_SCE_MI_Rdy,  // Some of Rdy bits was changed
 CIS_DMA_Done,    // Some DMA channel is finished. data - DMA channel index
 CIS_IntHit,      // Unspecified interrupt got. data - INT index
 CIS_CPUStop      // CPU is stopped (by clock control)
};

struct Callbacks {
 virtual void irq(CB_IRQ_Source src, uint64_t data) =0;
 virtual void free_sglist(SGList*) =0; // returns back list from Iterface::sce_mi_exch call

 virtual void sig_hierarchy(const void* cfg_pkt, size_t pkt_size) =0; // send a config packet to connected driver (up) / FW itself

 virtual void error(int level, const char* msg, ...) =0; // Report error on init/run time
};

extern "C" Interface* get_interface(InitArgs& init, Callbacks* cb);
extern "C" SCE_MI_HdrDecoder* get_hdr_decoder(const char*);

}


}

/* Connected drivers installation:

 TL - top level driver    (pipe manager)
 BL - bottom level driver (hardware)

BL is installed and already initialized.

Instalation procedure:

TL::get_interface(init.hello_pkt is PKT from top level FW)

 TL (via pipe in TL driver itself) <init.hello_pkt> -> (FW pipe manager) BL::on_sig_hierarchy  
  [BL::callback->sig_hierarchy( <FW pkt> ) ]
   or
  [BL::callback->sig_hierarchy( <answer pkt> ) (FW pipe manager) ->  
   (TL internal pipe) TL::internal 
    or
   TL::callback->sig_hierarchy( <FW pkt> )
    ...
  ]
 [ TL (via pipe in TL driver itself) <internal pkt> -> (FW pipe manager) BL::on_sig_hierarchy
  ...
 ]
*/


#endif
