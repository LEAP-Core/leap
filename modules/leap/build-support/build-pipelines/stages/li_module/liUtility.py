import sys
import re
import pygraph
from liChannel import *
from liChain import *
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
