import sys
import copy


class Method():
  
    def __init__(self, name, returnType, attributes):
        self.name = name
        self.returnType = returnType
        self.attributes = attributes

    def generateImportInterface(self, interfaceHandle, namePrefix=''):
        #interfaces don't know their name. this must be propagated.
        argBindings = []
        print "Examining Method " + namePrefix
        for arg in self.attributes['args']:
            argBindings.append(arg[0] + ' ' + arg[1])
            
        interfaceHandle.write('method ' + self.returnType + ' ' + namePrefix + '(' + ','.join(argBindings) + ');\n')
        self.attributes['namePrefix'] = namePrefix

    def generateImport(self, interfaceHandle):
        # set method defaults.
        clock = ""
        reset = ""
        args = ""
        ready = ""
        enable = ""
        result = ""

        # Action methods must have an enable defined. 
        if(self.returnType == 'Action'):
            enable = "enable((*inhigh*) en_" + self.attributes['namePrefix'] + ")"

        #fill in non-default methods. clock and reset can be default,
        #in which case, we should not emit anything.
        if(self.attributes['clock'] != '' and self.attributes['clock'] != 'default_clock'):
            clock = "clocked_by(" + self.attributes['clock'] + ")"

        if(self.attributes['reset'] != '' and self.attributes['reset'] != 'default_reset'):
            reset = "reset_by(" + self.attributes['reset'] + ")"

        if(self.attributes['ready'] != ''):
            ready = "ready(" + self.attributes['ready'] + ")"

        if(self.attributes['enable'] != ''):
            enable = "enable(" + self.attributes['enable'] + ")"

        if(self.attributes['result'] != ''):
            result = self.attributes['result']

        args = ",".join(map(lambda arg: arg[1], self.attributes['args']))

        interfaceHandle.write('method ' + result + ' ' + self.attributes['namePrefix'] + '(' + args + ') ' + ' '.join([ready, enable, clock, reset]) + ";\n")

    def generateHierarchy(self, interfaceHandle, ident, topModule):
        # remember top module name...
        self.attributes['definition'] = topModule + '.' + self.attributes['namePrefix']

    def getDefinition(self):
        return self.attributes['definition']        

