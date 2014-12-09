from li_module import LIModule

class TreeModule(LIModule):
  
    def __init__(self, type, name):
        LIModule.__init__(self, type, name)
        self.children = []
        self.seperator = None

