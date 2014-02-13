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

#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <string>
#include <iostream>

#include "asim/syntax.h"
#include "asim/config.h"

#include "awb/rrr/service_ids.h"
#include "awb/provides/command_switches.h"

#include "awb/provides/stats_service.h"

using namespace std;

void *StatsThread(void *arg);


// ===== service instantiation =====
STATS_SERVER_CLASS STATS_SERVER_CLASS::instance;

std::mutex STATS_SERVER_CLASS::ackMutex;
std::condition_variable STATS_SERVER_CLASS::ackCond;
bool STATS_SERVER_CLASS::ackReceived;

// ===== registered stats emitters =====
ALL_STATS_EMITTERS* STATS_EMITTER_CLASS::statsEmitters = NULL;

// ===== methods =====

// constructor
STATS_SERVER_CLASS::STATS_SERVER_CLASS() :
    statsInited(false),
    // instantiate stubs
    clientStub(new STATS_CLIENT_STUB_CLASS(this)),
    serverStub(new STATS_SERVER_STUB_CLASS(this)),
    initialized(),
    uninitialized()
{

    initialized = false;
    uninitialized = false;

}


// destructor
STATS_SERVER_CLASS::~STATS_SERVER_CLASS()
{
    Cleanup();
}


// init
void
STATS_SERVER_CLASS::Init(
    PLATFORMS_MODULE     p)
{
    // set parent pointer
    parent = p;

    VERIFYX(! pthread_create(&liveStatsThread, NULL, &StatsThread, NULL));
    initialized = true;
}


// init
void
STATS_SERVER_CLASS::SetupStats()
{
    // This call will cause the hardware to invoke ReportStat for every node.
    SendCommand(STATS_SERVER_CMD_INIT);

    // At this point the hardware has informed the software about all statistics
    // nodes by calling NodeInfo() below.  Generate collection buckets from
    // the data.
    for (unordered_map<GLOBAL_STRING_UID, STAT_NODE_DESC>::const_iterator mi = bucketMap.begin();
         mi != bucketMap.end(); mi++)
    {
        const STAT_NODE_DESC node = mi->second;

        // Iterate over all the buckets associated with this node.
        int entry_idx = 0;
        for (list<STAT_INIT_BUCKET>::const_iterator li = node->initBucketList.begin();
             li != node->initBucketList.end(); li++)
        {
            const STAT_INIT_BUCKET bucket = *li;

            if (bucket->statType == 'M')
            {
                // A true vector statistic.
                STAT_VECTOR svec = new STAT_VECTOR_CLASS(bucket->tag,
                                                         bucket->description,
                                                         node->GetLength());
                statVectors.push_front(svec);
                for (int i = 0; i < node->GetLength(); i++)
                {
                    node->SetEntry(i, svec->GetEntry(i));
                }
            }
            else if (bucket->statType == 'D')
            {
                // Distributed vector statistic that is referenced by multiple
                // statistics nodes, each node having a different index.
                STAT_VECTOR svec = bucket->dVec;
                if (svec == NULL)
                {
                    // First time the name is seen.  Allocate the vector.
                    svec = new STAT_VECTOR_CLASS(bucket->tag,
                                                 bucket->description,
                                                 bucket->maxIdx + 1);
                    bucket->dVec = svec;
                    statVectors.push_front(svec);
                }

                node->SetEntry(entry_idx, svec->GetEntry(node->GetDistribIdx()));
            }
            else
            {
                // An individual statistic.  Store it in a length 1 STAT_VECTOR.
                STAT_VECTOR svec = new STAT_VECTOR_CLASS(bucket->tag,
                                                         bucket->description,
                                                         1);
                statVectors.push_front(svec);
                node->SetEntry(entry_idx, svec->GetEntry(0));
            }

            entry_idx += 1;
        }
    }


    //
    // Clean up initialization data structures.
    //
    for (unordered_map<string, STAT_INIT_BUCKET>::const_iterator bi = initAllBuckets.begin();
         bi != initAllBuckets.end(); bi++)
    {
        delete bi->second;
    }
    initAllBuckets.clear();

    for (unordered_map<GLOBAL_STRING_UID, STAT_NODE_DESC>::const_iterator mi = bucketMap.begin();
         mi != bucketMap.end(); mi++)
    {
        mi->second->initBucketList.clear();
    }
    

    //
    // Initialization complete.  Turn on statistics collection (it starts
    // disabled.)
    //
    static bool once = false;
    if (! once)
    {
        SendCommand(STATS_SERVER_CMD_ENABLE);
        once = true;
    }

    statsInited = true;
}


