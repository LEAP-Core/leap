#ifndef __HARDWARE_DONE_H__
#define __HARDWARE_DONE_H__

#include <mutex>
#include <condition_variable>
#include "tbb/atomic.h"

/* Variables storing the hardware status. */
/* These variables should only be modified if this lock is held. */
/* Software can check if hardware is done as follows: */
/* First, check if hardwareFinished == 1. If so, it's done
/* (it finished before the software). Otherwise, sleep until you
/* receive the hardwareFinishedSignal. */

extern std::mutex hardwareStatusMutex;
extern std::condition_variable hardwareFinishedSignal;

extern class tbb::atomic<int> hardwareStarted;
extern class tbb::atomic<int> hardwareFinished;
extern class tbb::atomic<int> hardwareExitCode;

#endif
