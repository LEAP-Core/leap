import os
import cPickle as pickle
from li_module import *

from model import  *
from config import  *
 
# Load up LI graph from first pass. For now, we assume that this comes
# from a file, but eventually this will be generated from the first
# pass compilation.
def getFirstPassLIGraph():
    # The first pass will dump a well known file. 
    firstPassLIGraph = "lim.li"

    if(os.path.isfile(firstPassLIGraph)):
        # We got a valid LI graph from the first pass.
        pickleHandle = open(firstPassLIGraph, 'rb')
        firstPassGraph = pickle.load(pickleHandle)
        pickleHandle.close()
        return firstPassGraph
    return None

def generateSynthStub(moduleList, module):
    compileWrapperPath = get_build_path(moduleList, module)
    wrapper = open( compileWrapperPath + '/' + module.name + '_synth.bsv', 'w')
    wrapper.write('`include "awb/provides/soft_connections.bsh"\n')
    wrapper.write('`include "awb/provides/smart_synth_boundaries.bsh"\n')

    conSizePath =  compileWrapperPath + '/' + module.name + "_Wrapper_con_size.bsh"
    wrapper.write('import ' + module.name + '_Wrapper::*;\n')        

    wrapper.write("module [Connected_Module] " + module.synthBoundaryModule + "(" + module.interfaceType + ");\n")
    wrapper.write("\nendmodule\n")

    wrapper.close()

def generateAWBCompileWrapper(moduleList, module):
    compileWrapperPath = get_build_path(moduleList, module)
    wrapper = open( compileWrapperPath + '/' + module.name + '_compile.bsv', 'w')

    wrapper.write('//   This file was created by wrapper-gen')  
    wrapper.write('`define BUILDING_MODULE_' + module.name + '\n')

    for bsv in module.moduleDependency['GIVEN_BSVS']:
        wrapper.write('`include "' + bsv +'"\n')
    wrapper.close()

def generateWrapperStub(moduleList, module):
    compileWrapperPath = get_build_path(moduleList, module)
    for suffix in ['_Wrapper.bsv','_Log.bsv']:
         wrapper = open( compileWrapperPath + '/' + module.name + suffix, 'w')

         wrapper.write('//   This file was created by wrapper-gen')  

         wrapper.write('import HList::*;\n')
         wrapper.write('import Vector::*;\n')
         wrapper.write('import ModuleContext::*;\n')
         wrapper.write('// These are well-known/required leap modules\n')
         wrapper.write('`include "awb/provides/soft_connections.bsh"\n')
         wrapper.write('`include "awb/provides/soft_services_lib.bsh"\n')
         wrapper.write('`include "awb/provides/soft_services.bsh"\n')
         wrapper.write('`include "awb/provides/soft_services_deps.bsh"\n')
         wrapper.write('`include "awb/provides/soft_connections_debug.bsh"\n')
         wrapper.write('`include "awb/provides/soft_connections_latency.bsh"\n')
         wrapper.write('`include "awb/provides/physical_platform_utils.bsh"\n')
         wrapper.write('// import non-synthesis public files\n')
         wrapper.write('`include "' + module.name + '_compile.bsv"\n')

         wrapper.close()

                      
