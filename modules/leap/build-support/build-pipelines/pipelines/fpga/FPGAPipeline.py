##
## Build pipeline for FPGA targets
##

import os
import re
import SCons.Script  
from model import  *
from iface_tool import *
from bsv_tool import *
from fpga_program_tool import *
from software_tool import *
from synthesis_tool import  *
from post_synthesis_tool import *
from mcd_tool import *
from wrapper_gen_tool import *

class Build(ProjectDependency):
  def __init__(self, moduleList):
    WrapperGen(moduleList)
    Iface(moduleList)
    bsv = BSV(moduleList)
    if not bsv.isDependsBuild:
      FPGAProgram(moduleList)
      Software(moduleList)
      MCD(moduleList)
      #moduleList.dump()
      Synthesize(moduleList)
      #moduleList.dump()
      PostSynthesize(moduleList)

    # Legacy pipelines require the creation of a platform description file
    # END for platform
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
    platformMetadata.append('{"name" =>"' + platformName + '", "type" => "CPU", "directory" => "./", "master" => "False", "logicalName" => "Legacy"}')
    platformMetadata.append('{"name" =>"' + platformName + '", "type" => "FPGA", "directory" => "./", "master" => "True", "logicalName" => "Legacy"}')

    configFile.write('platforms=['+ ",".join(platformMetadata) +']\n')
    configFile.close()
