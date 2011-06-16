import ply.yacc as yacc
import ply.lex as lex
from multilex import *
from multiparse import *
from environment import *

def parseFPGAEnvironment (environmentFile):
    # build the compiler
    lex.lex()
    yacc.yacc()
    environmentDescription = (open(environmentFile, 'r')).read()
    environment = yacc.parse(environmentDescription)
    return environment
