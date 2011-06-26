
import os
import re
import sys
import string
from model import  *
from bsv_tool import *
from config import *

class Bluesim():

  def __init__(self, moduleList):
    # get rid of this at some point - since we know we're in 
    # bluesim, we should be able to do the right thing.
    APM_NAME = moduleList.env['DEFS']['APM_NAME']
    BSC = moduleList.env['DEFS']['BSC']
    BSC_FLAGS_SIM = '-v -steps 10000000 +RTS -K1000M -RTS -keep-fires -aggressive-conditions -wait-for-license -no-show-method-conf -no-opt-bool -licenseWarning 7 -elab -show-schedule -l pthread'

    LDFLAGS = moduleList.env['DEFS']['LDFLAGS']
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    ROOT_WRAPPER_SYNTH_ID = 'mk_' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper'

    bsc_sim_command = BSC + ' ' + BSC_FLAGS_SIM + ' ' + LDFLAGS + ' -o $TARGET'


    if (getBluespecVersion() >= 13013):
        # 2008.01.A compiler allows us to pass C++ arguments.
        if (getDebug(moduleList)):
            bsc_sim_command += ' -Xc++ -O0'
        else:
            bsc_sim_command += ' -Xc++ -O1'

    bsc_sim_command += \
        ' -sim -e ' + ROOT_WRAPPER_SYNTH_ID + ' -simdir ' + \
        TMP_BSC_DIR + ' ' + moduleList.env['DEFS']['GEN_BAS'] + ' ' + moduleList.env['DEFS']['GIVEN_BAS'] + \
        ' ' + moduleList.env['DEFS']['BDPI_CS']

    linker_str = ''
    for lib in moduleList.swLibs:
      linker_str += ' ' + lib + ' '
  
    bsc_sim_command += linker_str + linker_str 


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
