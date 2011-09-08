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

#ifndef _VICO_RRR_LAYER_H_
#define _VICO_RRR_LAYER_H_

#include <assert.h>

#include "vico_extra.h"

// Space for additional parameters (up to sizeof(void*) in size for each of possible 4 parameters) for *_async calls of clients

#define VICO_RRR_MAX_RES_SPACE 4

// Generic params
#define VICO_RRR_UMF_CHUNK_SIZE 64


// Define this macro to print out bits definitoon for fields
// #define VICO_PRN_BITS

namespace ViCo { namespace RRR {

struct RRRWaitAnsBase {
 bool is_done;
 Event* do_done;

 RRRWaitAnsBase() {is_done=false; do_done=NULL;}
 void signal() {is_done=true; if (do_done) *do_done=true;}
 void wait()
 {
  if (do_done) do_done->wait(); else
  while(!is_done)
   SceMi::Pointer()->ServiceLoop(0,0,0);
//   SCE_MI_Ex::main_cycle(SCE_MI_Ex::MCO_Wait|SCE_MI_Ex::MCO_Single,0);
 }

};

template<class RetVal>
struct RRRWaitAnsCTX : public RRRWaitAnsBase {
 RetVal ret_val;
};

class RRRBase {
 static RRRBase* vico_rrr_root;
 RRRBase* vico_rrr_next;

protected:
 static bool vico_rrr_is_main_thread();
 static bool vico_rrr_is_initialized;

public:
 RRRBase() {vico_rrr_next=vico_rrr_root; vico_rrr_root=this;}
 virtual ~RRRBase() {}

 virtual void vico_rrr_do_init() =0; // bind to ports
 static void vico_rrr_layer_init();
};

typedef RRRBase RRRClientBase;
typedef RRRBase RRRServerBase;

inline void rrr_init()
{
 RRRBase::vico_rrr_layer_init();
}

}}


// Now - macros ....

//////////////// Binding specific part - now made for HAsim infrastructure /////////////////

#include "asim/provides/low_level_platform_interface.h"

#define VICO_RRR_SERVER_START_TDEFS(ServiceName)
#define VICO_RRR_SERVER_END_TDEFS(ServiceName)
#define VICO_RRR_CLIENT_START_TDEFS(ServiceName)
#define VICO_RRR_CLIENT_END_TDEFS(ServiceName)

