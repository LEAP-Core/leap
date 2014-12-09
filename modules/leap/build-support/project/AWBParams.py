# -*-Python-*-

# This file is intended as a common interface to AWB parameters
# types, so that they can be emitted in various formats.

class AWBParams:

    def __init__(self, moduleList):
        self.moduleList = moduleList
        self.awbParams = {}

  
    def parseModuleAWBParams(self, module):
        self.awbParams[module.name] = module.parseAWBParams()

    ##
    ## getAWBParam -- 
    ##
    ##   Looks for an AWB parameter, and returns either the parameter
    ##   or throws an error if the parameter is not found.  This
    ##   function takes either a scalar or iterable argument.
    ##    
    def getAWBParam(self, moduleName, param):
        if (hasattr(moduleName, '__iter__') and not isinstance(moduleName, basestring)):
            ## moduleName is a list.  Look in each module, returning the first match.
            for m in moduleName:
                try:
                    return self.awbParams[m][param]
                except:
                    pass
        else:  
            ## moduleName is just a string
            try:
                return self.awbParams[moduleName][param]
            except:
                pass

        raise Exception(param + " not in modules: " + str(moduleName))


    ##
    ## getAWBParamSafe -- 
    ##   Looks for an AWB parameter, and returns
    ##   either the parameter or None if the parameter is not found.
    ##    
    def getAWBParamSafe(self, moduleName, param):
        try:
            return self.getAWBParam(moduleName, param)
        except:
            return None
    

    ##
    ## emitParametersTCL -- 
    ##   Builds a tcl - based representation of the AWB params, including accessor functions. 
    ##    
    def emitParametersTCL(self, fileName):
        fileHandle = open(fileName, 'w')
        dataStructure = ' set awbParams {'

        namespaces = []
        for namespace in self.awbParams:
            namespaceString = '{ "' + namespace + '" '  
            paramStrings = []
            for param in self.awbParams[namespace]:
                paramStrings.append('{"' + param + '" "' + str(self.awbParams[namespace][param]) +'"}')
                

            namespaceString += ' { ' + ' '.join(paramStrings) + '} }'
            namespaces.append(namespaceString)
            
        dataStructure += " ".join(namespaces) + '}\n\n'

        fileHandle.write(dataStructure)

        fileHandle.write('proc getMemberNamed {ft name} {\n')
        fileHandle.write('    foreach elem $ft {\n')
        fileHandle.write('        if {[lindex $elem 0] == $name } {\n')
        fileHandle.write('            return [lindex $elem 1]\n')
        fileHandle.write('        }\n')
        fileHandle.write('    }\n')
        fileHandle.write('    return ""\n')
        fileHandle.write('}\n')
                
        # Define some functions to operate of the data structure
        fileHandle.write('proc getAWBParamsHelper {awbParamsList argsList} {\n')
        fileHandle.write('    set searchName [lindex $argsList 0]\n')
        fileHandle.write('    set searchResult [getMemberNamed $awbParamsList $searchName]\n')
        fileHandle.write('    set argsListLength [llength $argsList]\n')
        fileHandle.write('    puts "$searchName -> $searchResult"\n')
       
        fileHandle.write('    if { $argsListLength < 2 } {\n')
        fileHandle.write('        return $searchResult\n')
        fileHandle.write('    } \n')
        fileHandle.write('    set poppedList [lrange $argsList 1 end]\n')
        fileHandle.write('    return [getAWBParamsHelper $searchResult $poppedList]\n')
        fileHandle.write('}\n')

        fileHandle.write('proc getAWBParams { argsList } {\n')
        fileHandle.write('    global awbParams\n')
        fileHandle.write('    return [getAWBParamsHelper $awbParams $argsList]\n')
        fileHandle.write('}\n')

      
