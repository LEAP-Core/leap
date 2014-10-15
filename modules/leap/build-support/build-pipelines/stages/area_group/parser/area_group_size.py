class AreaGroupSize(object):

    def __init__(self, name, xDimension, yDimension):
        self.name = name
        self.xDimension = xDimension
        self.yDimension = yDimension

    def __repr__(self):
        platformRepr = 'AreaGroupSize: ' + self.name + ' xDim ' + str(self.xDimension)  + ' yDim ' + str(self.yDimension) 
        
        return platformRepr
