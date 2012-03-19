#include <stdio.h>
#include <pthread.h>

#include "application-env-hybrid-soft-service.h"

#include "awb/provides/virtual_platform.h"
#include "awb/provides/stats_service.h"

APPLICATION_ENV_CLASS::APPLICATION_ENV_CLASS(VIRTUAL_PLATFORM vp) : 
    app(new CONNECTED_APPLICATION_CLASS(vp))
{
    return;
}

void 
APPLICATION_ENV_CLASS::InitApp(int argc, char** argv)
{
    // TODO: pass argc, argv?
    app->Init();
    return;
}

int 
APPLICATION_ENV_CLASS::RunApp(int argc, char** argv)
{
    // TODO: pass argc, argv, get return value
    // return app->Main(argc, argv);
    app->Main();

    // Emit statistics
    STATS_SERVER_CLASS::GetInstance()->DumpStats();
    STATS_SERVER_CLASS::GetInstance()->EmitFile();

    return 0;
}
