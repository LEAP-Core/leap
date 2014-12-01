import os
import cPickle as pickle
from li_module import *

from model import  *
from config import  *

# import bsv interface code
from vector import *
from interface import *
from struct import *
from method import *
from prim import *

try:
    import area_group_tool
except ImportError:
    pass # we won't be using this tool.

# Scons really, really wants dependencies to be ordered. 
def generateWellKnownIncludes(fileHandle):
     fileHandle.write('// These are well-known/required leap modules\n')
     fileHandle.write('`include "awb/provides/smart_synth_boundaries.bsh"\n')
     fileHandle.write('`include "awb/provides/soft_connections.bsh"\n')
     fileHandle.write('`include "awb/provides/soft_services_lib.bsh"\n')
     fileHandle.write('`include "awb/provides/soft_services.bsh"\n')
     fileHandle.write('`include "awb/provides/soft_services_deps.bsh"\n')
     fileHandle.write('`include "awb/provides/soft_connections_debug.bsh"\n')
     fileHandle.write('`include "awb/provides/soft_connections_latency.bsh"\n')
     fileHandle.write('`include "awb/provides/physical_platform_utils.bsh"\n')
     fileHandle.write('`include "awb/provides/librl_bsv_base.bsh"\n')

def generateBAImport(module, importHandle):
    ifc = ''

    # do some bookkeeping on conenctions
    incoming = 0
    outgoing = 0
    chains = len(module.chains)
    for channel in module.channels:
        if(channel.isSource()):                     
            outgoing += 1
        else:
            incoming += 1


    importHandle.write("\ninterface IMP_" + module.name + ";\n")
    # Some modules may have a secondary interface.
    if('BSV_IFC' in module.objectCache):
        ifcHandle = open(module.objectCache['BSV_IFC'][0], 'r')
        bsvIfc = eval(ifcHandle.read())
        ifcEnv = {} # environment for module generation

        # Bluespec doesn't provide a good interface for analyzing clock 
        # relationships.  This is a hardcoded hack to get around this 
        # issue.
        if(module.getAttribute('PLATFORM_MODULE') is None):
            ifcEnv['DEFAULT_CLOCK'] = 'default_clock'
        else:
            ifcEnv['DEFAULT_CLOCK'] = 'device_physicalDrivers_clocksDriver_clock'
        bsvIfc.generateImportInterfaceTop(importHandle, ifcEnv)

    else:

        for channel in module.channels:
            if(channel.isSource()):
                importHandle.write('\tinterface PHYSICAL_CONNECTION_OUT services_fst_outgoing_' + str(channel.module_idx) + ";// " + channel.name + "\n")
            else:
                importHandle.write('\tinterface PHYSICAL_CONNECTION_IN services_fst_incoming_' + str(channel.module_idx) + ";// " + channel.name + "\n")
        for chain in module.chains:
            importHandle.write('\tinterface PHYSICAL_CONNECTION_OUT services_fst_chains_' + str(chain.module_idx) + "_outgoing;// " + chain.name + "\n")
            importHandle.write('\tinterface PHYSICAL_CONNECTION_IN services_fst_chains_' + str(chain.module_idx) + "_incoming;// " + chain.name + "\n")

        
    importHandle.write("endinterface\n\n")


    importHandle.write('import "BVI" module mk_' + module.name + '_Converted (IMP_' + module.name + ');\n\n')

    if('BSV_IFC' in module.objectCache):
        if(module.getAttribute('PLATFORM_MODULE') is None):
             importHandle.write('default_clock default_clock(CLK);\n')
             importHandle.write('default_reset default_reset(RST_N) clocked_by(default_clock);\n')
        bsvIfc.generateImport(importHandle, ifcEnv)
    else:
        for channel in module.channels:
            if(channel.isSource()):                     

                importHandle.write('\tinterface PHYSICAL_CONNECTION_OUT services_fst_outgoing_' + str(channel.module_idx) + ";// " + channel.name + "\n")
                importHandle.write('\t\tmethod services_fst_outgoing_' + str(channel.module_idx) + '_notEmpty notEmpty() ready(RDY_services_fst_outgoing_' + str(channel.module_idx) + '_notEmpty);\n')
                importHandle.write('\t\tmethod services_fst_outgoing_' + str(channel.module_idx) + '_first first() ready(RDY_services_fst_outgoing_' + str(channel.module_idx) + '_first);\n')
                importHandle.write('\t\tmethod deq() ready(RDY_services_fst_outgoing_' + str(channel.module_idx) + '_deq) enable(EN_services_fst_outgoing_' + str(channel.module_idx) + '_deq);\n')
                importHandle.write('\t\toutput_clock clock(CLK_services_fst_outgoing_' + str(channel.module_idx) + '_clock);\n')
                importHandle.write('\t\toutput_reset reset(RST_N_services_fst_outgoing_' + str(channel.module_idx) + '_reset);\n')
                importHandle.write('\tendinterface\n\n')
            else:

                importHandle.write('\tinterface PHYSICAL_CONNECTION_IN services_fst_incoming_' + str(channel.module_idx) + ";// " + channel.name + "\n")
                importHandle.write('\t\tmethod try(services_fst_incoming_' + str(channel.module_idx) + '_try_d) ready(RDY_services_fst_incoming_' + str(channel.module_idx)  + '_try) enable(EN_services_fst_incoming_' + str(channel.module_idx) + '_try);\n')
                importHandle.write('\t\tmethod services_fst_incoming_' + str(channel.module_idx) + '_success  success() ready( RDY_services_fst_incoming_' + str(channel.module_idx) + '_success);\n')
                importHandle.write('\t\tmethod services_fst_incoming_' + str(channel.module_idx) + '_dequeued  dequeued() ready(RDY_services_fst_incoming_' + str(channel.module_idx) + '_dequeued);\n')
                importHandle.write('\t\toutput_clock clock(CLK_services_fst_incoming_' + str(channel.module_idx) + '_clock);\n')
                importHandle.write('\t\toutput_reset reset(RST_N_services_fst_incoming_' + str(channel.module_idx) + '_reset);\n')
                importHandle.write('\tendinterface\n\n')

        for chain in module.chains:
                importHandle.write('\tinterface PHYSICAL_CONNECTION_OUT services_fst_chains_' + str(chain.module_idx) + "_outgoing;// " + chain.name + "\n")
                importHandle.write('\t\tmethod services_fst_chains_' + str(chain.module_idx) + '_outgoing_notEmpty notEmpty() ready(RDY_services_fst_chains_' + str(chain.module_idx) + '_outgoing_notEmpty);\n')
                importHandle.write('\t\tmethod services_fst_chains_' + str(chain.module_idx) + '_outgoing_first first() ready(RDY_services_fst_chains_' + str(chain.module_idx) + '_outgoing_first);\n')
                importHandle.write('\t\tmethod deq() ready(RDY_services_fst_chains_' + str(chain.module_idx) + '_outgoing_deq) enable(EN_services_fst_chains_' + str(chain.module_idx) + '_outgoing_deq);\n')
                importHandle.write('\t\toutput_clock clock(CLK_services_fst_chains_' + str(chain.module_idx) + '_outgoing_clock);\n')
                importHandle.write('\t\toutput_reset reset(RST_N_services_fst_chains_' + str(chain.module_idx) + '_outgoing_reset);\n')
                importHandle.write('\tendinterface\n\n')

                importHandle.write('\tinterface PHYSICAL_CONNECTION_IN services_fst_chains_' + str(chain.module_idx) + "_incoming;// " + chain.name + "\n")
                importHandle.write('\t\tmethod try(services_fst_chains_' + str(chain.module_idx) + '_incoming_try_d) ready(RDY_services_fst_chains_' + str(chain.module_idx)  + '_incoming_try) enable(EN_services_fst_chains_' + str(chain.module_idx) + '_incoming_try);\n')
                importHandle.write('\t\tmethod services_fst_chains_' + str(chain.module_idx) + '_incoming_success  success() ready( RDY_services_fst_chains_' + str(chain.module_idx) + '_incoming_success);\n')
                importHandle.write('\t\tmethod services_fst_chains_' + str(chain.module_idx) + '_incoming_dequeued  dequeued() ready(RDY_services_fst_chains_' + str(chain.module_idx) + '_incoming_dequeued);\n')
                importHandle.write('\t\toutput_clock clock(CLK_services_fst_chains_' + str(chain.module_idx) + '_incoming_clock);\n')
                importHandle.write('\t\toutput_reset reset(RST_N_services_fst_chains_' + str(chain.module_idx) + '_incoming_reset);\n')
                importHandle.write('\tendinterface\n\n')
        
            
    # We cached scheduling and path information during the first pass. Use it now. 
    bsvPathHandle   = open(module.objectCache['BSV_PATH'][0], 'r')
    bsvSchedHandle  = open(module.objectCache['BSV_SCHED'][0], 'r')

    importHandle.write(bsvPathHandle.read() + '\n\n\n')
    importHandle.write(bsvSchedHandle.read() + '\n\n\n')

    importHandle.write('endmodule\n\n')

    # Change module generation code below here to use this new interface!
                     
    importHandle.write('(*synthesize*)\n')

    if('BSV_IFC' in module.objectCache):        
        ifc = bsvIfc.type
        importHandle.write('module mk_' + module.name + '_Wrapper (' + ifc + ');\n')

        # This code is very similar to module code below.  We should refactor.
        importHandle.write("\tlet m <- mk_" + module.name + "_Converted();\n")

        # two phases 1) interface definition.  I allow my children to define 2) interface binding I bind my children. 
        bsvIfc.generateHierarchy(importHandle, '\t', 'm', ifcEnv)
        importHandle.write('return ' + bsvIfc.getDefinition()  + ';\n')

    else:
        ifc = 'SOFT_SERVICES_SYNTHESIS_BOUNDARY#(' + str(incoming) + ', ' + str(outgoing) + ', 0, 0, ' + str(chains) + ', Empty)'

        importHandle.write('module mk_' + module.name + '_Wrapper (' + ifc + ');\n')

        # This code is very similar to module code below.  We should refactor.
        importHandle.write("\tlet m <- mk_" + module.name + "_Converted();\n") 
        module_body = ''

        subinterfaceType = "WITH_CONNECTIONS#(" + str(incoming) + ", " +\
                           str(outgoing) + ", 0, 0, " + str(chains) + ")"
        
        for channel in module.channels:
            if(channel.isSource()):                     
                module_body += "\toutgoingVec[" + str(channel.module_idx) + "] = m.services_fst_outgoing_" + str(channel.module_idx) + ";\n"
            else:
                module_body += "\tincomingVec[" + str(channel.module_idx) + "] = m.services_fst_incoming_" + str(channel.module_idx) + ";\n"

        for chain in module.chains:
            module_body += "\tchainsVec[" + str(chain.module_idx) + "] = PHYSICAL_CHAIN{outgoing: m.services_fst_chains_" + str(chain.module_idx) + "_outgoing, incoming: m.services_fst_chains_" + str(chain.module_idx) + "_incoming};\n"

        #declare interface vectors
        importHandle.write("    Vector#(" + str(incoming) + ", PHYSICAL_CONNECTION_IN)  incomingVec = newVector();\n")
        importHandle.write("    Vector#(" + str(outgoing) + ", PHYSICAL_CONNECTION_OUT) outgoingVec = newVector();\n")
        importHandle.write("    Vector#(" + str(chains) + ", PHYSICAL_CHAIN) chainsVec = newVector();\n")

        # lay down module body
        importHandle.write(module_body)
                        
        # fill in external interface 

        importHandle.write("    let clk <- exposeCurrentClock();\n")
        importHandle.write("    let rst <- exposeCurrentReset();\n")

        importHandle.write("    " + subinterfaceType + " moduleIfc = interface WITH_CONNECTIONS;\n")
        importHandle.write("        interface incoming = incomingVec;\n")
        importHandle.write("        interface outgoing = outgoingVec;\n")
        importHandle.write("        interface chains = chainsVec;\n")                                   
        importHandle.write("        interface incomingMultis = replicate(PHYSICAL_CONNECTION_IN_MULTI{try: ?, success: ?, clock: clk, reset: rst});\n")
        importHandle.write("        interface outgoingMultis = replicate(PHYSICAL_CONNECTION_OUT_MULTI{notEmpty: ?, first: ?, deq: ?, clock: clk, reset: rst});\n")
        importHandle.write("    endinterface;\n")
                                     
        importHandle.write("    interface services = tuple3(moduleIfc,?,?);\n")
        importHandle.write("    interface device = ?;//e2;\n")

        
    importHandle.write("endmodule\n\n")        

    return ifc


