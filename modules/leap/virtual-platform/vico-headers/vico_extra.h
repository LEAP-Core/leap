//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

#ifndef _VICO_EXTRA_UTILS_H_
#define _VICO_EXTRA_UTILS_H_

#include "vico_fw.h"

namespace ViCo { namespace Utils {

// Measure timings


class PerfTimerServer;

// No methods can be inlined - We should allow to run modules, compiled with VICO_TIMINGS to run on ViCo core without VICO_TIMINGS
class EXT_SYM PerfTimerDef {
#ifdef VICO_TIMINGS
 const char* name;
 std::map<uint32_t,uint32_t> freq_map;
 uint32_t min_v, max_v, total_v, count;
 uint32_t start_ts;
 friend class PerfTimerServer;
#endif
public:
 PerfTimerDef(const char* n);
 ~PerfTimerDef();

 void start();
 void end();
};

class PerfTimer {
 PerfTimerDef& pt;
public:
 PerfTimer(PerfTimerDef& d)  :pt(d) {pt.start();}
 ~PerfTimer() {pt.end();}
};

#ifdef VICO_TIMINGS
#define VICO_TIMING_BLOCK(name) \
  static ViCo::Utils::PerfTimerDef my_local_performance_timer_definition_instance_class_with_unique_name(name); \
  ViCo::Utils::PerfTimer my_local_performance_timer_instance_class_with_unique_name(my_local_performance_timer_definition_instance_class_with_unique_name)
#else
#define VICO_TIMING_BLOCK(name)
#endif


}}


#endif
