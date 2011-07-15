##
## Build pipeline for software simulation
##

import os
import re
import SCons.Script  
from iface_tool import *
from bsv_tool import *
from bluesim_tool import *
from verilog_tool import *
from software_tool import *
from wrapper_gen_tool import *
from model import  *

class Build(ProjectDependency):
  def __init__(self, moduleList):
    WrapperGen(moduleList)
    # Build interface first 
    Iface(moduleList)
    bsv = BSV(moduleList)
    if not bsv.isDependsBuild:
      Bluesim(moduleList)
      # Included to support optional Verilog build
      Verilog(moduleList, False)
      Software(moduleList)
