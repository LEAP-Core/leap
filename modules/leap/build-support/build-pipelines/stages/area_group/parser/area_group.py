# A data structure representing an area group. 

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
        
        # Coordinates defining the bounding box for the area group. 
        self.upperRight = None
        self.lowerLeft = None

        self.attributes = {}

    def __repr__(self):
        parent = 'None'
        if(not (self.parent is None)):
            parent = self.parent.name            

        platformRepr = 'AreaGroup: ' + self.name + ' Path: ' + str(self.sourcePath) + ' Area: ' + str(self.area) + ' XLoc: ' + str(self.xLoc) +  ' YLoc: ' + str(self.yLoc) + ' xDim ' + str(self.xDimension)  + ' yDim ' + str(self.yDimension) +  ' Parent: ' + parent
        
        return platformRepr
