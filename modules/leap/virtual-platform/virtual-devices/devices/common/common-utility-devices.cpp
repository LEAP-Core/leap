#include "awb/rrr/service_ids.h"

#include "awb/provides/common_utility_devices.h"

using namespace std;

// constructor
COMMON_UTILITY_DEVICES_CLASS::COMMON_UTILITY_DEVICES_CLASS() :
    dynamicParamsService(new DYNAMIC_PARAMS_SERVICE_CLASS())
{
}

// destructor
COMMON_UTILITY_DEVICES_CLASS::~COMMON_UTILITY_DEVICES_CLASS()
{
}

// init
void
COMMON_UTILITY_DEVICES_CLASS::Init()
{
    // Tell the dynamic parameters IO service to send all
    // parameters to the hardware.
    
    dynamicParamsService->SendAllParams();
}
