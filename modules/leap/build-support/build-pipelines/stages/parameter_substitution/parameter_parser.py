import ply.yacc as yacc
import ply.lex as lex
from parameterlex import *
from parameterparse import *

def parseAWBFile (awbFile):
    # build the compiler
    lex.lex()
    yacc.yacc()
    awbHandle = (open(awbFile, 'r')).read()
    return yacc.parse(awbHandle)
