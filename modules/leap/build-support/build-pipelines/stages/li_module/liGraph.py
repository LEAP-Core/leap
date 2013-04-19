import sys
import pygraph
from liModule import *
from liChannel import *
from liChain import *
try:
    from pygraph.classes.digraph import digraph
except ImportError:
    # don't need to do anything
    print "\n"
    # print "Warning you should upgrade to pygraph 1.8"
import pygraph.algorithms.sorting


class LIGraph():
  
    # connections are a mixture of chains and channels
    def __init__(self, connections):
        
        self.modules = {}
        
        for connection in connections:
            # give channels unit weight
            connection.activity = 1
            if(not connection.module_name in self.modules):
                # for now, type and name are the same
                self.modules[connection.module_name] = LIModule(connection.module_name, connection.module_name)
       
            if(isinstance(connection,LIChannel)):
                self.modules[connection.module_name].addChannel(connection)
            else:
                self.modules[connection.module_name].addChain(connection)
 
            connection.module = self.modules[connection.module_name]

        # let's match up all those connections
        self.matchChannels()       

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
                # depending on what we are doing with the graph, unmatched channels 
                # may not be an error.  We will instead mark the object in case 
                # the caller cares 
                if(not (channel.matched or channel.optional)):
                    print "Warning: Unmatched channel " + str(channel)
                    self.unmatchedChannels = True                    
                    continue
                # It is possible that optional channels do not have a match
                if(not channel.matched):
                    continue
                #Only add an edge if the channel is a source.
                if(channel.isSource()):
                    if(not self.graph.has_edge((module, channel.partnerModule))):
                        self.graph.add_edge((module, channel.partnerModule))
                        self.weights[(module, channel.partnerModule)] = channel.activity
                    else:
                        self.weights[(module, channel.partnerModule)] += channel.activity

    def __str__(self):        
        rep = '{'
        for (name,module) in self.modules.items():
            rep += name + ":\n"
            for channel in module.channels:
                partnerName = 'unassigned'
                if(channel.matched):
                    partnerName = channel.partnerModule.name
                rep += channel.name + " <-> " + partnerName + "\n"
        return rep + '}'


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
    def matchChannels(self):
        #all these for loops are overkill. We should have better algorithms
        for module in self.modules.values():
            for partnerModule in self.modules.values():
                # if we are the same module, skip
                if(module.name == partnerModule.name):
                    continue
                for channel in module.channels:
                    # ignore previously matched channels
                    if(channel.matched):
                        continue
                    for partnerChannel in partnerModule.channels:
                        if(partnerChannel.matched):
                            continue
                        if(channel.matches(partnerChannel)): # a potential match
                            channel.partnerChannel = partnerChannel
                            channel.partnerModule = partnerModule                       
                            partnerChannel.partnerChannel = channel
                            partnerChannel.partnerModule = module                       
                            channel.matched = True
                            partnerChannel.matched = True
                    

                                            

        