##
## getFirstPassLIGraph() --
##   Load up LI graph from first pass. For now, we assume that this comes
##   from a file, but eventually this will be generated from the first
##   pass compilation.
##
_cacheFirstPassLIGraph = None

def getFirstPassLIGraph():
    # Already computed the result?  It will be the same for every call.
    global _cacheFirstPassLIGraph
    if (_cacheFirstPassLIGraph != None):
        return _cacheFirstPassLIGraph

    # The first pass will dump a well known file. 
    firstPassLIGraph = "lim.li"

    if (os.path.isfile(firstPassLIGraph)):
        # We got a valid LI graph from the first pass.
        pickle_handle = open(firstPassLIGraph, 'rb')
        first_pass_graph = pickle.load(pickle_handle)
        pickle_handle.close()
        _cacheFirstPassLIGraph = first_pass_graph
        return first_pass_graph

    return None


##
## generateSynthWrapper --
##   Generate the wrapper for an LI synthesis boundary.
##
def generateSynthWrapper(liModule,
                         synthHandle,
                         moduleType = 'Empty',
                         extraImports = []):
     _emitSynthWrapper(liModule,
                       synthHandle,
                       moduleType = moduleType,
                       extraImports = extraImports)

##
## generateTopSynthWrapper --
##   Similar to the generate generateSynthWrapper but only for the top level
##   wrapper that will be connected directly to the platform.  This level is
##   special, mainly because the platform compilation will not insert buffering
##   to cover the latency of long distance wires.  The buffering will be
##   inserted explicitly here before passing wires to the platform.  Buffer
##   insertion is governed by area constraints.
##
def generateTopSynthWrapper(liModule,
                            synthHandle,
                            localPlatformName,
                            areaConstraints = None,
                            moduleType='Empty',
                            extraImports = []):
     _emitSynthWrapper(liModule,
                       synthHandle,
                       moduleType = moduleType,
                       extraImports = extraImports,
                       localPlatformName = localPlatformName,
                       areaConstraints = areaConstraints)

