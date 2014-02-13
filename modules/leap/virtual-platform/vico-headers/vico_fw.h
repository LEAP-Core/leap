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

#ifndef _VICO_H_
#define _VICO_H_

#include <string>
#include <map>
#include <vector>
#include <stdint.h>
#include "scemi.h"

#ifdef _WIN32
#include <windows.h>
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef int int32_t;
typedef unsigned uint32_t;
typedef __int64 int64_t;
typedef unsigned __int64 uint64_t;

#define MOD_ENT __declspec(dllexport) 
#else
#define MOD_ENT
#endif



namespace ViCo {

#ifndef _WIN32
namespace Utils { namespace LinEvents {
 class WaitMgr;
}};
#endif

class EXT_SYM Event {
#ifdef _WIN32
 HANDLE event;
#else
 friend class ViCo::Utils::LinEvents::WaitMgr;

 bool signaled;
 bool manual_reset;
 typedef std::map<ViCo::Utils::LinEvents::WaitMgr*,int/*,SmallBlockAlloc<std::pair<WaitMgr*,int> > */> WtSet;
 WtSet wt_set;  //TODO - enable allocator

 void rise();
 void clr(ViCo::Utils::LinEvents::WaitMgr*);
 void set(ViCo::Utils::LinEvents::WaitMgr*, int idx);
 void signal_all(bool sig_abort) {while(signal_one(sig_abort,true)) {;}}
 bool signal_one(bool sig_abort, bool remove);
#endif

 static int waitn(int n, Event* evs[], int timeout);

public:
 Event(bool manual_reset=false);
 ~Event();

 static const int w_tout = -1;

 void operator = (bool);

 bool wait(int timeout=-1) {Event* e=this; return waitn(1,&e,timeout)!=w_tout;}

 int wait(Event& ev2, int timeout=-1) {Event* e[2]={this,&ev2}; return waitn(2,e,timeout);}
 int wait(Event& ev2, Event& ev3, int timeout=-1) {Event* e[3]={this,&ev2,&ev3}; return waitn(3,e,timeout);}
 int wait(Event& ev2, Event& ev3, Event& ev4, int timeout=-1) {Event* e[4]={this,&ev2,&ev3,&ev4}; return waitn(4,e,timeout);}
};

typedef bool (*ErrorHook)(int level, const char* msg);

void EXT_SYM error(int level, const char* msg, ...);
ErrorHook EXT_SYM set_error_hook(ErrorHook);

namespace Plugin {

 enum MainOptions {
  MO_MainIsOptional    = 0x00000001,
  MO_ForceMultiThread  = 0x00000002,
  MO_DetachMainTh      = 0x00000004
 };

// Stage of System/Plugins
 enum PlState {
  PlS_Loaded,      // All plugins was loaded
  PlS_ThStarted,   // All plugins threads are started, entering main loop
  PlS_Terminating, // System entering shutdown state
  PlS_Terminated   // System enter shutdown state, all threads are stopped, all plugins will be unloaded
 };

// Execution state
 enum SysExecState {
  SES_Run,       // System is running
  SES_TermPend,  // Shutdown pending
  SES_Shutdown   // System in shutdown state
 };

 struct Main {
  uint32_t self_size;
  void (*pl_main)();
  void (*pl_thread_main)();
  bool (*pl_state)(PlState state, int substage);
  uint32_t options;
 };


 enum InitOption {
  IO_ForceMultiThread = 0x00000001,
  IO_UseCfgCurDir     = 0x00000002,
  IO_UseCfgExeDir     = 0x00000004
 };

 struct InitInfo {
  uint32_t self_size;
  uint32_t init_options;
  const char* attach_control;
   // Attach format:
   //  <type>[':'<data>[':'<args...>]]
   // 'Type' is
   //  AUTO  - Autoselect attach type (default)
   //  HW    - FPGA hardware. Data (optional) is a driver name
   //  SLAVE - Slave mode (in master-slave configuration). Data is [<host>':']<port>
   //  SOFT  - Software interface. Data is .so name
  char* ext_pipe_mode;  // 'ext_pipe_mode' can be modified, if wildcard pipe name was specified
   // If set force system run as master in master-slave mode
  const char* config_name;
 };

EXT_SYM  bool init(char** argv, InitInfo* ii=NULL);
EXT_SYM  bool register_self_module(Main& self, const char* self_name=NULL);
EXT_SYM  const char* can_run();
EXT_SYM  int run();
EXT_SYM  void terminate(int retv);
EXT_SYM  Event& get_terminate_event();
EXT_SYM  SysExecState get_sys_state();

 typedef Main* (*InitModuleEntry)(int args_total, char** args);
}

namespace VarsMgr {
 struct VarAccessProxy;
}

namespace SCE_MI_Ex {
 
  enum MC_Option {
   MCO_Wait      = 0x00000001,  // Wait for packet before return (no timeout check before pkt arrive)
   MCO_WRestart  = 0x00000002,  // Restart wait timeout after each pkt arrived
   MCO_WPrecise  = 0x00000004,  // Return precisely after 'timeout' ms
   MCO_Single    = 0x00000008   // Do not loop in main_cycle (avoid hangup if Rdy callbacks continously produce data to send)
  };
  enum MC_Ret {
   MCR_Done,
   MCR_Terminate,
   MCR_Event,
   MCR_Timeout
  };

EXT_SYM MC_Ret main_cycle(int opt, int timeout=-1, Event* stop_event=NULL, int* real_delay_proceed=NULL);

