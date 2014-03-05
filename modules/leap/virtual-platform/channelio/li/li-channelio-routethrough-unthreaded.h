//
// Copyright (C) 2014 Intel Corporation
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

#ifndef __LI_CHANNELIO_ROUTETHROUGH__
#define __LI_CHANNELIO_ROUTETHROUGH__

#include <queue>
#include <vector>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <pthread.h>

#include "platforms-module.h"
#include "awb/provides/umf.h"
#include "awb/provides/physical_platform.h"
#include "awb/provides/multifpga_switch.h"
#include "awb/provides/li_base_types.h"
#include "awb/provides/multifpga_switch.h"
#include "tbb/concurrent_queue.h"
#include "tbb/compat/condition_variable"
#include "tbb/atomic.h"

using namespace std;

/*****

Software route-through

These classes handle software route-throughs.  Software does not
attempt to decode the packet, only translate the header and push the
packet on. Because we want to provide backpressure across platforms,
the two ROUTE_THROUGH modules below must collaborate on flow control.

In the current implementation, the outgoing route-through is threaded.
This probably degrades performance, but it was easier to code up.
Incoming and outgoing routethrough share information about flow
control, and both will get updated when the outgoing route-through
receives credit from the consumer of the message. 

*****/

// Handles inbound route-through packets
typedef class ROUTE_THROUGH_LI_CHANNEL_IN_CLASS* ROUTE_THROUGH_LI_CHANNEL_IN;
class ROUTE_THROUGH_LI_CHANNEL_IN_CLASS: public FLOWCONTROL_LI_CHANNEL_IN_CLASS, public LI_CHANNEL_SEND_CLASS<UMF_MESSAGE>
{

  friend class ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS;

  private:

    pthread_t       forwardingThread; 
    queue<UMF_MESSAGE> msgBuffer;
    class std::mutex msgBufferMutex; // protects pops from message buffer
    
    static void * routeMessage(void *argv) 
    {
        UMF_MESSAGE inMesg;
        ROUTE_THROUGH_LI_CHANNEL_IN router = (ROUTE_THROUGH_LI_CHANNEL_IN) argv;

    }



  public:
    ROUTE_THROUGH_LI_CHANNEL_IN_CLASS(tbb::concurrent_bounded_queue<UMF_MESSAGE> *flowcontrolQInitializer,
                                   std::string nameInitializer,
				   UMF_FACTORY factoryInitializer,  
                                   UINT64 flowcontrolChannelIDInitializer):
      FLOWCONTROL_LI_CHANNEL_IN_CLASS(flowcontrolQInitializer, factoryInitializer, flowcontrolChannelIDInitializer),
      LI_CHANNEL_SEND_CLASS<UMF_MESSAGE>(nameInitializer),
      msgBuffer()
    {
	if (pthread_create(&forwardingThread,
			   NULL,
			   routeMessage,
			   this))
	  {
	    perror("pthread_create, forwardingThread:");
	    exit(1);
	  }
    };

    void pushUMF(UMF_MESSAGE &message);
    void clearMsgQ(); 

};


// Handles outbound route-through packets
typedef class ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS* ROUTE_THROUGH_LI_CHANNEL_OUT;
class ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS: public FLOWCONTROL_LI_CHANNEL_OUT_CLASS, public LI_HALF_CHANNEL_RECV_CLASS<UMF_MESSAGE>
{

  friend class ROUTE_THROUGH_LI_CHANNEL_IN_CLASS;

  private:
    UMF_FACTORY factory; // It isn't clear that the route through needs to make use of the UMF factory.
    UINT64 channelID;

  protected:

    void push(UMF_MESSAGE &element); // Our send friends can touch this interface
    bool tryPush(UMF_MESSAGE &element); // Our send friends can touch this interface

    void freeCredits(UINT32 credits); // override baseclass free credits

  public:
    ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS(class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQInitializer,
                                       UMF_FACTORY factoryInitializer, 
                                       std::string nameInitializer, 
                                       UINT64 channelIDInitializer):

      FLOWCONTROL_LI_CHANNEL_OUT_CLASS(outputQInitializer),
      LI_HALF_CHANNEL_RECV_CLASS<UMF_MESSAGE>(nameInitializer)
    { 
        factory = factoryInitializer;
        channelID = channelIDInitializer;
    };

    // We need to override the underlying 

    bool full() {flowcontrolCredits == 0;}; // not really accurate...
    
};


#endif
