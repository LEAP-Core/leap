from li_module import *

class TreeModule(LIModule):
  
    def __init__(self, type, name):
        LIModule.__init__(self, type, name)
        self.children = []
        self.seperator = None

