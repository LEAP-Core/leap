#include "li-base.h"

LI_CHANNEL_MATCHER_CLASS LI_CHANNEL_MATCHER_CLASS::liMatcher;
UINT32 LI_CHANNEL_MATCHER_CLASS::initCounter;

LI_CHANNEL_MATCHER_CLASS::LI_CHANNEL_MATCHER_CLASS()
{
    initialize();
}
  
void LI_CHANNEL_MATCHER_CLASS::initialize()
{
    // C++ guarantees all static values are zeroed before 
    // programmer dynamic initialization begins
    if(initCounter == 0) {
        sendMap = new std::map<string,LI_HALF_CHANNEL>(); 
        recvMap = new std::map<string,LI_HALF_CHANNEL>(); 
        matcherMutex = new std::mutex();
        initCounter++;
    }

}
  
// Some of this registration code might be refactored. 
LI_HALF_CHANNEL LI_CHANNEL_MATCHER_CLASS::registerSend(LI_HALF_CHANNEL send) 
{ 
    initialize();
    unique_lock<std::mutex> matcherLock( *matcherMutex );

    std::map<string,LI_HALF_CHANNEL>::iterator recvMatch = recvMap->find(send->GetName());
    std::map<string,LI_HALF_CHANNEL>::iterator sendMatch = sendMap->find(send->GetName());

    // Have we seen a channel named like this before?
    if(sendMatch != sendMap->end())
    {
        cerr << "Duplicate send channel named " << send->GetName() << endl;
        exit(1);
    }    

    // Check for a match in the recvMap    
    if(recvMatch != recvMap->end()) 
    {
        // Found a match
        // Check its type 
        if((*recvMatch).second->GetType() != send->GetType())
	{
	    cerr << "Exiting: Half channels named " << send->GetName() << " had types " << send->GetType() << " and " << (*recvMatch).second->GetType() << endl;
	    exit(1);
	}

        // Time will tell whether allowing the matcher to mutate the matchee is a good idea.
        LI_HALF_CHANNEL retVal = (*recvMatch).second;
        recvMap->erase(recvMatch);
        return retVal;  
    } 

    (*sendMap)[send->GetName()] = send;
    return NULL; // No match
}

LI_HALF_CHANNEL LI_CHANNEL_MATCHER_CLASS::registerRecv(LI_HALF_CHANNEL recv) 
{
    initialize();
    unique_lock<std::mutex> matcherLock( *matcherMutex );

    std::map<string,LI_HALF_CHANNEL>::iterator recvMatch = recvMap->find(recv->GetName());
    std::map<string,LI_HALF_CHANNEL>::iterator sendMatch = sendMap->find(recv->GetName());

    // Have we seen a channel named like this before?
    if(recvMatch != recvMap->end())
    {
        cerr << "Duplicate recv channel named " << recv->GetName() << endl;
        exit(1);
    }    

    // Check for a match in the recvMap    
    if(sendMatch != sendMap->end()) 
    {
        // Found a match
        // Check its type 
        if((*sendMatch).second->GetType() != recv->GetType())
	{
  	    cerr << "Exiting Half channels named " << recv->GetName() << " had types " << recv->GetType() << " and " << (*sendMatch).second->GetType() << endl;
            exit(1);
	}

        // Time will tell whether allowing the matcher to mutate the matchee is a good idea.
        LI_HALF_CHANNEL retVal = (*sendMatch).second;
        sendMap->erase(sendMatch);

        return retVal;  
    } 

    (*recvMap)[recv->GetName()] = recv;
    return NULL; // No match

}

LI_HALF_CHANNEL_CLASS::LI_HALF_CHANNEL_CLASS(string nameInit, string typeInit):
  name(nameInit),
  type(typeInit)
{

}


 

