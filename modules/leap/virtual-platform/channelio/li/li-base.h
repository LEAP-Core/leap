//
// Copyright (c) 2013, Intel Corporation
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

#ifndef __LI_BASE_TYPES__
#define __LI_BASE_TYPES__

#include <queue>
#include <vector>
#include <map>
#include <string>
#include <mutex>

#include "platforms-module.h"
#include "awb/provides/umf.h"
#include "awb/provides/physical_channel.h"
#include "tbb/concurrent_queue.h"
#include "tbb/compat/condition_variable"
#include "tbb/atomic.h"

using namespace std;

class LI_HALF_CHANNEL_CLASS;

///////
//
//  li-base.h -- 
//    This file contains the definitions of several base classes for named channels.
//    These base classes manage naming and connecting LI channels.  Child classes will 
//    provide other functionalities like marshalling, flowcontrol, etc.  
//

// The following serves as a reminder that I will eventually have to implement chains
// Currently, there is no support for chains to software. 
// class LI_CHANNEL_CHAIN_CLASS;

typedef class LI_HALF_CHANNEL_CLASS* LI_HALF_CHANNEL;

// 
// LI_CHANNEL_MATCHER_CLASS --
//   A class for matching LI channels by name. LI channels are placed into two maps. 
//   As channels are added, the matcher class ties channels with the same name 
//   together, using the private LI_HALF_CHANNEL_CLASS interface. 
//

// This is a private channel matching class
class LI_CHANNEL_MATCHER_CLASS
{
  template <typename U> friend class LI_HALF_CHANNEL_RECV_CLASS;
  template <typename V> friend class LI_CHANNEL_SEND_CLASS;

  protected:
    // Programmers may declare LI channels in static 
    // instances.  Thus, we must initialize our members when our class functions are 
    // called. 

    std::map<string, LI_HALF_CHANNEL> *sendMap;
    std::map<string, LI_HALF_CHANNEL> *recvMap;
    class std::mutex *matcherMutex;
    static UINT32 initCounter;
    static LI_CHANNEL_MATCHER_CLASS liMatcher;

    // Set up pointers.  This enables programmers to invoke the matcher even from 
    // static instances. 
    void initialize();

  public:
    LI_CHANNEL_MATCHER_CLASS();
    ~LI_CHANNEL_MATCHER_CLASS() {};

    // No public methods for now, though we may eventually want to assert that we have no dangling connections
    LI_HALF_CHANNEL registerSend(LI_HALF_CHANNEL send);
    LI_HALF_CHANNEL registerRecv(LI_HALF_CHANNEL recv);

};

// LI_HALF_CHANNEL_CLASS
//   A base class for named channels. This is a private interface for LI_MATCHER.
//   which uses the interface to tie together latency insensitive channels.
//
class LI_HALF_CHANNEL_CLASS 
{
 
  friend class LI_CHANNEL_MATCHER_CLASS;

  protected:  
    std::string name;
    std::string type; // Needed for type safety

  public:
    LI_HALF_CHANNEL_CLASS(std::string nameInit, std::string typeInit);
    ~LI_HALF_CHANNEL_CLASS() {};
 
    const string& GetName() { return name; };
    const string& GetType() { return type; };
  
};

template <typename T> class LI_CHANNEL_SEND_CLASS;

// LI_HALF_CHANNEL_RECV_CLASS --
//   Virtual base class allowing super classes to pick implementations for push. 
//   This is needed to allow for channels that must directly push data into another 
//   channel, that is route-throughs. 
//
template <typename T> class LI_HALF_CHANNEL_RECV_CLASS: public LI_HALF_CHANNEL_CLASS
{
    template <typename U> friend class LI_CHANNEL_SEND_CLASS; // Allow Send to access our push

  protected:
    class LI_CHANNEL_SEND_CLASS<T> *channelPartner; 

  public:
    virtual void push(T &message ) = 0;
    void SetChannelPartner(class LI_CHANNEL_SEND_CLASS<T> *channelPartnerInit) { channelPartner = channelPartnerInit; };
    LI_HALF_CHANNEL_RECV_CLASS(string nameInitializer);	   
   ~LI_HALF_CHANNEL_RECV_CLASS() {};

};

// LI_CHANNEL_SEND_CLASS --                                                                                                                             
//   This is the send side of an LI channel.  It simply invokes the push method of its partner RECV
//   channel, which performs some action, for example sending a message to a physical device.                                                       
//   The send class maintains a pointer to the partner channel, which is elaborated by the 
//   channel matcher. 
// 
template <typename T> class LI_CHANNEL_SEND_CLASS: public LI_HALF_CHANNEL_CLASS
{
    template <typename U> friend class LI_HALF_CHANNEL_RECV_CLASS; // Allow Recv to register with us
  
  protected:  
    class LI_HALF_CHANNEL_RECV_CLASS<T> *channelPartner; 

    void SetChannelPartner(class LI_HALF_CHANNEL_RECV_CLASS<T> *channelPartnerInit) { channelPartner = channelPartnerInit; };

  public:
    LI_CHANNEL_SEND_CLASS(string nameInitializer);
    ~LI_CHANNEL_SEND_CLASS() {};

    void push(T &message ) {assert(channelPartner); channelPartner->push(message);}; 

};



