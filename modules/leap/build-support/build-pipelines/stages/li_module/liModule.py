import sys
import copy

from code import *


class LIModule():
  
    def __init__(self, type, name):
        self.type = type
        self.name = name
        self.channels = []    
        self.chains = []    
        self.chainNames = {}
        self.channelNames = {}    

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

    def id(self):
        print "LIModule: " + self.name + ":"  + str(id(self)) + ':' + str(id(self.attributes))  
        for channel in self.channels:
            partnerID = str(id(channel.partnerModule))
            partnerName = 'unassigned'
            if(isinstance(channel.partnerModule, LIModule)):
                partnerName = channel.partnerModule.name
            print "\tchannel " + channel.name + ':' + str(id(channel)) + ' partner ' + partnerName + ':' + partnerID
        

    def __repr__(self):
        return "{ MODULE:" + self.name + ":" + self.type + ":\nChannels:" + ',\n'.join(map(str, self.channels)) + ":\nChains:" + ',\n'.join(map(str, self.chains)) + "\nChainsNames:" + ',\n'.join(map(str, self.chainNames.keys())) + "\nAttributes: " + str(self.attributes) + "}\n"



    def copy(self):
        moduleCopy = LIModule(self.type, self.name)
        for channel in self.channels:
            moduleCopy.addChannel(channel.copy())
        for chain in self.chains:
            moduleCopy.addChain(chain.copy())
        moduleCopy.numExportedRules = self.numExportedRules
        moduleCopy.attributes = copy.deepcopy(self.attributes)
        moduleCopy.objectCache = copy.deepcopy(self.objectCache)
        return moduleCopy  

    def addChannel(self, channel):
        channelCopy = channel.copy()
        channelCopy.module = self # You belong to me. 
        self.channels.append(channelCopy)
        self.channelNames[channelCopy.name] = channelCopy

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
            if (isinstance(value,list)):
                self.objectCache[key] += value
            else:
                self.objectCache[key].append(value)
        else: 
            if (isinstance(value,list)):
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
        if(key in self.attributes):
            return self.attributes[key]
        else:
            return None


    def trimOptionalChannels(self):
        self.channels = [channel for channel in self.channels if (channel.matched or not channel.optional)]

    def checkUnmatchedChannels(self):
        for channel in self.channels:
            if(not channel.matched):
                return True
        return False

    def dumpUnmatchedChannels(self):
        for channel in self.channels:
            if(not channel.matched):
                print str(channel)



# These functions make it easier to decide which modules connect to
# to one another. They are mostly used in the LIM compiler.
def channelsByPartner(liModule, channelPartnerModule):
    for channel in liModule.channels:
        if(isinstance(channel.partnerModule, str)): 
            print "Channel " + channel.name + " is " + channel.partnerModule
        
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

def generateSynthWrapper(liModule, synth_handle):
    synth_handle.write("//Generated by liModule.py\n")
    synth_handle.write("`ifndef BUILD_" + str(liModule.name) +  "_WRAPPER\n") # these may not be needed
    synth_handle.write("`define BUILD_" + str(liModule.name) + "_WRAPPER\n")
    synth_handle.write('import Vector::*;\n')
    synth_handle.write('`include "asim/provides/smart_synth_boundaries.bsh"\n')
    synth_handle.write('`include "asim/provides/soft_connections.bsh"\n')    
    synth_handle.write('import ' + liModule.name + '_Wrapper::*;\n')        
    synth_handle.write("\n\nmodule [Connected_Module] " + liModule.name +"();\n")

    synth_handle.write("    let mod <- liftModule(mk_" + liModule.name + '_Wrapper' + "());\n")
    synth_handle.write("    let connections = tpl_1(mod.services);\n")

    # these strings should probably made functions in the
    # liChannel code
    for channel in liModule.channels:
        ch_reg_stmt = 'registerRecv'
        ch_type = 'LOGICAL_RECV_INFO'
        ch_src = 'incoming'
        if (channel.isSource()):
            ch_reg_stmt = 'registerSend'
            ch_type = 'LOGICAL_SEND_INFO'
            ch_src = 'outgoing'

        synth_handle.write('    ' + ch_reg_stmt + '("' + channel.name + '", ' + ch_type +\
                        ' { logicalType: "' + channel.raw_type +\
                        '", optional: ' +\
                        str(channel.optional) + ', ' + ch_src + ': connections.' + ch_src +'[' +\
                        str(channel.module_idx) + '], bitWidth:' + str(channel.bitwidth) +\
                        ', moduleName: "' + channel.module_name + '"});\n')   

    for chain in liModule.chains:
        synth_handle.write('    registerChain(LOGICAL_CHAIN_INFO { logicalName: "' +\
                        chain.name + '", logicalType: "' + chain.raw_type +\
                        '", incoming: connections.chains[' + str(chain.module_idx) +\
                        '].incoming, outgoing: connections.chains[' + str(chain.module_idx) +\
                        '].outgoing, bitWidth:' + str(chain.bitwidth) +\
                        ', moduleNameIncoming: "' + chain.module_name +\
                        '",  moduleNameOutgoing: "' + chain.module_name + '"});\n')   

    synth_handle.write("endmodule\n")
    synth_handle.write("`endif\n")

def generateConnectionBSH(liModule, bsh_handle):
    send = 0
    recv = 0
   
    for channel in liModule.channels:
        if (channel.isSource()):
            send += 1
        else:
            recv += 1
    chains = len(liModule.chains)

    bsh_handle.write("//Generated by liModule.py\n")
    bsh_handle.write("`ifndef CON_RECV_" + liModule.name + "\n")
    bsh_handle.write("`define CON_RECV_" + liModule.name + " " + str(recv) + "\n")
    bsh_handle.write("`endif\n")

    bsh_handle.write("`ifndef CON_SEND_" + liModule.name + "\n")
    bsh_handle.write("`define CON_SEND_" + liModule.name + " " + str(send) + "\n")
    bsh_handle.write("`endif\n")
    bsh_handle.write("`ifndef CON_RECV_MULTI_" + liModule.name + "\n")
    bsh_handle.write("`define CON_RECV_MULTI_" + liModule.name + " 0\n")
    bsh_handle.write("`endif\n")

    bsh_handle.write("`ifndef CHAINS_" + liModule.name + "\n")
    bsh_handle.write("`define CHAINS_" + liModule.name + " " + str(chains) + "\n")
    bsh_handle.write("`endif\n")

    bsh_handle.write("`ifndef CON_SEND_MULTI_" + liModule.name + "\n")
    bsh_handle.write("`define CON_SEND_MULTI_" + liModule.name + " 0\n")
    bsh_handle.write("`endif\n")
        



