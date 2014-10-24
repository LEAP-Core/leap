class AreaGroupPath(object):

    def __init__(self, name, path):
        self.name = name
        self.path = path

    def __repr__(self):
        platformRepr = 'AreaGroupPath: ' + self.name + ' path: ' + str(self.path) 
        
        return platformRepr
