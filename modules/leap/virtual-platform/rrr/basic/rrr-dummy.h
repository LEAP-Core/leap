#ifndef _RRR_DUMMY_
#define _RRR_DUMMY_

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "asim/syntax.h"
#include "asim/mesg.h"
//#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/umf.h"
#include "awb/provides/model.h"

class RRR_CLIENT_CLASS : public PLATFORMS_MODULE_CLASS {
public:
 RRR_CLIENT_CLASS(PLATFORMS_MODULE p, void*) : PLATFORMS_MODULE_CLASS(p) {}

 void SetMonitorThreadID(pthread_t mon) {}
 void Poll() {pthread_exit(NULL);}
};

typedef RRR_CLIENT_CLASS* RRR_CLIENT;

class RRR_SERVER_CLASS  {};
typedef RRR_SERVER_CLASS* RRR_SERVER;

class RRR_SERVER_STUB_CLASS {
 static RRR_SERVER_STUB_CLASS* root;
 RRR_SERVER_STUB_CLASS* next;
public:
 RRR_SERVER_STUB_CLASS() {next=root; root=this;}
 virtual ~RRR_SERVER_STUB_CLASS() {}

 static RRR_SERVER_STUB_CLASS* get_root() {return root;}
 RRR_SERVER_STUB_CLASS* get_next() const {return next;}

 virtual void Init(PLATFORMS_MODULE) = 0;
};
typedef RRR_SERVER_STUB_CLASS* RRR_SERVER_STUB;

class CHANNELIO_CLASS : public PLATFORMS_MODULE_CLASS {
public:
 CHANNELIO_CLASS(PLATFORMS_MODULE p, void*) : PLATFORMS_MODULE_CLASS(p) {}
 void Poll() {pthread_exit(NULL);}
};

typedef CHANNELIO_CLASS* CHANNELIO;

class RRR_SERVER_MONITOR_CLASS : public PLATFORMS_MODULE_CLASS {
public:
  RRR_SERVER_MONITOR_CLASS(PLATFORMS_MODULE p, void*) : PLATFORMS_MODULE_CLASS(p) {}
 void Poll() {pthread_exit(NULL);}

 void Init()
 {
  for(RRR_SERVER_STUB_CLASS* p=RRR_SERVER_STUB_CLASS::get_root();p;p=p->get_next())
   p->Init(this);
  PLATFORMS_MODULE_CLASS::Init();
 }

};

typedef RRR_SERVER_MONITOR_CLASS* RRR_SERVER_MONITOR;


static RRR_CLIENT RRRClient;

#endif
