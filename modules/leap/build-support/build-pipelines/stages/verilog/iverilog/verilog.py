import os
import re
import sys
import string

import SCons.Script

import model
import bsv_tool
import software_tool
import wrapper_gen_tool

class Verilog():

  def __init__(self, moduleList, isPrimaryBuildTarget):
    APM_NAME = moduleList.env['DEFS']['APM_NAME']
    BSC = moduleList.env['DEFS']['BSC']
    inc_paths = moduleList.swIncDir # we need to depend on libasim

    self.firstPassLIGraph = wrapper_gen_tool.getFirstPassLIGraph()

    # This is not correct for LIM builds and needs to be fixed. 
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    ALL_DIRS_FROM_ROOT = moduleList.env['DEFS']['ALL_HW_DIRS']
    ALL_BUILD_DIRS_FROM_ROOT = model.transform_string_list(ALL_DIRS_FROM_ROOT, ':', '', '/' + TMP_BSC_DIR)
    ALL_LIB_DIRS_FROM_ROOT = ALL_DIRS_FROM_ROOT + ':' + ALL_BUILD_DIRS_FROM_ROOT


    # Due to the bluespec linker, for LI second pass builds, the final
    # verilog link step must occur in a different directory than the
    # bsc object code wrapper compilation step.  However, non-LIM
    # linker builds need to build in the original .bsc directory to
    # pick up VPI.
    vexe_vdir = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '/' + moduleList.env['DEFS']['TMP_BSC_DIR'] 
    if(not self.firstPassLIGraph is None):
        vexe_vdir = vexe_vdir + '_vlog'

    if not os.path.isdir(vexe_vdir):
        os.mkdir(vexe_vdir)

    LI_LINK_DIR = ""
    if (not self.firstPassLIGraph is None):
        LI_LINK_DIR = model.get_build_path(moduleList, moduleList.topModule) + "/.li/"
        inc_paths += [LI_LINK_DIR]
        ALL_LIB_DIRS_FROM_ROOT = LI_LINK_DIR + ':' +  ALL_LIB_DIRS_FROM_ROOT

    liCodeType = ['VERILOG', 'GIVEN_VERILOG_HS', 'GEN_VPI_CS', 'GEN_VPI_HS']

    # This can be refactored as a function.
    if (not self.firstPassLIGraph is None):
        for moduleName in self.firstPassLIGraph.modules:            
            moduleObject = self.firstPassLIGraph.modules[moduleName]
            for codeType in liCodeType:
                if(codeType in moduleObject.objectCache):
                    for verilog in moduleObject.objectCache[codeType]:
                        linkPath = vexe_vdir + '/' + os.path.basename(verilog)
                        def linkVerilog(target, source, env):
                            # It might be more useful if the Module contained a pointer to the LIModules...                        
                            if(os.path.lexists(str(target[0]))):
                                os.remove(str(target[0]))
                            print "Linking: " + str(source[0]) + " to " + str(target[0])
                            os.symlink(str(source[0]), str(target[0]))
                        moduleList.env.Command(linkPath, verilog, linkVerilog)

                        if(codeType in moduleList.topModule.moduleDependency):
                            moduleList.topModule.moduleDependency[codeType] += [linkPath]
                        else:
                            moduleList.topModule.moduleDependency[codeType] = [linkPath]
                    else:
                        # Warn that we did not find the ngc we expected to find..
                        print "Warning: We did not find verilog for module " + moduleName 
                
    bsc_version = bsv_tool.getBluespecVersion()

    ldflags = ''
    for ld_file in moduleList.getAllDependenciesWithPaths('GIVEN_BLUESIM_LDFLAGSS'):
      ldHandle = open(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + ld_file, 'r')
      ldflags += ldHandle.read() + ' '    

    BSC_FLAGS_VERILOG = '-steps 10000000 +RTS -K1000M -RTS -keep-fires -aggressive-conditions -wait-for-license -no-show-method-conf -no-opt-bool -licenseWarning 7 -elab -show-schedule ' + ldflags + ' -verilog -v -vsim iverilog '

    # Build in parallel.
    n_jobs = moduleList.env.GetOption('num_jobs')
    if (bsc_version >= 30006):
        BSC_FLAGS_VERILOG += '-parallel-sim-link ' + str(n_jobs) + ' '

    for path in inc_paths:
        BSC_FLAGS_VERILOG += ' -I ' + path + ' ' #+ '-Xv -I' + path + ' '

    LDFLAGS = moduleList.env['DEFS']['LDFLAGS']
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    ROOT_WRAPPER_SYNTH_ID = 'mk_' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper'

