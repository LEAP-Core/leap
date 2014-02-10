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

#include <stdio.h>
#include <unistd.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <time.h>
#include <iostream>
#include "awb/provides/channelio.h"
#include "awb/provides/li_base_types.h"
#include "awb/provides/multifpga_switch.h"

using namespace std;

// ============================================
//                 LI Channel Base Classes                
// ============================================



// ============================================
//                 Channel I/O                 
// ============================================

// constructor -- maybe it should be virtual?
CHANNELIO_BASE_CLASS::CHANNELIO_BASE_CLASS(
    PLATFORMS_MODULE parent,
    PHYSICAL_DEVICES devices) :
    PLATFORMS_MODULE_CLASS(parent)   
{
    physicalDevices = devices;
}

// destructor 
CHANNELIO_BASE_CLASS::~CHANNELIO_BASE_CLASS()
{
}


// Specialized marshalling logic for handling the UMF_MESSAGE type.

template<> void MARSHALLED_LI_CHANNEL_IN_CLASS<UMF_MESSAGE>::pushUMF(UMF_MESSAGE &incoming) 
{
    // Although the input queue has type UMF message, 
    // We can't directly do this write.  We need to translate the base message type
    // into the RRR style umf message.
    // first decode header
    UMF_MESSAGE element = new UMF_MESSAGE_CLASS();
    // This is so dirty, I can't believe that I'm writing it. 
    *((UMF_CHUNK*) element) = incoming->ExtractChunk();

    channelPartner->push(element); // Stuff this in our input Q.

    // Handle flow control.  
    // this code is common to all channels and should be moved up in the class
    // hierarchy.
    // Our flowcontrol variable appears not to need to be atomic.
    // UINT64 tempCredits = flowcontrolCredits + ((1+appends) * 3);
    acquireCredits(3);

    if(DEBUG_CHANNELIO) 
    {
        cout << "Channel is  " << this << endl;        
    }

    freeCredits(incoming->GetServiceID());

    if(DEBUG_CHANNELIO) 
    {
        cout << "****Channel " << this->name << " incoming message is complete" << endl; 
    }

    delete incoming; // We've translated the message, so get rid of it...

}

// This push is the push inherited from LI_CHANNEL_SEND.  It is user-facing
template<> void MARSHALLED_LI_CHANNEL_OUT_CLASS<UMF_MESSAGE>::push(UMF_MESSAGE &element) 
{
    // Check for space in flow control 
    // RRR allows small size/packed bytes.  We account for that here...
    // TODO: These values are probably constant. We should store as a static class variable.
    UINT32 extraChunk = ((element->GetLength()%sizeof(UMF_CHUNK)) != 0) ? 1 : 0; 
    UINT32 messageLength = (element->GetLength()/sizeof(UMF_CHUNK) + extraChunk + 1) * 3;  // Each chunk takes a header plus one bit for encoding?

    if(DEBUG_CHANNELIO) 
    {
        cout << endl << "****Channel "<< this->name << " Sends message " << endl;               
        cout << endl << "Base Message length "<< dec << (UINT32) (element->GetLength()) << endl;  
        cout << "Message Credits "<< dec << messageLength << endl;
        cout << "Channel ID "<< dec << this->channelID << endl;
    }
  

    acquireCredits(messageLength);

    // Send header first
    {
        UMF_CHUNK baseHeader = element->EncodeHeader();  
        UMF_MESSAGE outMesg = factory->createUMFMessage();
        outMesg->SetLength(2 * sizeof(UMF_CHUNK)); 
        outMesg->SetServiceID(this->channelID);
	outMesg->AppendChunk(0);
	outMesg->AppendChunk(baseHeader);
        outputQ->push(outMesg);
    }

    element->StartReverseExtract();
    while (element->CanReverseExtract())
    {
        UMF_CHUNK chunk = element->ReverseExtractChunk();
        UMF_MESSAGE outMesg = factory->createUMFMessage();

        if(DEBUG_CHANNELIO) 
        {
            cout << endl <<"Sending payload chunk " << this-> name;
            cout << " Factory ptr: " << factory << " Mesg ptr: " << outMesg << endl;
	}

        outMesg->SetLength(2 * sizeof(UMF_CHUNK));

        if(DEBUG_CHANNELIO) 
        {
            cout << "Reading Channel "<< this << endl;
            cout << "Name "<< this->name << endl;
            cout << "ID " << this->channelID << endl;
	}

        outMesg->SetServiceID(this->channelID);
	outMesg->AppendChunk(1);  
        outMesg->AppendChunk(chunk);

        if(DEBUG_CHANNELIO) 
        {
            cout << "Pushing message to output Q" << endl;
	}

        outputQ->push(outMesg);
    } 

    if(DEBUG_CHANNELIO) 
    {
        cout << endl << "****Channel "<< this->name << " Send message complete" << endl;               
    }

    UMF_MESSAGE elementCopy = element;
    delete elementCopy; // Should we delete here?
}


// Specialized marshalling logic for handling the UINT64 type.

