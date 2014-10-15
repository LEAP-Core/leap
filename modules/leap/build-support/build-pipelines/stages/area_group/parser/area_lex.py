reserved = {
    'in': 'IN',
    'location': 'LOCATION',
    'dimension': 'DIMENSION',
    'areagroup': 'AREAGROUP',
    'None': 'NONE',
    'FPGA': 'FPGA',
    }

tokens = [ 'SEMICOLON', 'EQUAL',
           'NAME', 'STRING', 'INT', 'COMMA', 'COMMENT'
         ] + list(reserved.values())


t_EQUAL = r'='
t_COMMA = r','
t_SEMICOLON = r';'
t_IN = r'in'
t_LOCATION = r'location'
t_DIMENSION = r'dimension'
t_NONE = r'None'
t_FPGA = r'FPGA'

def t_ignore_COMMENT(t):
    r'\#.*'
    pass

def t_NAME(t):
    r'[a-zA-Z_][]a-zA-Z0-9_[]*'
    t.type = reserved.get(t.value,'NAME')
    return t

def t_STRING(t):
    r'".*"'
    t.type = reserved.get(t.value,'STRING')
    return t

def t_INT(t):
    r'[0-9]+'
    t.type = reserved.get(t.value,'INT')
    return t

t_ignore = " \t\r" #white space requirements are evil

def t_newline(t):
    r'\n+'
    t.lexer.lineno += t.value.count("\n") 

def t_error(t):
    print 'Error at ' + str(t.lexer.lineno) +  ': Illegal character ' + t.value[0]
    t.lexer.skip(1) 

