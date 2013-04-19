import sys
from code import *

class LIModule():
  
    def __init__(self, type, name):
        self.type = type
        self.name = name
        self.channels = []    
        self.chains = []    


    def __repr__(self):
        return "{" + self.name + ":" + self.type + ":" + ','.join(map(str, self.channels)) + ":" + ','.join(map(str, self.chains)) + "}"

    def addChannel(self, channel):
        self.channels += [channel]

    def addChain(self, chain):
        self.chains += [chain]
