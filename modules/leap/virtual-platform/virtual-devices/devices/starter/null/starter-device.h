#ifndef _STARTER_
#define _STARTER_

#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/model.h"


// this module provides both client and server functionalities


//
// STARTER_SERVER_CLASS --
//
//

typedef class STARTER_DEVICE_SERVER_CLASS* STARTER_DEVICE_SERVER;

class STARTER_DEVICE_SERVER_CLASS: public PLATFORMS_MODULE_CLASS

{
  public:
    STARTER_DEVICE_SERVER_CLASS();
    ~STARTER_DEVICE_SERVER_CLASS();

    // static methods
    static STARTER_DEVICE_SERVER GetInstance() { return NULL; }

    // client methods
    void Start();
    void WaitForHardware() {};
};

// our STARTER_DEVICE_SERVER class is itself the main STARTER class
typedef STARTER_DEVICE_SERVER_CLASS STARTER_DEVICE_CLASS;

#endif