##
## Internal routine that implements generateSynthWrapper and
## generateTopSynthWrapper.
##
def _emitSynthWrapper(liModule,
                      synthHandle,
                      moduleType='Empty',
                      extraImports=[],
                      localPlatformName = None,
                      # If areaConstraints is defined then localPlatformName
                      # must also be defined!
                      areaConstraints = None):
    synthHandle.write("//Generated by liModule.py\n")

    # It may be the case that a module has no li channels. If this is
    # the case, drop it.  This seems to prevent downstream tools from
    # erroring on empty modules.
    if((len(liModule.channels) == 0) and (len(liModule.chains) == 0)):
        synthHandle.write("\n\nmodule [Connected_Module] " + str(liModule.name) + "(" + moduleType + ");\n")
        synthHandle.write("    //Module has been optimized away.\n")
        synthHandle.write("    return ?;\n")
        synthHandle.write("endmodule\n")
        return

    synthHandle.write("`ifndef BUILD_" + str(liModule.name) +  "_WRAPPER\n") # these may not be needed
    synthHandle.write("`define BUILD_" + str(liModule.name) + "_WRAPPER\n")
    synthHandle.write('import Vector::*;\n')
    for importStm in extraImports:
            synthHandle.write('import ' + importStm + '::*;\n')
    synthHandle.write('`include "awb/provides/smart_synth_boundaries.bsh"\n')
    synthHandle.write('`include "awb/provides/soft_connections.bsh"\n')    
    synthHandle.write('import ' + liModule.name + '_Wrapper::*;\n')      

    _emitSynthModule(liModule, synthHandle, moduleType,
                     localPlatformName = localPlatformName,
                     areaConstraints = areaConstraints)

    synthHandle.write("`endif\n")


