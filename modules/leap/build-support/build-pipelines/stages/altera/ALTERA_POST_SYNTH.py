import os
import re
import sys
import SCons.Script
from model import  *

class PostSynthesize():

    def __init__(self, moduleList):
        altera_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName

        synthDeps = moduleList.topModule.moduleDependency['SYNTHESIS']

        # find any edif that we claim to have produced.
        edfs = []
        for dep in synthDeps:
            if (re.search(r"\.edf",str(dep))):
                edfs.append(str(dep))

        altera_vqm = []
        vqms = []
        print "EDFS: " + str(edfs) + '\n'
        for generatedEdif in edfs:
            vqm = generatedEdif.replace('.edf','.vqm')
            altera_vqm.append(moduleList.env.Command(generatedEdif.replace('.edf','.vqm'),
                                                     generatedEdif,
                                                     'cp $SOURCE $TARGET'))
            vqms.append(os.path.abspath(vqm))

        newPrjFile = open(altera_apm_name + '.temp.qsf', 'w')

        newPrjFile.write('set_global_assignment -name TOP_LEVEL_ENTITY ' + moduleList.topModule.wrapperName() + '\n')

        # vqm from synplify
        for vqm in vqms:
            newPrjFile.write('set_global_assignment -name VQM_FILE ' + str(vqm) + ' -library '  + os.path.basename(vqm).replace('.','_') + '\n')

        # add the verilogs of the files generated by quartus system builder
        for v in Utils.clean_split(moduleList.env['DEFS']['GIVEN_ALTERAVS'], sep = ' ') :
            newPrjFile.write('set_global_assignment -name VERILOG_FILE ' + v + '\n'); 

        newPrjFile.write('set_global_assignment -name SDC_FILE ' + moduleList.topModule.wrapperName() + '.scf\n')
        newPrjFile.close()

        # Concatenate altera QSF files
        altera_qsf = moduleList.env.Command(
          altera_apm_name + '.qsf',
          [altera_apm_name + '.temp.qsf'] + Utils.clean_split(moduleList.env['DEFS']['GIVEN_QSFS'], sep = ' '),
          ['cat $SOURCES > $TARGET',
           'rm ' + altera_apm_name + '.temp.qsf'])

        # generate sof
        altera_sof = moduleList.env.Command(altera_apm_name + '.sof',
                                            altera_vqm + altera_qsf,
                                            ['quartus_map --lib_path=`pwd` ' + altera_apm_name,
                                             'quartus_fit ' + altera_apm_name,
                                             'quartus_sta ' + altera_apm_name,
                                             'quartus_asm ' + altera_apm_name])

        moduleList.topModule.moduleDependency['BIT'] = [altera_sof]

        # generate the download program
        newDownloadFile = open('config/' + moduleList.apmName + '.download.temp', 'w')
        newDownloadFile.write('#!/bin/sh\n')
        newDownloadFile.write('nios2-configure-sof ' + altera_apm_name + '.sof\n')
        newDownloadFile.close()

        altera_download = moduleList.env.Command(
            'config/' + moduleList.apmName + '.download',
            'config/' + moduleList.apmName + '.download.temp',
            ['cp $SOURCE $TARGET',
             'chmod 755 $TARGET'])

        altera_loader = moduleList.env.Command(
            moduleList.apmName + '_hw.errinfo',
            moduleList.swExe + moduleList.topModule.moduleDependency['BIT'] + altera_download,
            ['@ln -fs ' + moduleList.swExeOrTarget + ' ' + moduleList.apmName,
             SCons.Script.Delete(moduleList.apmName + '_hw.exe'),
             SCons.Script.Delete(moduleList.apmName + '_hw.vexe'),
             '@echo "++++++++++++ Post-Place & Route ++++++++"',
             'touch ' + moduleList.apmName + '_hw.errinfo'])

        moduleList.topModule.moduleDependency['LOADER'] = [altera_loader]
        moduleList.topDependency = moduleList.topDependency + [altera_loader]
