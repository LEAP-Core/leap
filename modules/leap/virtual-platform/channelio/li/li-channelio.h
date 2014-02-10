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
#include "awb/provides/multifpga_switch.h"
#include "awb/provides/li_base_types.h"
#include "awb/provides/multifpga_switch.h"
#include "tbb/concurrent_queue.h"
#include "tbb/compat/condition_variable"
#include "tbb/atomic.h"

using namespace std;

// I may need to make these virtual...

// Is using pointers in the queue structure creating subtle bugs?  Should I pass by reference?

// The marshalled LI classes represent the client-side interface. 
template <typename T> class MARSHALLED_LI_CHANNEL_IN_CLASS: public FLOWCONTROL_LI_CHANNEL_IN_CLASS, public LI_CHANNEL_SEND_CLASS<T>
{
  public:
    MARSHALLED_LI_CHANNEL_IN_CLASS(tbb::concurrent_bounded_queue<UMF_MESSAGE> *flowcontrolQInitializer,
                                   std::string nameInitializer,
				   UMF_FACTORY factoryInitializer,  
                                   UINT64 flowcontrolChannelIDInitializer):
      FLOWCONTROL_LI_CHANNEL_IN_CLASS(flowcontrolQInitializer, factoryInitializer, flowcontrolChannelIDInitializer),
      LI_CHANNEL_SEND_CLASS<T>(nameInitializer)
    {
    };

    virtual void pushUMF(UMF_MESSAGE &message);

};


template <typename T> class MARSHALLED_LI_CHANNEL_OUT_CLASS: public FLOWCONTROL_LI_CHANNEL_OUT_CLASS, public LI_HALF_CHANNEL_RECV_CLASS<T>
{

  private:
    UMF_FACTORY factory; // we need to take T and pack it in to a UMF_MESSAGE
    UINT64 channelID;

  protected:
    void push(T &element); // Our send friends can touch this interface

  public:
    MARSHALLED_LI_CHANNEL_OUT_CLASS(class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQInitializer,
                                    UMF_FACTORY factoryInitializer, 
                                    std::string nameInitializer, 
                                    UINT64 channelIDInitializer):

      FLOWCONTROL_LI_CHANNEL_OUT_CLASS(outputQInitializer),
      LI_HALF_CHANNEL_RECV_CLASS<T>(nameInitializer)
    { 
        factory = factoryInitializer;
        channelID = channelIDInitializer;
    };


    bool full() {flowcontrolCredits == 0;}; // not really accurate...
    
};



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


// A base class for matching send and receive channels.  Send and
// receive channels call into this message at construction time, and
// are paired when a match is found.

typedef class CHANNELIO_BASE_CLASS* CHANNELIO_BASE;
class CHANNELIO_BASE_CLASS:  public PLATFORMS_MODULE_CLASS
{

  protected:
        
    map<string, vector<LI_CHANNEL_IN>* > incomingChannels;
    map<string, vector<LI_CHANNEL_OUT>* > outgoingChannels;
    PHYSICAL_DEVICES physicalDevices;    

  public:

    CHANNELIO_BASE_CLASS(PLATFORMS_MODULE parent, PHYSICAL_DEVICES physicalDevicesInit);
    ~CHANNELIO_BASE_CLASS();

};

// Unfortunately we need all of these definitions in the router code. 
#include "software_routing.h"

#endif
