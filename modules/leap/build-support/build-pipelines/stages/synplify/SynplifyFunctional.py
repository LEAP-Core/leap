import os
import errno
import re
import SCons.Script  
import functools

import model
from model import ProjectDependency
# need to get the model clock frequency
import clocks_device
import synthesis_library 
import wrapper_gen_tool

try:
    import area_group_tool
except ImportError:
    pass # we won't be using this tool.


from SynplifyCommon import *

class Synthesize(ProjectDependency):
  def __init__(self, moduleList):

    if(moduleList.isDependsBuild):           
        return

    RESOURCE_COLLECTOR = eval(moduleList.getAWBParam('synthesis_tool', 'RESOURCE_COLLECTOR'))
    PLATFORM_BUILDER = eval(moduleList.getAWBParam('synthesis_tool', 'PLATFORM_BUILDER'))

    buildUser = functools.partial(buildSynplifyEDF, resourceCollector = RESOURCE_COLLECTOR)


    # Here we add user-defined area groups into the build.  These area
    # groups have a parent, and are explictly not already in the module list. 
    if(moduleList.getAWBParamSafe('area_group_tool', 'AREA_GROUPS_ENABLE')):
        if(wrapper_gen_tool.getFirstPassLIGraph() is None):
            area_group_tool.insertDeviceModules(moduleList)

    synthesis_library.buildNetlists(moduleList, buildUser, PLATFORM_BUILDER)



