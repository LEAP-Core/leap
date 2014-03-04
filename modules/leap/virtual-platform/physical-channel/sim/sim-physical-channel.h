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

#ifndef __SIM_PHYSICAL_CHANNEL__
#define __SIM_PHYSICAL_CHANNEL__

#include "awb/provides/umf.h"
#include "awb/provides/physical_platform_utils.h"
#include "awb/provides/unix_pipe_device.h"
#include "tbb/concurrent_queue.h"
#include "tbb/atomic.h"
#include <pthread.h>

// ============================================
//               Physical Channel              
// ============================================
typedef class SIM_PHYSICAL_CHANNEL_CLASS* SIM_PHYSICAL_CHANNEL;
class SIM_PHYSICAL_CHANNEL_CLASS: public PHYSICAL_CHANNEL_CLASS
{
    private:
        // our lower-level physical device.
        UNIX_PIPE_DEVICE_CLASS unixPipeDevice;
        
        // queue for storing messages 
	class tbb::concurrent_bounded_queue<UMF_MESSAGE> writeQ;

        // incomplete incoming read message
        UMF_MESSAGE incomingMessage;

        // internal methods
        void readPipe();

        UMF_FACTORY umfFactory;

        pthread_t   writerThread;

        class tbb::atomic<bool> uninitialized;

    public:
        SIM_PHYSICAL_CHANNEL_CLASS(PLATFORMS_MODULE);
        ~SIM_PHYSICAL_CHANNEL_CLASS();

        static void * WriterThread(void *argv) {
	    void ** args = (void**) argv;
	    SIM_PHYSICAL_CHANNEL physicalChannel = (SIM_PHYSICAL_CHANNEL) args[1];
	    tbb::concurrent_bounded_queue<UMF_MESSAGE> *incomingQ = &(physicalChannel->writeQ); 
	    UNIX_PIPE_DEVICE pipeDevice = (UNIX_PIPE_DEVICE) args[0];
	    while(1) {
	        UMF_MESSAGE message;
	        incomingQ->pop(message);

                // Check to see if we're being torn down -- this is
                // done by passing a special message through the writeQ

                if (message == NULL)
                {
                    if (!physicalChannel->uninitialized)
                    {
                        cerr << "SIM_PHYSICAL_CHANNEL got an unexpected NULL value" << endl;
                    }

                    pthread_exit(0);
                }

	        // construct header                               
	        UMF_CHUNK header = 0;
	        message->EncodeHeader((unsigned char *)&header);

                pipeDevice->Write((unsigned char *)&header, UMF_CHUNK_BYTES);

	        // write message data to pipe                                                     
	        // NOTE: hardware demarshaller expects chunk pattern to start from most       	    
                //       significant chunk and end at least significant chunk, so we will                  
                //       send chunks in reverse order                                                               
                message->StartExtract();
                while (message->CanExtract())
                {
                    UMF_CHUNK chunk = message->ExtractChunk();
                    pipeDevice->Write((unsigned char*)&chunk, sizeof(UMF_CHUNK));
                }

                // de-allocate message                                                                                 	
                delete message;
	    }
	}

        UMF_MESSAGE Read();             // blocking read
        UMF_MESSAGE TryRead();          // non-blocking read
        void        Write(UMF_MESSAGE); // write
        void        Uninit(); 
        class tbb::concurrent_bounded_queue<UMF_MESSAGE> *GetWriteQ() { return &writeQ; }
        void SetUMFFactory(UMF_FACTORY factoryInit) { umfFactory = factoryInit; };
        void RegisterLogicalDeviceName(string name) { unixPipeDevice.RegisterLogicalDeviceName(name); }
};

#endif
