//
// Copyright (C) 2011 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
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