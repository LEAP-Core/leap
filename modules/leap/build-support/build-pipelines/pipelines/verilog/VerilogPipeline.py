import os
import re
import SCons.Script  
from iface_tool import *
from bsv_tool import *
from verilog_tool import *
from software_tool import *
from model import  *
from wrapper_gen import *

class Build(ProjectDependency):
  def __init__(self, moduleList):
    WrapperGen(moduleList)
    #build interface first 
    Iface(moduleList)
    BSV(moduleList)
    Software(moduleList)
    Verilog(moduleList, True)