template<> void MARSHALLED_LI_CHANNEL_IN_CLASS<UINT128>::pushUMF(UMF_MESSAGE &incoming) 
{
    // Although the input queue has type UMF message, 
    UINT128 element;
    UINT8 appends = 0, rotation;
    UMF_CHUNK rotatedChunk, chunk1, chunk2;

    element = incoming->ExtractChunk();

    channelPartner->push(element);
    
    // Handle flow control.  
    // this code is common to all channels and should be moved up in the class
    // hierarchy.
    // Our flowcontrol variable appears not to need to be atomic.
    acquireCredits(2);

    if(DEBUG_CHANNELIO) 
    {
        cout << "(UINT128) Channel is  " << this << endl;
        
    }

    freeCredits(incoming->GetServiceID());

    if(DEBUG_CHANNELIO) 
    {
        cout << "****Channel " << this->name << " incoming message is complete" << endl; 
    }

    delete incoming; // We've translated the message, so get rid of it...
    
}


// This push is the push inherited from LI_CHANNEL_SEND.  It is user-facing
template<> void MARSHALLED_LI_CHANNEL_OUT_CLASS<UINT128>::push(UINT128 &element) 
{
    // Check for space in flow control 
    // RRR allows small size/packed bytes.  We account for that here...
   
    acquireCredits(2);

    {
        UMF_MESSAGE outMesg = factory->createUMFMessage();
        outMesg->SetLength(sizeof(UINT128)); 
        outMesg->SetServiceID(this->channelID);
	outMesg->AppendChunk(element);
        outputQ->push(outMesg);
    }

}

// The following routines implement data transfer by way of
// route-through channels.  These channels copy data between platforms
// without attempting to translate the data payload However, the
// headers must by translated. 

// This push is the push inherited from LI_CHANNEL_SEND. It is called
// directly by the ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS.  This function
// simply recodes the packet header and retransmits.  It also handles
// flowcontrol, however, this flowcontrol needs to be improved as
// noted below.

void ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS::push(UMF_MESSAGE &outMesg) 
{

    // Software expects encoding in terms of bytes while the credit scheme speaks in terms of chunks 
    UINT32 messageLengthBytes = outMesg->GetLength(); 
    UINT32 messageLengthChunks = 1 + ((outMesg->GetLength()) / sizeof(UMF_CHUNK));  // Each chunk takes a header plus one bit for encoding?


    if(DEBUG_CHANNELIO) 
    {
        cout << endl << "****Outbound Channel "<< this->name << " Sends message " << endl;               
        cout << endl << "Base Message length "<< dec << (UINT32) (outMesg->GetLength()) << endl;  
        cout << "UMF_CHUNK (bytes) " << sizeof(UMF_CHUNK) << endl;
        cout << "Message Length (bytes) "<< dec << messageLengthBytes << endl;
	cout << "Message Credits (chunks) "<< dec << messageLengthChunks << endl;
        cout << "Channel ID "<< dec << this->channelID << endl;
    }

    // For now we will allow the system to deadlock here. What is really needed is an 
    // means of back pressure all the way to the incoming route through. 
    // TODO: Fix this deadlock with better backpressure cooperation among threads

    acquireCredits(messageLengthChunks);

    // Recode message for the outbound link and send
    {
        outMesg->SetServiceID(this->channelID);
        outputQ->push(outMesg);
    }

    if(DEBUG_CHANNELIO) 
    {
        cout << endl << "****Outbound Route-through Channel "<< this->name << " message complete" << endl;            }
}


// This function handles incoming UMF packets.  Currently, the
// function simply copies the message through to its partner.  In the
// future, some better handshaking will be necessary to accept
// messages.

void ROUTE_THROUGH_LI_CHANNEL_IN_CLASS::pushUMF(UMF_MESSAGE &inMesg) 
{

    // Software expects encoding in terms of bytes while the credit scheme speaks in terms of chunks 
    UINT32 messageLengthBytes = inMesg->GetLength();  // Length of message already framed in bytes
    UINT32 messageLengthChunks = 1 + ((inMesg->GetLength()) / sizeof(UMF_CHUNK));  // Each chunk takes a header plus one bit for encoding?

    if(DEBUG_CHANNELIO) 
    {
        cout << "Channel is  " << this << endl;        
        cout << this->name << " route through acquiring credit " << messageLengthChunks << endl;
    }

    acquireCredits(messageLengthChunks);

    // We need to push the message directly to the the outbound queue.
    // If the outbound queue doesn't have credit, in theory this push
    // will block.  Currently this case is unhandled, potentially
    // leading to deadlocks, since the main handler threads are the
    // ones getting blocked.  A better solution needs to check
    // channelPartner's status and store messages that will be unsent.  

    channelPartner->push(inMesg); 

    freeCredits(inMesg->GetServiceID());

    if(DEBUG_CHANNELIO) 
    {
        cout << "****In Route-through Channel " << this->name << " message is complete" << endl; 
    }
    
    // Unlike the marshalled LI channels, we do not delete the
    // outbound message. channelPartner owns the message and is
    // responsible for deletion.

}
