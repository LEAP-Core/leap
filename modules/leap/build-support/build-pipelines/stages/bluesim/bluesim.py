
import os
import re
import sys
import string
from model import  *
from bsv_tool import *
from software_tool import *


class Bluesim():

  def __init__(self, moduleList):
    # get rid of this at some point - since we know we're in 
    # bluesim, we should be able to do the right thing.
    APM_NAME = moduleList.env['DEFS']['APM_NAME']
    BSC = moduleList.env['DEFS']['BSC']
    inc_paths = moduleList.swIncDir # we need to depend on libasim

    bsc_version = getBluespecVersion()
    
    BSC_FLAGS_SIM = '-steps 10000000 +RTS -K1000M -RTS -keep-fires -aggressive-conditions -wait-for-license -no-show-method-conf -no-opt-bool -licenseWarning 7 -elab -show-schedule -l pthread '

    # Build in parallel.
    n_jobs = moduleList.env.GetOption('num_jobs')
    if (bsc_version >= 30006):
        BSC_FLAGS_SIM += '-parallel-sim-link ' + str(n_jobs) + ' '

    for path in inc_paths:
        BSC_FLAGS_SIM += '-I ' + path + ' '

    LDFLAGS = moduleList.env['DEFS']['LDFLAGS']
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    ROOT_WRAPPER_SYNTH_ID = 'mk_' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper'

    bsc_sim_command = BSC + ' ' + BSC_FLAGS_SIM + ' ' + LDFLAGS + ' -o $TARGET'

    # Set MAKEFLAGS because Bluespec is going to invoke make on its own and
    # we don't want to pass on the current build's recursive flags.
    bsc_sim_command = 'env MAKEFLAGS="-j ' + str(n_jobs) + '" ' + bsc_sim_command


    if (bsc_version >= 13013):
        # 2008.01.A compiler allows us to pass C++ arguments.
        if (getDebug(moduleList)):
            bsc_sim_command += ' -Xc++ -O0'
        else:
            bsc_sim_command += ' -Xc++ -O1'

        # g++ 4.5.2 is complaining about overflowing the var tracking table

        if (getGccVersion() >= 40501):
             bsc_sim_command += ' -Xc++ -fno-var-tracking-assignments'

    defs = (host_defs()).split(" ")
    for definition in defs:
      bsc_sim_command += ' -Xc++ ' + definition + ' -Xc ' + definition

    bsc_sim_command += \
        ' -sim -e ' + ROOT_WRAPPER_SYNTH_ID + ' -simdir ' + \
        TMP_BSC_DIR + ' ' + moduleList.env['DEFS']['GEN_BAS'] + ' ' + moduleList.env['DEFS']['GIVEN_BAS'] + \
        ' ' + moduleList.env['DEFS']['BDPI_CS']

    if (getBuildPipelineDebug(moduleList) != 0):
        for ba in moduleList.getAllDependencies('BA'):
            print 'BA dep: ' + str(ba) + '\n'

    sbin = moduleList.env.Command(
        TMP_BSC_DIR + '/' + APM_NAME + '_hw.exe',
        moduleList.getAllDependencies('BA') + 
        moduleList.getAllDependencies('BDPI_CS') + moduleList.getAllDependencies('BDPI_HS'),
        bsc_sim_command)

    if moduleList.env.GetOption('clean'):
        os.system('rm -rf .bsc')

    # If we have bsc data files, copy them over to the .bsc directory 
    if len(moduleList.getAllDependencies('GEN_VS'))> 0:
       Copy(TMP_BSC_DIR,  moduleList.getAllDependencies('GIVEN_DATAS')) 

    #
    # The final step must leave a few well known names:
    #   APM_NAME must be the software side, if there is one.  If there isn't, then
    #   it must be the Bluesim image.
    #
    if (getBuildPipelineDebug(moduleList) != 0):
        print "ModuleList desp : " + str(moduleList.swExe)

    exe = moduleList.env.Command(
        APM_NAME + '_hw.exe', 
        sbin + moduleList.getAllDependencies('BDPI_CS') + moduleList.getAllDependencies('BDPI_HS'),
        [ '@ln -fs ${SOURCE} ${TARGET}',
          '@ln -fs ${SOURCE}.so ${TARGET}.so',
          '@ln -fs ' + moduleList.swExeOrTarget + ' ' + APM_NAME,
          SCons.Script.Delete(APM_NAME + '_hw.vexe'),
          SCons.Script.Delete(APM_NAME + '_hw.errinfo') ])

    moduleList.topDependency = moduleList.topDependency + [exe] 