// LI_CHANNEL_RECV_CLASS --
//   Class for non-route through communications. It is a simple wrapper around a lock-free
//   queue. External users pop from the queue.  The internal push interface is restricted
//   to the channel partner. 
//
template <typename T> class LI_CHANNEL_RECV_CLASS: LI_HALF_CHANNEL_RECV_CLASS<T>
{
    template <typename U> friend class LI_CHANNEL_SEND_CLASS; // Allow Recv to register with us  

  protected:  

    class tbb::concurrent_bounded_queue<T> dataQ; // We need flow control messages. 

  public:
    virtual void push(T &message ) {dataQ.push(message);}; 
    LI_CHANNEL_RECV_CLASS(string nameInitializer);
    ~LI_CHANNEL_RECV_CLASS() {};

    void pop(T &message ) { dataQ.pop(message); }; 

};


// These classes represent the physical LI channel implementation.
// They derive from the above send and receive classes to pick up the channel matching functionality. 

// LI_CHANNEL_OUT_CLASS --
//  The base outbound channel for the channelio side interface. This channel will mate with 
//  user-side channels forming a connection to a physical I/O device. Some of these channels, 
//  specifically the channels carrying flow control, do not themselves need flow control.  
//
typedef class LI_CHANNEL_OUT_CLASS* LI_CHANNEL_OUT;
class LI_CHANNEL_OUT_CLASS
{
  
  protected:  
    class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQ; // We need flow control messages. 
    bool needsFlowcontrol;

  public:
     LI_CHANNEL_OUT_CLASS(class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQInitializer): 
       outputQ(outputQInitializer) 
     {
         needsFlowcontrol = true;
     };

    ~LI_CHANNEL_OUT_CLASS() {};
    bool doesNeedFlowcontrol() { return needsFlowcontrol; }

};

// LI_CHANNEL_IN_CLASS --
//  The base inbound channel class for the channelio side interface. This channel will mate with 
//  user-side channels forming a connection to a physical I/O device.  
//
typedef class LI_CHANNEL_IN_CLASS* LI_CHANNEL_IN;
class LI_CHANNEL_IN_CLASS
{

  public:
     LI_CHANNEL_IN_CLASS() {};

    ~LI_CHANNEL_IN_CLASS() {};

    // This is how clients will convert their data from UMF
    // to their type. 
    virtual void pushUMF(UMF_MESSAGE &message) = 0; 

};

/////
//
//  Constructors for templatized classes.  These must appear in the same file as the template class
//  definitions. 
//
/////

// LI_HALF_CHANNEL_RECV_CLASS --
//  Constructor for LI_HALF_CHANNEL_RECV_CLASS.  Looks for a partner in the channel matcher.
//  If a partner is found, they will be mated. Otherwise, when the partner registers they will
//  be mated. 
template<typename T> LI_HALF_CHANNEL_RECV_CLASS<T>::LI_HALF_CHANNEL_RECV_CLASS(string nameInitializer):
    LI_HALF_CHANNEL_CLASS(nameInitializer, typeid(T).name()) 
{

    LI_CHANNEL_SEND_CLASS<T> *send = (LI_CHANNEL_SEND_CLASS<T>*) LI_CHANNEL_MATCHER_CLASS::liMatcher.registerRecv(this);

    if(send != NULL)
    {
        send->SetChannelPartner(this);
        SetChannelPartner(send);
    }
} 


// LI_HALF_CHANNEL_SEND_CLASS --
//  Constructor for LI_HALF_CHANNEL_SEND_CLASS.  Looks for a partner in the channel matcher.
//  If a partner is found, they will be mated. Otherwise, when the partner registers they will
//  be mated. 
template<typename T> LI_CHANNEL_SEND_CLASS<T>::LI_CHANNEL_SEND_CLASS(std::string nameInitializer):
  LI_HALF_CHANNEL_CLASS(nameInitializer, typeid(T).name())
{
    LI_HALF_CHANNEL_RECV_CLASS<T> *recv = (LI_HALF_CHANNEL_RECV_CLASS<T>*) LI_CHANNEL_MATCHER_CLASS::liMatcher.registerSend(this);

    if(recv != NULL)
    {
        recv->SetChannelPartner(this);
        SetChannelPartner(recv);
    }

}

// LI_CHANNEL_RECV_CLASS --
//  Constructor for LI_CHANNEL_RECV_CLASS.  Calls underlying constructor. 
//  Recv must own queue implementation as send has actionaable context.
template<typename T> LI_CHANNEL_RECV_CLASS<T>::LI_CHANNEL_RECV_CLASS(std::string nameInitializer):
  dataQ(), 
  LI_HALF_CHANNEL_RECV_CLASS<T>(nameInitializer)
{


}
 
#endif