#    vexe_gen_command = \
#        BSC + ' ' + BSC_FLAGS_VERILOG + ' -vdir ' + moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '/' + moduleList.env['DEFS']['TMP_BSC_DIR'] +' -p +:' + LI_LINK_DIR + ':' +  ALL_LIB_DIRS_FROM_ROOT + ' -vsearch +:' + LI_LINK_DIR + ":" + ALL_LIB_DIRS_FROM_ROOT + ' ' + \
#        ' -o $TARGET' 

    vexe_gen_command = \
        BSC + ' ' + BSC_FLAGS_VERILOG + ' -vdir ' + vexe_vdir + ' -simdir ' + vexe_vdir + ' -bdir ' + vexe_vdir +' -p +:' +  ALL_LIB_DIRS_FROM_ROOT + ' -vsearch +:' + ALL_LIB_DIRS_FROM_ROOT + ' ' + \
        ' -o $TARGET' 

    if (bsc_version >= 13013):
        # 2008.01.A compiler allows us to pass C++ arguments.
        if (model.getDebug(moduleList)):
            vexe_gen_command += ' -Xc++ -O0'
        else:
            vexe_gen_command += ' -Xc++ -O1'

        # g++ 4.5.2 is complaining about overflowing the var tracking table

        if (model.getGccVersion() >= 40501):
             vexe_gen_command += ' -Xc++ -fno-var-tracking-assignments'

    defs = (software_tool.host_defs()).split(" ")
    for definition in defs:
        vexe_gen_command += ' -Xc++ ' + definition + ' -Xc ' + definition

    # Hack to link against pthreads.  Really we should have a better solution.
    vexe_gen_command += ' -Xl -lpthread '

    # construct full path to BAs
    def modify_path(str):
        array = str.split('/')
        file = array.pop()
        return  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + '/'.join(array) + '/' + TMP_BSC_DIR + '/' + file 


    # Use systemverilog 2005
    if(moduleList.getAWBParam('verilog_tool', 'ENABLE_SYSTEM_VERILOG')):
        vexe_gen_command += ' -Xv -g2005-sv '

    # Allow .vh/.sv file extensions etc.
    # vexe_gen_command += ' -Xv -Y.vh -Xv -Y.sv '

    # Bluespec requires that source files terminate the command line.
    vexe_gen_command += '-verilog -e ' + ROOT_WRAPPER_SYNTH_ID + ' ' +\
                        moduleList.env['DEFS']['BDPI_CS']

    if (model.getBuildPipelineDebug(moduleList) != 0):
        for m in moduleList.getAllDependencies('BA'):
            print 'BA dep: ' + str(m)
        for m in moduleList.getAllDependencies('VERILOG'):
            print 'VL dep: ' + str(m)
        for m in moduleList.getAllDependencies('VHDL'):
            print 'BA dep: ' + str(m)
        print

    # Generate a thin wrapper around the verilog executable.  This
    # wrapper is used to address a problem in iverilog in which the
    # simulator does not support shared library search paths.  The
    # current wrapper only works for iverilog.  Due to brokeness in
    # the iverilog argument parser, we must construct a correct
    # iverilog command line by analyzing its compiled script. Also,
    # this script is not passing through the arguments that it should
    # be passing through. 
    def generate_vexe_wrapper(target, source, env):
        wrapper_handle = open(str(target[0]),'w')
        wrapper_handle.write('#!/usr/bin/perl\n')
        wrapper_handle.write('# generated by verilog.py\n') 
        wrapper_handle.write('$platform = $ENV{"PLATFORM_DIRECTORY"};\n')
        wrapper_handle.write('@script = `cat $platform/' + TMP_BSC_DIR + '/' + APM_NAME + '_hw.exe' + '`;\n')   
        wrapper_handle.write('$script[0] =~ s/#!/ /g;\n')
        wrapper_handle.write('$vvp = $script[0];\n')
        wrapper_handle.write('chomp($vvp);\n')
        wrapper_handle.write('exec("$vvp -m$platform/directc_mk_model_Wrapper.so $platform/' + TMP_BSC_DIR + '/' + APM_NAME + '_hw.exe' + ' +bscvcd \$* ");\n')
        wrapper_handle.close()
 
    def modify_path_ba_local(path):
        return bsv_tool.modify_path_ba(moduleList, path)

    # Bluesim builds apparently touch this code. This control block
    # preserves their behavior, but it is unclear why the verilog build is 
    # involved.
    if (isPrimaryBuildTarget):
        vbinDeps = []
        # If we got a lim graph, we'll pick up many of our dependencies from it. 
        # These were annotated in the top module above. Really, this seems unclean.
        # we should build a graph during the second pass and just use it.
        if(not self.firstPassLIGraph is None):
            vbinDeps += moduleList.getDependencies(moduleList.topModule, 'VERILOG') + moduleList.getDependencies(moduleList.topModule, 'GIVEN_VERILOG_HS') + moduleList.getDependencies(moduleList.topModule, 'GEN_VPI_HS') + moduleList.getDependencies(moduleList.topModule, 'GEN_VPI_CS') +moduleList.getDependencies(moduleList.topModule, 'VHDL') + moduleList.getDependencies(moduleList.topModule, 'BA') + map(modify_path_ba_local, moduleList.getModuleDependenciesWithPaths(moduleList.topModule, 'GEN_BAS'))
        # collect dependencies from all awb modules
        else:
            vbinDeps += moduleList.getAllDependencies('VERILOG') + moduleList.getAllDependencies('VHDL') + moduleList.getAllDependencies('BA') + map(modify_path_ba_local, moduleList.getAllDependenciesWithPaths('GEN_BAS'))


        vbin = moduleList.env.Command(
            TMP_BSC_DIR + '/' + APM_NAME + '_hw.exe',
            vbinDeps,
            [ vexe_gen_command,
              SCons.Script.Delete('directc.sft') ])

        vexe = moduleList.env.Command(
            APM_NAME + '_hw.exe',
            vbin,
            [  generate_vexe_wrapper,
              '@chmod a+x $TARGET',
            SCons.Script.Delete(APM_NAME + '_hw.errinfo') ])


        moduleList.topDependency = moduleList.topDependency + [vexe]

    else:
        vbinDeps = moduleList.getAllDependencies('VERILOG') + moduleList.getAllDependencies('VHDL') + moduleList.getAllDependencies('BA') + map(modify_path_ba_local, moduleList.getAllDependenciesWithPaths('GEN_BAS'))

        vbin = moduleList.env.Command(
            TMP_BSC_DIR + '/' + APM_NAME + '_hw.vexe',
            vbinDeps,
            [ vexe_gen_command,
              SCons.Script.Delete('directc.sft') ])


        vexe = moduleList.env.Command(
            APM_NAME + '_hw.vexe',
            vbin,
            [ generate_vexe_wrapper,
              '@chmod a+x $TARGET',
              SCons.Script.Delete(APM_NAME + '_hw.exe'),
            SCons.Script.Delete(APM_NAME + '_hw.errinfo') ])

    moduleList.env.Alias('vexe', vexe)
