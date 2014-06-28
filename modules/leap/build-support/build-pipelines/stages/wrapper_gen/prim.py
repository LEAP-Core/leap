import sys
import copy

class Prim():
    def __init__(self, name):
        # need some statement for compilation
        self.name = name
        self.attributes = {}

    def generateHierarchy(self, interfaceHandle, ident, topModule):
        # remember top module name...
        self.attributes['definition'] = topModule + '.' + self.attributes['namePrefix']

    def getDefinition(self):
        return self.attributes['definition']        

class Prim_Clock(Prim):
    def __init__(self, name, osc, gate):
        Prim.__init__(self, name)
        self.gate = gate
        self.osc = osc

    def generateImportInterface(self, interfaceHandle, namePrefix=''):
        #interfaces don't know their name. this must be propagated.
        interfaceHandle.write('interface Clock ' + namePrefix + ';\n')
        self.attributes['namePrefix'] = namePrefix

    def generateImport(self, interfaceHandle):
        interfaceHandle.write('output_clock ' + self.attributes['namePrefix'] + '(' + self.osc + ');\n') 
        interfaceHandle.write('ancestor(' + self.attributes['namePrefix'] + ', device_physicalDrivers_clocksDriver_clock);\n') 

class Prim_Reset(Prim):
    def __init__(self, name, port, clock):
        Prim.__init__(self, name)
        self.port = port
        self.clock = clock

    def generateImportInterface(self, interfaceHandle, namePrefix=''):
        #interfaces don't know their name. this must be propagated.
        interfaceHandle.write('interface Reset ' + namePrefix + ';\n')
        self.attributes['namePrefix'] = namePrefix

    def generateImport(self, interfaceHandle):
        interfaceHandle.write('output_reset ' + self.attributes['namePrefix'] + '(' + self.port + ') clocked_by(' + self.clock + ');\n') 

class Prim_Inout(Prim):
    def __init__(self, type, name, port, clock, reset):
        Prim.__init__(self, name)
        self.type = type
        self.port = port
        self.clock = clock
        self.reset = reset

    def generateImportInterface(self, interfaceHandle, namePrefix=''):
        #interfaces don't know their name. this must be propagated.
        interfaceHandle.write('interface ' + self.type + ' ' + namePrefix + ';\n')
        self.attributes['namePrefix'] = namePrefix

    def generateImport(self, interfaceHandle):
        #ifc_inout   dq(ddr3_dq)          clocked_by(no_clock)  reset_by(no_reset);
        interfaceHandle.write('ifc_inout ' + self.attributes['namePrefix'] + '(' + self.port + ') clocked_by(' + self.clock + ') reset_by(' + self.reset + ');\n') 
