import os
import re
import sys
import string
from model import  *

class Iface():

  def __init__(self, moduleList):
    # Create link for legacy asim include tree
    if not os.path.exists('iface/build/include/asim'):
      os.symlink('awb', 'iface/build/include/asim')

    if os.path.isfile('iface/SConstruct'):
      cmd = 'cd iface; scons'
      if moduleList.env.GetOption('clean'):
        cmd += ' -c'
      s = os.system(cmd)
      if (s & 0xffff) != 0:
        print 'Aborting due to iface submodel errors'
        sys.exit(1)
