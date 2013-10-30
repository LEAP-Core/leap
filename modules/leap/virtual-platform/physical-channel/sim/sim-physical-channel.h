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

#ifndef __PHYSICAL_CHANNEL__
#define __PHYSICAL_CHANNEL__

#include "awb/provides/umf.h"
#include "awb/provides/physical_platform.h"
#include "tbb/concurrent_queue.h"
#include <pthread.h>

// ============================================
//               Physical Channel              
// ============================================

class PHYSICAL_CHANNEL_CLASS: public PLATFORMS_MODULE_CLASS
{
    private:
        // cached links to useful physical devices
        UNIX_PIPE_DEVICE unixPipeDevice;

        // queue for storing messages 
	class tbb::concurrent_bounded_queue<UMF_MESSAGE> writeQ;

        // incomplete incoming read message
        UMF_MESSAGE incomingMessage;

        // internal methods
        void readPipe();

        UMF_FACTORY umfFactory;

        pthread_t   writerThread;

    public:
        PHYSICAL_CHANNEL_CLASS(UMF_FACTORY, PLATFORMS_MODULE, PHYSICAL_DEVICES);
        ~PHYSICAL_CHANNEL_CLASS();

        static void * WriterThread(void *argv) {
	    void ** args = (void**) argv;
	    tbb::concurrent_bounded_queue<UMF_MESSAGE> *incomingQ = (tbb::concurrent_bounded_queue<UMF_MESSAGE>*) args[1];
	    UNIX_PIPE_DEVICE pipeDevice = (UNIX_PIPE_DEVICE) args[0];
	    while(1) {
	        UMF_MESSAGE message;
	        incomingQ->pop(message);

	        // construct header                               
	        UMF_CHUNK header = 0;
	        message->EncodeHeader((unsigned char *)&header);

                pipeDevice->Write((unsigned char *)&header, UMF_CHUNK_BYTES);

	        // write message data to pipe                                                     
	        // NOTE: hardware demarshaller expects chunk pattern to start from most       	    
                //       significant chunk and end at least significant chunk, so we will                  
	        //       send chunks in reverse order                                                               
                message->StartReverseExtract();
	        while (message->CanReverseExtract())
	        {
	 	    UMF_CHUNK chunk = message->ReverseExtractChunk();
		    pipeDevice->Write((unsigned char*)&chunk, sizeof(UMF_CHUNK));
	        }

	       // de-allocate message                                                                                 	
               delete message;
	    }
	}

        UMF_MESSAGE Read();             // blocking read
        UMF_MESSAGE TryRead();          // non-blocking read
        void        Write(UMF_MESSAGE); // write
        class tbb::concurrent_bounded_queue<UMF_MESSAGE> *GetWriteQ() { return &writeQ; }
};

#endif
