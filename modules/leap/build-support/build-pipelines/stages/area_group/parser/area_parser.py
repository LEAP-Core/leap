import ply.yacc as yacc
import ply.lex as lex
from area_lex import *
from area_parse import *

areaParserCompiled = False
areaParser = None 
areaLexer = None 

def parseAreaGroupConstraints(area_group_file):
    # build the compiler
    global areaParser
    global areaLexer
    global areaParserCompiled

    if(not areaParserCompiled):
        areaLexer = lex.lex()
        areaParser = yacc.yacc()
        areaParserCompiled = True

    print "Parsing area file: " + str(area_group_file)
    areaGroupDescription = (open(area_group_file, 'r')).read()
    areaGroupConstraints = areaParser.parse(areaGroupDescription, lexer=areaLexer)
    return areaGroupConstraints
