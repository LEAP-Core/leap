import os
import SCons.Script
from model import  *

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

def getXilinxVersion():
  # What is the Xilinx Tool version?
  xilinx_version = 0
  
  xilinx_ostream = os.popen('par -help')
  ver_regexp = re.compile('^Release ([0-9]+).([0-9]+)')
  for ln in xilinx_ostream.readlines():
    m = ver_regexp.match(ln)
    if (m):
      xilinx_version = 10*int(m.group(1)) + int(m.group(2))
  xilinx_ostream.close()

  if xilinx_version == 0:
    print "Failed to get Xilinx par version, is it in your path?"
    sys.exit(1)

  return xilinx_version

class PAR():
  def __init__(self, moduleList):

    xilinx_version = getXilinxVersion()

    # xilinx changed the -t option in versions greater than 12.1
    placer_table = ' -t ' + moduleList.env['DEFS']['COST_TABLE'] + ' '
    if(xilinx_version > 120):
      placer_table = ' '

    fpga_part_xilinx = moduleList.env['DEFS']['FPGA_PART_XILINX']
    xilinx_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName
    # Place and route
    xilinx_par = moduleList.env.Command(
      xilinx_apm_name + '_par.ncd',
      moduleList.getAllDependencies('MAP'),
      [ SCons.Script.Delete(xilinx_apm_name + '_par.pad'),
        SCons.Script.Delete(xilinx_apm_name + '_par.par'),
        SCons.Script.Delete(xilinx_apm_name + '_par.ptwx'),
        SCons.Script.Delete(xilinx_apm_name + '_par.unroutes'),
        SCons.Script.Delete(xilinx_apm_name + '_par.xpi'),
        SCons.Script.Delete(xilinx_apm_name + '_par_pad.csv'),
        SCons.Script.Delete(xilinx_apm_name + '_par_pad.txt'),
        'par -w -ol high ' + moduleList.smartguide + placer_table + xilinx_apm_name + '_map.ncd $TARGET ' + xilinx_apm_name + '.pcf',
        SCons.Script.Copy(moduleList.smartguide_cache_dir + '/' + moduleList.smartguide_cache_file, '$TARGET') ])

    moduleList.topModule.moduleDependency['PAR'] = [xilinx_par]
