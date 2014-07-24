import sys
from code import *
from liModule import *

# TODO: Some of the data in this structure would be better captured as
# an attribute dictionary.  This would also be more modular since
# external access could be hidden behind an accessor function.


class LIChannel():
  
    def __init__(self, sc_type, raw_type, module_idx, name, optional, bitwidth, module_name, type_structure):
        self.sc_type = sc_type
        self.raw_type = raw_type
        self.name = name
        self.module_idx = module_idx # we don't care about the physical indexes yet. They get assigned during the match operation
        self.idx ="unassigned" # we don't care about the physical indexes yet. They get assigned during the match operation
        self.optional = optional 
        self.bitwidth = int(bitwidth)
        self.matched = False
        self.module_name = module_name # this is only the name of the module
        self.type_structure = type_structure
        self.via_idx_ingress = "unassigned"
        self.via_link_ingress = "unassigned"
        self.via_idx_egress = "unassigned"
        self.via_link_egress = "unassigned"
        self.activity = -1 # this is used in lane allocation
        self.module = "unassigned" # the actual module object.  Assigned at graph construction time
        self.partnerModule = "unassigned"
        self.partnerChannel = "unassigned"
        self.code = "" #Code() # This is used to store various definitions related to type compression


    def __repr__(self):

        partnerModule = "unassigned"
        partnerChannel = "unassigned"

        if(not isinstance(self.partnerChannel, str)):
            partnerChannel = self.partnerChannel.name

        if(not isinstance(self.partnerModule, str)):
            partnerModule = self.partnerModule.name
      
        return "{" + self.name + ":" + self.raw_type + ":" + self.sc_type + ":(physical idx)" + str(self.module_idx) + ":" + str(self.optional) + ":Module " + self.module_name + ":Platform " + self.platform() + "-> PartnerChannel " + partnerChannel + ": partnerModule " + partnerModule + ": RoutingInfo:" + self.routingInfo() +" }"

    def unmatch(self):
        self.partnerModule = "unassigned"
        self.partnerChannel = "unassigned"
        self.matched = False

    def copy(self):
        newChannel = LIChannel(self.sc_type, self.raw_type, self.module_idx, self.name, self.optional, self.bitwidth, self.module_name, self.type_structure)
        # Need to copy some other values as well...
        newChannel.activity = self.activity
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

    def platform(self):
        if(isinstance(self.module, LIModule)):
            if(self.module.getAttribute('MAPPING') is None):
                return "unassigned"
            else:
                return self.module.getAttribute('MAPPING')
        else:
            return "unassigned"

    # TODO: This is a less than satifactory was of getting the
    # to-software LIChannels to compile
    def CPPType(self):
        typeMod = self.raw_type.replace('#', '_po_')
        typeMod = typeMod.replace('(', '_lp_')
        typeMod = typeMod.replace(')', '_rp_')
        typeMod = typeMod.replace(',', '_cm_')
        typeMod = typeMod.replace(':', '_cn_')
        typeMod = typeMod.replace(' ', '_s_')

        return typeMod



    def routingInfo(self):
        return  "Ingress (via idx): " + str(self.via_idx_ingress) + " (via_vc): " + str(self.via_link_ingress)  + \
            " Egress (via idx): " + str(self.via_idx_egress) + " (via_vc): " + str(self.via_link_egress)  + \
            "Activity: " + str(self.activity)
