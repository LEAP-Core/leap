import sys
from code import *

class LIModule():
  
    def __init__(self, type, name):
        self.type = type
        self.name = name
        self.channels = []    


    def __repr__(self):
        return "{" + self.name + ":" + self.type + ":" + ','.join(map(str, self.channels)) + "}"

  
    def addChannel(self, channel):
        self.channels += [channel]
