#include <cstdlib>
#include <assert.h>
#include <iostream>

#include "platforms-module.h"

using namespace std;

UINT32 PLATFORMS_MODULE_MANAGER_CLASS::init;
   
PLATFORMS_MODULE_MANAGER_CLASS::PLATFORMS_MODULE_MANAGER_CLASS()
{ 
    if(!init) 
    {
        init = 1;
        modules = new list<PLATFORMS_MODULE>();
        uninitAtomic = new tbb::atomic<UINT32>();
        *uninitAtomic = 0;
    }
}

PLATFORMS_MODULE_MANAGER_CLASS::~PLATFORMS_MODULE_MANAGER_CLASS()
{

}


void PLATFORMS_MODULE_MANAGER_CLASS::AddModule(PLATFORMS_MODULE module)
{
    assert(init);
    assert(modules);
    modules->push_back(module);
}

// Sometimes modules encounter error conditions as a result of 
// exit()'s teardown of various modules.  
void PLATFORMS_MODULE_MANAGER_CLASS::CallbackExit(int exitCode)
{
    UINT32 uninit = (*uninitAtomic).fetch_and_store(1);
    if(!uninit)
    {
        UninitHelper();
        exit(exitCode);
    }
}

void PLATFORMS_MODULE_MANAGER_CLASS::Init()
{

    for(std::list<PLATFORMS_MODULE>::iterator modules_iter = (*modules).begin(); 
        modules_iter != (*modules).end(); modules_iter++)
    {
        (*modules_iter)->Init();
    }

}

void PLATFORMS_MODULE_MANAGER_CLASS::UninitHelper()
{
    
    for(std::list<PLATFORMS_MODULE>::reverse_iterator modules_iter = (*modules).rbegin(); 
        modules_iter != (*modules).rend(); modules_iter++)
    {
        (*modules_iter)->Uninit();
    }
}


void PLATFORMS_MODULE_MANAGER_CLASS::Uninit()
{

    UINT32 uninit = (*uninitAtomic).fetch_and_store(1);
    if(!uninit)
    {
        UninitHelper();
    }

}

PLATFORMS_MODULE_MANAGER_CLASS *PLATFORMS_MODULE_CLASS::manager;
UINT32 PLATFORMS_MODULE_CLASS::init;

// Declare a static platform module to ensure static construction 
// time intialization of platforms module manager. This enables us 
// get away with non-thread-safe initialization code, since there will be 
// no threads at this point.
 
static PLATFORMS_MODULE_CLASS dummyPlatform;

// constructors
PLATFORMS_MODULE_CLASS::PLATFORMS_MODULE_CLASS()
{ 
    InitPlatformsManager();
    manager->AddModule(this);
}

PLATFORMS_MODULE_CLASS::PLATFORMS_MODULE_CLASS(
    PLATFORMS_MODULE p)
{
    InitPlatformsManager();
    manager->AddModule(this);
}

PLATFORMS_MODULE_CLASS::PLATFORMS_MODULE_CLASS(
    PLATFORMS_MODULE p,
    string n):
    name(n)
{
    InitPlatformsManager();
    manager->AddModule(this);
}

PLATFORMS_MODULE_CLASS::~PLATFORMS_MODULE_CLASS()
{
}

// add child
void
PLATFORMS_MODULE_CLASS::AddChild(
    PLATFORMS_MODULE child)
{

}

// sets up static values. 
void 
PLATFORMS_MODULE_CLASS::InitPlatformsManager()
{
    if(!init)
    {
        init = 1;
        manager = new PLATFORMS_MODULE_MANAGER_CLASS();
    }
}

// init
void 
PLATFORMS_MODULE_CLASS::InitPlatforms()
{
    InitPlatformsManager();
    manager->Init();
}

// init
void
PLATFORMS_MODULE_CLASS::Init()
{
   
}

// init
void
PLATFORMS_MODULE_CLASS::Init(PLATFORMS_MODULE p)
{

}

// uninit
void
PLATFORMS_MODULE_CLASS::Uninit()
{

}

// callback-exit
void
PLATFORMS_MODULE_CLASS::CallbackExit(
    int exitcode)
{
  InitPlatformsManager();
  manager->CallbackExit(exitcode);
}
