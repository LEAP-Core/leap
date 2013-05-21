//
// Copyright (C) 2008 Intel Corporation
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
pthread_mutex_t STATS_SERVER_CLASS::scanLock = PTHREAD_MUTEX_INITIALIZER;

// ===== registered stats emitters =====
static list<STATS_EMITTER> statsEmitters;

// ===== methods =====

// constructor
STATS_SERVER_CLASS::STATS_SERVER_CLASS() :
    statsInited(false),
    // instantiate stubs
    clientStub(new STATS_CLIENT_STUB_CLASS(this)),
    serverStub(new STATS_SERVER_STUB_CLASS(this))
{
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
}


// init
void
STATS_SERVER_CLASS::SetupStats()
{
    // This call will cause the hardware to invoke ReportStat for every node.
    clientStub->DoInit(0);

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
        clientStub->Enable(0);
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
    // Kill the thread monitoring the live file
    pthread_cancel(liveStatsThread);
    pthread_join(liveStatsThread, NULL);
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
    clientStub->DumpStats(0);

    // Zero all stats vectors
    for (list<STAT_VECTOR>::iterator li = statVectors.begin();
         li != statVectors.end(); li++)
    {
      for(int i = 0; i < (*li)->GetLength(); i++) {
            (*li)->SetEntry(i,0);
        }
    }

}

// DumpStats
void
STATS_SERVER_CLASS::DumpStats()
{
    clientStub->DumpStats(0);
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
    pthread_mutex_lock(&scanLock);

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
    for (list<STATS_EMITTER>::iterator i = statsEmitters.begin();
         i != statsEmitters.end();
         i++)
    {
        (*i)->EmitStats(statsFile);
    }

    pthread_mutex_unlock(&scanLock);
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
    statsEmitters.push_front(this);
}

STATS_EMITTER_CLASS::~STATS_EMITTER_CLASS()
{
    //
    // Drop me from the global list of emitters.
    //
    for (list<STATS_EMITTER>::iterator i = statsEmitters.begin();
         i != statsEmitters.end();
         i++)
    {
        if (*i == this)
        {
            statsEmitters.erase(i);
            break;
        }
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
