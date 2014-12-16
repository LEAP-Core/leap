# -*-Python-*-
import os
import sys
import traceback

class Source():

    def dump(self):
        print "Module: " + self.file + "\n"
        print "\tBuildPath: " + str(self.attributes) + "\n"
    
    def __init__(self, fileName, attributes):
        self.file = fileName
        self.attributes = attributes 

    ## Base object methods
    def __str__(self):
        #traceback.print_stack(file=sys.stdout)
        #print "Converting " + str(self.file) 
        return str(self.file)
    
