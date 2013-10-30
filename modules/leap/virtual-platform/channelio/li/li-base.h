#ifndef __LI_BASE_TYPES__
#define __LI_BASE_TYPES__

#include <queue>
#include <vector>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <pthread.h>

#include "platforms-module.h"
#include "awb/provides/umf.h"
#include "awb/provides/physical_channel.h"
#include "tbb/concurrent_queue.h"
#include "tbb/compat/condition_variable"
#include "tbb/atomic.h"

using namespace std;


// The base LI Channel classes represent the channelio side interface. Outbound channels need a pop,
// inbound channels need a push.
typedef class LI_CHANNEL_OUT_CLASS* LI_CHANNEL_OUT;
class LI_CHANNEL_OUT_CLASS
{
  protected:  
    class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQ; // We need flow control messages. 
    std::string name;

  public:
     LI_CHANNEL_OUT_CLASS(const char* nameInitializer,  
                          class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQInitializer): 
    name(nameInitializer), outputQ(outputQInitializer) {};
    ~LI_CHANNEL_OUT_CLASS() {};

    const string& getName() { return name; };
};

typedef class LI_CHANNEL_IN_CLASS* LI_CHANNEL_IN;
class LI_CHANNEL_IN_CLASS
{
  protected: 
    class tbb::concurrent_bounded_queue<UMF_MESSAGE> inputQ; 
    std::string name;

  public:
     LI_CHANNEL_IN_CLASS(const char* nameInitializer): 
         name(nameInitializer), 
	 inputQ()
     {
     };

    ~LI_CHANNEL_IN_CLASS() {};

    virtual void push(UMF_MESSAGE &message ) {inputQ.push(message);}; 
    const string& getName() { return name; };
};

 
#endif
