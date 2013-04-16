import sys
import pygraph
from liModule import *
try:
    from pygraph.classes.digraph import digraph
except ImportError:
    # don't need to do anything
    print "\n"
    # print "Warning you should upgrade to pygraph 1.8"
import pygraph.algorithms.sorting


class LIGraph():
  
    def __init__(self, channels):
        
        self.modules = {}
        
        for channel in channels:
            # give channels unit weight
            channel.activity = 1
            if(not channel.modulename in self.modules):
                # for now, type and name are the same
                self.modules[channel.modulename] = LIModule(channel.modulename, channel.modulename)
       
            self.modules[channel.modulename].addChannel(channel)
            channel.module = self.modules[channel.modulename]

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
                #Ignore chains
                if(channel.isSource() and not channel.isChain()):
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


    # Should this move to liUtilities?
    def matchChannels(self):
        #all these for loops are overkill. We should have better algorithms
        for module in self.modules.values():
            for partnerModule in self.modules.values():
                # if we are the same module, skip
                if(module.name == partnerModule.name):
                    continue

                for channel in module.channels:
                    # ignore chains.  They get resolved later on physical mapping
                    if(channel.isChain() or channel.matched):
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
                    

                                            

        
