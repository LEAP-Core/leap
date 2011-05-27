#include <stdio.h>
#include <unistd.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <linux/unistd.h>
#include <signal.h>
#include <string.h>
#include <errno.h>

#include "asim/syntax.h"

#include "asim/dict/init.h"

#include "asim/provides/virtual_platform.h"
#include "asim/provides/low_level_platform_interface.h"
#include "asim/provides/application_env.h"
#include "asim/provides/command_switches.h"
#include "asim/provides/model.h"


RRR_SERVER_STUB_CLASS* RRR_SERVER_STUB_CLASS::root;

// inits FuncSim command-line arguments storage static member
FuncSimParams *FuncSimParams::s_instance = NULL;


// ViCo stuff
namespace ViCo { namespace RRR {


RRRBase* RRRBase::vico_rrr_root;
static pid_t vico_rrr_main_thread_id;

_syscall0(pid_t,gettid)

void RRRBase::vico_rrr_layer_init()
{
 vico_rrr_is_initialized=true;
 for(RRRBase* p=vico_rrr_root;p;p=p->vico_rrr_next)
  p->vico_rrr_do_init();
 vico_rrr_main_thread_id=gettid();
}

bool RRRBase::vico_rrr_is_main_thread() {return vico_rrr_main_thread_id==gettid();}

bool RRRBase::vico_rrr_is_initialized;

}}

static VIRTUAL_PLATFORM vp;
static APPLICATION_ENV  appEnv;

static void run_hasim()
{
    // Transfer control to Application via Environment
    int ret_val = appEnv->RunApp(0,NULL/*argc, argv*/);

    // Application's Main() exited => wait for hardware to be done.
    // The user can use a parameter to indicate the hardware never 
    // terminates (IE because it's a pure server).
    
    if (WAIT_FOR_HARDWARE && !hardwareFinished)
    {
        // We need to wait for it and it's not finished.
        // So we'll wait to receive the signal from the VP.

        // cout << "Waiting for HW..." << endl;
        pthread_mutex_lock(&hardwareStatusLock);
        pthread_cond_wait(&hardwareFinishedSignal, &hardwareStatusLock);
        pthread_mutex_unlock(&hardwareStatusLock);
    }

    // cout << "HW is done." << endl;
    // Cleanup and exit
    delete appEnv;
    delete vp;

    ViCo::Plugin::terminate(ret_val);
}


// =======================================
//           PROJECT MAIN
// =======================================


extern "C" {
MOD_ENT ViCo::Plugin::Main* InitModuleEntry(int args_total, char** args)
{
 ViCo::RRR::rrr_init();

    // Set line buffering to avoid fflush() everywhere.  stderr was probably
    // unbuffered already, but be sure.
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IOLBF, 0);

    // Initialize pthread conditions so we know
    // when the HW & SW are done.

    vp         = new VIRTUAL_PLATFORM_CLASS();
    appEnv     = new APPLICATION_ENV_CLASS(vp);

   // Set up default switches
    globalArgs = new GLOBAL_ARGS_CLASS();
   
    // Process command line arguments
    static COMMAND_SWITCH_PROCESSOR switchProc = new COMMAND_SWITCH_PROCESSOR_CLASS();
   switchProc->ProcessArgs(args_total, args);

/*
    printf("CmdLine arguments:\n");
    printf("\targc = %d\n", args_total);
    for (int i = 0; i < args_total; ++i) {
        printf("\targv[%d] = %s\n", i, args[i]);
    }
*/

    for (int i = 1; i < args_total; ++i) {
        string t = args[i];
        if (t.find("--funcp") != string::npos) {
            FuncSimParams::instance()->set(t.substr(8));
            break;
        }
    }

    printf("VP and Env initialization started\n");
    // Init the virtual platform and the application environment.
    vp->Init();
    appEnv->InitApp(args_total, args);
    printf("VP and Env initialization done\n");

 static ViCo::Plugin::Main M={0};
 M.self_size=sizeof(M);
 M.pl_thread_main=run_hasim;
 M.options=ViCo::Plugin::MO_DetachMainTh;
 return &M;
}

};

