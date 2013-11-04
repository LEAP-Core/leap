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
template <typename T> class MARSHALLED_LI_CHANNEL_IN_CLASS: public FLOWCONTROL_LI_CHANNEL_IN_CLASS
{
  public:
    MARSHALLED_LI_CHANNEL_IN_CLASS(tbb::concurrent_bounded_queue<UMF_MESSAGE> *flowcontrolQInitializer,
                                   const char * nameInitializer,
				   UMF_FACTORY factoryInitializer,  
                                   UINT64 flowcontrolChannelIDInitializer):
    FLOWCONTROL_LI_CHANNEL_IN_CLASS(flowcontrolQInitializer, nameInitializer, 
                                    factoryInitializer, flowcontrolChannelIDInitializer)
    {
    };

    void pop(T &element);  
    bool empty() {return inputQ.empty();};
};


template <typename T> class MARSHALLED_LI_CHANNEL_OUT_CLASS: public FLOWCONTROL_LI_CHANNEL_OUT_CLASS
{

  private:
    UMF_FACTORY factory; // we need to take T and pack it in to a UMF_MESSAGE
    UINT64 channelID;

  public:
    MARSHALLED_LI_CHANNEL_OUT_CLASS(class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQInitializer,
                                    UMF_FACTORY factoryInitializer, 
                                    const char * nameInitializer, 
                                    UINT64 channelIDInitializer):

    FLOWCONTROL_LI_CHANNEL_OUT_CLASS(nameInitializer, outputQInitializer)
    { 
        factory = factoryInitializer;
        channelID = channelIDInitializer;
    };

    void pop(T &element);
    void push(T &element); 
    bool full() {flowcontrolCredits == 0;}; // not really accurate...
    
};

// Not sure I even need this...
typedef class CHANNELIO_BASE_CLASS* CHANNELIO_BASE;
class CHANNELIO_BASE_CLASS:  public PLATFORMS_MODULE_CLASS
{

  protected:
        
    vector<vector<LI_CHANNEL_IN>*>  incomingChannels;
    vector<vector<LI_CHANNEL_OUT>*> outgoingChannels;
    PHYSICAL_DEVICES physicalDevices;    

  public:

    CHANNELIO_BASE_CLASS(PLATFORMS_MODULE parent, PHYSICAL_DEVICES physicalDevicesInit);
    ~CHANNELIO_BASE_CLASS();

    template<typename T>    
      MARSHALLED_LI_CHANNEL_IN_CLASS<T> *getChannelInByName(std::string &name)
    {

        for(std::vector<std::vector<LI_CHANNEL_IN>*>::iterator platform = incomingChannels.begin(); platform != incomingChannels.end(); ++platform) 
        {
	  for(std::vector<LI_CHANNEL_IN>::iterator channel = (*platform)->begin(); channel != (*platform)->end(); ++channel) 
            {
  	        if((*channel) == NULL)
		{
		    continue;
		}

	        if(name == (*channel)->getName()) 
                {
                    return (MARSHALLED_LI_CHANNEL_IN_CLASS<T> *) *channel;
                }
            }
        }
        // What happens if there is no match
        std::cerr << "Warning, unmatched named channel.  We'll probably die now. String name is: " << name;
    };

    template<typename T>    
      MARSHALLED_LI_CHANNEL_OUT_CLASS<T> *getChannelOutByName(std::string &name)
    {
      //cout << "looking up out channel " << name << endl;  
        for(std::vector<std::vector<LI_CHANNEL_OUT>*>::iterator platform = outgoingChannels.begin(); platform != outgoingChannels.end(); ++platform) 
        {
	  for(std::vector<LI_CHANNEL_OUT>::iterator channel = (*platform)->begin(); channel != (*platform)->end(); ++channel) 
            {
  	        if((*channel) == NULL)
		{
		    continue;
		}

	        if(name == (*channel)->getName()) 
                {
                    return (MARSHALLED_LI_CHANNEL_OUT_CLASS<T> *) *channel;
                }
            }
        }
        // What happens if there is no match
        std::cerr << "Warning, unmatched named channel.  We'll probably die now. String name is: " << name;
    };

};

// Unfortunately we need all of these definitions in the router code. 
#include "software_routing.h"

#endif
