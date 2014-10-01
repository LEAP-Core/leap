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

#ifndef __JTAG_PHYSICAL_CHANNEL__
#define __JTAG_PHYSICAL_CHANNEL__

#include <stdio.h>
#include <pthread.h>

#include "tbb/concurrent_queue.h"
#include "tbb/atomic.h"
#include "awb/provides/umf.h"
#include "awb/provides/physical_platform_utils.h"



// ============================================
//               Physical Channel              
// ============================================
typedef class JTAG_PHYSICAL_CHANNEL_CLASS* JTAG_PHYSICAL_CHANNEL;
class JTAG_PHYSICAL_CHANNEL_CLASS: public PHYSICAL_CHANNEL_CLASS
{

  private:
 
  int msg_count_in, msg_count_out;

  // queue for storing messages 
  class tbb::concurrent_bounded_queue<UMF_MESSAGE> writeQ;

  // incomplete incoming read message
  UMF_MESSAGE incomingMessage;

  FILE* errfd;
  int input;
  int output;
  int pid;

  void   readPipe();

  UMF_FACTORY umfFactory;

  public:

    JTAG_PHYSICAL_CHANNEL_CLASS(PLATFORMS_MODULE p);
    ~JTAG_PHYSICAL_CHANNEL_CLASS();
    
    UMF_MESSAGE Read();             // blocking read
    UMF_MESSAGE TryRead();          // non-blocking read
    void        Write(UMF_MESSAGE); // write

    class tbb::concurrent_bounded_queue<UMF_MESSAGE> *GetWriteQ() { return &writeQ; }
    void SetUMFFactory(UMF_FACTORY factoryInit) { umfFactory = factoryInit; };
    void RegisterLogicalDeviceName(string name) { }
};

#endif
