# This file takes two li channels traces and compares them.  It can be
# used to find deviations in the ordering and content of channels
# across runs.
from optparse import OptionParser
import numpy
import matplotlib.pyplot as plt
import math

parser = OptionParser()
(options, args) = parser.parse_args()

if len(args) < 2:
    sys.exit(-1)

trace1 = open(args[0], "r");
trace2 = open(args[1], "r");

traceDatabase1 = {}
traceDatabase2 = {}

def handleTrace(trace, traceDB):
    for line in trace.readlines():

        components = line.split(':')

        if(len(components) == 3 and components[0] == 'Dequeue'):
            
            if(not (components[1] in traceDB)):
                traceDB[components[1]] = []
 
            traceDB[components[1]].append(components[2])

handleTrace(trace1, traceDatabase1)            
handleTrace(trace2, traceDatabase2)            

channels = set(traceDatabase1.keys() + traceDatabase2.keys())

for channel in channels:
    print "Examining " + channel + "\n"
    if(not channel in traceDatabase1):
        print channel + " not in " + args[0]
        continue 

    if(not channel in traceDatabase2):
        print channel + " not in " + args[1]
        continue

    if(len(traceDatabase1[channel]) > len(traceDatabase2[channel])):
        print "For this channel " + args[0] + " had " + str(len(traceDatabase1[channel])) + " elements " + \
              " while " + args[1] + " had " + str(len(traceDatabase2[channel])) + " elements \n" 

    for index in range(min(len(traceDatabase1[channel]), len(traceDatabase2[channel]))):
        if(traceDatabase1[channel][index] != traceDatabase2[channel][index]):
            print "Channel " + channel + " differs at " + str(index) + ":" + traceDatabase1[channel][index] + ":" + traceDatabase2[channel][index] + "\n"
        

 