// uninit: we have to write this explicitly
void
STATS_SERVER_CLASS::Uninit()
{
    Cleanup();

    // chain
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
STATS_SERVER_CLASS::Cleanup()
{
    bool didCleanup = uninitialized.fetch_and_store(true);

    if (didCleanup)
    {
        return;
    }

    // Kill the thread monitoring the live file
    if (initialized)
    {
        pthread_cancel(liveStatsThread);
        pthread_join(liveStatsThread, NULL);
    }
    unlink(LEAP_LIVE_DEBUG_PATH "/stats");

    // kill stubs
    delete serverStub;
    delete clientStub;

    // Delete all statistics vectors (the counter buckets)
    for (list<STAT_VECTOR>::const_iterator li = statVectors.begin();
         li != statVectors.end(); li++)
    {
        delete *li;
    }
    statVectors.clear();

    // Delete all maps from statistics nodes to counter vectors
    for (unordered_map<GLOBAL_STRING_UID, STAT_NODE_DESC>::const_iterator mi = bucketMap.begin();
         mi != bucketMap.end(); mi++)
    {
        delete mi->second;
    }
    bucketMap.clear();
}

//
// RRR request methods
//

//
// ReportStat --
//     Receive an updated counter value for a single bucket.
//
void
STATS_SERVER_CLASS::ReportStat(
    GLOBAL_STRING_UID desc,
    UINT32 pos,
    UINT32 value)
{
    VERIFY(bucketMap.find(desc) != bucketMap.end(),
            "stats device: Failed lookup: " << *GLOBAL_STRINGS::Lookup(desc));

    // The bucketMap points to a vector of buckets, indexed by pos.
    bucketMap[desc]->GetEntry(pos)->IncrBy(value);
}


//
// NodeInfo --
//     During initialization, receive details of a statistics node.
//
void
STATS_SERVER_CLASS::NodeInfo(GLOBAL_STRING_UID desc)
{
    // Get the statistic node's descriptor string
    char *str = strdup(GLOBAL_STRINGS::Lookup(desc)->c_str());
    VERIFYX(strlen(str) > 2);

    // First character is the node type
    char node_type = str[0];

    // The number of elements in the vector immediately follows the node type
    int node_vlen = atoi(str + 1);
    VERIFYX(strsep(&str, "~") != NULL);

    // Allocate a map from this descriptor to statistics buckets.  It will
    // be used later when values come from the hardware.
    STAT_NODE_DESC node_desc = new STAT_NODE_DESC_CLASS(node_vlen);
    VERIFY(bucketMap.find(desc) == bucketMap.end(),
           "stats device: Multiple instances of descriptor: " << *GLOBAL_STRINGS::Lookup(desc));
    bucketMap[desc] = node_desc;

    // For distributed statistics nodes the next field is the array index
    if (node_type == 'D')
    {
        const char *s = strsep(&str, "~");
        node_desc->SetDistribIdx(atoi(s));
    }

    // The remainder of the descriptor is pairs of statistic tags and
    // descriptive text.
    int entry_idx = 0;
    const char* s;
    while ((s = strsep(&str, "~")) != NULL)
    {
        const char *stat_tag = s;
        const char *stat_text = strsep(&str, "~");
        VERIFYX(stat_text != NULL);

        STAT_INIT_BUCKET b = NULL;
        unordered_map<string, STAT_INIT_BUCKET>::const_iterator bi;
        bi = initAllBuckets.find(stat_tag);
        if (bi == initAllBuckets.end())
        {
            // First time this bucket name is seen.
            b = new STAT_INIT_BUCKET_CLASS(stat_tag, stat_text, node_type);
            b->maxIdx = node_desc->GetDistribIdx();
            initAllBuckets[stat_tag] = b;
        }
        else
        {
            b = bi->second;

            // The bucket name already exists.  In general this is an error
            // unless the node type is distributed, in which case each reference
            // to the name is supposed to have a unique distributed index.
            if ((b->statType != 'D') || (node_type != 'D'))
            {
                ASIMERROR("stats device: Multiple instances of tag: " << stat_tag);
            }
            else
            {
                // Is the current index the largest yet seen?
                if (node_desc->GetDistribIdx() > b->maxIdx)
                {
                    b->maxIdx = node_desc->GetDistribIdx();
                }
            }
        }
        
        // Save an ordered list of buckets (tags and descriptors)
        node_desc->initBucketList.push_back(b);
            
        entry_idx += 1;
    }

    if (node_type == 'M')
    {
        VERIFY(entry_idx == 1,
               "stats device: MultiEntry stat must have exactly 1 descriptor: " << *GLOBAL_STRINGS::Lookup(desc));
    }
    else if ((node_type == 'V') || (node_type == 'D'))
    {
        VERIFY(node_vlen == entry_idx,
               "stats device: Invalid descriptor: " << *GLOBAL_STRINGS::Lookup(desc));
    }
    else
    {
        ASIMERROR("stats device: Invalid descriptor: " << *GLOBAL_STRINGS::Lookup(desc));
    }

    free(str);
}

// Reset Stats values
// Calls a dump stats followed by setting all the software side stats to
// zero.  This effectively clears all the statistics values.
void STATS_SERVER_CLASS::ResetStatValues()
{
    SendCommand(STATS_SERVER_CMD_DUMP);

    // Zero all stats vectors
    for (list<STAT_VECTOR>::iterator li = statVectors.begin();
         li != statVectors.end(); li++)
    {
      for(int i = 0; i < (*li)->GetLength(); i++) {
            (*li)->SetEntry(i,0);
        }
    }

    // Call other emitters.
    ALL_STATS_EMITTERS emitters = STATS_EMITTER_CLASS::GetStatsEmitters();
    for (ALL_STATS_EMITTERS::iterator i = emitters.begin();
         i != emitters.end();
         i++)
    {
        (*i)->ResetStats();
    }
}

//
// SendCommand --
//     Send a command to the HW service and wait for the ack.
//
void
STATS_SERVER_CLASS::SendCommand(STATS_SERVER_COMMAND cmd)
{
    // Only one command is allowed to execute at a time.  Get the command lock.
    static std::mutex commandMutex;
    // Hold the mutex within the SendCommand scope.  It will be unlocked when
    // destroyed at the end of the function.
    std::unique_lock<std::mutex> commandLock(commandMutex);

    ackReceived = false;

    // Send the request to HW.
    clientStub->Command(cmd);

    // Wait for the command to complete (indicated by commandActive clear)
    std::unique_lock<std::mutex> ackLock(ackMutex);
    ackCond.wait(ackLock, []{ return ackReceived; });
}


//
// Ack --
//     Each HW command request gets an ack to indicate the operation is
//     complete.
//
void
STATS_SERVER_CLASS::Ack(UINT8 cmd)
{
    std::unique_lock<std::mutex> ackLock(ackMutex);
    ackReceived = true;
    ackCond.notify_one();
}


// DumpStats
void
STATS_SERVER_CLASS::DumpStats()
{
    SendCommand(STATS_SERVER_CMD_DUMP);
}

void
STATS_SERVER_CLASS::EmitFile(string statsFileName)
{
    ofstream statsFile(statsFileName.c_str());

    if (! statsFile.is_open())
    {
        cerr << "Failed to open stats file: " << statsFile << endl;
        ASIMERROR("Can't dump statistics");
    }

    EmitFile(statsFile);
    statsFile.close();
}

void
STATS_SERVER_CLASS::EmitFile(ofstream& statsFile)
{
    static std::mutex scanMutex;
    // Hold the mutex within the EmitFile scope.  It will be unlocked when
    // destroyed at the end of the function.
    std::unique_lock<std::mutex> scanLock(scanMutex);

    statsFile.precision(10);

    for (list<STAT_VECTOR>::const_iterator li = statVectors.begin();
         li != statVectors.end(); li++)
    {
        statsFile << (*li)->GetTag() << ",\"" << (*li)->GetDescription() << "\"";
        
        for (UINT32 i = 0; i < (*li)->GetLength(); i++)
        {
            statsFile << "," << (*li)->GetValue(i);
        }

        statsFile << endl;
    }

    // Hack: instantiate the simulator configuration here to be able to emit
    // all the model parameters.
    ASIM_CONFIG sim_config = new ASIM_CONFIG_CLASS();
    sim_config->RegisterSimulatorConfiguration();
    sim_config->EmitStats(statsFile);

    // Call other emitters.  Clearly this needs to be improved with some
    // structured data.
    ALL_STATS_EMITTERS emitters = STATS_EMITTER_CLASS::GetStatsEmitters();
    for (ALL_STATS_EMITTERS::iterator i = emitters.begin();
         i != emitters.end();
         i++)
    {
        (*i)->EmitStats(statsFile);
    }
}

//
// EmitStatsFile --
//    Dump the in-memory statistics to a file.
//
void
STATS_SERVER_CLASS::EmitFile()
{
    // Open the output file
    string statsFileName = string(globalArgs->Workload()) + ".stats";
    EmitFile(statsFileName);
}


void
StatsEmitFile()
{
    STATS_SERVER_CLASS::GetInstance()->EmitFile();
}



// ========================================================================
//
//   Internal statistics buckets and pointers.
//
// ========================================================================

STAT_VECTOR_CLASS::STAT_VECTOR_CLASS(const string &t, const string &d, UINT32 len) :
    tag(t),
    description(d),
    length(len)
{
    v = new STAT_COUNTER_CLASS[len];
}

STAT_VECTOR_CLASS::~STAT_VECTOR_CLASS() 
{ 
    delete [] v;
}


STAT_NODE_DESC_CLASS::STAT_NODE_DESC_CLASS(UINT32 len) :
    length(len)
{
    v = new STAT_COUNTER[len];
    for (UINT32 i = 0; i < len; i++)
    {
        v[i] = NULL;
    }
}

STAT_NODE_DESC_CLASS::~STAT_NODE_DESC_CLASS()
{
    delete [] v;
}


// ========================================================================
//
//   HACK!  Clients may "register" as stats emitters by allocating an
//   instance of the following class.  They may then write whatever
//   they wish to the stats file.  Clearly this should be improved with
//   some structure, perhaps by switching to statistics code from
//   Asim.
//
// ========================================================================

STATS_EMITTER_CLASS::STATS_EMITTER_CLASS()
{
    if (statsEmitters == NULL)
    {
        statsEmitters = new ALL_STATS_EMITTERS;
    }

    statsEmitters->insert({this, this});
}

STATS_EMITTER_CLASS::~STATS_EMITTER_CLASS()
{
    //
    // Drop me from the global set of emitters.
    //
    if (statsEmitters != NULL)
    {
        statsEmitters->erase(statsEmitters->find(this));
    }
}


// ========================================================================
//
//   Live system statistics.
//
// ========================================================================

//
// StatsThread --
//   Run as a permanent thread providing a live file (a named pipe) that,
//   when read, initiates a dump of statistics to the pipe.
//
void *StatsThread(void *arg)
{
    mkfifo(LEAP_LIVE_DEBUG_PATH "/stats", 0755);

    while (true)
    {
        // The open blocks until a reader also opens the pipe.
        ofstream f(LEAP_LIVE_DEBUG_PATH "/stats");

        STATS_SERVER_CLASS::GetInstance()->DumpStats();
        STATS_SERVER_CLASS::GetInstance()->EmitFile(f);
        f.close();

        // The close causes readers to terminate, however the open
        // on the next iteration would cause a slow reader to miss the
        // EOF and trigger another dump.  Is there a way to wait for
        // the reader to exit?  Until we find one, sleep for a while.
        sleep(10);
    }
}
