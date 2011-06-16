import os
import sys
import re
import SCons.Script
from model import  *
from config import *
from fpga_environment_parser import *
from subprocess import call


def makePlatformLogName(name, apm):
  return name +'_'+ apm + '_multifpga_logs'

class MultiFPGAGenerateLogfile():

  def __init__(self, moduleList):
    APM_FILE = moduleList.env['DEFS']['APM_FILE']
    APM_NAME = moduleList.env['DEFS']['APM_NAME']
    applicationRootName = APM_NAME  + '_mutlifpga_connected_application'
    applicationName = applicationRootName + '.apm'
    applicationPath =  'config/pm/private/' + applicationName
    mappingRootName = APM_NAME  + '_mutlifpga_mapping'
    mappingName = mappingRootName + '.apm'
    mappingPath =  'config/pm/private/' + mappingName
  
    envFile = moduleList.getAllDependenciesWithPaths('GIVEN_FPGAENVS')
    if(len(envFile) != 1):
      print "Found more than one environment file: " + str(envFile) + ", exiting\n"
    environment = parseFPGAEnvironment(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + envFile[0])
    print "environment keys: " + str(environment.getPlatformNames)

    # select the connected_app and make it a submodel
    call(['asim-shell','create', 'submodel', APM_FILE , 'connected_application', applicationPath]) 
    call(['asim-shell','rename', 'submodel', applicationPath, applicationRootName]) 
    # do the same for the fpga mapping
    call(['asim-shell','create', 'submodel', APM_FILE , 'fpga_mapping', mappingPath])        
    call(['asim-shell','rename', 'submodel', mappingPath, mappingRootName]) 

    def compile_closure(platform):
         
         def compile_platform_log(target, source, env):
          
           platformAPMName = makePlatformLogName(platform.name,APM_NAME) + '.apm'
           platformPath = 'config/pm/private/' + platformAPMName
           platformBuildDir = moduleList.env['DEFS']['BUILD_DIR'] +'/' + platformAPMName
           # and now we can build them -- should we use SCons here?
           # what we want to gather here is dangling top level connections
           # so we should depend on the model log
           # Ugly - we need to physically reconstruct the apm path
           # set the fpga parameter
           # for the first pass, we will ignore mismatched platforms

           print "alive in call platform log " + platform.name
           execute('awb-shell build model ' + platformPath)   
           print "dead in call platform log" + platform.name
         return compile_platform_log

    moduleList.topModule.moduleDependency['FPGA_PLATFORM_LOGS'] = []

    # the stuff below here should likely go in a different file, and there will be many hard-coded paths
    # copy the environment descriptions to private 
    #APM_FILE
    #WORKSPACE_ROOT
    for platformName in environment.getPlatformNames():
      platform = environment.getPlatform(platformName)
      platformAPMName = makePlatformLogName(platform.name,APM_NAME) + '.apm'
      platformPath = 'config/pm/private/' + platformAPMName
      platformBuildDir = moduleList.env['DEFS']['BUILD_DIR'] +'/../../' + makePlatformLogName(platform.name,APM_NAME) + '/pm/'
      wrapperLog =  platformBuildDir +'/'+ moduleList.env['DEFS']['ROOT_DIR_HW']+ '/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '/.bsc/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper.log'

      print "wrapper: " + wrapperLog
      print "platformPath: " + moduleList.env['DEFS']['WORKSPACE_ROOT'] + '/src/private/' + platformPath

      execute('asim-shell cp ' + platform.path +" "+ platformPath)        
      execute('asim-shell replace module ' + platformPath + ' ' + applicationPath)
      execute('asim-shell replace module ' + platformPath + ' ' + mappingPath)
      execute('asim-shell set parameter ' + platformPath + ' MULTI_FPGA_PLATFORM \\"' + platform.name + '\\"')
      execute('asim-shell set parameter ' + platformPath + ' IGNORE_PLATFORM_MISMATCH 1 ')
      execute('asim-shell set parameter ' + platformPath + ' BUILD_LOGS_ONLY 1 ')
      execute('asim-shell set parameter ' + platformPath + ' USE_ROUTING_KNOWN 0 ')
      execute('asim-shell configure model ' + platformPath)

      subbuild = moduleList.env.Command( 
          [wrapperLog],
          [],
          compile_closure(platform)
          )                   
      moduleList.topModule.moduleDependency['FPGA_PLATFORM_LOGS'] += [wrapperLog] 

      #force build remove me later....          
      moduleList.topDependency += [subbuild]
      moduleList.env.AlwaysBuild(subbuild)
