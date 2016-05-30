import os
import sys
import re
import pygraph
import cPickle as pickle

import model
from liChannel import LIChannel
from liChain import LIChain
from liService import LIService
from liGraph import LIGraph
from liModule import LIModule
from model import Module, Source, get_build_path

try:
    from pygraph.classes.digraph import digraph
except ImportError:
    # don't need to do anything
    print "\n"
    # print "Warning you should upgrade to pygraph 1.8"
import pygraph.algorithms.minmax

def parseLogfiles(logfiles):
    connections = []
    for logfile in logfiles:
        log = open(str(logfile), 'r')
        
        for line in log:
            r1 = re.match("Compilation message: .*: Dangling (\w+) {.*",line)
            if (r1): 
                if (r1.group(1) == "Chain") or (r1.group(1) == "Send") or (r1.group(1) == "Recv"):
                    match = re.search(r'.*Dangling (\w+) {(.*)} \[(\d+)\]:(\w+):(\w+):(\d+):(\w+):(\w+)', line)
                    if (match):
                        #python groups begin at index 1  
                        if (match.group(1) == "Chain"):
                            connections +=  [LIChain(match.group(1), 
                                                     match.group(2),
                                                     match.group(3),
                                                     match.group(4),      
                                                     eval(match.group(5)), # optional
                                                     match.group(6),
                                                     match.group(7),
                                                     match.group(8),
                                                     match.group(8),
                                                     type)]
                        else:
                            connections +=  [LIChannel(match.group(1), 
                                                       match.group(2),
                                                       match.group(3),
                                                       match.group(4),      
                                                       eval(match.group(5)), # optional
                                                       match.group(6),
                                                       match.group(7),
                                                       match.group(7),
                                                       type)]
                    else: 
                        print "Malformed connection message: " + line
                        sys.exit(-1)
                else:
                    match = re.search(r'.*Dangling (\w+) {(.*)} {(.*)} \[(\d+)\]:(\w+):(\d+):(\d+):(\d+):(\w+):(\d+)', line)
                    if (match):
                        connections +=  [LIService(match.group(1), 
                                                   match.group(2),
                                                   match.group(3),
                                                   match.group(4),      
                                                   match.group(5),
                                                   False, 
                                                   match.group(6),
                                                   match.group(7),
                                                   match.group(8),
                                                   match.group(9), 
                                                   match.group(9), 
                                                   match.group(10),
                                                   type)]
                    else: 
                        print "Malformed connection message: " + line
                        sys.exit(-1)
            
    return connections

##
## placement_cut --
##   Cut the tree based on the placement of logic in area groups.  This will
##   cause chains to be connected with minimized paths.  The area constraints
##   code pre-sorts all modules.
##
def placement_cut(graph, areaConstraints):
    # Sort the nodes according to the pre-sorted order already set by the
    # area group code.
    nodes = sorted(graph.nodes(),
                   key=lambda module: areaConstraints.constraints[module.name].sortIdx)

    # Map the first half of the sorted list to tree "0" and the second half
    # to tree "1".
    map = {}
    cut_point = (1 + len(graph.nodes())) / 2
    for i in range(len(nodes)):
        n = nodes[i]
        map[n] = int(i >= cut_point)

    return map


##
## min_cut --
##   When area groups aren't computed, sort the tree such that inter-module
##   connections determine grouping.
##
##   The code is a basic S-T min-cut algorithm.  Eventually we should swap
##   this for Karger's algorithm.
##
def min_cut(graph):
    minimum_cut = float("inf")
    minimum_mapping = None
    # for all pairs s-t 
    nodes = sorted(graph.nodes(), key=lambda module: module.name)
    for source in nodes:
        for sink in nodes:
            if (source != sink):
                (flow, cut) =  pygraph.algorithms.minmax.maximum_flow(graph, source, sink)
                value = pygraph.algorithms.minmax.cut_value(graph, flow, cut)
                if (value < minimum_cut):
                    minimum_cut = value
                    minimum_mapping = cut

    return minimum_mapping


# this function allows us to supply resource utilizations for
# different modules.  It is used in the LIM compilation pipeline, and
# also to construct area groups during single platform builds. 
def assignResources(moduleList, environmentGraph = None, moduleGraph = None):

    pipeline_debug = model.getBuildPipelineDebug(moduleList) or True

    # We require this extra 'S', but maybe this should not be the case.
    resourceFile = moduleList.getAllDependenciesWithPaths('GIVEN_RESOURCESS')    

    filenames = []
    if (len(resourceFile) > 0):
        filenames.append(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + resourceFile[0])
        # let's read in a resource file
        
    # we can also get resource files from the first compilation pass.
    # pick those resource files up here.  However, we don't force the
    # caller to supply such things. 
    if (moduleGraph is not None):
        for moduleName in moduleGraph.modules:
            moduleObject = moduleGraph.modules[moduleName]   
            filenames += moduleObject.getObjectCode('RESOURCES')
    else:
        filenames += moduleList.getAllDependencies('RESOURCES')    

    resources = {}

    # need to check for file existance. returning an empty resource
    # dictionary is acceptable.
    for filename in filenames:
        if (not os.path.exists(str(filename.from_bld()))):
            print "Warning, no resources found at " + str(filename.from_bld()) + "\n"
            continue

        logfile = open(str(filename.from_bld()), 'r')  
        for line in logfile:
            # There are several ways that we can get resource. One way is instrumenting the router. 
            params = line.split(':')
            moduleName = params.pop(0)
            resources[moduleName] = {}
            for index in range(len(params)/2):
                resources[moduleName][params[2*index]] = float(params[2*index+1])
    if (pipeline_debug):        
        print "PLACER RESOURCES: " + str(resources)

    return resources


