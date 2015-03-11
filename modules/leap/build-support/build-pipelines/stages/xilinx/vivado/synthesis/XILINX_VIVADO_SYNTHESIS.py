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
        area_group_tool.insertDeviceModules(moduleList)

            
    synthesis_library.buildNetlists(moduleList, synthesis_library.buildVivadoEDF, synthesis_library.buildVivadoEDF)





