import sys
from code import *

class LIModule():
  
    def __init__(self, type, name):
        self.type = type
        self.name = name
        self.channels = []    
        self.chains = []    

        # The number of exported rules is a metric useful as a heuristic for
        # deciding where to emit synthesis boundaries instead of just Bluespec
        # modules.  A module that is, itself, a synthesis boundary exports
        # no rules.  A module that is not a synthesis boundary exports a
        # number of rules equal to the number of local rules for channels
        # plus the number of exported rules of its children.
        self.numExportedRules = 0

    def __repr__(self):
        return "{" + self.name + ":" + self.type + ":" + ','.join(map(str, self.channels)) + ":" + ','.join(map(str, self.chains)) + "}"

    def addChannel(self, channel):
        self.channels += [channel]

    def addChain(self, chain):
        self.chains += [chain]

    def setNumExportedRules(self, n):
        self.numExportedRules = n
