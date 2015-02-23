import sys
import traceback
import pygraph
#import gv

from liModule import LIModule
from liChannel import LIChannel

try:
    from pygraph.classes.digraph import digraph
except ImportError:
    print "\n"
import pygraph.algorithms.sorting

DUMP_GRAPH_DEBUG = 0

class LIGraph():
  
    # connections are a mixture of chains and channels
    def __init__(self, connections):

        self.unmatchedChannels = False                    
        
        self.modules = {}
 
        for connection in connections:
            # give channels unit weight
            connection.activity = 1
            if (not connection.module_name in self.modules):
                # for now, type and name are the same
                if(DUMP_GRAPH_DEBUG):
                    print "Adding module, Found channel " + connection.name + " with module " + connection.module_name
                self.modules[connection.module_name] = LIModule(connection.module_name,\
                                                                connection.module_name)
       
            if (isinstance(connection, LIChannel)):
                self.modules[connection.module_name].addChannel(connection)
            else:
                self.modules[connection.module_name].addChain(connection)
 

        # let's match up all those connections
        self.matchGraphChannels()       

        # now that we have a dictionary, we can create a graph
        try:
            self.graph = pygraph.digraph() 
        except (NameError, AttributeError): 
            self.graph = digraph() 
      
        self.graph.add_nodes(self.modules.values())
        self.weights = {} # unfortunately pygraph does not support multiedges
    
        # add edges - for now all edges have unit weight
        for module in self.modules.values():
            for channel in module.channels:
                # depending on what we are doing with the graph,
                # unmatched channels may not be an error.  We will
                # instead mark the object in case the caller cares
                if (not (channel.matched or channel.optional)):
                    self.unmatchedChannels = True                    
                    continue
                # It is possible that optional channels do not have a match
                if (not channel.matched):
                    continue
                #Only add an edge if the channel is a source.
                if (channel.isSource()):
                    if (not self.graph.has_edge((module, channel.partnerModule))):
                        self.graph.add_edge((module, channel.partnerModule))
                        self.weights[(module, channel.partnerModule)] = channel.activity
                    else:
                        self.weights[(module, channel.partnerModule)] += channel.activity

    def id(self):
        for module in self.modules:
            self.modules[module].id()

    def __str__(self):        
        rep = '\nLIGraph{\n'
        for (name,module) in self.modules.items():
            rep += "\n\n"
            rep += name + ":\n"
            for channel in module.channels:
                partnerName = 'unassigned'
                if (channel.matched):
                    partnerName = channel.partnerModule.name
                rep += "Channel: " + channel.name + " <-> " + partnerName + "\n"
            for chain in module.chains:
                rep += "Chain: " + chain.name + "\n"
            rep += "Names " + str(module.chainNames) +"\n"
        rep += '\n}'

        rep += 'DETAILED:\n'

        for (name,module) in self.modules.items():
            rep += name + ":\n\n" + str(module) + "\n\n"
        
        rep += 'ENDDETAILED\n\n'

        return rep

    def __repr__(self):        
        rep = '{'
        for (name,module) in self.modules.items():
            rep += str(module)+"\n"
        return rep + '}'


    def getChannels(self):
        channels = []
        for (name,module) in self.modules.items():
            channels += module.channels
        return channels

    def getChains(self):
        chains = []
        for (name,module) in self.modules.items():
            chains += module.chains
        return chains


    # Should this move to liUtilities?
    def matchGraphChannels(self):
        #all these for loops are overkill. We should have better algorithms
        for module in self.modules.values():
            for partnerModule in self.modules.values():
                # if we are the same module, skip
                if (module.name != partnerModule.name):
                    self.matchChannels(module, partnerModule)

    # Match channels for a pair of modules
    def matchChannels(self, module, partnerModule):
        for channel in module.channels:
            # ignore previously matched channels
            if (channel.matched):
                continue
            for partnerChannel in partnerModule.channels:
                if (partnerChannel.matched):
                    continue
                if (channel.matches(partnerChannel)):
                    # a potential match
                    channel.partnerChannel = partnerChannel
                    channel.partnerModule = partnerModule
                    partnerChannel.partnerChannel = channel
                    partnerChannel.partnerModule = module
                    channel.matched = True
                    partnerChannel.matched = True


    # merge another LI Graph into this one.  
    def merge(self, otherGraphs):
        otherModules = []
        for otherGraph in otherGraphs:
            otherModules += otherGraph.modules.values()

        self.mergeModules(otherModules)

    def mergeModules(self, otherModules):

        # Should we make copies of modules here?  
        
        for module in otherModules:
            module.unmatch()
            # have we seen this module before? If so, this might be an error. 
            while (module.name in self.modules):
                #bail?
                print "Error: Merging platform modules.  We already have a module named " + module.name 
                exit(0)               


            self.modules[module.name] = module

        # let's match up all those connections
        self.matchGraphChannels()       

        self.graph.add_nodes(otherModules)
                    
        # add edges - for now all edges have unit weight
        for module in otherModules:
            for channel in module.channels:
                # depending on what we are doing with the graph,
                # unmatched channels may not be an error.  We will
                # instead mark the object in case the caller cares
                if (not (channel.matched or channel.optional)):
                    self.unmatchedChannels = True                    
                    continue

                # It is possible that optional channels do not have a match
                if (not channel.matched):
                    continue

                #Only add an edge if the channel is a source.
                if (channel.isSource()):
                    if (not self.graph.has_edge((channel.module, channel.partnerModule))):
                        self.graph.add_edge((module, channel.partnerModule))
                        self.weights[(module, channel.partnerModule)] = channel.activity
                    else:
                        self.weights[(module, channel.partnerModule)] += channel.activity
         

    def trimOptionalChannels(self):
        for module in self.modules.values():
            module.trimOptionalChannels()

    def checkUnmatchedChannels(self):
        unmatched = False
        for module in self.modules.values():
            unmatched = unmatched or module.checkUnmatchedChannels()
    
        return unmatched

    # Checks to see that all internal pointers are correct.
    def healthCheck(self):
        for module in self.modules.values():
            for channel in module.channels:
                partnerModuleId = id(channel.partnerModule)
                partnerChannelId = id(channel.partnerChannel)
                partnerModuleIdLocal = id(self.modules[channel.partnerModule.name])
                partnerChannelIdLocal = id(self.modules[channel.partnerModule.name].channelNames[channel.name])
                if(partnerModuleId != partnerModuleIdLocal):
                    print "Warning, "  + channel.partnerModule.name + " pointer is not correct"
                if(partnerChannelId != partnerChannelIdLocal):
                    print "Warning, "  + channel.name + " pointer is not correct"

    def dumpUnmatchedChannels(self):
        for line in traceback.format_stack():
            print line.strip()
        for module in self.modules.values():
            module.dumpUnmatchedChannels()
    
#    def dumpDot(self, filename):
#        dot = pygraph.readwrite.dot.write(self.graph)
#        gvv = gv.readstring(dot)
#        gv.layout(gvv,'dot')
#        gv.render(gvv,'png',filename)                                                

        
