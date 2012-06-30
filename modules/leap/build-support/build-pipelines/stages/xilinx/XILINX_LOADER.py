import os
import stat
import SCons.Script
from model import  *

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class LOADER():
  def __init__(self, moduleList):

    fpga_part_xilinx = moduleList.env['DEFS']['FPGA_PART_XILINX']
    xilinx_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName
    # Generate the FPGA timing report -- this report isn't built by default.  Use
    # the "timing" target to generate it
    xilinx_trce = moduleList.env.Command(
      xilinx_apm_name + '_par.twr',
      moduleList.getAllDependencies('PAR') + [ xilinx_apm_name + '.pcf' ],
      'trce -e 100 $SOURCES -o $TARGET')

    moduleList.topModule.moduleDependency['TRCE'] = [xilinx_trce]

    # Generate the signature for the FPGA image
    signature = moduleList.env.Command(
      'config/signature.sh',
      moduleList.getAllDependencies('BIT'),
      [ '@echo \'#!/bin/sh\' > $TARGET',
        '@echo signature=\\"' + moduleList.apmName + '-`md5sum $SOURCE | sed \'s/ .*//\'`\\" >> $TARGET' ])
    
    moduleList.topModule.moduleDependency['SIGNATURE'] = [signature]

    if (getBuildPipelineDebug(moduleList) != 0):
        print  moduleList.swExeOrTarget + "\n"

    ##
    ## Generate a script for loading bitfiles onto an FPGA.
    ##
    def leap_xilinx_loader(xilinx_apm_name):
      fpga_pos = moduleList.getAWBParam('physical_platform', 'FPGA_POSITION')

      def leap_xilinx_loader_closure(target, source, env):
        lf = open(str(target[0]), 'w')

        lf.write('#!/usr/bin/perl\n')
        lf.write('\n')
        lf.write('use Getopt::Long;\n')
        lf.write('my $dev_id = undef;\n')
        lf.write('GetOptions(\'device-id=i\', \$dev_id);\n')
        lf.write('\n')
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
        lf.write('assignfile -p 2 -file .xilinx/hello_hybrid_htg_par.bit\n')
        lf.write('program -p 2\n')
        lf.write('quit\n')
        lf.write('EOF\n')
        lf.write('";\n')
        lf.write('close(BATCH);\n')
        lf.write('open (PIPE, "impact -batch batch.opt 2>&1 | tee $ARGV[0] |");\n')
        lf.write('while(<PIPE>) {\n')
        lf.write('  if ($_ =~ /ERROR:iMPACT/) {exit(257);}\n')
        lf.write('  if ($_ =~ /autodetection failed/) {exit(257);}\n')
        lf.write('}\n')
        lf.write('exit(0);\n')

        lf.close()
        os.chmod(str(target[0]), stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                                 stat.S_IRGRP | stat.S_IXGRP |
                                 stat.S_IROTH | stat.S_IXOTH)

      return leap_xilinx_loader_closure


    ##
    ## Generate a summary of the build and write a target file describing
    ## whether the build was successful.
    ##
    def leap_xilinx_summary(xilinx_apm_name):
      def leap_xilinx_summary_closure(target, source, env):
        map_file = open(xilinx_apm_name + '_map.map','r')
        par_file = open(xilinx_apm_name + '_par.par','r')
        errinfo_file = open(str(target[0]), 'w')

        # handle map file        
        print('')
        emit_map = 0
        for full_line in map_file:
          line = full_line.rstrip()

          match = re.match(r'^Slice Logic Utilization:', line)
          if (match):
            emit_map=1

          last = re.match(r'^Peak Memory Usage:', line)
          if (last):
            break

          if (emit_map):
            if (     re.match(r'^ .*:', line) and
               not  re.search(r' O[56] ', line) and
               not  re.match(r'^$', line)):
              print line

        map_file.close()
        print ''

        timing_score = -1
        clk_err = 0

        for full_line in par_file:
          line = full_line.rstrip()
          match = re.match(r'^Timing Score: ([0-9]*)', line)
          if (match):
            timing_score = int(match.group(1))
        
          match = re.match(r'^\|.*\| *([0-9\.]*)ns\| *([0-9\.]*)ns\| *([0-9\.N/A]*)[ns]*\| *([0-9]*)\| *([0-9]*)\| *([0-9]*)\| *([0-9]*)\|', line)
          if (match):
            period_req = float(match.group(1))
            if match.group(3) == 'N/A':
              period_actual = float(match.group(2))
            else:
              period_actual = float(match.group(3))

            msg = 'Clock: Requires %6.2f MHz (%6.3f ns) / Achieves %6.2f MHz (%6.3f ns)' \
                     % (1000.0 / period_req, period_req, \
                        1000.0 / period_actual, period_actual)
            if (period_actual <= period_req):
              print msg
            else:
              print msg + ' ** ERROR **'
              errinfo_file.write(msg + ' ** ERROR **\n')

        par_file.close()

        if (timing_score < 0):
          print 'Failed to find timing score!'
          clk_err = 1

        if (clk_err or timing_score > 0):
          print '\n        ******** Design does NOT meet timing! ********\n'
          errinfo_file.write('Timing Score: ' + str(timing_score) + '\n')
        else:
          print '\nDesign meets timing.'

        print 'Timing Score: ' + str(timing_score)

        errinfo_file.close()

      return leap_xilinx_summary_closure
 
    loader = moduleList.env.Command(
      'config/' + moduleList.apmName + '.download',
      [],
      leap_xilinx_loader(xilinx_apm_name))

    summary = moduleList.env.Command(
      moduleList.apmName + '_hw.errinfo',
      moduleList.getAllDependencies('SIGNATURE') + moduleList.swExe + moduleList.getAllDependencies('TRCE'),
      [ '@ln -fs ' + moduleList.swExeOrTarget + ' ' + moduleList.apmName,
        SCons.Script.Delete(moduleList.apmName + '_hw.exe'),
        SCons.Script.Delete(moduleList.apmName + '_hw.vexe'),
        '@echo "++++++++++++ Post-Place & Route ++++++++"',
        leap_xilinx_summary(xilinx_apm_name) ])

    moduleList.env.Depends(summary, loader)

    moduleList.topModule.moduleDependency['LOADER'] = [summary]
    moduleList.topDependency = moduleList.topDependency + [summary]     
