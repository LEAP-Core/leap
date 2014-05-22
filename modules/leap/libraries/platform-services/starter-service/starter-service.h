#ifndef _STARTER_
#define _STARTER_

#include <stdio.h>
#include <sys/time.h>
#include <pthread.h>

#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/rrr.h"
#include "awb/provides/starter_service.h"
#include "awb/provides/model.h"
#include "awb/rrr/client_stub_STARTER_SERVICE.h"


// this module provides both client and server functionalities


//
// STARTER_SERVER_CLASS --
//
//

typedef class STARTER_SERVICE_SERVER_CLASS* STARTER_SERVICE_SERVER;

class STARTER_SERVICE_SERVER_CLASS: public RRR_SERVER_CLASS,
                            public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static STARTER_SERVICE_SERVER_CLASS instance;

    // stubs
    STARTER_SERVICE_CLIENT_STUB clientStub;
    RRR_SERVER_STUB     serverStub;

    // Cycle when statistics were last scanned
    UINT64 lastStatsScanCycle;
    // Mask of bits to monitor for triggering statistics scan out from HW
    UINT64 statsScanMask;

    UINT8 exitCode;

  public:
    STARTER_SERVICE_SERVER_CLASS();
    ~STARTER_SERVICE_SERVER_CLASS();

    // static methods
    static STARTER_SERVICE_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();

    //
    // RRR server methods
    //
    void End(UINT8 success);
    void Heartbeat(UINT64 fpga_cycles);

    // client methods
    void Start();
    UINT8 WaitForHardware();
    void StatusMsg();
};


// server stub
#include "awb/rrr/server_stub_STARTER_SERVICE.h"

// our STARTER_SERVICE_SERVER class is itself the main STARTER class
typedef STARTER_SERVICE_SERVER_CLASS STARTER_SERVICE_CLASS;

#endif
