import os
import sys
import re
import SCons.Script
from model import  *
from config import *
from fpga_environment_parser import *
from subprocess import call
from subprocess import Popen
from subprocess import PIPE
from subprocess import STDOUT

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
    environmentRootName = APM_NAME  + '_multifpga_environment'
    environmentName = environmentRootName + '.apm'
    environmentPath =  'config/pm/private/' + environmentName

    def makePlatformBuildDir(name):
      return 'multi_fpga/' + makePlatformLogName(name,APM_NAME) + '/pm'

    def makePlatformDictDir(name):
      return makePlatformBuildDir(name) + '/iface/src/dict'

    def makePlatformRRRDir(name):
      return makePlatformBuildDir(name) + '/iface/src/rrr'

  
    envFile = moduleList.getAllDependenciesWithPaths('GIVEN_FPGAENVS')
    if(len(envFile) != 1):
      print "Found more than one environment file: " + str(envFile) + ", exiting\n"
    environment = parseFPGAEnvironment(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + envFile[0])
    print "environment keys: " + str(environment.getPlatformNames)

    # select the connected_app and make it a submodel
    call(['asim-shell','--batch','create', 'submodel', APM_FILE , 'connected_application', applicationPath]) 
    call(['asim-shell','--batch','rename', 'submodel', applicationPath, applicationRootName]) 
    # do the same for the fpga mapping
    call(['asim-shell','--batch','create', 'submodel', APM_FILE , 'fpga_mapping', mappingPath])        
    call(['asim-shell','--batch','create', 'submodel', APM_FILE , 'environment_description', environmentPath])    
    call(['asim-shell','--batch','rename', 'submodel', mappingPath, mappingRootName]) 

    def compile_closure(platform):
         
         def compile_platform_log(target, source, env):
          
           platformAPMName = makePlatformLogName(platform.name,APM_NAME) + '.apm'
           platformPath = 'config/pm/private/' + platformAPMName
           platformBuildDir = makePlatformBuildDir(platform.name)
           # and now we can build them
           # what we want to gather here is dangling top level connections
           # so we should depend on the model log
           # Ugly - we need to physically reconstruct the apm path
           # set the fpga parameter
           # for the first pass, we will ignore mismatched platforms

           print "tool.py: alive in call platform log " + platform.name
           # Always pass raw scons command here without DEBUG, OPT, COST_TABLE,
           # etc.  This rule is only for model topology, not the final build.
           sts = execute('cd ' + platformBuildDir + '; scons')
           print "tool.py: dead in call platform log" + platform.name
           return sts
         return compile_platform_log

    moduleList.topModule.moduleDependency['FPGA_PLATFORM_LOGS'] = []

    # the stuff below here should likely go in a different file, and there will be many hard-coded paths
    # copy the environment descriptions to private 
    #APM_FILE
    #WORKSPACE_ROOT
    # the first thing to do is construct the global set of dictionaries
    # I can communicate this to the subbuilds 
    # I build the links here, but I can't physcially check the files until later
    moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'] = {}

    for platformName in environment.getPlatformNames():
      platform = environment.getPlatform(platformName)
      print "leap-configure --pythonize " +  platform.path
      rawDump = Popen(["leap-configure", "--pythonize", "--silent", platform.path], stdout=PIPE ).communicate()[0]
      # fix the warning crap sometimes
      moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'][platformName] = ModuleList(moduleList.env, eval(rawDump), moduleList.arguments, "")
    
    # check that all same named file are the same.  Then we can blindly copy all files to all directories and life will be good. 
    # once that's done, we still need to tell the child about these extra dicts. 
    # need to handle dynamic params specially somehow.... 
    # for now we'll punt on it. 

    # The missing dictionaries and RRRs need to be communicated to the 
    # second compilation pass.
    moduleList.topModule.moduleDependency['MISSING_DICTS'] = {}
    moduleList.topModule.moduleDependency['MISSING_RRRS'] = {}

    for platformName in environment.getPlatformNames():
      platform = environment.getPlatform(platformName)
      for dict in moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'][platformName].getAllDependencies('GIVEN_DICTS'):
        if(not dict in moduleList.topModule.moduleDependency['MISSING_DICTS']):                                                     
          moduleList.topModule.moduleDependency['MISSING_DICTS'][dict] = platform.name

      # RRR calls can appear in services which can differ across environments. 
      # This code can probably be deprecated at some point once RRR goes away.
      for rrr in moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'] [platformName].getAllDependenciesWithPaths('GIVEN_RRRS'):
        if(not rrr in moduleList.topModule.moduleDependency['MISSING_RRRS']):                                                     
          moduleList.topModule.moduleDependency['MISSING_RRRS'][rrr] = platform.name
                                        
    for platformName in environment.getPlatformNames():
      platform = environment.getPlatform(platformName)
      platformAPMName = makePlatformLogName(platform.name,APM_NAME) + '.apm'
      platformPath = 'config/pm/private/' + platformAPMName
      platformBuildDir = makePlatformBuildDir(platformName)
      wrapperLogTgt =  platformBuildDir + '/' + moduleList.env['DEFS']['ROOT_DIR_HW']+ '/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '/.bsc/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper.log.multi_fpga'
      wrapperLogBld =  platformBuildDir + '/' + moduleList.env['DEFS']['ROOT_DIR_HW']+ '/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '/.bsc/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper.log'
      routerBSH =  platformBuildDir + '/' + moduleList.env['DEFS']['ROOT_DIR_HW']+ '/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '/multifpga_routing.bsh'

      print "wrapper: " + wrapperLogTgt
      print "platformPath: " + moduleList.env['DEFS']['WORKSPACE_ROOT'] + '/src/private/' + platformPath

      execute('asim-shell --batch cp ' + platform.path +" "+ platformPath)        
      execute('asim-shell --batch replace module ' + platformPath + ' ' + applicationPath)
      execute('asim-shell --batch replace module ' + platformPath + ' ' + mappingPath)
      execute('asim-shell --batch replace module ' + platformPath + ' ' + environmentPath)
      execute('asim-shell --batch set parameter ' + platformPath + ' MULTI_FPGA_PLATFORM \\"' + platform.name + '\\"')
      execute('asim-shell --batch set parameter ' + platformPath + ' IGNORE_PLATFORM_MISMATCH 1 ')
      execute('asim-shell --batch set parameter ' + platformPath + ' BUILD_LOGS_ONLY 1 ')
      execute('asim-shell --batch set parameter ' + platformPath + ' USE_ROUTING_KNOWN 0 ')
      execute('asim-shell --batch set parameter ' + platformPath + ' CLOSE_CHAINS 0 ')

      # Dictionaries are global.  Therefore, all builds must see the same context or bad things 
      # will happen.   
      missingDicts = ""
      firstPass = True
      platformDicts = moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'][platformName].getAllDependencies('GIVEN_DICTS')     
      for dict in moduleList.topModule.moduleDependency['MISSING_DICTS'].keys():
        if(not dict in platformDicts):
          seperator = ':'
          if(firstPass):
            seperator = ''
          missingDicts += seperator+dict
          firstPass = False

      print "missingDicts: " + missingDicts
    
      # RRRs can appear in services sometimes and thereby lack global 
      # visibility.  We need to treat them in the same way we treat dictionaries. 
      missingRRRs = ""
      firstPass = True
      platformRRRs = moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'][platformName].getAllDependenciesWithPaths('GIVEN_RRRS')     
      for dict in moduleList.topModule.moduleDependency['MISSING_RRRS'].keys():
        if(not dict in platformRRRs):
          seperator = ':'
          if(firstPass):
            seperator = ''
          missingRRRs += seperator+dict
          firstPass = False

      print "missingRRRs: " + missingRRRs

      execute('asim-shell --batch set parameter ' + platformPath + ' EXTRA_DICTS \\"' + missingDicts  + '\\"')
      execute('asim-shell --batch set parameter ' + platformPath + ' EXTRA_RRRS \\"' + missingRRRs  + '\\"')

      # Configure the build tree
      if not os.path.exists(platformBuildDir): os.makedirs(platformBuildDir) 
      execute('asim-shell --batch -- configure model ' + platformPath + ' --builddir ' + platformBuildDir)

      # set up the symlinks to missing dictionaries- they aree broken
      # at first, but as we fill in the platforms, they'll come up
      for dict in moduleList.topModule.moduleDependency['MISSING_DICTS'].keys():
        if(not dict in platformDicts):
          # lexists works on broken symlinks...
          path = os.getcwd()
          dictPath = os.path.realpath(makePlatformDictDir(moduleList.topModule.moduleDependency['MISSING_DICTS'][dict]) + '/' + dict)
          linkDir  = makePlatformDictDir(platform.name)  
          linkPath = linkDir  + '/' + dict
          relDictPath = os.path.relpath(dictPath, linkDir)
          print "missing link: " + linkPath + ' -> ' + relDictPath
          if(os.path.lexists(linkPath)):
            print("This symlink already exists: " + makePlatformDictDir(platform.name)  + '/' + dict)
          else:
            os.symlink(relDictPath, linkPath)

      # do the same for missing RRRs - this code is similar to that above and should be refactored. 
      for rrr in moduleList.topModule.moduleDependency['MISSING_RRRS'].keys():
        if(not rrr in platformRRRs):
          # lexists works on broken symlinks...
          path = os.getcwd()
          if(os.path.lexists(makePlatformRRRDir(platform.name)  + '/' + rrr)):
            print("This symlink already exists: " + makePlatformRRRDir(platform.name)  + '/' + rrr)
          else:
            rrrpath = os.path.realpath( makePlatformRRRDir(moduleList.topModule.moduleDependency['MISSING_RRRS'][rrr]) + '/' + rrr)
            #the rrr values have some hierarchical information in them...
            linkPath  = makePlatformRRRDir(platform.name)  + '/' + rrr
            linkDir = os.path.dirname(linkPath)
            print ('Link dir is ' + linkDir)
            os.symlink(os.path.relpath(rrrpath, linkDir), linkPath)


      subbuild = moduleList.env.Command( 
          [wrapperLogTgt],
          [routerBSH],
          [ compile_closure(platform),
            SCons.Script.Copy(wrapperLogTgt, wrapperLogBld) ]
          )
                   
      moduleList.topModule.moduleDependency['FPGA_PLATFORM_LOGS'] += [wrapperLogTgt]

      # we now need to create a multifpga_routing.bsh so that we can get the sizes of the various links.
      # we'll need this later on. 
      header = open(routerBSH,'w')
      header.write('`include "awb/provides/stats_service.bsh"\n')
      header.write('`include "awb/provides/debug_scan_service.bsh"\n')
      header.write('// we need to pick up the module sizes\n')
      header.write('module [CONNECTED_MODULE] mkCommunicationModule#(VIRTUAL_PLATFORM vplat) (Empty);\n')
      header.write('let m <- mkCommunicationModuleIfaces(vplat ') 
      for target in  platform.getSinks().keys():
        header.write(', ' + platform.getSinks()[target].physicalName + '.write')
      for target in  platform.getSources().keys():
        header.write(', ' + platform.getSources()[target].physicalName + '.first')
     
      header.write(');\n')
      # we also need a stat here to make the stats work right.  
      # we don't care about the ID because it will get replaced later during the second compilation pass
      if(GENERATE_ROUTER_STATS):    
        header.write('let stat <- mkStatCounter(?);\n')   

      if(GENERATE_ROUTER_DEBUG):    
        header.write('DEBUG_SCAN#(Bit#(1)) debug <- mkDebugScanNode(?,?);\n')   

      header.write('endmodule\n')

      header.write('module [CONNECTED_MODULE] mkCommunicationModuleIfaces#(VIRTUAL_PLATFORM vplat ')
        
      for target in  platform.getSinks().keys():
        # really I should disambiguate by way of a unique path
        via  = (platform.getSinks()[target]).physicalName.replace(".","_") + '_write'
        header.write(', function Action write_' + via + '_egress(Bit#(p' + via + '_egress_SZ) data),') 
      for target in  platform.getSources().keys():
        # really I should disambiguate by way of a unique path
        via  = (platform.getSources()[target]).physicalName.replace(".","_") + '_read'
        header.write('function Bit#(p'+ via + '_ingress_SZ) read_' + via + '_ingress()') 

      header.write(') (Empty);\n')

      for target in  platform.getSinks().keys():
        via  = (platform.getSinks()[target]).physicalName.replace(".","_") + '_write'
        header.write('messageM("SizeOfVia:'+via+':" + integerToString(valueof(p' + via + '_egress_SZ)));\n')
        
      for target in  platform.getSources().keys():
        # really I should disambiguate by way of a unique path
        via  = (platform.getSources()[target]).physicalName.replace(".","_") + '_read' 
        header.write('messageM("SizeOfVia:'+via+':" + integerToString(valueof(p' + via + '_ingress_SZ)));\n')
      header.write('endmodule\n')

      header.close();

      #force build remove me later....          
      moduleList.topDependency += [subbuild]
      moduleList.env.AlwaysBuild(subbuild)

    # now that we configured things, let's check that the dicts and rrrs are sane
    # we use os.stat to check file equality. It follows symlinks,
    # and it would be an _enormous_ coincidence if non-equal files 
    # matched
    for platformName in environment.getPlatformNames():
      platformDicts = moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'][platformName].getAllDependencies('GIVEN_DICTS')
      for dict in platformDicts:
        platStat = os.stat(os.path.abspath(makePlatformDictDir(platformName)  + '/' + dict))
        globalStat = os.stat(os.path.abspath(makePlatformDictDir(moduleList.topModule.moduleDependency['MISSING_DICTS'][dict]) + '/' + dict))

        if(platStat != globalStat):
          print "Warning, mismatched dicts: " + str(dict) + " on " + platformName

      #and now for RRRs
      platformRRRs = moduleList.topModule.moduleDependency['PLATFORM_HIERARCHIES'][platformName].getAllDependenciesWithPaths('GIVEN_RRRS')
      for rrr in platformRRRs:
        platStat = os.stat(os.path.abspath(makePlatformRRRDir(platformName)  + '/' + rrr))
        globalStat = os.stat(os.path.abspath(makePlatformRRRDir(moduleList.topModule.moduleDependency['MISSING_RRRS'][rrr]) + '/' + rrr))

        if(platStat != globalStat):
          print "Warning, mismatched dicts: " + str(rrr) + " on " + platformName
