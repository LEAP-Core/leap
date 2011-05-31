#ifndef _CENTRAL_CONTROLLERS_
#define _CENTRAL_CONTROLLERS_

#include <stdio.h>

#include "platforms-module.h"
#include "awb/provides/events_controller.h"
#include "awb/provides/stats_controller.h"
#include "awb/provides/assertions_controller.h"
#include "awb/provides/params_controller.h"


typedef class CENTRAL_CONTROLLERS_CLASS* CENTRAL_CONTROLLERS;

class CENTRAL_CONTROLLERS_CLASS: public PLATFORMS_MODULE_CLASS
{
    public:

        CENTRAL_CONTROLLERS_CLASS();
        ~CENTRAL_CONTROLLERS_CLASS();

};

#endif
