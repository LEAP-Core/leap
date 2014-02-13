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

#ifndef __STATS_SERVICE_H__
#define __STATS_SERVICE_H__

#include <pthread.h>
#include <unordered_map>
#include <unordered_set>
#include <iostream>
#include <mutex>
#include <condition_variable>
#include <list>

#include "tbb/atomic.h"

#include "asim/syntax.h"

#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/rrr.h"
#include "awb/provides/soft_services_deps.h"

#include "awb/rrr/client_stub_STATS.h"

//
// STAT_COUNTER_CLASS --
//     The basic counter for a single statistics bucket.
//
typedef class STAT_COUNTER_CLASS* STAT_COUNTER;

class STAT_COUNTER_CLASS
{
  private:
    UINT64 value;

  public:
    STAT_COUNTER_CLASS() : value(0) {};
    ~STAT_COUNTER_CLASS() {};
    
    void IncrBy(UINT64 inc) { value += inc; };
    UINT64 GetValue() { return value; };
    UINT64 SetValue(UINT64 newValue) { value = newValue; };
};


//
// STAT_VECTOR_CLASS --
//     A fixed size vector of statistics counters, all sharing the same name
//     (tag and description).
//
typedef class STAT_VECTOR_CLASS* STAT_VECTOR;


class STAT_VECTOR_CLASS
{

  private:
    const string tag;
    const string description;
    UINT32 length;

    STAT_COUNTER v;

  public:
    STAT_VECTOR_CLASS(const string &t, const string &d, UINT32 len);
    ~STAT_VECTOR_CLASS();

    const string& GetTag() const { return tag; };
    const string& GetDescription() const { return description; };
    UINT32 GetLength() const { return length; };

    UINT64 GetValue(UINT32 n) const
    {
        ASSERTX(n < length);
        return v[n].GetValue();
    };
    
    STAT_COUNTER GetEntry(UINT32 n)
    {
        ASSERTX(n < length);
        return &v[n];
    };

    void SetEntry(UINT32 n, UINT64 value)
    {
        ASSERTX(n < length);
        v[n].SetValue(value);
    };
};


//
// STAT_INIT_BUCKET --
//     During initialization the names of individual statistics buckets are
//     tracked.  For the most part this is simply to verify that all names are
//     used only once.  For distributed statistics this is used to find the
//     maximum index.
//
typedef class STAT_INIT_BUCKET_CLASS* STAT_INIT_BUCKET;

class STAT_INIT_BUCKET_CLASS
{
  public:
    const string tag;   // Tag from descriptor
    const string description;

    STAT_VECTOR dVec;   // Distributed vector for all instances of this
                        // statistic (used by SetupStats method).
    UINT32 maxIdx;      // Largest index seen (for distributed statistics)

    char statType;      // Statistic type from descriptor
    
    STAT_INIT_BUCKET_CLASS(const char *t, const char *d, char stype) :
        tag(t),
        description(d),
        dVec(NULL),
        maxIdx(0),
        statType(stype)
    {};

    ~STAT_INIT_BUCKET_CLASS() {};
};


//
// STAT_NODE_DESC_CLASS --
//     A statistics node descriptor is derived from the a single global
//     string, associated with a single statistics node on the FPGA.  It
//     maps references to from the descriptor to STAT_COUNTERs.
//
typedef class STAT_NODE_DESC_CLASS* STAT_NODE_DESC;

class STAT_NODE_DESC_CLASS
{
  private:
    const UINT32 length;
    STAT_COUNTER *v;
    UINT32 distribArrayIdx;

  public:
    list<STAT_INIT_BUCKET> initBucketList;

    STAT_NODE_DESC_CLASS(UINT32 len);
    ~STAT_NODE_DESC_CLASS();

    void SetEntry(UINT32 n, STAT_COUNTER cnt)
    {
        ASSERTX(n < length);
        v[n] = cnt;
    }

    STAT_COUNTER GetEntry(UINT32 n)
    {
        ASSERTX((n < length) && (v[n] != NULL));
        return v[n];
    }

    void SetDistribIdx(UINT32 i) { distribArrayIdx = i; }
    UINT32 GetDistribIdx() const { return distribArrayIdx; }

    UINT32 GetLength() const { return length; }
};


//
// Commands that may be passed to the Command port in hardware.  This
// enumeration must match the Bluespec equivalent.
//
enum STATS_SERVER_COMMAND
{
    STATS_SERVER_CMD_INIT,
    STATS_SERVER_CMD_DUMP,
    STATS_SERVER_CMD_ENABLE,
    STATS_SERVER_CMD_DISABLE
};


typedef class STATS_SERVER_CLASS* STATS_SERVER;

class STATS_SERVER_CLASS: public RRR_SERVER_CLASS,
                          public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static STATS_SERVER_CLASS instance;

    // stubs
    RRR_SERVER_STUB serverStub;
    STATS_CLIENT_STUB clientStub;

    // Have we initialized the stats yet?
    bool statsInited;

    // Map from statistics node descriptors on the FPGA to buckets.
    unordered_map<GLOBAL_STRING_UID, STAT_NODE_DESC> bucketMap;

    // List of statistics buckets
    list<STAT_VECTOR> statVectors;

    // During initialization maintain a map of all buckets in order to validate
    // that each name is used only once.
    unordered_map<string, STAT_INIT_BUCKET> initAllBuckets;

    static std::mutex ackMutex;
    static std::condition_variable ackCond;
    static bool ackReceived;

    pthread_t liveStatsThread;
    
    class tbb::atomic<bool> initialized;
    class tbb::atomic<bool> uninitialized;

    void SendCommand(STATS_SERVER_COMMAND cmd);

  public:
    STATS_SERVER_CLASS();
    ~STATS_SERVER_CLASS();

    // Methods other people call to control stats.
    void SetupStats();
    void ToggleEnabled();
    void ResetStatValues();
    void DumpStats();
    void EmitFile();
    void EmitFile(string statsFileName);
    void EmitFile(ofstream& statsFile);

    // static methods
    static STATS_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();

    // RRR server methods
    void ReportStat(GLOBAL_STRING_UID desc, UINT32 pos, UINT32 value);
    void NodeInfo(GLOBAL_STRING_UID desc);
    void Ack(UINT8 cmd);
};

// server stub
#include "awb/rrr/server_stub_STATS.h"

// all functionalities of the stats controller are completely implemented
// by the STATS_SERVER class
typedef STATS_SERVER_CLASS STATS_DEVICE_CLASS;

void StatsEmitFile();


// ========================================================================
//
//   HACK!  Clients may "register" as stats emitters by allocating an
//   instance of the following class.  They may then write whatever
//   they wish to the stats file.  Clearly this should be improved with
//   some structure, perhaps by switching to statistics code from
//   Asim.
//
// ========================================================================

typedef class STATS_EMITTER_CLASS *STATS_EMITTER;

// Set of all stats emitters.
typedef std::unordered_set<STATS_EMITTER> ALL_STATS_EMITTERS;

class STATS_EMITTER_CLASS
{
  private:
    static ALL_STATS_EMITTERS* statsEmitters;

  public:
    STATS_EMITTER_CLASS();
    ~STATS_EMITTER_CLASS();

    static ALL_STATS_EMITTERS GetStatsEmitters(void)
    {
        if (statsEmitters == NULL)
        {
            statsEmitters = new ALL_STATS_EMITTERS;
        }

        return *statsEmitters;
    };

    virtual void EmitStats(ofstream &statsFile) = 0;
    virtual void ResetStats() = 0;
};

#endif // __STATS_SERVICE_H__