def _emitSynthModule(liModule,
                     synthHandle,
                     moduleType='Empty',
                     localPlatformName = None,
                     # If areaConstraints is defined then localPlatformName
                     # must also be defined!
                     areaConstraints = None):
    synthHandle.write("\n\nmodule [Connected_Module] " + liModule.name + "(" + moduleType + ");\n")

    synthHandle.write("    let mod <- liftModule(mk_" + liModule.name + '_Wrapper' + "());\n")
    synthHandle.write("    let connections = tpl_1(mod.services);\n")
    
    platform_ag = None
    if areaConstraints:
         platform_ag = areaConstraints.constraints[localPlatformName + "_platform"]


    ##
    ## Returns the name of a channel that is either directly the name of the
    ## interface object or a wrapped instance with buffers added to manage
    ## inter-module I/O latency.
    ##
    def maybeWrapConnection(ch_src, ch_idx, ch_suffix, ch_dir, root_name):
        # Name of the incoming/outgoing connection interface object
        connection = 'connections.' + ch_src + '[' + str(ch_idx) + ']'
        if (ch_suffix != ''):
            connection = connection + '.' + ch_suffix

        # Are area groups being managed?
        if (areaConstraints):
            # These connections will be attached to the platform.  If the wires
            # are long then insert buffers in the path.
            n_buf = areaConstraints.numIOBufs(areaConstraints.constraints[root_name],
                                              platform_ag)
            if (n_buf > 0):
                tmpName = 'buf_' + ch_src + '_' + ch_suffix + '_' + str(ch_idx)
                synthHandle.write('    let ' + tmpName + ' <- ' +\
                                  'mkBufferedConnection' + ch_dir + '(' +\
                                  connection + ', ' + str(n_buf) + ');\n')
                # Expose the buffered connection
                connection = tmpName

        return connection


    # these strings should probably made functions in the
    # liChannel code
    for channel in liModule.channels:
        ch_reg_stmt = 'registerRecv'
        ch_type = 'LOGICAL_RECV_INFO'
        ch_src = 'incoming'
        ch_dir = 'In'
        if (channel.isSource()):
            ch_reg_stmt = 'registerSend'
            ch_type = 'LOGICAL_SEND_INFO'
            ch_src = 'outgoing'
            ch_dir = 'Out'

        # Connection to pass to the platform.
        connection = maybeWrapConnection(ch_src,
                                         channel.module_idx,
                                         '',
                                         ch_dir,
                                         channel.root_module_name)

        # Expose the connection to the platform.
        synthHandle.write('    ' + ch_reg_stmt + '("' + channel.name + '", ' + ch_type +\
                          ' { logicalType: "' + channel.raw_type +\
                          '", optional: ' +\
                          str(channel.optional) + ', ' + ch_src + ': ' + connection +\
                          ', bitWidth:' + str(channel.bitwidth) +\
                          ', moduleName: "' + channel.module_name + '"});\n')   

    for chain in liModule.chains:
        chain_in = maybeWrapConnection('chains',
                                       chain.module_idx,
                                       'incoming',
                                       'In',
                                       chain.chain_root_in)

        chain_out = maybeWrapConnection('chains',
                                        chain.module_idx,
                                        'outgoing',
                                        'Out',
                                        chain.chain_root_out)

        synthHandle.write('    registerChain(LOGICAL_CHAIN_INFO { logicalName: "' +\
                          chain.name + '", logicalType: "' + chain.raw_type +\
                          '", incoming: ' + chain_in +\
                          ', outgoing: ' + chain_out +\
                          ', bitWidth:' + str(chain.bitwidth) +\
                          ', moduleNameIncoming: "' + chain.module_name +\
                          '",  moduleNameOutgoing: "' + chain.module_name + '"});\n')   

    synthHandle.write("    return mod.device;\n")
    synthHandle.write("endmodule\n")


