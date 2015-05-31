import os
import stat
import SCons.Script
from SCons.Errors import BuildError
import model 
import synthesis_library

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class LOADER():
  def __init__(self, moduleList):

    fpga_part_xilinx = moduleList.env['DEFS']['FPGA_PART_XILINX']
    xilinx_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName

    # Generate the signature for the FPGA image
    signature = moduleList.env.Command(
      'config/signature.sh',
      moduleList.getAllDependencies('BIT'),
      [ '@echo \'#!/bin/sh\' > $TARGET',
        '@echo signature=\\"' + moduleList.apmName + '-`md5sum $SOURCE | sed \'s/ .*//\'`\\" >> $TARGET' ])
    
    moduleList.topModule.moduleDependency['SIGNATURE'] = [signature]

    if (model.getBuildPipelineDebug(moduleList) != 0):
        print  moduleList.swExeOrTarget + "\n"

    ##
    ## Generate a script for loading bitfiles onto an FPGA.
    ##
    def leap_xilinx_loader(xilinx_apm_name):
      try:
        fpga_pos = moduleList.getAWBParam(['physical_platform_config', 'physical_platform'], 'FPGA_POSITION')
      except:
        fpga_pos = None

      def leap_xilinx_loader_closure(target, source, env):
        lf = open(str(target[0]), 'w')

        lf.write('#!/usr/bin/perl\n')
        lf.write('\n')
        lf.write('my $retval = 0;\n')
        if fpga_pos != None:
          lf.write('use Getopt::Long;\n')
          lf.write('my $dev_id = undef;\n')
          lf.write('GetOptions(\'device-id=i\', \$dev_id);\n')
          lf.write('\n')

          lf.write('# Check for existance of expected bitfile.\n') 
          lf.write('if ( ! -e  "' + xilinx_apm_name + '_par.bit" ) {\n')
          lf.write('  die "Could not find bitfile ' + xilinx_apm_name + '_par.bit";\n')
          lf.write('}\n')

          lf.write('# Specify specific cable if device database includes a cable ID\n')
          lf.write('my $setCable = \'setCable -p auto\';\n')
          lf.write('if (defined($dev_id)) {\n')
          lf.write('  my $cable_cfg = `leap-fpga-ctrl --device-id=${dev_id} --getconfig prog_cable_id`;\n')
          lf.write('  chomp($cable_cfg);\n')
          lf.write('  $setCable = "setCable $cable_cfg" if ($cable_cfg ne "");\n')
          lf.write('}\n')
          lf.write('\n')
          lf.write('open (BATCH,">batch.opt");\n')
          lf.write('print BATCH "setMode -bscan\n')
          lf.write('${setCable}\n')
          lf.write('identify\n')
          lf.write('assignfile -p ' + str(fpga_pos) + ' -file ' + xilinx_apm_name + '_par.bit\n')
          lf.write('program -p ' + str(fpga_pos) + '\n')
          lf.write('quit\n')
          lf.write('EOF\n')
          lf.write('";\n')
          lf.write('close(BATCH);\n')
          lf.write('open (STDOUT, ">$ARGV[0]");\n')
          lf.write('open (STDERR, ">$ARGV[0]");\n')
          lf.write('$retval = system("impact -batch batch.opt");\n')
        lf.write('if($retval != 0) {\n')
        lf.write('    exit(257);\n') # some perl installs only return an 8 bit value
        lf.write('}\n')

        lf.close()
        os.chmod(str(target[0]), stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                                 stat.S_IRGRP | stat.S_IXGRP |
                                 stat.S_IROTH | stat.S_IXOTH)

      return leap_xilinx_loader_closure
 
    loader = moduleList.env.Command(
      'config/' + moduleList.apmName + '.download',
      [],
      leap_xilinx_loader(xilinx_apm_name))

    dependOnSW = moduleList.getAWBParam(['xilinx_loader'], 'DEPEND_ON_SW')
    summary = 0
    if(dependOnSW):   
      summary = moduleList.env.Command(
        moduleList.apmName + '_hw.errinfo',
        moduleList.getAllDependencies('SIGNATURE') + moduleList.swExe,
        [ '@ln -fs ' + moduleList.swExeOrTarget + ' ' + moduleList.apmName,
          SCons.Script.Delete(moduleList.apmName + '_hw.exe'),
          SCons.Script.Delete(moduleList.apmName + '_hw.vexe'),
          '@echo "++++++++++++ Post-Place & Route ++++++++"',
          synthesis_library.leap_physical_summary(xilinx_apm_name + '.par.twr', moduleList.apmName + '_hw.errinfo', '^Slack \(MET\)', '^Slack \(VIOLATED\)') ])
    else:
      summary = moduleList.env.Command(
        moduleList.apmName + '_hw.errinfo',
        moduleList.getAllDependencies('SIGNATURE'),
        [ SCons.Script.Delete(moduleList.apmName + '_hw.exe'),
          SCons.Script.Delete(moduleList.apmName + '_hw.vexe'),
          '@echo "++++++++++++ Post-Place & Route ++++++++"',
          synthesis_library.leap_physical_summary(xilinx_apm_name + '.par.twr', moduleList.apmName + '_hw.errinfo', '^Slack \(MET\)', '^Slack \(VIOLATED\)') ])



    moduleList.env.Depends(summary, loader)

    moduleList.topModule.moduleDependency['LOADER'] = [summary]
    moduleList.topDependency = moduleList.topDependency + [summary]     
