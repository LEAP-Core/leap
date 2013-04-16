import sys
import re
import pygraph
from liChannel import *
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
            if(re.match("Compilation message: .*: Dangling",line)):                
                #Dangling Send {front_panel::FRONTP_MASKED_LEDS} [0]:fpga_leds:Unknown:False:8:traffic_light_function:None            
                match = re.search(r'.*Dangling (\w+) {(.*)} \[(\d+)\]:(\w+):(\w+):(\w+):(\d+):(\w+):(\w+)', line)
                if(match):
                    #python groups begin at index 1  
                    if(match.group(1) == "Chain"):
                        sc_type = "ChainSrc"
                    else:
                        sc_type = match.group(1)

                
                  
                    parentConnection = LIChannel(sc_type, 
                                                      match.group(2),
                                                      match.group(3),
                                                      match.group(4),      
                                                      match.group(5),
                                                      eval(match.group(6)), # optional
                                                      match.group(7),
                                                      match.group(8),
                                                      match.group(9),
                                                      type)
                           
                  
                    connections += [parentConnection]
   
                    if(match.group(1) == "Chain"):
                        sinkConnection = LIChannel("ChainSink", 
                                                       match.group(2),
                                                       match.group(3),
                                                       match.group(4),
                                                       match.group(5),
                                                       eval(match.group(6)), # optional
                                                       match.group(7),
                                                       match.group(8),
                                                       match.group(9),
                                                       type)
                        parentConnection.chainPartner = sinkConnection
                        sinkConnection.chainPartner = parentConnection
                        connections += [sinkConnection]
                        

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
   for source in graph.nodes():
      for sink in graph.nodes():
          if(source != sink):
              (flow, cut) =  pygraph.algorithms.minmax.maximum_flow(graph, source, sink)
              value = pygraph.algorithms.minmax.cut_value(graph, flow, cut)
              if(value < minimum_cut):
                  minimum_cut = value
                  minimum_mapping = cut

   return minimum_mapping
