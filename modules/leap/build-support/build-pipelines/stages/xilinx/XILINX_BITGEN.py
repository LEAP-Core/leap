import os
import SCons.Script
from model import  *

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class BITGEN():
  def __init__(self, moduleList):

    ## Virtex 7 gives errors on unconstrained pins.  For now we allow them
    ## until our designs have no spurious top-level wires (like RDY signals).
    try:
      fpga_tech = moduleList.getAWBParam('physical_platform_config', 'FPGA_TECHNOLOGY')
    except:
      fpga_tech = 'unknown'

    unconstrained_arg = ''
    if (fpga_tech == 'Virtex7'):
      unconstrained_arg = '-g UnconstrainedPins:Allow '

    fpga_part_xilinx = moduleList.env['DEFS']['FPGA_PART_XILINX']
    xilinx_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName
    # Generate the FPGA image
    xilinx_bit = moduleList.env.Command(
      xilinx_apm_name + '_par.bit',
      [ 'config/' + moduleList.apmName + '.ut' ] + moduleList.getAllDependencies('PAR'),
      [ SCons.Script.Delete('config/signature.sh'),
        SCons.Script.Delete(xilinx_apm_name + '_par.drc'),
        SCons.Script.Delete(xilinx_apm_name + '_par.msk'),
        'bitgen ' + unconstrained_arg + moduleList.elf + ' -m -f $SOURCES $TARGET ' + xilinx_apm_name + '.pcf' ])
    
    SCons.Script.Depends(xilinx_bit, Utils.clean_split(moduleList.env['DEFS']['GIVEN_ELFS'], sep = ' '));

    moduleList.topModule.moduleDependency['BIT'] = [xilinx_bit]
    moduleList.topDependency = moduleList.topDependency + [xilinx_bit]     
