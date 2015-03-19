##
## Copyright (c) 2014, Intel Corporation
## All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## Redistributions of source code must retain the above copyright notice, this
## list of conditions and the following disclaimer.
##
## Redistributions in binary form must reproduce the above copyright notice,
## this list of conditions and the following disclaimer in the documentation
## and/or other materials provided with the distribution.
##
## Neither the name of the Intel Corporation nor the names of its contributors
## may be used to endorse or promote products derived from this software
## without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.

##
## Generate a source file that merges exposed wires of all synthesis boundaries.
## The merge could be accomplished in a single module, but this results in
## slow compilation.  Instead, a tree of modules is generated.
##

import os
import functools
import pickle

from SCons.Errors import BuildError

import model
from model import Module, get_build_path
import li_module
from li_module import LIGraph, LIModule
import bsv_tool
import wrapper_gen_tool
from bsv_tool.treeModule import TreeModule

try:
    import area_group_tool
except ImportError:
    pass # we won't be using this tool.


def getInstanceName(myModuleName):
    return 'inst_' + myModuleName


class BSVSynthTreeBuilder():
    def __init__(self, parent):
        self.parent = parent
        self.getFirstPassLIGraph = wrapper_gen_tool.getFirstPassLIGraph()

    ##
    ## setupTreeBuild --
    ##   Merge exposed soft connections using a tree of synthesis boundaries
    ##   instead of merging them all at once.  This reduces Bluespec
    ##   scheduling pressure and allows us to build larger systems.
    ##
    def setupTreeBuild(self, moduleList, topo):
        useBVI = self.parent.USE_BVI
        env = moduleList.env

        root_directory = model.rootDir

        ##
        ## Load intra-Bluespec dependence already computed.  This
        ## information will ultimately drive the building of Bluespec
        ## modules. Build tree has a few dependencies which must be
        ## captured.
        ##

        ## If we aren't building the build tree, don't bother with its dependencies
        env.ParseDepends(get_build_path(moduleList, moduleList.topModule) + '/.depends-build-tree',
                         must_exist = not moduleList.env.GetOption('clean'))
        tree_base_path = env.Dir(get_build_path(moduleList, moduleList.topModule))

        tree_file_synth = tree_base_path.File('build_tree_synth.bsv')
        tree_file_synth_bo_path = tree_base_path.File(self.parent.TMP_BSC_DIR + '/build_tree_synth.bo')

        tree_file_wrapper = tree_base_path.File('build_tree_Wrapper.bsv')
        tree_file_wrapper_bo_path = tree_base_path.File(self.parent.TMP_BSC_DIR + '/build_tree_Wrapper.bo')

        # Area constraints
        area_constraints = None
        try:
            if (moduleList.getAWBParam('area_group_tool', 'AREA_GROUPS_ENABLE')):
                area_constraints = area_group_tool.AreaConstraints(moduleList)
        except:
            # The area constraints code is not present.
            pass

        boundary_logs = []
        for module in topo:
            # Remove any platform modules.. These are special in that
            # they can have wired interfaces.
            if (not module.platformModule):
                for log in module.moduleDependency['BSV_LOG']:
                    boundary_logs += [root_directory.File(log)]
        ##
        ## Back to SCons configuration (first) pass...
        ##

        top_module_path = get_build_path(moduleList, moduleList.topModule)

        # Inform object code build of the LI Graph retrieved from the
        # first pass.  Probe firstPassGraph for relevant object codes
        # (BA/NGC/BSV_SYNTH/BSV_SYNTH_BSH) accessed:
        # module.objectCache['NGC'] (these already have absolute
        # paths) I feel like the GEN_BAS/GEN_VERILOGS of the first
        # pass may be missing.  We insert these modules as objects in
        # the ModuleList.

        def makeAWBLink(doLink, source, buildPath, uniquifier=''):
            base_file = os.path.basename(str(source))
            link_dir = buildPath + '/.li'
            link_path =  link_dir + '/' + uniquifier + base_file
            if (doLink):
                if (os.path.lexists(link_path)):
                    os.remove(link_path)
                rel = os.path.relpath(str(source), link_dir)
                print 'Linking: ' + link_path + ' -> ' + rel
                os.symlink(rel, link_path)

            return link_path


        limLinkUserSources = []
        limLinkUserTargets = []
        limLinkPlatformSources = []
        limLinkPlatformTargets = []
        importStubs = []


        if (not self.getFirstPassLIGraph is None):
            # Now that we have demanded bluespec builds (for
            # dependencies), we should now should downgrade synthesis boundaries for the backend.
            oldStubs = []
            for module in topo:
                if(not module.platformModule):
                    if((not module.name in self.getFirstPassLIGraph.modules) or (self.getFirstPassLIGraph.modules[module.name].getAttribute('RESYNTHESIZE') is None)): 
                        module.liIgnore = True
                    # this may not be needed.
                    else:
                        oldStubs += module.moduleDependency['GEN_VERILOG_STUB']

            # let's pick up the platform dependencies, since they are also special.
            env.ParseDepends(get_build_path(moduleList, moduleList.topModule) + '/.depends-platform',
                             must_exist = not moduleList.env.GetOption('clean'))

            # Due to the way that string files are
            # generated, they are difficult to rename in
            # the front-end compilation. This leads to
            # collisions amoung similarly-typed LI
            # Modules.  We fix it by uniquifying the links.

            def getModuleName(module):
                return module.name

            def getEmpty(module):
                return ''

            linkthroughMap = {'BA': getEmpty, 'GEN_BAS': getEmpty, 'GEN_VERILOGS': getEmpty, 'GEN_VERILOG_STUB': getEmpty, 'STR': getModuleName}

            buildPath = get_build_path(moduleList, moduleList.topModule)
            for module in self.getFirstPassLIGraph.modules.values():
            
                # do not link through those modules marked for resynthesis. 
                if(not module.getAttribute('RESYNTHESIZE') is None):  
                    continue

                moduleDeps = {}

                for objType in linkthroughMap:
                    if(objType in module.objectCache):
                        localNames =  map(lambda fileName: makeAWBLink(False,
                                                                       fileName.from_bld(),
                                                                       buildPath, 
                                                                       uniquifier=linkthroughMap[objType](module)),
                                          module.objectCache[objType])

                        # The previous passes GEN_VERILOGS are not
                        # really generated here, so we can't call them
                        # as such. Tuck them in to 'VERILOG'
                        if(objType == 'GEN_VERILOG_STUB'):
                            oldStubs += localNames                        
                        moduleDeps[objType] = localNames

                        if (module.getAttribute('PLATFORM_MODULE') is None):
                            limLinkUserTargets += localNames
                            limLinkUserSources += module.objectCache[objType]
                        else:
                            limLinkPlatformTargets += localNames
                            limLinkPlatformSources += module.objectCache[objType]

                m = Module(module.name, ["mk_" + module.name + "_Wrapper"],\
                           moduleList.topModule.buildPath, moduleList.topModule.name,\
                           [], moduleList.topModule.name, [], moduleDeps)

                moduleList.insertModule(m)
        else:
            # The top module/build pipeline only depend on non-platformModules
            oldStubs = [module.moduleDependency['GEN_VERILOG_STUB'] for module in moduleList.synthBoundaries() if not module.platformModule]




        ## Enumerate the dependencies created by the build tree.
        buildTreeDeps = {}

        ## We have now generated a completely new module. Let's throw it
        ## into the list.  Although we are building it seperately, this
        ## module is an extension to the build tree.
        expected_wrapper_count = len(boundary_logs) - 2
        importBOs = []

        if (not self.getFirstPassLIGraph is None):
            # we now have platform modules in here.
            expected_wrapper_count = len(self.getFirstPassLIGraph.modules) - 2

            # If we have an LI graph, we need to construct and compile
            # LI import wrappers for the modules we received from the
            # first pass.  Do that here.  include all the dependencies
            # in the graph in the wrapper.
            liGraph = LIGraph([])
            firstPassGraph = self.getFirstPassLIGraph
            # We should ignore the 'PLATFORM_MODULE'
            liGraph.mergeModules([ module for module in bsv_tool.getUserModules(firstPassGraph) if module.getAttribute('RESYNTHESIZE') is None])
            for module in sorted(liGraph.graph.nodes(), key=lambda module: module.name):
                # pull in the dependecies generate by the dependency pass.
                env.ParseDepends(str(tree_base_path) + '/.depends-' + module.name,
                                 must_exist = not moduleList.env.GetOption('clean'))
                wrapper_path = tree_base_path.File(module.name + '_Wrapper.bsv')
                wrapper_bo_path = tree_base_path.File(self.parent.TMP_BSC_DIR + '/' + module.name + '_Wrapper.bo')

                # include commands to build the wrapper .bo/.ba
                # Here, we won't be using the generated .v (it's garbage), so we intentionally  get rid of it.
                importVDir = env.Dir('.lim_import_verilog')
                if not os.path.isdir(str(importVDir)):
                   os.mkdir(str(importVDir))

                wrapper_command = self.parent.compile_bo_bsc_base([wrapper_bo_path], get_build_path(moduleList, moduleList.topModule), vdir=importVDir) + ' $SOURCES'
                wrapper_bo = env.Command([wrapper_bo_path],
                                         [wrapper_path],
                                         wrapper_command)
                # create BO.
                importBOs += [wrapper_bo]

        verilog_deps = [ "__TREE_MODULE__" + str(id) for id in range(expected_wrapper_count)]

        if(self.parent.BUILD_LOGS_ONLY == 0):
            buildTreeDeps['GEN_VERILOGS'] = ["mk_" + vlog + '_Wrapper' + ".v"  for vlog in verilog_deps]
        else:
            buildTreeDeps['GEN_VERILOGS'] = []

        buildTreeDeps['GEN_BAS'] = [  "mk_" + vlog + '_Wrapper' + ".ba" for vlog in verilog_deps]
        buildTreeDeps['BA'] = []
        buildTreeDeps['STR'] = []
        buildTreeDeps['VERILOG'] = [top_module_path + '/' + self.parent.TMP_BSC_DIR + '/mk_build_tree_Wrapper.v']
        buildTreeDeps['GIVEN_BSVS'] = []
        buildTreeDeps['VERILOG_STUB'] = model.convertDependencies(oldStubs)

        tree_module = Module( 'build_tree', ["mkBuildTree"], moduleList.topModule.buildPath,\
                             moduleList.topModule.name,\
                             [], moduleList.topModule.name, [], buildTreeDeps, platformModule=True)

        tree_module.putAttribute('LI_GRAPH_IGNORE', True)

        moduleList.insertModule(tree_module)    
        wrapper_gen_tool.generateAWBCompileWrapper(moduleList, tree_module)

        ## This produces the treeNode BSV. It must wait for the
        ## compilation of the log files, which it will read to form the
        ## LIM graph
        ##
        ## We do two operations during this phase.  First, we dump a
        ## representation of the user program. This representation is
        ## used by the LIM compiler to create heterogeneous
        ## executables.  We then do a local modification to the build
        ## tree to reduce Bluespec compilation time.

        # If I got an LI graph, I don't care about the boundary logs.
        # In this case, everything comes from the first pass graph.

        # Usually, we only need logs and BOs to build the build tree.
        # However, during the second pass build we also need to fill
        # in information about area group paths (changed by tree build)
        tree_build_deps = boundary_logs + importBOs
        tree_build_results = [tree_file_wrapper, tree_file_synth]

        if (self.getFirstPassLIGraph and area_constraints):
            tree_build_deps += [area_constraints.areaConstraintsFilePlaced()]
            tree_build_results += [area_constraints.areaConstraintsFile()]

        ##
        ## The cutTreeBuild builder function needs some of the local state
        ## in the current function.  Build a dictionary with the required
        ## state and partial instance of cutTreeBuild with the state applied.
        ##
        cut_tree_state = dict()
        cut_tree_state['area_constraints'] = area_constraints
        cut_tree_state['boundary_logs'] = boundary_logs
        cut_tree_state['moduleList'] = moduleList
        cut_tree_state['tree_file_synth'] = tree_file_synth
        cut_tree_state['tree_file_wrapper'] = tree_file_wrapper

        cut_tree_build = functools.partial(self.cutTreeBuild, cut_tree_state)
        cut_tree_build.__name__ = 'cutTreeBuild'

        tree_components = env.Command(tree_build_results,
                                      tree_build_deps,
                                      cut_tree_build)

        ## Compiling the build tree wrapper produces several .ba
        ## files, some that are useful, the TREE_MODULES, and some
        ## which are not, the _Wrapper.ba.  As a result, we dump the
        ## tree build output to a different directory, so as not to
        ## pollute the existing build.  Here, we link to the relevant
        ## files in that directory.

        def linkLIMObjClosure(liModules, buildPath):
            def linkLIMObj(target, source, env):
                if (not self.getFirstPassLIGraph is None):
                    # The LIM build has passed us some source and we need
                    # to patch it through.
                    for module in liModules:
                        for objType in linkthroughMap:
                            if(objType in module.objectCache):                
                                map(lambda fileName: makeAWBLink(True, fileName.from_bld(), buildPath, uniquifier=linkthroughMap[objType](module)),
                                    module.objectCache[objType])

            return linkLIMObj


        ## The top level build depends on the compilation of the tree components
        ## into bo/ba/v files.

        # the GEN_BAS attached to the build tree need to be massaged
        # to reflect their actual path.  Perhaps we should be using
        # some kind of object that makes these sorts of conversions
        # simpler.

        producedBAs = map(lambda path: bsv_tool.modify_path_ba(moduleList, path), moduleList.getModuleDependenciesWithPaths(tree_module, 'GEN_BAS'))
        producedVs = map(lambda path: bsv_tool.modify_path_ba(moduleList, path), moduleList.getModuleDependenciesWithPaths(tree_module, 'GEN_VERILOGS')) + \
                     buildTreeDeps['VERILOG']

        tree_command = self.parent.compile_bo_bsc_base([tree_file_wrapper_bo_path], get_build_path(moduleList, moduleList.topModule)) + ' ' + tree_file_wrapper.path
        tree_file_wrapper_bo = env.Command([tree_file_wrapper_bo_path] + producedBAs + producedVs,
                                           tree_components,
                                           tree_command)

        # If we got a first pass LI graph, we need to link its object codes.
        if (not self.getFirstPassLIGraph is None):
            srcs = [s.from_bld() for s in limLinkUserSources]
            link_lim_user_objs = env.Command(limLinkUserTargets,
                                             srcs,
                                             linkLIMObjClosure([ module for module in bsv_tool.getUserModules(firstPassGraph) if module.getAttribute('RESYNTHESIZE') is None],
                                                               tree_base_path.path))
            env.Depends(link_lim_user_objs, tree_file_wrapper_bo)


        # the tree_file_wrapper build needs all the wrapper bo from the user program,
        # but not the top level build.
        top_bo = moduleList.topModule.moduleDependency['BSV_BO']
        all_bo = moduleList.getAllDependencies('BO')

        env.Depends(tree_file_wrapper_bo, all_bo)

        tree_synth_command = self.parent.compile_bo_bsc_base([tree_file_synth_bo_path], get_build_path(moduleList, moduleList.topModule)) + ' ' + tree_file_synth.path
        tree_file_synth_bo = env.Command([tree_file_synth_bo_path],
                                         [tree_file_synth, tree_file_wrapper_bo],
                                         tree_synth_command)

        env.Depends(top_bo, tree_file_synth_bo)
        env.Depends(moduleList.topModule.moduleDependency['BSV_LOG'],
                    tree_file_synth_bo)


        #Handle the platform_synth build, which is special cased.
        platform_synth = get_build_path(moduleList, moduleList.topModule) + "/" +  moduleList.localPlatformName + "_platform_synth.bsv"
        platform_synth_bo_path = get_build_path(moduleList, moduleList.topModule) + "/" + self.parent.TMP_BSC_DIR +"/" + moduleList.localPlatformName + "_platform_synth"
        # if we are in the lim linking phase, we need to change the
        # vdir directory to hide the spurious verilog generated by
        # bluespec.
        importVDir = None
        if(not self.getFirstPassLIGraph is None):
            importVDir = env.Dir('.lim_import_verilog')
            if not os.path.isdir(str(importVDir)):
                os.mkdir(str(importVDir))

        platform_synth_command = self.parent.compile_bo_bsc_base([platform_synth_bo_path + '.bo'], get_build_path(moduleList, moduleList.topModule), vdir=importVDir) + ' $SOURCE'
        platform_wrapper_bo = get_build_path(moduleList, moduleList.topModule) + "/" + self.parent.TMP_BSC_DIR + "/" +moduleList.localPlatformName + '_platform_Wrapper.bo'

        platform_synth_deps = [platform_synth]
        #if we have a module graph, we don't require the compilation of the platform_wrapper_bo.
        if (self.getFirstPassLIGraph is None):
            platform_synth_deps.append(platform_wrapper_bo)
        platform_synth_bo = env.Command([platform_synth_bo_path + '.bo'],
                                         platform_synth_deps,
                                         platform_synth_command)
        # this produces a ba also?
        env.Depends(moduleList.topModule.moduleDependency['BSV_LOG'],
                        platform_synth_bo)

        # Platform synth does the same object-bypass dance as tree_module.
        if(not self.getFirstPassLIGraph is None):
            srcs = [s.from_bld() for s in limLinkPlatformSources]
            link_lim_platform_objs = env.Command(limLinkPlatformTargets,
                                                 srcs,
                                                 linkLIMObjClosure([ module for module in bsv_tool.getPlatformModules(firstPassGraph) if module.getAttribute('RESYNTHESIZE') is None],
                                                                   tree_base_path.path))
            env.Depends(link_lim_platform_objs, platform_synth_bo)

        # need to generate a stub file for the build tree module.
        # note that in some cases, there will be only one module in
        # the graph, usually in a multifpga build.  In this case,
        # the build_tree module will be vestigal, but since we can't
        # predict this statically we'll have to build it anyway.

        tree_module.moduleDependency['GEN_VERILOG_STUB'] = [self.parent.stubGenCommand(top_module_path,
                                                                                       "build_tree",
                                                                                       top_module_path + '/' + self.parent.TMP_BSC_DIR + "/mk_build_tree_Wrapper.v")]

        # top level only depends on platform modules
        moduleList.topModule.moduleDependency['VERILOG_STUB'] = model.convertDependencies([module.moduleDependency['GEN_VERILOG_STUB'] for module in moduleList.synthBoundaries() if module.platformModule])
        if(not self.getFirstPassLIGraph is None):
            #Second pass build picks up stub files from the first pass build.
            moduleList.topModule.moduleDependency['VERILOG_STUB'] += model.convertDependencies(oldStubs)

    ## END of setupTreeBuild


    ##
    ## cutTreeBuild does the heavy lifting as a build-time method when
    ## invoked in the 2nd pass of SCons.
    ##
    def cutTreeBuild(self, state, target, source, env):
        pipeline_debug = self.parent.pipeline_debug
        boundary_logs = state['boundary_logs']
        moduleList = state['moduleList']
        area_constraints = state['area_constraints']

        # If we got a graph from the first pass, merge it in now.
        if (self.getFirstPassLIGraph is None):
            liGraph = LIGraph(li_module.parseLogfiles(boundary_logs))
        else:
            #cut_tree_build may modify the first pass graph, so we need
            #to make a copy
            liGraph = LIGraph([])
            firstPassGraph = self.getFirstPassLIGraph
            # We should ignore the 'PLATFORM_MODULE'
            liGraph.mergeModules(bsv_tool.getUserModules(firstPassGraph))

            if (area_constraints):
                area_constraints.loadAreaConstraintsPlaced()

        synth_handle = open(state['tree_file_synth'].path,'w')
        wrapper_handle = open(state['tree_file_wrapper'].path,'w')
        state['wrapper_handle'] = wrapper_handle

        fileID = 0
        for tree_file in [wrapper_handle, synth_handle]:
            fileID = fileID + 1
            tree_file.write("// Generated by BSVSynthTreeBuilder.py\n")
            tree_file.write("`ifndef BUILD_" + str(fileID) +  "\n") # these may not be needed
            tree_file.write("`define BUILD_" + str(fileID) + "\n")
            tree_file.write('import Vector::*;\n')
            wrapper_gen_tool.generateWellKnownIncludes(tree_file)
            tree_file.write('// import non-synthesis public files\n')
            tree_file.write('`include "build_tree_compile.bsv"\n')

        #If we are only building logs, we don't really require the build tree. 
        if(self.parent.BUILD_LOGS_ONLY):

            wrapper_handle.write("\n\n(*synthesize*)\n")
            wrapper_handle.write("module mk_build_tree_Wrapper#(Reset baseReset) (Reg#(Bit#(1)));\n")
            wrapper_handle.write("    let m <- mkRegU();\n")
            wrapper_handle.write("    return m;\n")
            wrapper_handle.write("endmodule\n")

            synth_handle.write("module build_tree#(Reset baseReset) (Reg#(Bit#(1)));\n")
            synth_handle.write("    let m <- mkRegU();\n")
            synth_handle.write("    return m;\n")
            synth_handle.write("endmodule\n")

            for tree_file in [wrapper_handle, synth_handle]:

                tree_file.write("// Log build only.  This space intentionally left blank.\n")
                tree_file.write("`endif\n")
                tree_file.close()
            return

        # include all the dependencies in the graph in the wrapper.
        for module in sorted(liGraph.graph.nodes(), key=lambda module: module.name):
            wrapper_handle.write('import ' + module.name + '_Wrapper::*;\n')

        wrapper_handle.write('module mk_empty_Wrapper#(Reset baseReset) (SOFT_SERVICES_SYNTHESIS_BOUNDARY#(0,0,0,0,0, Empty)); return ?; endmodule\n')

        if (pipeline_debug != 0):
            print "LIGraph: " + str(liGraph)

        # Top module has a special, well-known name for stub gen.
        # unless there is only one module in the graph.
        expected_wrapper_count = len(boundary_logs) - 2
        if(not self.getFirstPassLIGraph is None):
            expected_wrapper_count = len(self.getFirstPassLIGraph.modules) - 2

        module_names = [ "__TREE_MODULE__" + str(id) for id in range(expected_wrapper_count)] + ["build_tree"]

        # partition the top level LIM graph to produce a tree of
        # latency insensitive modules.  If there is only a
        # single module, we need to add a vestigial empty module
        # to the graph. This situation only occurs in a handful
        # of multifpga modules.

        # In the first LIM pass, we need to expose all
        # connections.  Doing so through Bluespec results in
        # object code changes, which are unacceptable.  Therefore,
        # We optionally trim the build tree.

        # assign top_module some default.
        top_module = None
        if(self.parent.BUILD_LOGS_ONLY == 0):
            if (len(liGraph.graph.nodes()) == 1):
                # Singleton Modules still need to pass through the
                # trimming phase to remove references to unmatched
                # channels.  If there's only one module, introduce
                # a trivial second module. Having no LI modules is
                # handled correctly.
                liGraph.mergeModules([LIModule("empty", "empty")])

            state['empty_count'] = 0

            # Cut the build into a tree of merged wrappers.  We could merge
            # all of them in a single level, but the Bluespec compiler winds
            # up being too slow.  A hierarchy compiles more efficiently.
            top_module = self.cutRecurse(state, liGraph, 1, module_names)

            # Generate the code for the cut tree.
            self.emitWrappersRecurse(state, top_module, 1)


            # walk the top module to annotate area group paths
            def annotateAreaGroups(treeModule, verilogPath):
                if (isinstance(treeModule, TreeModule)):
                    if (not treeModule.children is None):
                        for child in treeModule.children:
                            annotateAreaGroups(child,verilogPath + getInstanceName(treeModule.name) + treeModule.seperator)
                else:
                    # fill in the area group data structure
                    if (area_constraints and (treeModule.name in area_constraints.constraints)):
                        # We always have synthesis boundaries at the bottom of the tree.
                        area_constraints.constraints[treeModule.name].sourcePath = \
                            verilogPath + getInstanceName(treeModule.name)


            # If necessary, dump out the area groups file.
            if(not self.getFirstPassLIGraph is None):
                # Also load up areaGroups
                # top module has a funny recursive base case.  Fix it here.

                # It is possible the the top_module will be a singleton LI module.
                if(isinstance(top_module,TreeModule)):
                    for child in top_module.children:
                        annotateAreaGroups(child, 'm_sys_sys_syn_m_mod/')
                else:
                    annotateAreaGroups(top_module, 'm_sys_sys_syn_m_mod/')

                # Annotate physical platform. This is sort of a hack.
                if (area_constraints):
                    n = moduleList.localPlatformName + "_platform"
                    if (n in area_constraints.constraints):
                        # Vivado has difficulties in placing platform
                        # code in the presence of device driver area
                        # groups.  We optionally disable the
                        # generation of platform area groups here.
                        if (moduleList.getAWBParam('area_group_tool', 'AREA_GROUPS_GROUP_PLATFORM_CODE')):
                            area_constraints.constraints[n].sourcePath = "m_sys_sys_vp_m_mod"
                        else:
                            area_constraints.constraints[n].sourcePath = None

                    area_constraints.storeAreaConstraints()

        # In multifpga builds, we may have some leftover modules
        # due to the way that the LIM compiler currently
        # operates. We emit dummy modules here to make
        # downstream tools happy.  This can be removed once we
        # reorganize the multifpga compiler.

        for module in module_names:
            wrapper_handle.write("\n\n(*synthesize*)\n")
            wrapper_handle.write("module mk_" + module + '_Wrapper' + " (Reg#(Bit#(1)));\n")
            wrapper_handle.write("    let m <- mkRegU();\n")
            wrapper_handle.write("    return m;\n")
            wrapper_handle.write("endmodule\n")

        # we need to create a top level wrapper module to
        # re-monadize the soft connections so that the platform
        # compiles correctly

        # however the synth file depends only on the build tree wrapper
        # if we have a single module, it will be the case that
        # this module and not a tree build will be returned. Handle both.
        if(top_module is None):
            # If we have no top module, then the build tree is empty.
            synth_handle.write("\n\nmodule [Connected_Module] build_tree();\n")
            synth_handle.write("    //this space intentionally left blank\n")
            synth_handle.write("endmodule\n")
        else:
            wrapper_gen_tool.generateTopSynthWrapper(top_module,
                                                     synth_handle,
                                                     moduleList.localPlatformName,
                                                     areaConstraints = area_constraints)

        for tree_file in [synth_handle, wrapper_handle]:
            tree_file.write("`endif\n")
            tree_file.close()

        return None
    # END OF cutTreeBuild


    ##
    ## cutRecurse --
    ##   A recursive function for partitioning a latency insensitive graph
    ##   into a a tree of modules so as to minimize the number of rules in
    ##   the modules of the tree.  This construction reduces the complexity
    ##   of the design as seen by the bluespec compiler.
    ##
    ##   Input: LIGraph representing the user program
    ##
    ##   Output: LIModule repesenting the tree produced by the function.
    ##           This tree may have unmatched channels.
    ##
    def cutRecurse(self, state, subgraph, isTopModule, moduleNames):
        pipeline_debug = self.parent.pipeline_debug

        # Doesn't make sense to cut up a null or size-one LIM
        # trivially return the base LI module to the caller
        if (len(subgraph.graph.nodes()) < 2):
            if (not isTopModule):
                if (len(subgraph.graph.nodes()) == 0):
                    # Construct a dummy empty node.  Empty nodes are assigned
                    # UIDs in case more than one is created and they wind up
                    # in the same wrapper.  (This happens only when the tree
                    # is completely empty.)
                    name = "empty" + str(state['empty_count'])
                    state['empty_count'] = state['empty_count'] + 1
                    return TreeModule("empty", name)
                else:
                    return subgraph.graph.nodes()[0]
            elif (len(subgraph.graph.nodes()) != 0):
                # Top module is never passed in as a singleton.  This code
                # Should never be reached.
                raise BuildError(errstr = "Singleton top module",
                                 filename = state['tree_file_wrapper'].path)

        ##
        ## The graph partitioning algorithm depends on whether area groups
        ## are being generated.  When area groups are in use, partitions
        ## seek to minimize the path around a chain by building the tree
        ## as a representation of the physical topology.  When area groups
        ## are not in use, the graph is cut based on connections between
        ## synthesis boundaries.  In theory, the area group partitioning
        ## should already have accounted for inter-module connections.
        ##
        if state['area_constraints']:
            map = li_module.placement_cut(subgraph.graph, state['area_constraints'])
        else:
            map = li_module.min_cut(subgraph.graph)

        if (pipeline_debug != 0):
            print "Cut map: " + str(map)

        ## Now that we've got a cut, Build new li graphs from the sub
        ## components of original graph. We must be careful because some
        ## modules may not have internal channels, only external channels.
        ## Thus for each module we add an optional, dummy edge to ensure
        ## that the partitioned graphs are constructed correctly.

        graph0Connections = []
        graph1Connections = []

        for connection in subgraph.getChannels() + subgraph.getChains():
            connectionSet = graph0Connections
            if (map[connection.module] == 1):
                connectionSet = graph1Connections
            connectionSet += [connection.copy()]

        graph0 = LIGraph(graph0Connections)
        graph1 = LIGraph(graph1Connections)

        # Pick a name for the local module.
        localModule = moduleNames.pop()

        # In order to build an LI module for this node in the tree,
        # we need to have the code for the subtrees
        # below the current node.  And so we recurse.  If only one
        # module remains in the cut graph, there is no need to recurse
        # and we just use that module.
        submodule0 = None
        if(len(graph0.modules) == 1):
            submodule0 = graph0.modules.values()[0]
        else:
            submodule0 = self.cutRecurse(state, graph0, 0, moduleNames)

        submodule1 = None
        if(len(graph1.modules) == 1):
            submodule1 = graph1.modules.values()[0]
        else:
            submodule1 = self.cutRecurse(state, graph1, 0, moduleNames)

        # Build a representation of the new liModule we are about to construct.
        treeModule = TreeModule("node", localModule)
        treeModule.children = [submodule0, submodule1]

        return treeModule
    # END OF cutRecurse


    ##
    ## emitWrappersRecurse --
    ##   Walk the tree generated by cutRecurse and emit wrappers to merge
    ##   all synthesis boundaries.
    ##
    def emitWrappersRecurse(self, state, treeModule, isTopModule):
        pipeline_debug = self.parent.pipeline_debug
        wrapper_handle = state['wrapper_handle']
        area_constraints = state['area_constraints']
        moduleList = state['moduleList']

        num_child_exported_rules = 0

        # Walk the tree recursively and generate wrappers for each level.
        # Not all modules have children, hence the try/except.
        try:
            for submodule in treeModule.children:
                self.emitWrappersRecurse(state, submodule, 0)

                num_child_exported_rules += submodule.numExportedRules
        except AttributeError:
            # Nodes without children are terminal and will be merged with
            # a sibling in their parent.  No action.
            return

        if ((treeModule.children is None) or (len(treeModule.children) == 0)):
            return

        # The tree is binary.  If this line triggers a ValueError then there
        # is a bug in the binary tree construction.
        submodule0, submodule1 = treeModule.children

        # In order to generate the module, we need a type,
        # but we can only get it after analyzing the module pair
        # Thus we store the module body code for later consumption
        module_body = ""

        # Instantiate the submodules.
        r_idx = 0
        for m in [submodule0, submodule1]:
            name = m.name
            module_name = name

            # Empty module types are a special case.  The name is numbered
            # with a UID to support multiple empty modules.  The instantiated
            # wrapper is always mk_empty_Wrapper.
            if (m.type == "empty"):
                module_name = "empty"

            rst = 'rst' + str(r_idx)
            r_idx += 1

            module_body += "\n";
            module_body += "    let " + rst + " <- mkResetFanout(baseReset);\n"
            module_body += "    let " + getInstanceName(name) + " <- mk_" +\
                            module_name + "_Wrapper(baseReset, reset_by " + rst + ");\n"
            module_body += "    let " + name + " = tpl_1(" +\
                            getInstanceName(name) + ".services);\n"
            module_body += "\n";


        # At this node in the tree, we can match channels from our two children.
        # This matching is what reduces the bluespec compiler complexity, since matched
        # channels do not need to be propagated upward.

        matched = {} # Use a hash to detect matching

        # handle matching channels
        for channel in submodule0.channels:
            for partnerChannel in submodule1.channels:
                if (channel.matches(partnerChannel)):
                    if (pipeline_debug != 0):
                        print "Found match with " + str(partnerChannel)
                    matched[channel.name] = channel

                    if (channel.isSource()):
                        c_out = channel
                        c_in = partnerChannel
                    else:
                        c_out = partnerChannel
                        c_in = channel

                    # Buffering between out and in depends on distance
                    n_buf = 0
                    if (area_constraints):
                        if (pipeline_debug != 0):
                            print "Channel (" + c_out.name + ") " + c_out.root_module_name + " -> " + c_in.root_module_name + ": " + c_out.module_name + " -> " + c_in.module_name
                        area_groups = area_constraints.constraints
                        n_buf = area_constraints.numLIChannelBufs(area_groups[c_out.root_module_name],
                                                                  area_groups[c_in.root_module_name])

                    module_body += "    connectOutToIn(" + c_out.module_name + ".outgoing[" + str(c_out.module_idx) + "], " +\
                                   c_in.module_name + ".incoming[" + str(c_in.module_idx) + "], " +\
                                   str(n_buf) +\
                                   ");// " + c_out.name + "\n"

        #handle matching chains
        for chain in submodule0.chains:
            for partnerChain in submodule1.chains:
                if (chain.matches(partnerChain)):
                    if (pipeline_debug != 0):
                        print "Found match with " + str(partnerChain)
                    matched[chain.name] = chain
                    chain.sinkPartnerChain = partnerChain
                    chain.sourcePartnerChain = chain

                    # Buffering between out and in depends on distance
                    n_buf = 0
                    if (area_constraints):
                        if (pipeline_debug != 0):
                            print "Chain (" + chain.name + ") " + chain.chain_root_out + " -> " + partnerChain.chain_root_in + ": " + chain.module_name + " -> " + partnerChain.module_name

                        area_groups = area_constraints.constraints
                        n_buf = area_constraints.numLIChannelBufs(area_groups[chain.chain_root_out],
                                                                  area_groups[partnerChain.chain_root_in])

                    module_body += "    connectOutToIn(" + chain.module_name + ".chains[" + str(chain.module_idx) + "].outgoing, " +\
                                   partnerChain.module_name + ".chains[" + str(partnerChain.module_idx) + "].incoming, " +\
                                   str(n_buf) +\
                                   ");// " + chain.name + "\n"


        # Stick the remaining connections of child modules
        # into the interface of this new module.  Include
        # any chains.  we need to check chains for a match
        # so that we get the routing right.  if matched,
        # ingress will be module0 and egress will be module1

        incoming = 0
        outgoing = 0
        chains = 0

        # We need to propagate any remaining unmatched channels and chains up the tree,
        # To do this we populate the LI module representing this node with the unmatched
        # channels of the child node.
        if (pipeline_debug != 0):
            for channel in submodule0.channels:
                print "Channel in " + submodule0.name + " " + str(channel)
            for channel in submodule1.channels:
                print "Channel in " + submodule1.name + " " + str(channel)

        for channel in submodule0.channels + submodule1.channels:
            channelCopy = channel.copy()

            if (not channel.name in matched):
                if (channel.isSource()):
                    sizeName = "sz_" + channel.module_name + "_" + channel.name + "_" + str(channel.module_idx)
                    module_body += "    NumTypeParam#(" + str(channel.bitwidth) + ") " + sizeName + " = ?;\n"
                    module_body += "    outgoingVec[" + str(outgoing) +"] = resizeConnectOut(" + channel.module_name +\
                                   ".outgoing[" + str(channel.module_idx) + "], " + sizeName + ");// " + channel.name + "\n"
                    channelCopy.module_idx = outgoing
                    outgoing = outgoing + 1
                else:
                    module_body += "    incomingVec[" + str(incoming) +"] = " + channel.module_name +\
                                   ".incoming[" + str(channel.module_idx) + "];// " + channel.name + "\n"
                    channelCopy.module_idx =  incoming
                    incoming = incoming + 1

                # override the module_name with the local
                # module so that our parent will refer to us
                # correctly
                channelCopy.module_name = treeModule.name
                treeModule.addChannel(channelCopy)

        # Chains are always propagated up, but they can also
        # be matched. In this case, we must use a portion of
        # each child module's chain.

        for chain in submodule0.chains + submodule1.chains:
            chainCopy = chain.copy()
            if (not (chain.name in matched)):
                # need to add both incoming and outgoing
                sizeName = "sz_" + chain.module_name + "_" + chain.name + "_" + str(chain.module_idx)
                module_body += "    NumTypeParam#(" + str(chain.bitwidth) + ") " + sizeName + " = ?;\n"
                module_body += "    chainsVec[" + str(chains) +"] = PHYSICAL_CHAIN{incoming: " +\
                               chain.module_name + ".chains[" + str(chain.module_idx) +\
                               "].incoming, outgoing: resizeConnectOut(" + chain.module_name + ".chains[" +\
                               str(chain.module_idx) + "].outgoing, " + sizeName + ")};// " + chain.name + "\n"
                chainCopy.module_idx =  chains
                chainCopy.module_name = treeModule.name
                treeModule.addChain(chainCopy)
                chains = chains + 1

            else:
                # We see matched chains twice, but we should only emit code once.
                if ((chain.module_name == submodule1.name)):
                    # Need to get form a chain based on the combination of the
                    # two modules.
                    chain0 = matched[chain.name]

                    # The chain is partially connected.  The exposed in/out
                    # halves now come from different modules.
                    chainCopy.chain_root_in = chain0.chain_root_in

                    sizeName = "sz_" + chain.module_name + "_" + chain.name + "_" + str(chain.module_idx)
                    module_body += "    NumTypeParam#(" + str(chain.bitwidth) + ") " + sizeName + " = ?;\n"
                    module_body += "    chainsVec[" + str(chains) +"] = PHYSICAL_CHAIN{incoming: " +\
                                   chain0.module_name + ".chains[" + str(chain0.module_idx) +\
                                   "].incoming, outgoing: resizeConnectOut(" + chain.module_name+ ".chains[" +\
                                   str(chain.module_idx) + "].outgoing, " + sizeName + ")};// " + chain.name + "\n"
                    chainCopy.module_idx =  chains
                    chainCopy.module_name = treeModule.name
                    treeModule.addChain(chainCopy)
                    chains = chains + 1

        ##
        ## Should this module be a synthesis boundary?  We could just
        ## make all the modules boundaries, but the Bluespec compiler
        ## is quite slow for boundaries.  Only generate a true
        ## synthesis boundary when the number of rules grows large
        ## enough to slow down the Bluespec scheduler.
        ##

        # Always generate a boundary for top level
        gen_synth_boundary = isTopModule

        # Threshold for Bluespec scheduler
        total_rules = len(treeModule.channels) + num_child_exported_rules
        if (total_rules > 250):
            gen_synth_boundary = True
            treeModule.setNumExportedRules(0)
        else:
            treeModule.setNumExportedRules(total_rules)

        if(gen_synth_boundary):
            treeModule.seperator = '/'
        else:
            treeModule.seperator = '_'


        ##
        ## Now we can write out our modules.
        ##
        if (gen_synth_boundary):
            wrapper_handle.write("\n\n(*synthesize*)")

        wrapper_handle.write("\nmodule ")
        if (not gen_synth_boundary):
            wrapper_handle.write("[Module] ")
        wrapper_handle.write("mk_" + treeModule.name + '_Wrapper#(Reset baseReset)')
        moduleType = "SOFT_SERVICES_SYNTHESIS_BOUNDARY#(" + str(incoming) +\
                     ", " + str(outgoing) + ", 0, 0, " + str(chains) + ", Empty)"

        subinterfaceType = "WITH_CONNECTIONS#(" + str(incoming) + ", " +\
                           str(outgoing) + ", 0, 0, " + str(chains) + ")"
        wrapper_handle.write(" (" + moduleType +")")
        if (gen_synth_boundary):
            wrapper_handle.write(";\n")
        else:
            wrapper_handle.write("\n")
            wrapper_handle.write("    provisos (IsModule#(Module, Id__));\n\n")

            ##
            ## Here is a hack:  we didn't know on the SCons first pass
            ## whether a synthesis boundary would be generated for this
            ## module.  Hence we had to assume that one might be and
            ## dependence was added on the generated Verilog.  Now
            ## that we know there is none, generate a dummy Verilog
            ## file.
            ##
            v_path = "mk_" + treeModule.name + '_Wrapper' + ".v"
            wrapper_handle.write("    // Hack to generate Verilog file to simulate the possible synthesis boundary\n")
            wrapper_handle.write("    Handle hdl <- openFile(\"" + v_path + "\", WriteMode);\n")
            wrapper_handle.write("    hPutStrLn(hdl, \"// Dummy\");\n")
            wrapper_handle.write("    hClose(hdl);\n")

        #declare interface vectors
        wrapper_handle.write("    Vector#(" + str(incoming) + ", PHYSICAL_CONNECTION_IN)  incomingVec = newVector();\n")
        wrapper_handle.write("    Vector#(" + str(outgoing) + ", PHYSICAL_CONNECTION_OUT) outgoingVec = newVector();\n")
        wrapper_handle.write("    Vector#(" + str(chains) + ", PHYSICAL_CHAIN) chainsVec = newVector();\n")

        # lay down module body
        wrapper_handle.write(module_body)

        # fill in external interface

        wrapper_handle.write("    let clk <- exposeCurrentClock();\n")
        wrapper_handle.write("    let rst <- exposeCurrentReset();\n")

        wrapper_handle.write("    " + subinterfaceType + " moduleIfc = interface WITH_CONNECTIONS;\n")
        wrapper_handle.write("        interface incoming = incomingVec;\n")
        wrapper_handle.write("        interface outgoing = outgoingVec;\n")
        wrapper_handle.write("        interface chains = chainsVec;\n")
        wrapper_handle.write("        interface incomingMultis = replicate(PHYSICAL_CONNECTION_IN_MULTI{try: ?, success: ?, clock: clk, reset: rst});\n")
        wrapper_handle.write("        interface outgoingMultis = replicate(PHYSICAL_CONNECTION_OUT_MULTI{notEmpty: ?, first: ?, deq: ?, clock: clk, reset: rst});\n")
        wrapper_handle.write("    endinterface;\n")

        wrapper_handle.write("    interface services = tuple3(moduleIfc,?,?);\n")
        wrapper_handle.write("    interface device = ?;//e2;\n")
        wrapper_handle.write("endmodule\n")

        if (pipeline_debug != 0):
            for channel in treeModule.channels:
                print "Channel in " + treeModule.name + " " + str(channel)

        return
    # END OF emitWrappersRecurse
