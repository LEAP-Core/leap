##
## Build pipeline for software simulation
##

import os
import re
import SCons.Script  
from iface_tool import *
from bsv_tool import *
from bluesim_tool import *
from verilog_tool import *
from software_tool import *
from wrapper_gen_tool import *
from model import  *

class Build(ProjectDependency):
  def __init__(self, moduleList):
    if not moduleList.isDependsBuild:
      WrapperGen(moduleList)

    # Build interface first 
    Iface(moduleList)
    bsv = BSV(moduleList)
    if not bsv.isDependsBuild:
      Bluesim(moduleList)
      # Included to support optional Verilog build
      Verilog(moduleList, False)
      Software(moduleList)

    # Legacy pipelines require the creation of a platform description file
    # for platform
    configFile = open("config/platform_env.sh","w");

    # the stuff below here should likely go in a different file, and there will be many hard-coded paths                         
    # copy the environment descriptions to private                                                                               
    #APM_FILE                                                                                                                    
    #WORKSPACE_ROOT                                                                                                              
    platformMetadata = []
    platformName = moduleList.apmName
  
    # sprinkle breadcrumbs in config file                                                                                       
    # The run script allows us to have multiple types for the same apm
    # This accomodate legacy builds.  If multiple types are assigned to the same APM, 
    # then their directory and master (soon to be deprecated) will go away. 
    platformMetadata.append('{"name" =>"' + platformName + '", "type" => "CPU", "directory" => "./", "master", "0"}')
    platformMetadata.append('{"name" =>"' + platformName + '", "type" => "BLUESIM", "directory" => "./", "master", "1"}')

    configFile.write('platforms=['+ ",".join(platformMetadata) +']\n')
    configFile.close()
