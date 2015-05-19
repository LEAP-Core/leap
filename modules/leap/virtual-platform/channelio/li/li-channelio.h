//
// Copyright (C) 2013 Intel Corporation
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

#ifndef __LI_CHANNELIO__
#define __LI_CHANNELIO__

#include <queue>
#include <vector>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <pthread.h>

#include "platforms-module.h"
#include "awb/provides/umf.h"
#include "awb/provides/physical_platform.h"
#include "awb/provides/physical_platform_utils.h"
#include "awb/provides/multifpga_switch.h"
#include "awb/provides/li_base_types.h"
#include "awb/provides/multifpga_switch.h"
#include "tbb/concurrent_queue.h"
#include "tbb/compat/condition_variable"
#include "tbb/atomic.h"
#include "li-channelio-routethrough.h"

using namespace std;

// I may need to make these virtual...

// Is using pointers in the queue structure creating subtle bugs?  Should I pass by reference?

// The marshalled LI classes represent the client-side interface. 
template <typename T> class MARSHALLED_LI_CHANNEL_IN_CLASS: public FLOWCONTROL_LI_CHANNEL_IN_CLASS, public LI_CHANNEL_SEND_CLASS<T>
{
    ofstream debugLog;

  public:
    MARSHALLED_LI_CHANNEL_IN_CLASS(tbb::concurrent_bounded_queue<UMF_MESSAGE> *flowcontrolQInitializer,
                                   std::string nameInitializer,
                                   UMF_FACTORY factoryInitializer,  
                                   UINT64 flowcontrolChannelIDInitializer):
      FLOWCONTROL_LI_CHANNEL_IN_CLASS(&debugLog, flowcontrolQInitializer, factoryInitializer, flowcontrolChannelIDInitializer),
      LI_CHANNEL_SEND_CLASS<T>(nameInitializer)
    {
        debugLog.open(this->name + ".log");
    };

    virtual void pushUMF(UMF_MESSAGE &message);
  
};


template <typename T> class MARSHALLED_LI_CHANNEL_OUT_CLASS: public FLOWCONTROL_LI_CHANNEL_OUT_CLASS, public LI_HALF_CHANNEL_RECV_CLASS<T>
{

  private:
    UMF_FACTORY factory; // we need to take T and pack it in to a UMF_MESSAGE
    UINT64 channelID;
    UINT64 packetNumber;
    UINT64 chunkNumber;
    ofstream debugLog;

    // TODO: this doesn't really need to be a mutex. Probably we could
    // get away with building a linked list of messages. 
    std::mutex pushMutex;

  protected:
    void push(T &element); // Our send friends can touch this interface

  public:
    MARSHALLED_LI_CHANNEL_OUT_CLASS(class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQInitializer,
                                    UMF_FACTORY factoryInitializer, 
                                    std::string nameInitializer, 
                                    UINT64 channelIDInitializer):

      FLOWCONTROL_LI_CHANNEL_OUT_CLASS(&debugLog, outputQInitializer),
      LI_HALF_CHANNEL_RECV_CLASS<T>(nameInitializer)
    { 
        factory = factoryInitializer;
        channelID = channelIDInitializer;        
        debugLog.open(this->name + ".log");
    };


    bool full() {flowcontrolCredits == 0;}; // not really accurate...
    
};

// A base class for matching send and receive channels.  Send and
// receive channels call into this message at construction time, and
// are paired when a match is found.

typedef class CHANNELIO_BASE_CLASS* CHANNELIO_BASE;
class CHANNELIO_BASE_CLASS:  public PLATFORMS_MODULE_CLASS
{

  protected:
        
    map<string, vector<LI_CHANNEL_IN>* > incomingChannels;
    map<string, vector<LI_CHANNEL_OUT>* > outgoingChannels;
    vector<pthread_t*> incomingHandlers;

    PHYSICAL_DEVICES physicalDevices;    

    static void * handleIncomingMessages(void *argv)
    {
        void ** args = (void**) argv;
        PHYSICAL_CHANNEL_CLASS *physicalChannel = (PHYSICAL_CHANNEL_CLASS*) args[0];
        vector<LI_CHANNEL_IN> *inChannels = (vector<LI_CHANNEL_IN>*) args[1];

        while (1) 
        {
            UMF_MESSAGE msg = physicalChannel->Read();
            inChannels->at(msg->GetServiceID())->pushUMF(msg);
        }
    }

    // This code is currently unused in generated routers
    static void * handleOutgoingMessages(void *argv)
    {
        void ** args = (void**) argv;
        tbb::concurrent_bounded_queue<UMF_MESSAGE> *mergedMessages = (tbb::concurrent_bounded_queue<UMF_MESSAGE>*) args[1];
        PHYSICAL_CHANNEL_CLASS *physicalChannel = (PHYSICAL_CHANNEL_CLASS*) args[0];
        while(1) 
        {
            UMF_MESSAGE msg;
            mergedMessages->pop(msg);
            physicalChannel->Write(msg);
        }
    }

  public:

    CHANNELIO_BASE_CLASS(PLATFORMS_MODULE parent, PHYSICAL_DEVICES physicalDevicesInit);
    ~CHANNELIO_BASE_CLASS();
 
    void Uninit();
    bool UninitComplete();


};

// Unfortunately we need all of these definitions in the router code. 
#include "software_routing.h"

#endif
