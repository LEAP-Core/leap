##
## Build pipeline for Verilog
##

import os
import re
import SCons.Script  
from iface_tool import *
from bsv_tool import *
from verilog_tool import *
from software_tool import *
from model import  *
from wrapper_gen_tool import *

class Build(ProjectDependency):
  def __init__(self, moduleList):
    WrapperGen(moduleList)
    #build interface first 
    Iface(moduleList)
    bsv = BSV(moduleList)
    if not moduleList.isDependsBuild:
      Software(moduleList)
      Verilog(moduleList, True)

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
    platformMetadata.append('{"name" =>"' + platformName +
                            '", "type" => "CPU", ' +
                            '"directory" => "./", "master" => "0", "logicalName" => "' +
                            moduleList.localPlatformName  + '"}')

    build_sim_type = moduleList.getAWBParam('build_pipeline', 'BUILD_PIPELINE_SIM_TYPE')
    platformMetadata.append('{"name" =>"' + platformName +
                            '", "type" => "' + build_sim_type + '", ' +
                            '"directory" => "./", "master" => "1", "logicalName" => "' +
                            moduleList.localPlatformName  + '"}')

    configFile.write('platforms=['+ ",".join(platformMetadata) +']\n')
    configFile.close()
