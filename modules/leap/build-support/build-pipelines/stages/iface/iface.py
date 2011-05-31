import os
import re
import sys
import string
from model import  *

class Iface():

  def __init__(self, moduleList):
    cmd = ''
    if os.path.isfile('iface/SConstruct'):
        cmd = 'cd iface; scons; ln -s awb build/include/asim'
    if moduleList.env.GetOption('clean'):
        cmd += ' -c'
    s = os.system(cmd)
    if (s & 0xffff) != 0:
        print 'Aborting due to iface submodel errors'
        sys.exit(1)
