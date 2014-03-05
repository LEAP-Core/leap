
//
// @file dynamic-parameters.h
// @brief Pass dynamic parameters to the hardware side
//
// @author Michael Adler
//

#ifndef _PARAMS_CONTROLLER_
#define _PARAMS_CONTROLLER_

#include <stdio.h>

#include "awb/provides/rrr.h"
#include "awb/rrr/client_stub_PARAMS.h"
#include "awb/provides/low_level_platform_interface.h"

typedef class DYNAMIC_PARAMS_SERVICE_CLASS* DYNAMIC_PARAMS_SERVICE;

class DYNAMIC_PARAMS_SERVICE_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:
 
    // stub
    PARAMS_CLIENT_STUB clientStub;

  public:
    DYNAMIC_PARAMS_SERVICE_CLASS();
    ~DYNAMIC_PARAMS_SERVICE_CLASS();

    // Send dynamic parameters to hardware
    void SendAllParams();

    // required RRR service methods
    void Init(PLATFORMS_MODULE);

};


#endif
