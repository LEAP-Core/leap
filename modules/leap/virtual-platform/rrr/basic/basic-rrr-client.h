#ifndef __BASIC_RRR_CLIENT__
#define __BASIC_RRR_CLIENT__

#include <queue>
#include <pthread.h>

#include "awb/provides/channelio.h"

using namespace std;

// ============== RRR client stub base class =================

typedef class RRR_CLIENT_STUB_CLASS* RRR_CLIENT_STUB;
class RRR_CLIENT_STUB_CLASS
{
  protected:
    UMF_MESSAGE MakeRequest(UMF_MESSAGE);
    void MakeRequestNoResponse(UMF_MESSAGE);

  public:
    RRR_CLIENT_STUB_CLASS(const char *serviceName, const UINT64 serviceID): ServiceName(serviceName), ServiceID(serviceID) {};
    const std::string ServiceName;
    const UINT64 ServiceID;
};


typedef class RRR_CLIENT_CLASS* RRR_CLIENT;
class RRR_CLIENT_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:

    // link to channelio
    CHANNELIO   channelio;

    // system thread response buffer
    queue<UMF_MESSAGE> systemThreadResponseBuffer;

    // multi-thread support
    pthread_mutex_t bufferLock;     // response buffer lock
    pthread_cond_t  bufferCond;     // response buffer condition variable
    pthread_t monitorThreadID;      // thread ID of the service thread
    int initialized;                // are we ready to start polling?
    
  public:

    RRR_CLIENT_CLASS(PLATFORMS_MODULE, CHANNELIO);
    ~RRR_CLIENT_CLASS();

    static void RegisterClient(int serviceid, RRR_CLIENT_STUB client_stub);
    
    UMF_MESSAGE MakeRequest(UMF_MESSAGE);
    void MakeRequestNoResponse(UMF_MESSAGE);
    
    void SetMonitorThreadID(pthread_t mon);

    void Poll();
};

// globally-visible link
extern RRR_CLIENT RRRClient;

#endif
