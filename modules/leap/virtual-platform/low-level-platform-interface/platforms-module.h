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
        list<PLATFORMS_MODULE>  *modules;
   
        // this variable can be non-atomic. It will only be used at static construction time, 
        // which is single threaded.     
        static bool             init;   

        class tbb::atomic<bool> *uninitAtomic;
     
        // Actually do the uninit.
        void UninitHelper();

    public:
        PLATFORMS_MODULE_MANAGER_CLASS();
        ~PLATFORMS_MODULE_MANAGER_CLASS();
        void AddModule(PLATFORMS_MODULE module);
        void CallbackExit(int retVal);
        void Init();
        void Uninit();
        bool UninitInProgress();
};

class PLATFORMS_MODULE_CLASS
{
    protected:
        static PLATFORMS_MODULE_MANAGER_CLASS *manager;
        static UINT32                         init;   
        PLATFORMS_MODULE parent;
        string       name;     // descriptive name
        
	static void InitPlatformsManager();
        bool UninitInProgress();

    public:
        // constructor - destructor
        PLATFORMS_MODULE_CLASS();
        PLATFORMS_MODULE_CLASS(PLATFORMS_MODULE);
        PLATFORMS_MODULE_CLASS(PLATFORMS_MODULE, string);
        ~PLATFORMS_MODULE_CLASS();

        // Call to initialize all platforms modules
	static void InitPlatforms();
	static void UninitPlatforms();

        // common methods
        void AddChild(PLATFORMS_MODULE);

        // common virtual methods
        virtual void Init();
        virtual void Init(PLATFORMS_MODULE parent);

        // Unlike init, which can complete asychronously, we need to
        // be sure that uninit operations have completed before
        // exiting the program. Uninit routines may be asynchronous,
        // so we need a means of testing that they have completed. 

        virtual void Uninit();
        virtual bool UninitComplete() {return true;}; 
        virtual void CallbackExit(int);

};

#endif
