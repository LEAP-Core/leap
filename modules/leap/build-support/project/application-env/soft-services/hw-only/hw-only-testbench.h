#ifndef __CONNECTED_APPLICATION__
#define __CONNECTED_APPLICATION__

#include "asim/provides/virtual_platform.h"

typedef class CONNECTED_APPLICATION_CLASS* CONNECTED_APPLICATION;
class CONNECTED_APPLICATION_CLASS
{
  public:
    CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp);
    ~CONNECTED_APPLICATION_CLASS();

    // init
    void Init();

    // main
    void Main();
};

#endif
