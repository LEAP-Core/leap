import sys
import copy
from interface import *

class Vector(Interface):
    def __init__(self, type, name, members):
        Interface.__init__(self, type, name, members)


    def generateHierarchy(self, interfaceHandle, ident, topModule, ifcEnv):
        #interfaces don't know their name. this must be propagated.
        # First I let my children write down their definitions. Then I
        # bind them.
        for member in self.members:
            self.members[member].generateHierarchy(interfaceHandle, ident + '\t', topModule, ifcEnv)

        # now I can create my binding.
        interfaceHandle.write("//begin import vector " + self.name + "\n")
        interfaceHandle.write(ident + self.type + " " + self.getDefinition() + "= newVector;\n")
        for member in self.members:
            memberObj = self.members[member]
            interfaceHandle.write(self.getDefinition() + '[' + str(member) + '] =' +  memberObj.getDefinition() + ";\n")