#define VICO_RRR_SERVER_START_CLASS(ServiceName) \
typedef class ServiceName##_SERVER_STUB_CLASS* ServiceName##_SERVER_STUB; \
class ServiceName##_SERVER_STUB_CLASS: public ViCo::RRR::RRRServerBase,  public RRR_SERVER_STUB_CLASS, \
    public PLATFORMS_MODULE_CLASS \
{ \
  \
  private: \
           \
    ServiceName##_SERVER server; \
    typedef ServiceName##_SERVER_STUB_CLASS ME; \
    \
  public:                        \
                                 \
    ServiceName##_SERVER_STUB_CLASS(ServiceName##_SERVER s) \
    { \
        parent = PLATFORMS_MODULE(s); \
        server = s; \
        if (vico_rrr_is_initialized) ME::vico_rrr_do_init(); \
    }  \
       \
    ~ServiceName##_SERVER_STUB_CLASS() \
    {                                  \
    }                                  \
                                       \
    void Init(PLATFORMS_MODULE p)      \
    {                                  \
        server->Init(p);               \
    }                                  \
  private:
                                       

#define VICO_RRR_SERVER_END_CLASS(ServiceName) };

#define VICO_RRR_CLIENT_START_CLASS(ServiceName) \
typedef class ServiceName##_CLIENT_STUB_CLASS* ServiceName##_CLIENT_STUB; \
class ServiceName##_CLIENT_STUB_CLASS: public ViCo::RRR::RRRClientBase, \
 public PLATFORMS_MODULE_CLASS \
{ \
  typedef ServiceName##_CLIENT_STUB_CLASS ME; \
  public:  \
           \
    ServiceName##_CLIENT_STUB_CLASS(PLATFORMS_MODULE p) : \
            PLATFORMS_MODULE_CLASS(p)                    \
    {                                                    \
     if (vico_rrr_is_initialized) ME::vico_rrr_do_init(); \
    }                                                    \
                                                         \
    ~ServiceName##_CLIENT_STUB_CLASS()                    \
    {                                                    \
    }                                                    \
  private:


#define VICO_RRR_CLIENT_END_CLASS(ServiceName) };


#define VICO_RRR_SERVER_CALL_FUNC(MethodName) server->MethodName


///////////////////// ViCo/RRR Layer framework macros //////////////////////////////////////////////////

#define VICO_RRR_SERVER_START_METHODS_LIST(ServiceName) virtual void vico_rrr_do_init() {
#define VICO_RRR_SERVER_END_METHODS_LIST(ServiceName) }
#define VICO_RRR_CLIENT_START_METHODS_LIST(ServiceName) virtual void vico_rrr_do_init() {
#define VICO_RRR_CLIENT_END_METHODS_LIST(ServiceName) }

#define VICO_RRR_SERVER_ML_METHOD_V(ServiceName,MethodName) \
  {                                                         \
   SceMiMessageOutPortBinding bind=ViCo::SCE_MI_Ex::BindOutPort<ME,&ME::MethodName##_Recieve>(this).data(); \
   void* port_##ServiceName##_##MethodName = SceMi::Pointer()->BindMessageOutPort("$RRR/" #ServiceName "/s",#MethodName "_in",&bind);\
   assert(port_##ServiceName##_##MethodName != NULL);\
  }

#define VICO_RRR_SERVER_ML_METHOD(ServiceName,MethodName) \
  VICO_RRR_SERVER_ML_METHOD_V(ServiceName,MethodName) \
  MethodName##_SendPort=SceMi::Pointer()->BindMessageInPort("$RRR/" #ServiceName "/s", #MethodName "_out"); \
  assert(MethodName##_SendPort != NULL);

#define VICO_RRR_CLIENT_ML_METHOD_V(ServiceName,MethodName) \
  vico_rrr_port_##MethodName=SceMi::Pointer()->BindMessageInPort("$RRR/" #ServiceName "/c", #MethodName "_out"); \
  assert(vico_rrr_port_##MethodName != NULL);

#define VICO_RRR_CLIENT_ML_METHOD(ServiceName,MethodName) \
  VICO_RRR_CLIENT_ML_METHOD_V(ServiceName,MethodName) \
  vico_rrr_ans_server_##MethodName.vico_rrr_do_init();


#define VICO_RRR_SERVER_GENERATE_METHOD_V(ServiceName,MethodName) \
 void MethodName##_Recieve(const SceMiMessageData& vico_data) \
  {  \
   VICO_TIMING_BLOCK("RRR-Server:" #ServiceName "::" #MethodName);   \
   VICO_RRR_SERVER_ARGS_UNP \
   VICO_RRR_SERVER_CALL_FUNC (MethodName) ( VICO_RRR_SERVER_ARGS_N ); \
  }

#define VICO_RRR_SERVER_GENERATE_METHOD(ServiceName,MethodName) \
 SceMiMessageInPortProxy* MethodName##_SendPort;  \
 void MethodName##_Recieve(const SceMiMessageData& vico_data) \
  {   \
   VICO_TIMING_BLOCK("RRR-Server:" #ServiceName "::" #MethodName);   \
   VICO_RRR_SERVER_ARGS_UNP \
   { \
    OUT_TYPE_##MethodName vico_ret_var = VICO_RRR_SERVER_CALL_FUNC (MethodName) ( VICO_RRR_SERVER_ARGS_N ); \
    SceMiMessageData vico_data(*MethodName##_SendPort); \
    VICO_RRR_SERVER_ARGS_PACK \
    MethodName##_SendPort->Send(vico_data); \
   } \
  }


#define VICO_RRR_CLIENT_MAKE_METHOD_V(ServiceName,MethodName) \
 VICO_RRR_CLIENT_DEF_FIELD(ServiceName,MethodName)            \
 VICO_RRR_CLIENT_GENERATE_METHOD_VOID(ServiceName,MethodName)

#define VICO_RRR_CLIENT_MAKE_METHOD(ServiceName,MethodName) \
 VICO_RRR_CLIENT_DEF_FIELD(ServiceName,MethodName)              \
 VICO_RRR_CLIENT_DEF_ANS(ServiceName,MethodName)                \
 VICO_RRR_CLIENT_GENERATE_METHOD_ASYNC(ServiceName,MethodName)  \
 VICO_RRR_CLIENT_GENERATE_METHOD_SYNC(ServiceName,MethodName)   

// Second level defines - internals for client generation
#define VICO_RRR_CLIENT_DEF_FIELD(ServiceName,MethodName) \
 SceMiMessageInPortProxy* vico_rrr_port_##MethodName;

#define VICO_RRR_CLIENT_DEF_ANS(ServiceName,MethodName) \
 private:                                               \
 VICO_RRR_AUX_DEF_ANS_SERVER(ServiceName,MethodName) vico_rrr_ans_server_##MethodName; \
 void vico_rrr_aux_##MethodName##_wait_for_ans(VICO_RRR_CLIENT_OARGS_TN , ViCo::RRR::RRRWaitAnsCTX<OUT_TYPE_##MethodName>* vico_rrr_ctx) \
  { \
   VICO_RRR_CLIENT_OARGS_CPY; \
   vico_rrr_ctx->signal(); \
  }

#define VICO_RRR_PLIST1_TN P1 p1
#define VICO_RRR_PLIST2_TN P1 p1, P2 p2
#define VICO_RRR_PLIST3_TN P1 p1, P2 p2, P3 p3
#define VICO_RRR_PLIST4_TN P1 p1, P2 p2, P3 p3, P4 p4
#define VICO_RRR_PLIST5_TN P1 p1, P2 p2, P3 p3, P4 p4, P5 p5
#define VICO_RRR_PLIST6_TN P1 p1, P2 p2, P3 p3, P4 p4, P5 p5, P6 p6

#define VICO_RRR_PLIST1_N p1
#define VICO_RRR_PLIST2_N p1, p2
#define VICO_RRR_PLIST3_N p1, p2, p3
#define VICO_RRR_PLIST4_N p1, p2, p3, p4
#define VICO_RRR_PLIST5_N p1, p2, p3, p4, p5
#define VICO_RRR_PLIST6_N p1, p2, p3, p4, p5, p6

#define VICO_RRR_PLIST1_TC class P1
#define VICO_RRR_PLIST2_TC class P1, class P2
#define VICO_RRR_PLIST3_TC class P1, class P2, class P3
#define VICO_RRR_PLIST4_TC class P1, class P2, class P3, class P4
#define VICO_RRR_PLIST5_TC class P1, class P2, class P3, class P4, class P5
#define VICO_RRR_PLIST6_TC class P1, class P2, class P3, class P4, class P5, class P6

#define VICO_RRR_PLIST1_INST P1 p1
#define VICO_RRR_PLIST2_INST P1 p1; P2 p2
#define VICO_RRR_PLIST3_INST P1 p1; P2 p2; P3 p3
#define VICO_RRR_PLIST4_INST P1 p1; P2 p2; P3 p3; P4 p4
#define VICO_RRR_PLIST5_INST P1 p1; P2 p2; P3 p3; P4 p4; P5 p5
#define VICO_RRR_PLIST6_INST P1 p1; P2 p2; P3 p3; P4 p4; P5 p5; P6 p6

#define VICO_RRR_PLIST1_IL p1(p1)                    
#define VICO_RRR_PLIST2_IL p1(p1), p2(p2)                
#define VICO_RRR_PLIST3_IL p1(p1), p2(p2), p3(p3)            
#define VICO_RRR_PLIST4_IL p1(p1), p2(p2), p3(p3), p4(p4)        
#define VICO_RRR_PLIST5_IL p1(p1), p2(p2), p3(p3), p4(p4), p5(p5)    
#define VICO_RRR_PLIST6_IL p1(p1), p2(p2), p3(p3), p4(p4), p5(p5), p6(p6)


#define VICO_RRR_AUX_CGMASYNC(ServiceName,MethodName,Args) \
 public:                                                   \
  template<VICO_RRR_PLIST##Args##_TC>  \
  void MethodName##_async( VICO_RRR_CLIENT_IARGS_TN , VICO_RRR_PLIST##Args##_TN )\
  {                                                                             \
   VICO_TIMING_BLOCK("RRR-Client(async):" #ServiceName "::" #MethodName);   \
   vico_rrr_ans_server_##MethodName.reg(VICO_RRR_PLIST##Args##_N); \
   SceMiMessageData vico_data(*vico_rrr_port_##MethodName); \
   VICO_RRR_CLIENT_IARGS_PACK                               \
   vico_rrr_port_##MethodName->Send(vico_data); \
  }

#define VICO_RRR_CLIENT_GENERATE_METHOD_ASYNC(ServiceName,MethodName) \
 VICO_RRR_AUX_CGMASYNC(ServiceName,MethodName,1) \
 VICO_RRR_AUX_CGMASYNC(ServiceName,MethodName,2) \
 VICO_RRR_AUX_CGMASYNC(ServiceName,MethodName,3) \
 VICO_RRR_AUX_CGMASYNC(ServiceName,MethodName,4) \
 VICO_RRR_AUX_CGMASYNC(ServiceName,MethodName,5) \
 VICO_RRR_AUX_CGMASYNC(ServiceName,MethodName,6) 

#define VICO_RRR_CLIENT_GENERATE_METHOD_SYNC(ServiceName,MethodName) \
 public: \
  OUT_TYPE_##MethodName MethodName( VICO_RRR_CLIENT_IARGS_TN ) \
  {                                                           \
   VICO_TIMING_BLOCK("RRR-Client(sync):" #ServiceName "::" #MethodName);   \
   ViCo::RRR::RRRWaitAnsCTX<OUT_TYPE_##MethodName> vico_rrr_ctx; \
                                                              \
   if (!vico_rrr_is_main_thread())                            \
    {                                                         \
     ViCo::Event e;                                           \
     vico_rrr_ctx.do_done=&e;                                 \
     MethodName##_async(VICO_RRR_CLIENT_IARGS_N ,this,&ME::vico_rrr_aux_##MethodName##_wait_for_ans,&vico_rrr_ctx); \
    }                                                         \
   else                                                       \
    {                                                         \
     MethodName##_async(VICO_RRR_CLIENT_IARGS_N ,this,&ME::vico_rrr_aux_##MethodName##_wait_for_ans,&vico_rrr_ctx); \
    }                                                         \
   vico_rrr_ctx.wait();                                       \
                                                              \
   return vico_rrr_ctx.ret_val;                               \
  }                                                           

#define VICO_RRR_CLIENT_GENERATE_METHOD_VOID(ServiceName,MethodName) \
 public:                                                    \
  void MethodName( VICO_RRR_CLIENT_IARGS_TN)\
  {                                                         \
   VICO_TIMING_BLOCK("RRR-Client:" #ServiceName "::" #MethodName);   \
   SceMiMessageData vico_data(*vico_rrr_port_##MethodName); \
   VICO_RRR_CLIENT_IARGS_PACK                               \
   vico_rrr_port_##MethodName->Send(vico_data); \
  }



template<class T>
inline T* atomic_exchange_pointer(T* &ptr, T* newvalue)
{
 T* result;
 if (sizeof (T) == 4)
    __asm __volatile ("xchgl %0, %1"					      
	 : "=r" (result), "=m" (ptr)
	 : "0" (newvalue), "m" (ptr));
 else
 if (sizeof (T) == 8)
    __asm __volatile ("xchgq %0, %1"					      
	 : "=r" (result), "=m" (ptr)
	 : "0" (newvalue), "m" (ptr));
 return result;
}


#define VICO_RRR_AUX_DEF_ANS_SERVER(ServiceName,MethodName) \
 class VICO_RRR_ans_server_##MethodName : public ViCo::SCE_MI_Ex::MessageOutPortCallback { \
   struct SpaceHolder {                                                                         \
    void* vtbl;                                                                                 \
    void* object;                                                                               \
    void (SpaceHolder::*Func)( VICO_RRR_CLIENT_OARGS_TN );                                      \
    void* opaque[VICO_RRR_MAX_RES_SPACE];                                                       \
   };                                                                                           \
   SpaceHolder vico_rrr_space;                                                                  \
                                                                                                \
   struct CallProxy {                                                                           \
    virtual void call( VICO_RRR_CLIENT_OARGS_TN ) =0;                                           \
   };                                                                                           \
                                                                                                \
   CallProxy* vico_rrr_call_handler;                                                            \
                                                                                                \
   void vico_rrr_reg_ptr(CallProxy* h)                                                          \
    {                                                                                           \
     if (atomic_exchange_pointer(vico_rrr_call_handler,h)!=NULL)                                \
      ViCo::error(2,"RRR Ans Server: " #ServiceName "::" #MethodName " - Nested call(s)");      \
    }                                                                                           \
                                                                                                \
  public:                                                                                       \
   virtual void Receive(const SceMiMessageData& vico_data)                                      \
    {                                                                                           \
     VICO_RRR_CLIENT_OARGS_UNP                                                                  \
     CallProxy* h=atomic_exchange_pointer(vico_rrr_call_handler,(CallProxy*)NULL);              \
     if (h) h->call( VICO_RRR_CLIENT_OARGS_N );                                                 \
    }                                                                                           \
                                                                                                \
   void reg(void (*h)( VICO_RRR_CLIENT_OARGS_TN ) )                                             \
    {                                                                                           \
     struct PXY : public CallProxy {                                                            \
      void (*h)( VICO_RRR_CLIENT_OARGS_TN );                                                    \
      virtual void call ( VICO_RRR_CLIENT_OARGS_TN ) {h( VICO_RRR_CLIENT_OARGS_N );}            \
      PXY(void (*i)( VICO_RRR_CLIENT_OARGS_TN )) :h(i) {}                                       \
     };                                                                                         \
     assert(sizeof(PXY)<=sizeof(vico_rrr_space));                                               \
     vico_rrr_reg_ptr(new(&vico_rrr_space) PXY(h));                                             \
    }                                                                                           \
                                                                                                \
   template<class T>                                                                            \
   void reg(T* self, void (T::*h)( VICO_RRR_CLIENT_OARGS_TN ) )                                 \
    {                                                                                           \
     struct PXY : public CallProxy {                                                            \
      T* self;                                                                                  \
      void (T::*h)( VICO_RRR_CLIENT_OARGS_TN );                                                 \
      virtual void call ( VICO_RRR_CLIENT_OARGS_TN ) {(self->*h)( VICO_RRR_CLIENT_OARGS_N );}   \
      PXY(T* s, void (T::*i)( VICO_RRR_CLIENT_OARGS_TN )) :self(s), h(i) {}                     \
     };                                                                                         \
     assert(sizeof(PXY)<=sizeof(vico_rrr_space));                                               \
     vico_rrr_reg_ptr(new(&vico_rrr_space) PXY(self,h));                                        \
    }                                                                                           \
                                                                                                \
   VICO_RRR_AUX_DAS_REG(1) VICO_RRR_AUX_DAS_REG(2) VICO_RRR_AUX_DAS_REG(3) VICO_RRR_AUX_DAS_REG(4) \
                                                                                                \
   void vico_rrr_do_init()                                                                      \
    {                                                                                           \
     SceMiMessageOutPortBinding bind=get_binding(); \
     void* port_##ServiceName##_##MethodName = SceMi::Pointer()->BindMessageOutPort("$RRR/" #ServiceName "/c",#MethodName "_in",&bind); \
     assert(port_##ServiceName##_##MethodName != NULL); \
    }                                                                                           \
  }

#define VICO_RRR_AUX_DAS_REG(Arg) \
   template<VICO_RRR_PLIST##Arg##_TC>  \
   void reg(void (*h)( VICO_RRR_CLIENT_OARGS_TN , VICO_RRR_PLIST##Arg##_TN ) , VICO_RRR_PLIST##Arg##_TN ) \
    {                                                                         \
     struct PXY : public CallProxy {                                          \
      void (*h)( VICO_RRR_CLIENT_OARGS_TN , VICO_RRR_PLIST##Arg##_TN);         \
      VICO_RRR_PLIST##Arg##_INST;                                             \
      virtual void call ( VICO_RRR_CLIENT_OARGS_TN ) {h( VICO_RRR_CLIENT_OARGS_N , VICO_RRR_PLIST##Arg##_N);} \
      PXY(void (*i)( VICO_RRR_CLIENT_OARGS_TN , VICO_RRR_PLIST##Arg##_TN ), VICO_RRR_PLIST##Arg##_TN) :h(i), VICO_RRR_PLIST##Arg##_IL {} \
     };                                                                       \
     assert(sizeof(PXY)<=sizeof(vico_rrr_space));                             \
     vico_rrr_reg_ptr(new(&vico_rrr_space) PXY(h,VICO_RRR_PLIST##Arg##_N));   \
    }                                                                         \
                                                                              \
   template<class T, VICO_RRR_PLIST##Arg##_TC>                                \
   void reg(T* self, void (T::*h)( VICO_RRR_CLIENT_OARGS_TN , VICO_RRR_PLIST##Arg##_TN ) , VICO_RRR_PLIST##Arg##_TN ) \
    {                                                                         \
     struct PXY : public CallProxy {                                          \
      T* self;                                                                \
      void (T::*h)( VICO_RRR_CLIENT_OARGS_TN , VICO_RRR_PLIST##Arg##_TN );     \
      VICO_RRR_PLIST##Arg##_INST;                                             \
      virtual void call ( VICO_RRR_CLIENT_OARGS_TN ) {(self->*h)( VICO_RRR_CLIENT_OARGS_N , VICO_RRR_PLIST##Arg##_N );} \
      PXY(T* s, void (T::*i)( VICO_RRR_CLIENT_OARGS_TN,VICO_RRR_PLIST##Arg##_TN), VICO_RRR_PLIST##Arg##_TN) :self(s), h(i), VICO_RRR_PLIST##Arg##_IL {} \
     };                                                                       \
     assert(sizeof(PXY)<=sizeof(vico_rrr_space));                             \
     vico_rrr_reg_ptr(new(&vico_rrr_space) PXY(self,h,VICO_RRR_PLIST##Arg##_N));\
    }


// Pack-unpack defines
namespace ViCo { namespace RRR {

template<size_t PktLengthInBits>
struct PackUnpackDefs {
 enum {Gap = (VICO_RRR_UMF_CHUNK_SIZE - PktLengthInBits%VICO_RRR_UMF_CHUNK_SIZE)%VICO_RRR_UMF_CHUNK_SIZE};
 enum {TotalWords = (PktLengthInBits+VICO_RRR_UMF_CHUNK_SIZE-1)/VICO_RRR_UMF_CHUNK_SIZE*(VICO_RRR_UMF_CHUNK_SIZE/32)};
 enum {FirstFldBit = TotalWords*32 - Gap};
};

template<size_t FldLength, size_t FldStart, size_t PktLength>
struct PackUnpField {
 enum {BitEnd    = PackUnpackDefs<PktLength>::FirstFldBit-FldStart};
 enum {BitStart  = BitEnd - FldLength};
 enum {WordEnd   = (BitEnd-1)/32};
 enum {WordStart = BitStart/32};
 enum {Words     = WordEnd - WordStart + 1};

 static size_t swp_r(size_t B) 
  {
   return B;
  }
 static size_t swp_w(size_t B) 
  {
//   return ((PackUnpackDefs<PktLength>::TotalWords-1)*32 - (B&~31))|(B&31);
   enum {M=VICO_RRR_UMF_CHUNK_SIZE-1};
   return ((PackUnpackDefs<PktLength>::TotalWords/(VICO_RRR_UMF_CHUNK_SIZE/32)-1)*VICO_RRR_UMF_CHUNK_SIZE - (B&~M))|(B&M);
  }
};

template<size_t Start, size_t Length>
struct PUF_Cut {
 enum {MyDelta    = Start & 31};
 enum {MyLength   = (Length<32-MyDelta)?Length:32-MyDelta};
 enum {NextStart  = Start + MyLength};
 enum {NextLength = Length - MyLength};
};



template<size_t FldLength, size_t FldStart, size_t PktLength, size_t WordsCount>
struct FieldManipulator {};

template<size_t FldLength, size_t FldStart, size_t PktLength>
struct FieldManipulator<FldLength,FldStart,PktLength,1> {
 typedef PackUnpField<FldLength,FldStart,PktLength> P;

#ifdef VICO_PRN_BITS
 static int prn()
  {
   typedef PackUnpackDefs<PktLength> D;
   static int i=printf("FieldManipulator<FldLength=%d,FldStart=%d,PktLength=%d,1>\n",FldLength,FldStart,PktLength);
   static int k=printf("PackUnpackDefs: Gap=%d,TotalWords=%d,FirstFldBit=%d\n",
    D::Gap,D::TotalWords,D::FirstFldBit);
   static int j=printf("PackUnpField: BitStart=%d,swp_r(BitStart)=%d,BitEnd=%d,WordEnd=%d,WordStart=%d,Words=%d\n\n",
    P::BitStart,P::swp_r(P::BitStart),P::BitEnd,P::WordEnd,P::WordStart,P::Words);
   return 1;
  }

#define PRN_INST static int i=prn();
#else
#define PRN_INST
#endif



 static void pack(SceMiMessageData& dst, uint64_t data)
  {
   PRN_INST

   dst.SetBitRange(P::swp_w(P::BitStart),FldLength,SceMiU32(data));
  }

 static uint64_t unpack(const SceMiMessageData& src)
  {
   PRN_INST

   return src.GetBitRange(P::swp_r(P::BitStart),FldLength);
  }
};


template<size_t FldLength, size_t FldStart, size_t PktLength>
struct FieldManipulator<FldLength,FldStart,PktLength,2> {
 typedef PackUnpField<FldLength,FldStart,PktLength> P;
 typedef PUF_Cut<P::BitStart,FldLength> Cut1;
 enum {L1 = Cut1::MyLength};

#ifdef VICO_PRN_BITS
 static int prn()
  {
   typedef PackUnpackDefs<PktLength> D;
   static int i=printf("FieldManipulator<FldLength=%d,FldStart=%d,PktLength=%d,2>\n",FldLength,FldStart,PktLength);
   static int k=printf("PackUnpackDefs: Gap=%d,TotalWords=%d,FirstFldBit=%d\n",
    D::Gap,D::TotalWords,D::FirstFldBit);
   static int j=printf("PackUnpField: BitStart=%d,swp_r(BitStart)=%d,BitEnd=%d,WordEnd=%d,WordStart=%d,Words=%d\n",
    P::BitStart,P::swp_r(P::BitStart),P::BitEnd,P::WordEnd,P::WordStart,P::Words);

   static int i1=printf("SetBitRange(swp_w(BitStart)=%d,Cut1::MyLength=%d)\n",P::swp_w(P::BitStart),Cut1::MyLength);
   static int i2=printf("SetBitRange(swp_w(Cut1::NextStart)=%d,Cut1::NextLength=%d)\n\n",P::swp_w(Cut1::NextStart),Cut1::NextLength);

   return 1;
  }
#endif

 static void pack(SceMiMessageData& dst, uint64_t data)
  {
   PRN_INST

   dst.SetBitRange(P::swp_w(P::BitStart),Cut1::MyLength,SceMiU32(data));
   dst.SetBitRange(P::swp_w(Cut1::NextStart),Cut1::NextLength,SceMiU32(data>>L1));
  }

 static uint64_t unpack(const SceMiMessageData& src)
  {
   PRN_INST

   return           src.GetBitRange(P::swp_r(P::BitStart),Cut1::MyLength) |
          (uint64_t(src.GetBitRange(P::swp_r(Cut1::NextStart),Cut1::NextLength))<<L1);
  }
};

template<size_t FldLength, size_t FldStart, size_t PktLength>
struct FieldManipulator<FldLength,FldStart,PktLength,3> {
 typedef PackUnpField<FldLength,FldStart,PktLength> P;
 typedef PUF_Cut<P::BitStart,FldLength> Cut1;
 typedef PUF_Cut<Cut1::NextStart,Cut1::NextLength> Cut2;
 enum {L1 = Cut1::MyLength, L2 = L1 + Cut2::MyLength};

#ifdef VICO_PRN_BITS
 static int prn()
  {
   typedef PackUnpackDefs<PktLength> D;
   static int i=printf("FieldManipulator<FldLength=%d,FldStart=%d,PktLength=%d,2>\n",FldLength,FldStart,PktLength);
   static int k=printf("PackUnpackDefs: Gap=%d,TotalWords=%d,FirstFldBit=%d\n",
    D::Gap,D::TotalWords,D::FirstFldBit);
   static int j=printf("PackUnpField: BitStart=%d,swp_r(BitStart)=%d,BitEnd=%d,WordEnd=%d,WordStart=%d,Words=%d\n",
    P::BitStart,P::swp_r(P::BitStart),P::BitEnd,P::WordEnd,P::WordStart,P::Words);

   static int i1=printf("SetBitRange(swp_w(BitStart)=%d,Cut1::MyLength=%d)\n",P::swp_w(P::BitStart),Cut1::MyLength);
   static int i2=printf("SetBitRange(swp_w(Cut1::NextStart)=%d,Cut1::NextLength=%d)\n",P::swp_w(Cut1::NextStart),Cut1::NextLength);
   static int i3=printf("SetBitRange(swp_w(Cut2::NextStart)=%d,Cut2::NextLength=%d)\n",P::swp_w(Cut2::NextStart),Cut2::NextLength);

   return 1;
  }
#endif

 static void pack(SceMiMessageData& dst, uint64_t data)
  {
   PRN_INST

   dst.SetBitRange(P::swp_w(P::BitStart),Cut1::MyLength,SceMiU32(data));
   dst.SetBitRange(P::swp_w(Cut1::NextStart),Cut1::NextLength,SceMiU32(data>>L1));
   dst.SetBitRange(P::swp_w(Cut2::NextStart),Cut2::NextLength,SceMiU32(data>>L2));
  }

 static uint64_t unpack(const SceMiMessageData& src)
  {
   PRN_INST

   return           src.GetBitRange(P::swp_r(P::BitStart),Cut1::MyLength) |
          (uint64_t(src.GetBitRange(P::swp_r(Cut1::NextStart),Cut1::NextLength))<<L1) |
          (uint64_t(src.GetBitRange(P::swp_r(Cut2::NextStart),Cut2::NextLength))<<L2);
  }
};

template<size_t FldLength, size_t FldStart, size_t PktLength>
struct FM {
 typedef FieldManipulator<FldLength,FldStart,PktLength, 
          PackUnpField<FldLength,FldStart,PktLength>::Words> body;
};

}}


// Extract data from 'vico_data' SceMiMessageData buffer. Returns extracted data
#define VICO_RRR_UNP(Length,StartBit,TotalLength) ViCo::RRR::FM<Length,StartBit,TotalLength>::body::unpack(vico_data)

// Put data in 'vico_data' SceMiMessageData buffer. Data to put - SrcVar arg
#define VICO_RRR_PCK(SrcVar,Length,StartBit,TotalLength) ViCo::RRR::FM<Length,StartBit,TotalLength>::body::pack(vico_data,SrcVar)

#endif
