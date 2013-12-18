#ifndef __PLATFORMS_MODULE_H__
#define __PLATFORMS_MODULE_H__

#include <string>
#include <list>

#include "tbb/atomic.h"
#include "asim/syntax.h"

using namespace std;

// =========== Platforms hardware/software module =========
typedef class PLATFORMS_MODULE_CLASS* PLATFORMS_MODULE;

// There can be only one manager class. 
class PLATFORMS_MODULE_MANAGER_CLASS
{
    protected:
        list<PLATFORMS_MODULE> *modules;   // parent module
        // this can be non-atomic. It will only be used at static construction time, 
        // which is single threaded.     
        static UINT32           init;   
        class tbb::atomic<UINT32> *uninitAtomic;
     
        // Actually do the uninit.
        void UninitHelper();

    public:
        PLATFORMS_MODULE_MANAGER_CLASS();
        ~PLATFORMS_MODULE_MANAGER_CLASS();
        void AddModule(PLATFORMS_MODULE module);
        void CallbackExit(int retVal);
        void Init();
        void Uninit();
};

class PLATFORMS_MODULE_CLASS
{
    protected:
        static PLATFORMS_MODULE_MANAGER_CLASS *manager;
        static UINT32                         init;   
        PLATFORMS_MODULE parent;
        string       name;     // descriptive name
        
	static void InitPlatformsManager();

    public:
        // constructor - destructor
        PLATFORMS_MODULE_CLASS();
        PLATFORMS_MODULE_CLASS(PLATFORMS_MODULE);
        PLATFORMS_MODULE_CLASS(PLATFORMS_MODULE, string);
        ~PLATFORMS_MODULE_CLASS();

        // Call to initialize all platforms modules
	static void InitPlatforms();

        // common methods
        void AddChild(PLATFORMS_MODULE);

        // common virtual methods
        virtual void Init();
        virtual void Init(PLATFORMS_MODULE parent);
        virtual void Uninit();
        virtual void CallbackExit(int);
};

#endif
