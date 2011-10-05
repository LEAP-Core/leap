import os
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

    #
    # The final step must leave a few files in well-known locations since they are
    # used by the run scripts.  moduleList.apmName is the software side, if there is one.
    #
    if (getBuildPipelineDebug(moduleList) != 0):
        print  moduleList.swExeOrTarget + "\n"

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
      moduleList.apmName + '_hw.errinfo',
      moduleList.getAllDependencies('SIGNATURE') + moduleList.swExe + moduleList.getAllDependencies('TRCE'),
      [ '@ln -fs ' + moduleList.swExeOrTarget + ' ' + moduleList.apmName,
        SCons.Script.Delete(moduleList.apmName + '_hw.exe'),
        SCons.Script.Delete(moduleList.apmName + '_hw.vexe'),
        '@echo "++++++++++++ Post-Place & Route ++++++++"',
        leap_xilinx_summary(xilinx_apm_name) ])

    moduleList.topModule.moduleDependency['LOADER'] = [loader]
    moduleList.topDependency = moduleList.topDependency + [loader]     
