import sys
from code import *
from liModule import *

# TODO: Some of the data in this structure would be better captured as
# an attribute dictionary.  This would also be more modular since
# external access could be hidden behind an accessor function.

class LIChain():
  
    def __init__(self, sc_type, raw_type, module_idx, name, optional, bitwidth, module_name, chainroot, type_structure):
        self.sc_type = sc_type
        self.raw_type = raw_type
        self.name = name
        self.module_idx = module_idx # we don't care about the physical indexes yet. They get assigned during the match operation
        self.idx ="unassigned" # we don't care about the physical indexes yet. They get assigned during the match operation

        self.optional = optional 
        self.bitwidth = int(bitwidth)
        self.matched = False
        self.module_name = module_name
        self.chainroot = chainroot
        self.via_idx_ingress = "unassigned"
        self.via_link_ingress = "unassigned"
        self.via_idx_egress = "unassigned"
        self.via_link_egress = "unassigned"
        self.type_structure = type_structure
        self.activity = -1 # this is used in lane allocation
        self.module = "unassigned"
        self.sourcePartnerChain = "unassigned"
        self.sinkPartnerChain = "unassigned"
        self.sourcePartnerModule = "unassigned"
        self.sinkPartnerModule = "unassigned"

    def __repr__(self):
        # Partner objects may not be initialized.
        sourcePartnerChain = "unassigned"
        sinkPartnerChain = "unassigned"
        sourcePartnerModule = "unassigned"
        sinkPartnerModule = "unassigned"

        if(not isinstance(self.sourcePartnerChain, str)):
            sourcePartnerChain = self.sourcePartnerChain.name

        if(not isinstance(self.sinkPartnerChain, str)):
            sinkPartnerChain = self.sinkPartnerChain.name

        if(not isinstance(self.sourcePartnerModule, str)):
            sourcePartnerModule = self.sourcePartnerModule.name

        if( not isinstance(self.sinkPartnerModule, str)):
            sinkPartnerModule = self.sinkPartnerModule.name
   
        return "{" + self.name + ":" + self.raw_type + ":" + self.sc_type + ":(idx)" + str(self.module_idx) + ":" + str(self.optional) + ":" + self.module_name + "Platform: " + self.platform() + " : sink->" + sinkPartnerChain + ":" + sinkPartnerModule +  "source->" +  sourcePartnerChain + ":" + sourcePartnerModule +  " }"

    def unmatch(self):
        self.matched = False
        self.sourcePartnerChain = "unassigned"
        self.sinkPartnerChain = "unassigned"
        self.sourcePartnerModule = "unassigned"
        self.sinkPartnerModule = "unassigned"

    def copy(self):
        newChain = LIChain(self.sc_type, self.raw_type, self.module_idx, self.name, self.optional, self.bitwidth, self.module_name, self.chainroot, self.type_structure)

        newChain.activity = self.activity
        return newChain

    def matches(self, other):
        if (other.name == self.name):
            #do the types match?
            if (other.raw_type != self.raw_type):
                print "SoftConnection type mismatch for " + self.name + ": " + other.raw_type + " and " + self.raw_type
                sys.exit(-1)
     
            #Can't match if one is already matched
            if (other.matched or self.matched):
              return False

            return True

        return False

    def platform(self):
        if(isinstance(self.module, LIModule)):
            if(self.module.getAttribute('MAPPING') is None):
                return "unassigned"
            else:
                return self.module.getAttribute('MAPPING')
        else:
            return "unassigned"

    def isChain(self):
        return True


    
