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

#ifndef __PHYSICAL_CHANNEL__
#define __PHYSICAL_CHANNEL__

#include <pthread.h>

#include "awb/provides/umf.h"
#include "awb/provides/pci_express_device.h"
#include "awb/provides/physical_platform.h"

// ============================================
//               Physical Channel              
// ============================================

class PHYSICAL_CHANNEL_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:

    // links to useful physical devices
    PCIE_DEVICE pciExpressDevice;
    
    // physical channel state
    CSR_INDEX f2hHead;
    CSR_INDEX f2hTailCache;
    CSR_INDEX h2fHeadCache;
    CSR_INDEX h2fTail;
    
    // incomplete incoming read message
    UMF_MESSAGE incomingMessage;
    
    // instruction ID
    CSR_DATA iid;
    
    // internal methods
    void     readCSR();
    CSR_DATA genIID();
    
    pthread_mutex_t channelLock;

  public:

    PHYSICAL_CHANNEL_CLASS(PLATFORMS_MODULE, PHYSICAL_DEVICES);
    ~PHYSICAL_CHANNEL_CLASS();

    void Init();

    UMF_MESSAGE Read();             // blocking read
    UMF_MESSAGE TryRead();          // non-blocking read
    void        Write(UMF_MESSAGE); // write
};

#endif
