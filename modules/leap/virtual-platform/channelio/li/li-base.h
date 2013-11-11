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
// The following serves as a reminder that I will eventually have to implement chains
//class LI_CHANNEL_CHAIN_CLASS;

typedef class LI_HALF_CHANNEL_CLASS* LI_HALF_CHANNEL;

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

// This is a private interface for the LI_MATCHER.
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


// Virtual base class allowing super classes to pick implementations for push
template <typename T> class LI_HALF_CHANNEL_RECV_CLASS: public LI_HALF_CHANNEL_CLASS
{
    template <typename U> friend class LI_CHANNEL_SEND_CLASS; // Allow Send to access our push

  public:
    virtual void push(T &message ) = 0;
    LI_HALF_CHANNEL_RECV_CLASS(string nameInitializer);	   
   ~LI_HALF_CHANNEL_RECV_CLASS() {};

};



// Send does push
template <typename T> class LI_CHANNEL_SEND_CLASS: public LI_HALF_CHANNEL_CLASS
{
    template <typename U> friend class LI_HALF_CHANNEL_RECV_CLASS; // Allow Recv to register with us
  
  protected:  
    // need to tuck the matcher class somehere.  This is a decent place to do it. 
    class LI_HALF_CHANNEL_RECV_CLASS<T> *channelPartner; 

    void SetChannelPartner(class LI_HALF_CHANNEL_RECV_CLASS<T> *channelPartnerInit) { channelPartner = channelPartnerInit; };

  public:
    LI_CHANNEL_SEND_CLASS(string nameInitializer);
    ~LI_CHANNEL_SEND_CLASS() {};

    void push(T &message ) {assert(channelPartner); channelPartner->push(message);}; 

};



// Recv does pop
template <typename T> class LI_CHANNEL_RECV_CLASS: LI_HALF_CHANNEL_RECV_CLASS<T>
{
  
  protected:  

    class tbb::concurrent_bounded_queue<T> dataQ; // We need flow control messages. 

  public:
    virtual void push(T &message ) {dataQ.push(message);}; 
    LI_CHANNEL_RECV_CLASS(string nameInitializer);
    ~LI_CHANNEL_RECV_CLASS() {};

    void pop(T &message ) { dataQ.pop(message); }; 

};


// These classes are used in the synthesized physical code.  
// They derive from sends and receives to pick up the matching functionality. 

// The base LI Channel classes represent the channelio side interface. Outbound channels need a pop,
// inbound channels need a push.
typedef class LI_CHANNEL_OUT_CLASS* LI_CHANNEL_OUT;
class LI_CHANNEL_OUT_CLASS
{
  
  protected:  
    class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQ; // We need flow control messages. 

  public:
     LI_CHANNEL_OUT_CLASS(class tbb::concurrent_bounded_queue<UMF_MESSAGE> *outputQInitializer): 
     outputQ(outputQInitializer) {};
    ~LI_CHANNEL_OUT_CLASS() {};

};

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


template<typename T> LI_HALF_CHANNEL_RECV_CLASS<T>::LI_HALF_CHANNEL_RECV_CLASS(string nameInitializer):
    LI_HALF_CHANNEL_CLASS(nameInitializer, typeid(T).name()) 
{

    LI_CHANNEL_SEND_CLASS<T> *send = (LI_CHANNEL_SEND_CLASS<T>*) LI_CHANNEL_MATCHER_CLASS::liMatcher.registerRecv(this);

    if(send != NULL)
    {
        send->SetChannelPartner(this);
    }
} 



template<typename T> LI_CHANNEL_SEND_CLASS<T>::LI_CHANNEL_SEND_CLASS(std::string nameInitializer):
  LI_HALF_CHANNEL_CLASS(nameInitializer, typeid(T).name())
{
    LI_HALF_CHANNEL_RECV_CLASS<T> *recv = (LI_HALF_CHANNEL_RECV_CLASS<T>*) LI_CHANNEL_MATCHER_CLASS::liMatcher.registerSend(this);

    if(recv != NULL)
    {
        SetChannelPartner(recv);
    }

}

// Recv must own queue implementation as send has actionaable context.
template<typename T> LI_CHANNEL_RECV_CLASS<T>::LI_CHANNEL_RECV_CLASS(std::string nameInitializer):
  dataQ(), 
  LI_HALF_CHANNEL_RECV_CLASS<T>(nameInitializer)
{


}
 
#endif
