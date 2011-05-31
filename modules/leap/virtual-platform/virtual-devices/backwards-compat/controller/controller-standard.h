#ifndef __CONTROLLER__
#define __CONTROLLER__

#include <stdio.h>
#include <pthread.h>

#include "platforms-module.h"
#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/central_controllers.h"
#include "awb/provides/software_system.h"

// controller
typedef class CONTROLLER_CLASS* CONTROLLER;
class CONTROLLER_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:
    // links to LLPI and SYSTEM
    LLPI   llpi;
    SYSTEM system;

    // central controllers
    CENTRAL_CONTROLLERS_CLASS centralControllers;

  public:
    CONTROLLER_CLASS(LLPI, SYSTEM);
    ~CONTROLLER_CLASS();
    
    void Main();
    void Uninit();
    void Cleanup();
    
    // static methods
    static CONTROLLER GetInstance();
};

// globally visible monitor threadID
extern pthread_t monitorThreadID;

#endif
