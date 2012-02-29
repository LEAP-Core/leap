//
// @file common-utility-devices.h
// @brief Instantiate useful utility devices.
//
// @author Michael Adler
//

#include <stdio.h>

#include "awb/provides/dynamic_parameters_service.h"

typedef class COMMON_UTILITY_DEVICES_CLASS* COMMON_UTILITY_DEVICES;

class COMMON_UTILITY_DEVICES_CLASS
{
  private:
 
    // The parameter controller is a pure client
    // so we must instantiate it.
    DYNAMIC_PARAMS_SERVICE dynamicParamsService;

  public:
    COMMON_UTILITY_DEVICES_CLASS();
    ~COMMON_UTILITY_DEVICES_CLASS();

    void Init();
};

