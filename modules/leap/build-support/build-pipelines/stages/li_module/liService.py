import sys

from liModule import LIModule

# TODO: Some of the data in this structure would be better captured as
# an attribute dictionary.  This would also be more modular since
# external access could be hidden behind an accessor function.

class LIService():
  
    def __init__(self,
                 sc_type,
                 req_raw_type,
                 resp_raw_type,
                 module_idx,
                 name,
                 optional,
                 req_bitwidth,
                 resp_bitwidth,
                 idx_bitwidth,
                 module_name,
                 root_module_name,
                 client_idx,
                 type_structure):
        
        self.sc_type = sc_type
        self.req_raw_type = req_raw_type
        self.resp_raw_type = resp_raw_type
        self.name = name
        self.module_idx = module_idx # we don't care about the physical indexes yet. They get assigned during the match operation
        self.idx ="unassigned" # we don't care about the physical indexes yet. They get assigned during the match operation

        self.optional = False 
        self.req_bitwidth = int(req_bitwidth)
        self.resp_bitwidth = int(resp_bitwidth)
        self.idx_bitwidth = int(idx_bitwidth)
        self.matched = False
        self.module_name = module_name

        # Root module name associated with the channel endpoint
        self.root_module_name = root_module_name

        self.client_idx = client_idx

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
        self.attributes = {}

    def __repr__(self):
        partnerModule = "unassigned"
        partnerChannel = "unassigned"

        if(not isinstance(self.partnerChannel, str)):
            partnerChannel = self.partnerChannel.name

        if(not isinstance(self.partnerModule, str)):
            partnerModule = self.partnerModule.name
      
        return "{" + self.name + ":" + self.req_raw_type + ":" + self.resp_raw_type + ":" + self.sc_type + ":(physical idx)" + str(self.module_idx) + ":" + str(self.optional) + ":Module " + self.module_name + ":Platform " + self.platform() + "-> PartnerChannel " + partnerChannel + ": partnerModule " + partnerModule + " }"

    def unmatch(self):
        self.partnerModule = "unassigned"
        self.partnerChannel = "unassigned"
        self.matched = False
    
    def copy(self):
        newService = LIService(self.sc_type,
                               self.req_raw_type,
                               self.resp_raw_type,
                               self.module_idx,
                               self.name,
                               self.optional,
                               self.req_bitwidth,
                               self.resp_bitwidth,
                               self.idx_bitwidth,
                               self.module_name,
                               self.root_module_name,
                               self.client_idx,
                               self.type_structure)
        # Need to copy some other values as well...
        newService.attributes = dict(self.attributes)
        newService.activity = self.activity
        return newService

    def matches(self, other):
        if (other.name == self.name):
            #do the types match?
            if (other.req_raw_type != self.req_raw_type):
                print "SoftConnection request type mismatch for " + self.name + ": " + other.req_raw_type + " and " + self.req_raw_type
                sys.exit(-1)
            elif (other.resp_raw_type != self.resp_raw_type):
                print "SoftConnection response type mismatch for " + self.name + ": " + other.resp_raw_type + " and " + self.resp_raw_type
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
    
    def isClient(self):
        return self.sc_type == 'ServiceClient'

    def isServer(self):
        return self.sc_type == 'ServiceServer'

