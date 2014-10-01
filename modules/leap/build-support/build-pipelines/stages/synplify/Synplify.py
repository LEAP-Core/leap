import os
import re
import SCons.Script  

from model import  *
from clocks_device import  *
from synthesis_library import  *
from wrapper_gen_tool import *

from SynplifyCommon import *

class Synthesize(ProjectDependency):
  def __init__(self, moduleList):

    # We load this graph in to memory several times. 
    # TODO: load this graph once. 
    self.firstPassGraph = getFirstPassLIGraph()

    # need to eventually break this out into a seperate function
    # first step - modify prj options file to contain any generated wrappers
    prjFile = open('config/' + moduleList.apmName + '.synplify.prj','r');  
    newPrjFile = open('config/' + moduleList.apmName + '.modified.synplify.prj','w');  

    #build unified sdc 
    combinedSDC = open(moduleList.compileDirectory + '/' + moduleList.apmName + '.sdc','w')
    combinedSDC.write('set_hierarchy_separator {/}\n')
    for sdc in moduleList.getAllDependencies('SDC'):
      sdcIn = open(sdc,'r')
      print 'reading SDC' + sdc + '\n' 
      combinedSDC.write(sdcIn.read()+'\n')
    combinedSDC.close();

    synplify_ucf = []
    if(len(moduleList.topModule.moduleDependency['UCF']) > 0):
      synplify_ucf = moduleList.env.Command(
        ['config/' + moduleList.topModule.wrapperName() + '.ucf'],
        moduleList.topModule.moduleDependency['UCF'],
        'cat $SOURCES > $TARGET')


    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)
    synth_deps = []
    for module in [ mod for mod in moduleList.synthBoundaries() + [moduleList.topModule]]:
        if((not self.firstPassGraph is None) and (module.name in self.firstPassGraph.modules)):
            # TODO: Need to fix this loop. 
            synth_deps += linkEDF(moduleList, module, self.firstPassLIGraph)
        else:
            synth_deps += buildModuleEDF(moduleList, module, globalVerilogs, globalVHDs)


    # Synplify sometimes produces a synplify .ucf, but we should 
    # write to it, incase synplify doesn't.
    synplifyUCF = moduleList.compileDirectory + '/synplicity.ucf'
    # XXX we should be replacing _ALL_ module dependencies here
    moduleList.topModule.moduleDependency['UCF'] = [synplifyUCF]    


    # Now that we've set up the world let's compile

    #first dump the wrapper files to the new prj 

    moduleList.topModule.moduleDependency['SYNTHESIS'] = synth_deps   

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)
