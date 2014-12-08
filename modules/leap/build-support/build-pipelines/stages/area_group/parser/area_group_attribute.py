class AreaGroupAttribute(object):

    def __init__(self, name, key, value):
        self.name = name
        self.key = key
        self.value = value

    def __repr__(self):
        platformRepr = 'AreaGroupAttribute: ' + self.name + ' key ' + str(self.key)  + ' -> ' + str(self.value) 
        
        return platformRepr
