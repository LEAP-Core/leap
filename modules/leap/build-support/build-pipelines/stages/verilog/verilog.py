
import os
import re
import sys
import string
from model import  *
from bsv_tool import *

class Verilog():

  def __init__(self, moduleList, isPrimaryBuildTarget):
    APM_NAME = moduleList.env['DEFS']['APM_NAME']
    BSC = moduleList.env['DEFS']['BSC']
    BSC_FLAGS_VERILOG = '-steps 10000000 +RTS -K1000M -RTS -keep-fires -aggressive-conditions -wait-for-license -no-show-method-conf -no-opt-bool -licenseWarning 7 -elab -show-schedule -verilog'

    LDFLAGS = moduleList.env['DEFS']['LDFLAGS']
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    ROOT_WRAPPER_SYNTH_ID = 'mk_' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper'

    vexe_gen_command = \
        BSC + ' ' + BSC_FLAGS_VERILOG + ' -vdir ' + moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '/' + moduleList.env['DEFS']['TMP_BSC_DIR'] + \
        ' -o $TARGET -verilog -e ' + ROOT_WRAPPER_SYNTH_ID + \
        ' $SOURCES ' + moduleList.env['DEFS']['BDPI_CS']

    if (getBuildPipelineDebug(moduleList) != 0):
        for m in moduleList.getAllDependencies('BA'):
            print 'BA dep: ' + str(m)
        for m in moduleList.getAllDependencies('VERILOG'):
            print 'VL dep: ' + str(m)
        for m in moduleList.getAllDependencies('VHDL'):
            print 'BA dep: ' + str(m)
        print

    vbin = moduleList.env.Command(
        TMP_BSC_DIR + '/' + APM_NAME + '_hw.vexe',
        moduleList.getAllDependencies('VERILOG') +
        moduleList.getAllDependencies('VHDL') +
        moduleList.getAllDependencies('BA'),
        [ vexe_gen_command,
          SCons.Script.Delete('directc.sft') ])

    vexe = moduleList.env.Command(
        APM_NAME + '_hw.vexe',
        vbin + moduleList.swExe,
        [ '@echo "#!/bin/sh" > $TARGET',
          '@echo "./$SOURCE +bscvcd \$*" >> $TARGET',
          '@chmod a+x $TARGET',
          '@ln -fs ' + moduleList.swExeOrTarget + ' ' + APM_NAME,
          SCons.Script.Delete(APM_NAME + '_hw.exe'),
          SCons.Script.Delete(APM_NAME + '_hw.errinfo') ])

    if (isPrimaryBuildTarget):
        moduleList.topDependency = moduleList.topDependency + [vexe]

    moduleList.env.Alias('vexe', vexe)
