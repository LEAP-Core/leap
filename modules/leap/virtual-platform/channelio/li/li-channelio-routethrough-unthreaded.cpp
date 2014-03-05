//
// Copyright (C) 2014 Intel Corporation
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
        cout << endl << "****Outbound Route-through Channel "<< this->name << " message complete" << endl;            
    }
}

// Try push does a push, if credits can be allocated.  Otherwise, 

bool ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS::tryPush(UMF_MESSAGE &outMesg) 
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

    if(tryAcquireCredits(messageLengthChunks))
    {
        outMesg->SetServiceID(this->channelID);
        outputQ->push(outMesg);
        return true;
    }

    return false;
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
        cout << "Channel " << this->name << " is  " << this << endl;
        inMesg->Print(cout);
        cout << this->name << " route through acquiring credit " << messageLengthChunks << endl;
    }

    // This technically frees our credits.
    

    // We need to push the message directly to the the outbound queue.
    // If the outbound queue doesn't have credit, in theory this push
    // will block.  Currently this case is unhandled, potentially
    // leading to deadlocks, since the main handler threads are the
    // ones getting blocked.  A better solution needs to check
    // channelPartner's status and store messages that will be unsent.  
    
    unique_lock<std::mutex> flowcontrolLock(msgBufferMutex);
    
    // If msgBuffer is empty, we should try to send.  If not empty,
    // then the fifo is full and we are guaranteed that the partner
    // will try to send upon reception of flow control.
    if (msgBuffer.empty()) 
    { 
        UINT32 messageLengthBytes = inMesg->GetLength();  // Length of message already framed in bytes
        UINT32 messageLengthChunks = 1 + ((inMesg->GetLength()) / sizeof(UMF_CHUNK));  // Each message has a header
        // Must get ID before sending to partner.  Partner may recode header.       
        UINT32 serviceID = inMesg->GetServiceID(); 
        if(((ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS*)channelPartner)->tryPush(inMesg)) 
        {
            acquireCredits(messageLengthChunks);
            freeCredits(serviceID);
        }      
        else 
	{
	    // No dice, try to send later. 
            msgBuffer.push(inMesg);
	}
    }
    else
    {
        msgBuffer.push(inMesg);
    }

    if(DEBUG_CHANNELIO) 
    {
        cout << "****In Route-through Channel " << this->name << " message is complete" << endl; 
    }
    
    // Unlike the marshalled LI channels, we do not delete the
    // outbound message. channelPartner owns the message and is
    // responsible for deletion.

}

void ROUTE_THROUGH_LI_CHANNEL_IN_CLASS::clearMsgQ()
{
    // Lock message Q
    unique_lock<std::mutex> flowcontrolLock(msgBufferMutex);

    // try to send data while data is available
    while (!msgBuffer.empty()) 
    {
        UMF_MESSAGE inMesg = msgBuffer.front();
        UINT32 messageLengthBytes = inMesg->GetLength();  // Length of message already framed in bytes
        UINT32 messageLengthChunks = 1 + ((inMesg->GetLength()) / sizeof(UMF_CHUNK));  // Each message has a header

        // Must get message before sending to partner.  Partner may recode header.      
        UINT32 serviceID = inMesg->GetServiceID(); 
        if (((ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS*)channelPartner)->tryPush(inMesg)) // do not touch inMesg after this call. Partner will recode header.cd 
	{    
   	    // fix up incoming channel credit
            acquireCredits(messageLengthChunks);
            freeCredits(serviceID);
            msgBuffer.pop();
	}
        else
	{
  	    // No more credit
	    return; 
	}
    }
    // No more messages
    return;
}


// Since the route-through class has special properties. Actually, I
// think all channel classes have these properties, so this
// implementation might extend to send/recv pairs also.  
void ROUTE_THROUGH_LI_CHANNEL_OUT_CLASS::freeCredits(UINT32 credits) 
{
    // we could probably have a templatized version of this
    // class/function which does not involve a lock, since
    // route-throughs already have a lock. 
    FLOWCONTROL_LI_CHANNEL_OUT_CLASS::freeCredits(credits);
    ((ROUTE_THROUGH_LI_CHANNEL_IN_CLASS*)channelPartner)->clearMsgQ();
}
