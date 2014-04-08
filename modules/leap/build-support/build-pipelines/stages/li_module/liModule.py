import sys
from code import *

class LIModule():
  
    def __init__(self, type, name):
        self.type = type
        self.name = name
        self.channels = []    
        self.chains = []    
        self.chainNames = {}

        self.attributes = {}
        
        # The module will also include references to the object code
        # necessary to build the module. This enables us to cache
        # compilation results in the multiple stage LIM flow

        self.objectCache = {}

        # The number of exported rules is a metric useful as a heuristic for
        # deciding where to emit synthesis boundaries instead of just Bluespec
        # modules.  A module that is, itself, a synthesis boundary exports
        # no rules.  A module that is not a synthesis boundary exports a
        # number of rules equal to the number of local rules for channels
        # plus the number of exported rules of its children.
        self.numExportedRules = 0

    def __repr__(self):
        return "{ MODULE:" + self.name + ":" + self.type + ":\nChannels:" + ',\n'.join(map(str, self.channels)) + ":\nChains:" + ',\n'.join(map(str, self.chains)) + "\nChainsNames:" + ',\n'.join(map(str, self.chainNames.keys())) + "}"

    def addChannel(self, channel):
        channelCopy = channel.copy()
        channelCopy.module = self # You belong to me.
        self.channels.append(channelCopy)

    # it is nonsensical to have more than one instance of the same
    # chain, so we drop extraneous chain references. 
    def addChain(self, chain):
        if(not chain.name in self.chainNames):          
            chainCopy = chain.copy()
            chainCopy.module = self
            self.chains.append(chainCopy)
            self.chainNames[chain.name] = chain.name
        else:
            print "Warning, dropping spurious chain: " + chain.name + " in module " + self.name + "\n"

    def deleteChain(self, chain):
        del self.chainNames[chain]
        self.chains = [memberChain for memberChain in self.chains if memberChain.name != chain]

    def setNumExportedRules(self, n):
        self.numExportedRules = n
 
    def putObjectCode(self, key, value):
        if (key in self.objectCache):
            if (value is list):
                self.objectCache[key] += value
            else:
                self.objectCache[key].append(value)
        else: 
            if (value is list):
                self.objectCache[key] = value
            else:
                self.objectCache[key] = [value]

    def getObjectCode(self, key):
        if(key in self.objectCache):
            return self.objectCache[key]
        else:
            return []

    def putAttribute(self, key, value):
        self.attributes[key] = value
        

    def getAttribute(self, key):
        try:
            return self.attributes[key]
        except KeyError:
            print "Module " + self.name + " does not have attribute " + key + "\n"
            exit(0)


# These functions make it easier to decide which modules connect to
# to one another. They are mostly used in the LIM compiler.
def channelsByPartner(liModule, channelPartnerModule):
    return [channel for channel in liModule.channels if (channel.partnerModule.name == channelPartnerModule)]

def ingressChainsByPartner(liModule, chainPartnerModule):
    for chain in liModule.chains:
        if(isinstance(chain.sourcePartnerModule, str)):
            print "Warning : " + str(chain) + "\n"
    return [chain for chain in liModule.chains if(chain.sourcePartnerModule.name == chainPartnerModule)]

def egressChainsByPartner(liModule, chainPartnerModule):
    for chain in liModule.chains:
        if(isinstance(chain.sinkPartnerModule, str)):
            print "Warning : " + str(chain) + "\n"
    return [chain for chain in liModule.chains if(chain.sinkPartnerModule.name == chainPartnerModule)]

def egressChannelsByPartner(liModule, channelPartnerModule):
    return [channel for channel in channelsByPartner(liModule, channelPartnerModule) if(channel.isSource())]

def ingressChannelsByPartner(liModule, channelPartnerModule):
    return [channel for channel in channelsByPartner(liModule, channelPartnerModule) if(not channel.isSource())]


