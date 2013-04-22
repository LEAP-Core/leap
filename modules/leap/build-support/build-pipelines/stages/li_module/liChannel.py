import sys
from code import *


class LIChannel():
  
  def __init__(self, sc_type, raw_type, module_idx, name, platform, optional, bitwidth, module_name, type_structure):
      self.sc_type = sc_type
      self.raw_type = raw_type
      self.name = name
      self.inverse_name = "ERROR"
      self.module_idx = module_idx # we don't care about the physical indexes yet. They get assigned during the match operation
      self.idx ="unassigned" # we don't care about the physical indexes yet. They get assigned during the match operation
      self.platform = platform
      self.optional = optional 
      self.bitwidth = int(bitwidth)
      self.matched = False
      self.module_name = module_name # this is only the name of the module
      self.inverse_sc_type = "ERROR"
      self.via_idx = "unassigned"
      self.via_link = "unassigned"
      self.type_structure = type_structure
      self.activity = -1 # this is used in lane allocation
      self.module = "unassigned" # the actual module object.  Assigned at graph construction time
      self.partnerModule = "unassigned"
      self.partnerChannel = "unassigned"

  def __repr__(self):
      return "{" + self.name + ":" + self.raw_type + ":" + self.sc_type + ":(idx)" + str(self.module_idx) + ":" + str(self.optional) + ":" + self.module_name + ":" + self.platform + " }"

  def copy(self):
      newChannel = LIChannel(self.sc_type, self.raw_type, self.module_idx, self.name, self.platform, self.optional, self.bitwidth, self.module_name, self.type_structure)
      return newChannel
  # can probably extend matches to support chains
  def matches(self, other):
      if (other.name == self.name):
          #do the types match?
          if (other.raw_type != self.raw_type):
              print "SoftConnection type mismatch for " + self.name + ": " + other.raw_type + " and " + self.raw_type
              sys.exit(-1)
   
          #Can't match if one is already matched
          if (other.matched or self.matched):
            return False

          if (other.sc_type == 'Recv' and self.sc_type == 'Send'):
              return True
          if (self.sc_type == 'Recv' and other.sc_type == 'Send'):
              return True

      return False

  def isSource(self):
      return self.sc_type == 'Send'

  def isSink(self):
      return self.sc_type == 'Recv'

  def linkPriority(self):
      if ((self.sc_type == 'Recv') or (self.sc_type == 'Send')):
        return 1
      else:
        return 2
