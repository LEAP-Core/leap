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
packet on. Incoming flow-control is simple for now: we simply
deallocate the credit as soon as we get the message. This implements
an infinitely sized buffer.  To prevent pathological cases and improve
 fairness, this buffer should eventually be finite in size.  Outgoing
flows require special handling with respect to flowcontrol.  Normally,
if credit is available, we send directly on enqueue. However, if not
enough credit is availabel, this will deadlock if we block for credit.
In this case, we will buffer the incoming packets and when flowcontrol
updates are obtained, the flowcontrol update thread will send packets
on our behalf, as many as are possible.  

*****/

// Handles inbound route-through packets

class ROUTE_THROUGH_LI_CHANNEL_IN_CLASS: public FLOWCONTROL_LI_CHANNEL_IN_CLASS, public LI_CHANNEL_SEND_CLASS<UMF_MESSAGE>
{
  public:
    ROUTE_THROUGH_LI_CHANNEL_IN_CLASS(tbb::concurrent_bounded_queue<UMF_MESSAGE> *flowcontrolQInitializer,
                                   std::string nameInitializer,
				   UMF_FACTORY factoryInitializer,  
                                   UINT64 flowcontrolChannelIDInitializer):
      FLOWCONTROL_LI_CHANNEL_IN_CLASS(flowcontrolQInitializer, factoryInitializer, flowcontrolChannelIDInitializer),
      LI_CHANNEL_SEND_CLASS<UMF_MESSAGE>(nameInitializer)
    {
    };

    void pushUMF(UMF_MESSAGE &message);

};


// Handles outbound route-through packets

class ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS: public FLOWCONTROL_LI_CHANNEL_OUT_CLASS, public LI_HALF_CHANNEL_RECV_CLASS<UMF_MESSAGE>
{

  private:
    UMF_FACTORY factory; // we need to take T and pack it in to a UMF_MESSAGE
    UINT64 channelID;

  protected:
    void push(UMF_MESSAGE &element); // Our send friends can touch this interface

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


    bool full() {flowcontrolCredits == 0;}; // not really accurate...
    
};


#endif
