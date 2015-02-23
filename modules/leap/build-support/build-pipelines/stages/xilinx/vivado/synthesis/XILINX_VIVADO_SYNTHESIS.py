import os
import re 
import sys
import SCons.Script
import functools
import copy
import bsv_tool

import model
from model import Module
# need to pick up clock frequencies for xcf
import synthesis_library 
import parameter_substitution
import wrapper_gen_tool

try:
    import area_group_tool
except ImportError:
    pass # we won't be using this tool.


   
#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class Synthesize():
  def __init__(self, moduleList):

    if(moduleList.isDependsBuild):           
        return

    # Here we add user-defined area groups into the build.  These area
    # groups have a parent, and are explictly not already in the module list. 
    if(moduleList.getAWBParamSafe('area_group_tool', 'AREA_GROUPS_ENABLE') and (wrapper_gen_tool.getFirstPassLIGraph() is None)):
        elabAreaConstraints = area_group_tool.AreaConstraints(moduleList)
        elabAreaConstraints.loadAreaConstraintsElaborated()

        print "SYNTH: " + str(elabAreaConstraints)

        for userAreaGroup in elabAreaConstraints.constraints.values():
      
            if('SYNTH_BOUNDARY' in userAreaGroup.attributes):  
                 # Modify parent to know about this child.               
                 parentModule = moduleList.modules[userAreaGroup.parentName]
                 # pick up deps from parent. 
                 moduleDeps ={} 
                 moduleName = userAreaGroup.attributes['MODULE_NAME']
 
                 # grab the parent module verilog and convert it. This
                 # is really ugly, and demonstrates whe first class
                 # language constructs are so nice.  Eventually, we
                 # should push these new synth boundary objects into
                 # flow earlier.
                 moduleVerilog = None
                 for dep in map(functools.partial(bsv_tool.modify_path_ba, moduleList), model.convertDependencies(moduleList.getAllDependenciesWithPaths('GEN_VERILOGS'))):
                     print "Examining dep: " + dep
                     if (re.search(moduleName, dep)):
                         moduleVerilog = dep  
                      

                 if(moduleVerilog is None):
                     print "ERROR: failed to find verilog for area group: " + userAreaGroup.name 
                     exit(1)
            
                 moduleVerilogBlackBox = moduleVerilog.replace('.v', '_stub.v')

                 moduleDeps['GEN_VERILOG_STUB'] = [moduleVerilogBlackBox]

                 print "BLACK_BOX: " + moduleVerilog + " -> " + moduleVerilogBlackBox

                 moduleList.env.Command([moduleVerilogBlackBox], [moduleVerilog],
                                        'leap-gen-black-box -nohash $SOURCE > $TARGET')

                 if(parentModule.getAttribute('BLACK_BOX') is None):
                     parentModule.putAttribute('BLACK_BOX', {moduleVerilog: moduleVerilogBlackBox})
                 else:
                     blackBoxDict = parentModule.getAttribute('BLACK_BOX') 
                     blackBoxDict[moduleVerilog] = moduleVerilogBlackBox

                 m = Module(userAreaGroup.name, [moduleName],\
                             parentModule.buildPath, parentModule.name,\
                             [], parentModule.name, [], moduleDeps)
                 m.putAttribute("WRAPPER_NAME", moduleName)
                 m.putAttribute("AREA_GROUP", 1)
                 
                 moduleList.insertModule(m)
            
    synthesis_library.buildNetlists(moduleList, synthesis_library.buildVivadoEDF, synthesis_library.buildVivadoEDF)