def generateConnectionBSH(liModule, bshHandle):
    send = 0
    recv = 0
   
    for channel in liModule.channels:
        if (channel.isSource()):
            send += 1
        else:
            recv += 1
    chains = len(liModule.chains)

    bshHandle.write("//Generated by liModule.py\n")
    bshHandle.write("`ifndef CON_RECV_" + liModule.name + "\n")
    bshHandle.write("`define CON_RECV_" + liModule.name + " " + str(recv) + "\n")
    bshHandle.write("`endif\n")

    bshHandle.write("`ifndef CON_SEND_" + liModule.name + "\n")
    bshHandle.write("`define CON_SEND_" + liModule.name + " " + str(send) + "\n")
    bshHandle.write("`endif\n")
    bshHandle.write("`ifndef CON_RECV_MULTI_" + liModule.name + "\n")
    bshHandle.write("`define CON_RECV_MULTI_" + liModule.name + " 0\n")
    bshHandle.write("`endif\n")

    bshHandle.write("`ifndef CHAINS_" + liModule.name + "\n")
    bshHandle.write("`define CHAINS_" + liModule.name + " " + str(chains) + "\n")
    bshHandle.write("`endif\n")

    bshHandle.write("`ifndef CON_SEND_MULTI_" + liModule.name + "\n")
    bshHandle.write("`define CON_SEND_MULTI_" + liModule.name + " 0\n")
    bshHandle.write("`endif\n")

def getSynthHandle(moduleList, module):
    compileWrapperPath = get_build_path(moduleList, module)
    path = compileWrapperPath + '/' + module.name + '_synth.bsv'
    print "Generating synthesis stub: " + path
    return open(path, 'w')

def generateSynthStub(moduleList, module):
    wrapper = getSynthHandle(moduleList, module)
       
    wrapper.write('`include "awb/provides/soft_connections.bsh"\n')
    wrapper.write('`include "awb/provides/smart_synth_boundaries.bsh"\n')
    wrapper.write('`include "awb/provides/soft_connections.bsh"\n')
    wrapper.write('`include "awb/provides/soft_services_lib.bsh"\n')
    wrapper.write('`include "awb/provides/soft_services.bsh"\n')
    wrapper.write('`include "awb/provides/soft_services_deps.bsh"\n')
    wrapper.write('`include "awb/provides/soft_connections_debug.bsh"\n')
    wrapper.write('`include "awb/provides/soft_connections_latency.bsh"\n')
    wrapper.write('`include "awb/provides/physical_platform_utils.bsh"\n')
    wrapper.write('`include "awb/provides/virtual_platform.bsh"\n')

    compileWrapperPath = get_build_path(moduleList, module)
    conSizePath =  compileWrapperPath + '/' + module.name + "_Wrapper_con_size.bsh"
    wrapper.write('import ' + module.name + '_Wrapper::*;\n')        

    wrapper.write("module [Connected_Module] " + module.synthBoundaryModule + "(" + module.interfaceType + ");\n")
    wrapper.write("\nendmodule\n")

    wrapper.close()

def generateAWBCompileWrapper(moduleList, module):
    compileWrapperPath = get_build_path(moduleList, module)
    wrapper = open( compileWrapperPath + '/' + module.name + '_compile.bsv', 'w')

    wrapper.write('//   AWB Compile Wrapper. This file was created by wrapper-gen\n')  
    wrapper.write('`define BUILDING_MODULE_' + module.name + '\n')

    for bsv in module.moduleDependency['GIVEN_BSVS']:
        wrapper.write('`include "' + bsv +'"\n')
    wrapper.close()
 
# This function generates wrapper stubs so that depends-init does the right thing. 
def generateWrapperStub(moduleList, module):
    suffixes=['_Wrapper.bsv','_Log.bsv']
    compileWrapperPath = get_build_path(moduleList, module)
    for suffix in suffixes:
         # check for file's existance before overwriting. 
         wrapperPath = compileWrapperPath + '/' + module.name + suffix
         if(os.path.exists(wrapperPath)):
             # No need to dump a spurious wrapper.
             continue

         wrapper = open(wrapperPath, 'w')

         wrapper.write('//   Wrapper Stub. This file was created by wrapper-gen\n')  

         wrapper.write('import HList::*;\n')
         wrapper.write('import Vector::*;\n')
         wrapper.write('import ModuleContext::*;\n')
         generateWellKnownIncludes(wrapper)
         wrapper.write('// import non-synthesis public files\n')
         wrapper.write('`include "' + module.name + '_compile.bsv"\n')

         wrapper.close()

                      