#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path
# This is going to recursively build all the bsvs
class WrapperGen():

  def __init__(self, moduleList):

    # The LIM compiler uniquifies synthesis boundary names  
    uidOffset = int(moduleList.getAWBParam('wrapper_gen_tool', 'MODULE_UID_OFFSET'))

    # Inject a synth boundary for platform build code. 
    platformDeps = {}
    platformDeps['GEN_VERILOGS'] = []
    platformDeps['GEN_BAS'] = []
    #This is sort of a hack.
    platformDeps['GIVEN_BSVS'] = ['awb/provides/virtual_platform.bsh']
    platformDeps['BA'] = []
    platformDeps['STR'] = []
    platformDeps['VERILOG'] = []
    platformDeps['BSV_LOG'] = []
    platformDeps['VERILOG_STUB'] = []
       
    platform_module = Module( moduleList.localPlatformName, ["mkVirtualPlatform"], moduleList.topModule.buildPath,\
                          moduleList.topModule.name,\
                          [], moduleList.topModule.name, [], platformDeps, platformModule=True)

    platform_module.dependsFile = '.depends-platform'
    platform_module.interfaceType = 'VIRTUAL_PLATFORM'
    platform_module.extraImports = ['virtual_platform']

    moduleList.insertModule(platform_module)
    moduleList.graphize()
    moduleList.graphizeSynth()

    # Sprinkle more files expected by the two-pass build.  
    generateWrapperStub(moduleList, platform_module)
    generateAWBCompileWrapper(moduleList, platform_module)

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


          #os.system('leap-connect --dummy --dynsize ' + module.name + ' ' + conSizePath)

      wrapper_bsv.write('import HList::*;\n')
      wrapper_bsv.write('import Vector::*;\n')
      wrapper_bsv.write('import ModuleContext::*;\n')

      # the top module is handled specially
      if (module.name == moduleList.topModule.name):

        wrapper_bsv.write('// These are well-known/required leap modules\n')
        wrapper_bsv.write('// import non-synthesis public files\n')
        # Include all subordinate synthesis boundaries for use by
        # instantiateAllSynthBoundaries() below.
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


        wrapper_bsv.write('    import ' + moduleList.localPlatformName +'_synth::*;\n'); 
        wrapper_bsv.write('    module [Connected_Module] instantiatePlatform ('+ platform_module.interfaceType +');\n')
        wrapper_bsv.write('        let m <- ' + moduleList.localPlatformName + '();\n')
        wrapper_bsv.write('        return m;\n')
        wrapper_bsv.write('    endmodule\n')

     

        wrapper_bsv.write('`include "' + module.name + '.bsv"\n')

        wrapper_bsv.write('\n// import non-synthesis private files\n')
        wrapper_bsv.write('// Get defintion of TOP_LEVEL_WIRES\n')
        wrapper_bsv.write('import physical_platform::*;\n')
        wrapper_bsv.write('(* synthesize *)\n')

        if (n_top_clocks != 0):
          # Expose the standard reset interface argument and some top-level
          # clocks.  The first clock is the default clock.  Additional
          # clocks are exposed as a vector, named externally as CLK_0, etc.
          # All incoming clocks are combined into a single vector and
          # passed to mkModel.  Index 0 of the generated vector is
          # the same clock as the default clock.
          wrapper_bsv.write('module [Module] mk_model_Wrapper(\n')
          if (n_top_clocks > 1):
            wrapper_bsv.write('    (* osc="CLK" *) Vector#(' + str(n_top_clocks-1) + ', Clock) topClocks,\n')
          wrapper_bsv.write('    TOP_LEVEL_WIRES wires);\n\n')
          wrapper_bsv.write('    Reset topReset <- exposeCurrentReset;\n');
          wrapper_bsv.write('    Vector#(' + str(n_top_clocks) + ', Clock) allClocks = newVector();\n');
          wrapper_bsv.write('    Vector#(1, Clock) curClk = newVector();\n');
          wrapper_bsv.write('    curClk[0] <- exposeCurrentClock;\n');
          if (n_top_clocks > 1):
            wrapper_bsv.write('    allClocks = Vector::append(curClk, topClocks);\n');
          else:
            wrapper_bsv.write('    allClocks = curClk;\n');
          wrapper_bsv.write('\n');
          wrapper_bsv.write('    // Instantiate main module\n')
          wrapper_bsv.write('    let m <- mkModel(allClocks, topReset,\n')
          wrapper_bsv.write('                     clocked_by noClock, reset_by noReset);\n')
        else:
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
            wrapper.write('`include "awb/provides/soft_connections.bsh"\n')
            wrapper.write('`include "awb/provides/soft_services_lib.bsh"\n')
            wrapper.write('`include "awb/provides/soft_services.bsh"\n')
            wrapper.write('`include "awb/provides/soft_services_deps.bsh"\n')
            wrapper.write('`include "awb/provides/soft_connections_debug.bsh"\n')
            wrapper.write('`include "awb/provides/soft_connections_latency.bsh"\n')
            wrapper.write('`include "awb/provides/physical_platform_utils.bsh"\n')
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


