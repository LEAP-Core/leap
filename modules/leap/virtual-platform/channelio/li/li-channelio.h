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
    void push(T &element); // Our send friednds can touch this interface

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

// Not sure I even need this...
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
