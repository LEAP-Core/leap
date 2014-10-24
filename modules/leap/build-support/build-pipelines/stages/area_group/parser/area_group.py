class AreaGroup(object):

    def __init__(self, name, sourcePath):
        self.name = name
        self.sourcePath = sourcePath         
        self.children = {} # Gets filled in later. 
        self.area = None
        self.parent = None
        
        # Aspect ratio. Must multiply to 1. 
        self.xDimension = None
        self.yDimension = None

        # Location of area group centroid.
        self.xLoc = None
        self.yLoc = None
        

    def __repr__(self):
        platformRepr = 'AreaGroup: ' + self.name + ' Path: ' + str(self.sourcePath) + ' Area: ' + str(self.area) + ' XLoc: ' + str(self.xLoc) +  ' YLoc: ' + str(self.yLoc) + ' xDim ' + str(self.xDimension)  + ' yDim ' + str(self.yDimension) 
        
        return platformRepr