#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path
# This is going to recursively build all the bsvs
class WrapperGen():

  def __init__(self, moduleList):
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    topModulePath = get_build_path(moduleList, moduleList.topModule)
    # The LIM compiler uniquifies synthesis boundary names  
    uidOffset = int(moduleList.getAWBParam('wrapper_gen_tool', 'MODULE_UID_OFFSET'))

    # We only inject the platform wrapper in first pass builds.  In
    # the second pass, we import the first pass object code.  It may
    # be that we need this code?

    # Inject a synth boundary for platform build code.  we need to
    # pick up some dependencies from the top level code.  this is a
    # pretty major hack, in my opinion. Better would be to actually
    # inspect the eventual .ba files for their dependencies. 
    platformName = moduleList.localPlatformName + '_platform'
    platformDeps = {}
    platformDeps['GEN_VERILOGS'] = []
    platformDeps['GEN_BAS'] = [] #moduleList.getSynthBoundaryDependencies(moduleList.topModule, 'GEN_BAS')                               
    platformDeps['GEN_VPI_HS'] = moduleList.getSynthBoundaryDependencies(moduleList.topModule, 'GEN_VPI_HS')                               
    platformDeps['GEN_VPI_CS'] = moduleList.getSynthBoundaryDependencies(moduleList.topModule, 'GEN_VPI_CS')                          
     
    #This is sort of a hack.
    platformDeps['GIVEN_BSVS'] = ['awb/provides/virtual_platform.bsh', 'awb/provides/physical_platform.bsh']
    platformDeps['BA'] = []
    platformDeps['STR'] = []
    platformDeps['VERILOG'] = [topModulePath + '/' + TMP_BSC_DIR + '/mk_' + platformName + '_Wrapper.v']
    platformDeps['BSV_LOG'] = []
    platformDeps['VERILOG_STUB'] = []
       
    platform_module = Module( platformName, ["mkVirtualPlatform"], moduleList.topModule.buildPath,\
                          moduleList.topModule.name,\
                          [], moduleList.topModule.name, [], platformDeps, platformModule=True)

    platform_module.dependsFile = '.depends-platform'
    platform_module.interfaceType = 'VIRTUAL_PLATFORM'
    platform_module.extraImports = ['virtual_platform']

    first_pass_LI_graph = getFirstPassLIGraph()
    if(first_pass_LI_graph is None):
        moduleList.insertModule(platform_module)
        moduleList.graphize()
        moduleList.graphizeSynth()
            
        # Sprinkle more files expected by the two-pass build.  
        generateWrapperStub(moduleList, platform_module)
        generateAWBCompileWrapper(moduleList, platform_module)

    else:
        platform_module_li = first_pass_LI_graph.modules[moduleList.localPlatformName + '_platform']

        # This gives us the right path. 
        synthHandle = getSynthHandle(moduleList, platform_module)

        # throw in some includes...
        synthHandle.write('import HList::*;\n')
        synthHandle.write('import Vector::*;\n')
        synthHandle.write('import ModuleContext::*;\n')
        synthHandle.write('import GetPut::*;\n')
        synthHandle.write('import Clocks::*;\n')
        synthHandle.write('`include "awb/provides/virtual_platform.bsh"\n')
        synthHandle.write('`include "awb/provides/physical_platform.bsh"\n')
        generateWellKnownIncludes(synthHandle)
        # May need an extra import here?
        # get the platform module from the LIGraph            
        generateBAImport(platform_module_li, synthHandle)
        # include synth stub here....
        _emitSynthModule(platform_module_li, synthHandle, platform_module.interfaceType)

    ## Here we use a module list sorted alphabetically in order to guarantee
    ## the generated wrapper files are consistent.  The topological sort
    ## guarantees only a depth first traversal -- not the same traversal
    ## each time.
    synth_modules = [moduleList.topModule] + moduleList.synthBoundaries()

    ## Models have the option of declaring top-level clocks that will
    ## be exposed as arguments.  When top-level clocks exist a single
    ## top-level reset is also defined.  To request no top-level clocks
    ## the variable N_TOP_LEVEL_CLOCKS should be removed from a platform's
    ## AWB configuration file, since Bluespec can't test the value of
    ## a preprocessor variable.
    try:
      n_top_clocks = int(moduleList.getAWBParam('physical_platform', 'N_TOP_LEVEL_CLOCKS'))
      if (n_top_clocks == 0):
        sys.stderr.write("Error: N_TOP_LEVEL_CLOCKS may not be 0 due to Bluespec preprocessor\n")
        sys.stderr.write("       limitations.  To eliminate top-level clocks, remove the AWB\n")
        sys.stderr.write("       parameter from the platform configuration.\n")
        sys.exit(1)
    except:
      n_top_clocks = 0

    for module in synth_modules:
      modPath = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/' + module.name
      wrapperPath =  modPath + "_Wrapper.bsv"
      logPath = modPath + "_Log.bsv"

      conSizePath =  modPath + "_Wrapper_con_size.bsh"
      ignorePath = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/.ignore'

      # clear out code on clean.
      if moduleList.env.GetOption('clean'):
          os.system('rm -f ' + wrapperPath)
          os.system('rm -f ' + logPath)
          os.system('rm -f ' + conSizePath)
          os.system('rm -f ' + ignorePath)
          if (module.name != moduleList.topModule.name):
              os.system('rm -f ' + modPath + '.bsv') 
          continue

      if (getBuildPipelineDebug(moduleList) != 0):
        print "Wrapper path is " + wrapperPath
      wrapper_bsv = open(wrapperPath, 'w')

      ignore_bsv = open(ignorePath, 'w')
      ignore_bsv.write("// Generated by wrapper_gen.py\n\n")

      # Connection size doesn't appear on the first dependence pass, since it
      # doesn't exist until after the first build.  Finding it later results in
      # build dependence changes and rebuilding.  Ignore it, since the file will
      # change only when some other file changes.
      ignore_bsv.write(conSizePath)
      ignore_bsv.close()

      # Generate a dummy connection size file to avoid errors during dependence
      # analysis.
      if not os.path.exists(conSizePath):
          dummyModule = LIModule(module.name, module.name)
          bsh_handle = open(conSizePath, 'w')
          generateConnectionBSH(dummyModule, bsh_handle)
          bsh_handle.close()

      wrapper_bsv.write('import HList::*;\n')
      wrapper_bsv.write('import Vector::*;\n')
      wrapper_bsv.write('import ModuleContext::*;\n')
      # the top module is handled specially
      if (module.name == moduleList.topModule.name):
        generateWellKnownIncludes(wrapper_bsv)
        wrapper_bsv.write('// These are well-known/required leap modules\n')
        wrapper_bsv.write('// import non-synthesis public files\n')

        # Include all subordinate synthesis boundaries for use by
        # instantiateAllSynthBoundaries() below.
        # If we're doing a LIM build, there are no *_synth.bsv for use codes.
        # Probably if we're doing a build tree they aren't necessary either, but
        # removing those dependencies would take a little work. 
        if(first_pass_LI_graph is None):
            for synth in synth_modules:
                if synth != module:
                    wrapper_bsv.write('`include "' + synth.name + '_synth.bsv"\n')

        # Provide a method that imports all subordinate synthesis
        # boundaries.  It will be invoked inside the top level model
        # in order to build all soft connections
        use_build_tree = moduleList.getAWBParam('wrapper_gen_tool', 'USE_BUILD_TREE')
        expose_all_connections = 0
        try:
            expose_all_connections = moduleList.getAWBParam('model', 'EXPOSE_ALL_CONNECTIONS')
        except:
            pass

        if (use_build_tree == 1):
            wrapper_bsv.write('\n\n`ifdef  CONNECTION_SIZES_KNOWN\n');
            # build_tree.bsv will get generated later, during the
            # leap-connect phase.
            wrapper_bsv.write('    import build_tree_synth::*;\n'); 
            wrapper_bsv.write('    module [Connected_Module] instantiateAllSynthBoundaries ();\n')
            wrapper_bsv.write('        let m <- build_tree();\n')
            wrapper_bsv.write('    endmodule\n')
            wrapper_bsv.write('`else\n');

        wrapper_bsv.write('\n    module ')
        if len(synth_modules) != 1:
            wrapper_bsv.write('[Connected_Module]')
        wrapper_bsv.write(' instantiateAllSynthBoundaries ();\n')

        for synth in synth_modules:
          if synth != module and not synth.platformModule:
              wrapper_bsv.write('        ' + synth.synthBoundaryModule + '();\n')

        wrapper_bsv.write('    endmodule\n')
        if (use_build_tree == 1):
            wrapper_bsv.write('`endif\n'); 


        # Import platform wrapper.
        wrapper_bsv.write('    import ' + moduleList.localPlatformName +'_platform_synth::*;\n'); 

        wrapper_bsv.write('    module [Connected_Module] instantiatePlatform ('+ platform_module.interfaceType +');\n')
        wrapper_bsv.write('        let m <- ' + moduleList.localPlatformName + '_platform();\n')
        wrapper_bsv.write('        return m;\n')
        wrapper_bsv.write('    endmodule\n')

        wrapper_bsv.write('`include "' + module.name + '.bsv"\n')

        wrapper_bsv.write('\n// import non-synthesis private files\n')
        wrapper_bsv.write('// Get defintion of TOP_LEVEL_WIRES\n')
        wrapper_bsv.write('import physical_platform::*;\n')
        wrapper_bsv.write('(* synthesize *)\n')

        wrapper_bsv.write('module [Module] mk_model_Wrapper\n')
        wrapper_bsv.write('    (TOP_LEVEL_WIRES);\n\n')
        wrapper_bsv.write('    // Instantiate main module\n')
        
        wrapper_bsv.write('    let m <- mkModel(clocked_by noClock, reset_by noReset);\n')

        wrapper_bsv.write('    return m;\n')
        wrapper_bsv.write('endmodule\n')

      else:
        log_bsv = open(logPath, 'w')
        log_bsv.write('import HList::*;\n')
        log_bsv.write('import ModuleContext::*;\n')

        # Parents of a synthesis boundary likely import the top level module of
        # the boundary.  This way, the synthesis boundary could be removed and
        # the code within the boundary would be imported correctly by the parent.
        # The code within the synthesis boundary will actually be imported at the
        # top level instead, so we need a dummy module for use by the parent of
        # a boundary that looks like it imports the code but actually does nothing.
        # Importing at the top level allows us to build all synthesis regions
        # in parallel.
        dummy_import_bsv = open(modPath + '.bsv', 'w')
        dummy_import_bsv.write('// Generated by wrapper_gen.py\n\n')
        dummy_import_bsv.write('module ' + module.synthBoundaryModule + ' ();\n');
        dummy_import_bsv.write('endmodule\n');
        dummy_import_bsv.close()

        if not os.path.exists(modPath + '_synth.bsv'):            
            generateSynthStub(moduleList, module)

        for wrapper in [wrapper_bsv, log_bsv]:      
            wrapper.write('// These are well-known/required leap modules\n')
            generateWellKnownIncludes(wrapper)
            wrapper.write('`include "awb/provides/librl_bsv_base.bsh"\n')
            wrapper.write('// import non-synthesis public files\n')
            wrapper.write('`include "' + module.name + '_compile.bsv"\n')
            wrapper.write('\n\n')
            
        log_bsv.write('// First pass to see how large the vectors should be\n')
        log_bsv.write('`define CON_RECV_' + module.name + ' 100\n')
        log_bsv.write('`define CON_SEND_' + module.name + ' 100\n')
        log_bsv.write('`define CON_RECV_MULTI_' + module.name + ' 50\n')
        log_bsv.write('`define CON_SEND_MULTI_' + module.name + ' 50\n')
        log_bsv.write('`define CHAINS_' + module.name + ' 50\n')
        wrapper_bsv.write('// Real build pass.  Include file built dynamically.\n')
        wrapper_bsv.write('`include "' + module.name + '_Wrapper_con_size.bsh"\n')

        for wrapper in [wrapper_bsv, log_bsv]:      
            wrapper.write('(* synthesize *)\n')
            wrapper.write('module [Module] mk_' + module.name + '_Wrapper (SOFT_SERVICES_SYNTHESIS_BOUNDARY#(`CON_RECV_' + module.name + ', `CON_SEND_' + module.name + ', `CON_RECV_MULTI_' + module.name + ', `CON_SEND_MULTI_' + module.name +', `CHAINS_' + module.name +', ' + module.interfaceType + '));\n')
            wrapper.write('  \n')
            # we need to insert the fpga platform here
            # get my parameters 

            wrapper.write('    // instantiate own module\n')
            wrapper.write('    let int_ctx0 <- initializeServiceContext();\n')
            wrapper.write('    match {.int_ctx1, .int_name1} <- runWithContext(int_ctx0, putSynthesisBoundaryID(fpgaNumPlatforms() + ' + str(module.synthBoundaryUID + uidOffset)  + '));\n');
            wrapper.write('    match {.int_ctx2, .int_name2} <- runWithContext(int_ctx1, putSynthesisBoundaryPlatform("' + moduleList.localPlatformName + '"));\n')
            wrapper.write('    match {.int_ctx3, .int_name3} <- runWithContext(int_ctx2, putSynthesisBoundaryPlatformID(' + str(moduleList.localPlatformUID) + '));\n')
            wrapper.write('    match {.int_ctx4, .int_name4} <- runWithContext(int_ctx3, putSynthesisBoundaryName("' + str(module.name) + '"));\n')
            wrapper.write('    // By convention, global string ID 0 (the first string) is the module name\n');
            wrapper.write('    match {.int_ctx5, .int_name5} <- runWithContext(int_ctx4, getGlobalStringUID("' + moduleList.localPlatformName + ':' + module.name + '"));\n');
            wrapper.write('    match {.int_ctx6, .module_ifc} <- runWithContext(int_ctx5, ' + module.synthBoundaryModule + ');\n')
            
            # Need to expose clocks of the platform Module
            if(module.platformModule):
                wrapper.write('    match {.clk, .rst} = extractClocks(module_ifc);\n')
                wrapper.write('    match {.int_ctx7, .int_name7} <- runWithContext(int_ctx6, mkSoftConnectionDebugInfo(clocked_by clk, reset_by rst));\n')
                wrapper.write('    match {.final_ctx, .m_final}  <- runWithContext(int_ctx7, mkSoftConnectionLatencyInfo(clocked_by clk, reset_by rst));\n')                
            else:
                wrapper.write('    match {.int_ctx7, .int_name7} <- runWithContext(int_ctx6, mkSoftConnectionDebugInfo);\n')
                wrapper.write('    match {.final_ctx, .m_final}  <- runWithContext(int_ctx7, mkSoftConnectionLatencyInfo);\n')
            wrapper.write('    let service_ifc <- exposeServiceContext(final_ctx);\n')
            wrapper.write('    interface services = service_ifc;\n')
            wrapper.write('    interface device = module_ifc;\n')
            wrapper.write('endmodule\n')
    
        log_bsv.close()

      wrapper_bsv.close()


