import os
import errno
import re
import SCons.Script  
import functools

from model import  *
# need to get the model clock frequency
from clocks_device import  *
import synthesis_library 
from wrapper_gen_tool import *

from SynplifyCommon import *

class Synthesize(ProjectDependency):
  def __init__(self, moduleList):

    RESOURCE_COLLECTOR = eval(moduleList.getAWBParam('synthesis_tool', 'RESOURCE_COLLECTOR'))
    PLATFORM_BUILDER = eval(moduleList.getAWBParam('synthesis_tool', 'PLATFORM_BUILDER'))

    buildUser = functools.partial(buildSynplifyEDF, resourceCollector = RESOURCE_COLLECTOR)

    synthesis_library.buildNetlists(moduleList, buildUser, PLATFORM_BUILDER)