def linkFirstPassObject(moduleList, module, firstPassLIGraph, sourceType, destinationType, linkDirectory=None):
    if(linkDirectory is None):
        linkDirectory = moduleList.compileDirectory

    deps = []
    moduleObject = firstPassLIGraph.modules[module.name]
    if (sourceType in moduleObject.objectCache):
        for src in moduleObject.objectCache[sourceType]:
            linkPath = moduleList.env.File(linkDirectory + '/' + os.path.basename(str(src)))
            def linkSource(target, source, env):
                # It might be more useful if the Module contained a pointer to the LIModules...                        
                if (os.path.lexists(str(target[0]))):
                    os.remove(str(target[0]))
                rel = os.path.relpath(str(source[0]), os.path.dirname(str(target[0])))
                print "Linking: " + str(target[0]) + " -> " + rel
                os.symlink(rel, str(target[0]))

            link = moduleList.env.Command(linkPath, src.from_bld(), linkSource)

            if(destinationType in  module.moduleDependency):  
                module.moduleDependency[destinationType] += [link]
            else:
                module.moduleDependency[destinationType] = [link]

            deps += [link]
    else:
        return None
    return deps



def dump_lim_graph(moduleList):
    lim_logs = []
    lim_stubs = []

    pipeline_debug = model.getBuildPipelineDebug(moduleList)

    for module in moduleList.synthBoundaries():

        if(module.getAttribute('LI_GRAPH_IGNORE')):
            continue

        # scrub tree build/platform, which are redundant.
        lim_logs.extend(module.getDependencies('BSV_LOG'))
        lim_stubs.extend(module.getDependencies('GEN_VERILOG_STUB'))

    # clean duplicates in logs/stubs
    lim_logs  = list(set(lim_logs))
    lim_stubs = list(set(lim_stubs))

    li_graph = moduleList.env['DEFS']['APM_NAME'] + '.li'

    ## dump a LIM graph for use by the LIM compiler.  here
    ## we wastefully contstruct (or reconstruct, depending on your
    ## perspective, a LIM graph including the platform channels.
    ## Probably this result could be acheived with the mergeGraphs
    ## function.
    def dump_lim_graph(target, source, env):
        # Find the subset of sources that are log files and parse them
        logs = [s for s in source if (str(s)[-4:] == '.log')]
        fullLIGraph = LIGraph(parseLogfiles(logs))

        # annotate modules with relevant object code (useful in
        # LIM compilation)
        # this is not technically a part of the tree cut methodology, but we need to do this

        # For the LIM compiler, we must also annotate those
        # channels which are coming out of the platform code.

        for module in moduleList.synthBoundaries():
            modulePath = module.buildPath


            # Wrap the real findBuildPath() so it can be invoked
            # later by map().
            def __findBuildPath(path):
                return Source.findBuildPath(path, modulePath)

            # User area groups add a wrinkle. We need to
            # keep them around, but they don't have LI
            # channels

            if(not module.getAttribute('AREA_GROUP') is None):
                # We now need to create and integrate an
                # LI Module for this module
                newModule = LIModule(module.name, module.name)
                newModule.putAttribute('PLATFORM_MODULE', True)
                newModule.putAttribute('BLACK_BOX_AREA_GROUP', True)
                fullLIGraph.mergeModules([newModule])

            # the liGraph only knows about modules that actually
            # have connections some modules are vestigial, andso
            # we can forget about them...
            if (module.boundaryName in fullLIGraph.modules):
                for objectType in module.moduleDependency:
                    # it appears that we need to filter
                    # these objects.  TODO: Clean the
                    # things adding to this list so we
                    # don't require the filtering step.
                    depList = module.moduleDependency[objectType]
                    convertedDeps = model.convertDependencies(depList)
                    relativeDeps = map(__findBuildPath, convertedDeps)
                    fullLIGraph.modules[module.boundaryName].putObjectCode(objectType, relativeDeps)

        for module in moduleList.synthBoundaries():
            if(module.boundaryName in fullLIGraph.modules):
                # annotate platform module with local mapping.
                if(module.name == moduleList.localPlatformName + '_platform'):
                    # The platform module is special.
                    fullLIGraph.modules[module.boundaryName].putAttribute('MAPPING', moduleList.localPlatformName)
                    fullLIGraph.modules[module.boundaryName].putAttribute('PLATFORM_MODULE', True)

        # Decorate LI modules with type
        for module in fullLIGraph.modules.values():
            module.putAttribute("EXECUTION_TYPE","RTL")

        # dump graph representation.
        pickleHandle = open(str(target[0]), 'wb')
        pickle.dump(fullLIGraph, pickleHandle, protocol=-1)
        pickleHandle.close()

        if (pipeline_debug != 0):
            print "Initial Graph is: " + str(fullLIGraph) + ": " + sys.version +"\n"

    # Setup the graph dump Although the graph is built
    # from only LI modules, the top wrapper contains
    # sizing information. Also needs stubs.
    dumpGraph = moduleList.env.Command(li_graph,
                                       lim_logs + lim_stubs,
                                       dump_lim_graph)

    moduleList.topModule.moduleDependency['LIM_GRAPH'] = [li_graph]

    # dumpGraph depends on most other top level builds since it
    # walks the set of generated files.
    moduleList.env.Depends(dumpGraph, moduleList.topDependency)
    moduleList.topDependency = [dumpGraph]

