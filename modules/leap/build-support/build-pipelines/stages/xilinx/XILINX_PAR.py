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

    self.COST_TABLE       = moduleList.getAWBParam('xilinx_map', 'COST_TABLE')
    self.DUMP_UTILIZATION = moduleList.getAWBParam('xilinx_par', 'DUMP_UTILIZATION')
    self.MEMOIZE_NCD      = moduleList.getAWBParam('xilinx_par', 'MEMOIZE_NCD')

    xilinx_version = getXilinxVersion()

    # xilinx changed the -t option in versions greater than 12.1
    placer_table = ' -t ' + str(self.COST_TABLE) + ' '
    multi_thread = ''
    if(xilinx_version > 120):
      placer_table = ' '
      multi_thread = '-mt 4 ' 

    fpga_part_xilinx = moduleList.env['DEFS']['FPGA_PART_XILINX']
    xilinx_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName
    # Place and route
    memoize_ncd_command = []
    if(self.MEMOIZE_NCD):
        memoize_ncd_command = [SCons.Script.Copy(moduleList.smartguide_cache_dir + '/' + moduleList.smartguide_cache_file, '$TARGET')] 

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
        'par -w -ol high ' + moduleList.smartguide + placer_table + multi_thread + xilinx_apm_name + '_map.ncd $TARGET ' + xilinx_apm_name + '.pcf' ]
        + memoize_ncd_command)


    utilizationFile = moduleList.compileDirectory + '/dumpUtilization.tcl'

    # Once par is complete, we can dump a hierarchical utilization.
    def dump_utilization(target, source, env):
        tclHandle = open(utilizationFile,'w') 
        tclHandle.write('create_project -force ' + moduleList.apmName + ' ' + xilinx_apm_name + '\n') # Need to know part? -part xc7vx485tffg1157-1
        tclHandle.write('set_property design_mode GateLvl [current_fileset]\n')

        # For reasons unclear to me, planAhead requires netlists.
        netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ] + moduleList.getAllDependencies('SYNTHESIS')

        tclHandle.write('set_property top mk_model_Wrapper [current_fileset]\n')
        tclHandle.write('add_files -norecurse {' + ' '.join(netlists) + '}\n')
        tclHandle.write('import_files -force -norecurse\n')
        tclHandle.write('import_as_run -run impl_1 ' + xilinx_apm_name + '_par.ncd\n')
        tclHandle.write('open_run impl_1 \n')
        tclHandle.write('report_utilization -file ' + xilinx_apm_name + '_par.util -hierarchical\n')
        #tclHandle.write('save_project_as -force ' + xilinx_apm_name + ' ' + moduleList.compileDirectory + '/' + xilinx_apm_name + '\n')
        tclHandle.close()

    if(self.DUMP_UTILIZATION):
        xilinx_utilization = moduleList.env.Command( 
            xilinx_apm_name + '_par.util',
            xilinx_apm_name + '_par.ncd',
            [ dump_utilization,
              'planAhead -mode batch -source ' + utilizationFile])
        moduleList.topDependency += [xilinx_utilization]
        
    moduleList.topModule.moduleDependency['PAR'] = [xilinx_par]

