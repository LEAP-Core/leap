import sys
from code import *


class LIChain():
  
  def __init__(self, sc_type, raw_type, module_idx, name, platform, optional, bitwidth, module_name, chainroot, type_structure):
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
      self.module_name = module_name
      self.chainroot = chainroot
      self.inverse_sc_type = "ERROR"
      self.via_idx = "unassigned"
      self.via_link = "unassigned"
      self.type_structure = type_structure
      self.activity = -1 # this is used in lane allocation
      self.module = "unassigned"
      self.sourcePartnerChain = "unassigned"
      self.sinkPartnerChain = "unassigned"

  def __repr__(self):
      return "{" + self.name + ":" + self.raw_type + ":" + self.sc_type + ":(idx)" + str(self.module_idx) + ":" + str(self.optional) + ":" + self.module_name + ":" + self.platform + " }"

  def copy(self):
      newChain = LIChain(self.sc_type, self.raw_type, self.module_idx, self.name, self.platform, self.optional, self.bitwidth, self.module_name, self.chainroot, self.type_structure)
      return newChain

  def matches(self, other):
      if(other.name == self.name):
          #do the types match?
          if(other.raw_type != self.raw_type):
              print "SoftConnection type mismatch for " + self.name + ": " + other.raw_type + " and " + self.raw_type
              sys.exit(-1)
   
          #Can't match if one is already matched
          if(other.matched or self.matched):
            return False

          return True

      return False

  def isChain(self):
      return True