  // Parameters access
class EXT_SYM Parameters {
   Parameters();
  public:

   static Parameters* get();
   SceMiParameters* get_parameters();

   enum VarInfoOpt {
    VIO_String = 0x00000001,
    VIO_RO     = 0x00000002
   };

   struct AttrInfo {
    uint64_t    i_value;
    std::string s_value;    
    uint32_t    options;
   };

   struct VarInfo {
    std::string var_name;
    AttrInfo var_value;
    std::map<std::string,AttrInfo> attrs;
   };

   bool get_var(const std::string& name, VarInfo&);
   bool set_var(const std::string& name, const AttrInfo&);
   void scan_vars(const std::string& name_prefix, std::vector<VarInfo> &vars);
  };

  // HW register or Config var access
class EXT_SYM VarAccess {
   ViCo::VarsMgr::VarAccessProxy* proxy;
  public:
   VarAccess(const char* var_name);
   ~VarAccess();

   bool is_connected() const {return proxy!=NULL;}

   operator uint64_t() const;
   uint64_t operator = (uint64_t);

   const char* as_str() const;
   void as_str(const char*);
  };

  // C++ interface style callbacks
struct EXT_SYM MessageInPortCallback {
   virtual ~MessageInPortCallback() {}

   virtual void IsReady() =0;
   virtual int Close() {return 0;}

   SceMiMessageInPortBinding get_binding();
  };

struct EXT_SYM MessageOutPortCallback {
   virtual ~MessageOutPortCallback() {}

   virtual void Receive(const SceMiMessageData& data) =0;
   virtual int Close() {return 0;}

   SceMiMessageOutPortBinding get_binding();
  };

  template<typename T, void (T::*IsReady)()>
  class BindInPort {
   struct Wrapper {
    static void p_IsReady(void* p)
     {
      (((T*)p)->*IsReady)();
     }
   };
   SceMiMessageInPortBinding rv;
  public:
   BindInPort(T* s)
    {
     rv.Close=NULL;
     rv.Context=s;
     rv.IsReady=&Wrapper::p_IsReady;
    }
   const SceMiMessageInPortBinding& data() const {return rv;}
  };

  template<typename T, void (T::*Receive)(const SceMiMessageData&)>
  class BindOutPort {
   struct Wrapper {
    static void p_Receive(void* p, const SceMiMessageData* d)
    {
     (((T*)p)->*Receive)(*d);
    }
   };
   SceMiMessageOutPortBinding rv;
  public:
   BindOutPort(T* s)
   {
    rv.Close=NULL;
    rv.Context=s;
    rv.Receive=&Wrapper::p_Receive;
   }
   const SceMiMessageOutPortBinding& data() const {return rv;}
  };
}


namespace Platform {

//TODO Not implemented yet - FileLoader
class EXT_SYM FileLoader { 
 public:
  FileLoader();
  FileLoader(const char* f_name, int64_t shift=0);

  void set_section_address(const char* sec_name, uint64_t address);
  void set_section_shift(const char* sec_name, int64_t shift);

  enum Status {
   ST_OK,
   ST_NotExists,
   ST_WrongFormat
  };

  enum FileType {
   FT_Auto,
   FT_Bin,
   FT_iHex,
   FT_Hex,
   FT_ELF
  };

  Status load(const char* file_name, FileType ft=FT_Auto);
  Status load_cl(std::string cmd_line);

  enum SymType {
   ST_NoSym,
   ST_Symbol,
   ST_Section
  };

  struct SymInfo {
   SymType type;
   uint64_t address;
   size_t size;
  };
  Status get_sym_info(const char* sym_name, SymInfo&);
 };

 void* main_mem_dmi(size_t &mem_size);
 void  main_mem_exch(uint64_t mem_addr, void* buf, size_t size, bool is_write);

}

//TODO Not implemented yet - Sync services
namespace Sync {

class EXT_SYM SyncSite {
protected:
 virtual ~SyncSite() {}
public:

 virtual bool stop() {return false;} // return true if model was successfully suspended
 virtual void resume() {}
 virtual void recomend_granularity(uint64_t) {}
 virtual uint64_t get_current_tick() {return (uint64_t)-1;}
};

class EXT_SYM SyncClient {
protected:
 virtual ~SyncClient() {}
public:
 virtual void sync(uint64_t ticks) =0;
 virtual void define_time_scale(uint64_t ps_in_tick) =0;
 virtual void recomend_granularity(uint64_t) =0;
};


class EXT_SYM SyncServer {
public:
 static SyncServer* get();

 SyncClient* register_client(SyncSite* site=NULL);
 void deregister_client(SyncClient*);
};


}

}

/* Special pipes (all in/out):

wr - $FPGA/DMA       Control (int64 address, int count, byte DMA_sel)

wr - $System/Control Stop    (int ret_value)

   - $Soft/... ... -- Installed from Plugin config files

*/

#endif
