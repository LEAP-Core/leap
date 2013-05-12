# foo @PARAM@

tokens = [ 'AT', 'STRING']

t_AT = r'@'
#t_ENDPLATFORM = r'unknown'

def t_STRING(t):
    r'[^@]+'
    #t.type = reserved.get(t.value,'STRING')
    return t

def t_error(t):
    print 'Error at ' + str(t.lexer.lineno) +  ': Illegal character ' + t.value[0]
    t.lexer.skip(1) 

