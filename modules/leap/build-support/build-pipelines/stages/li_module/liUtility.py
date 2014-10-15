import sys
import re
import pygraph
from liChannel import *
from liChain import *
from model import *

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
        log = open(logfile,'r')
             
        for line in log:
            if (re.match("Compilation message: .*: Dangling",line)):                
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
                                                 type)]
                    else:
                        connections +=  [LIChannel(match.group(1), 
                                                   match.group(2),
                                                   match.group(3),
                                                   match.group(4),      
                                                   eval(match.group(5)), # optional
                                                   match.group(6),
                                                   match.group(7),
                                                   type)]
                           
             
            
                else:
                    print "Malformed connection message: " + line
                    sys.exit(-1)

    return connections

#Basic S-T min-cut algorithm
#Eventually we should swap this for Karger's algorithm
def min_cut(graph):
   minimum_cut = float("inf")
   minimum_mapping = None
   # for all pairs s-t 
   for source in sorted(graph.nodes(), key=lambda module: module.name):
      for sink in sorted(graph.nodes(), key=lambda module: module.name):
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

    pipeline_debug = getBuildPipelineDebug(moduleList) or True

    # We require this extra 'S', but maybe this should not be the case.
    resourceFile = moduleList.getAllDependenciesWithPaths('GIVEN_RESOURCESS')    
    filenames = []
    if(len(resourceFile) > 0):
        filenames.append(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + resourceFile[0])
        # let's read in a resource file
        
    # we can also get resource files from the first compilation pass.
    # pick those resource files up here.  However, we don't force the
    # caller to supply such things. 
    if( moduleGraph is not None):
        for moduleName in moduleGraph.modules:
            moduleObject = moduleGraph.modules[moduleName]   
            filenames += moduleObject.getObjectCode('RESOURCES')
    else:
        filenames += moduleList.getAllDependencies('RESOURCES')    

    resources = {}

    # need to check for file existance. returning an empty resource
    # dictionary is acceptable.
    for filename in filenames:
        if( not os.path.exists(filename)):
            print "Warning, no resources found at " + filename + "...\n"
            continue

        logfile = open(filename,'r')  
        for line in logfile:
            # There are several ways that we can get resource. One way is instrumenting the router. 
            params = line.split(':')
            moduleName = params.pop(0)
            resources[moduleName] = {}
            for index in range(len(params)/2):
                resources[moduleName][params[2*index]] = float(params[2*index+1])
    if(pipeline_debug):        
        print "PLACER RESOURCES: " + str(resources)

    return resources

