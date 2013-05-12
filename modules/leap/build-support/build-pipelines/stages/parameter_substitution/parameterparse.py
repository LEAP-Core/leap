import sys
import ply.yacc as yacc
from parameter import *

def p_document(p):
    """
    document :
    document : token_list
    """
   
    if len(p) == 1:
        p[0] = []
    else:
        p[0] = p[1]    

def p_token_list(p):
    """
    token_list :
    token_list : STRING token_list
    token_list : parameter token_list
    """
    if len(p) == 1:
        p[0] = [] 
    else:
        p[0] = [p[1]] + p[2]
        
def p_paramter(p):
    """
    parameter : AT STRING AT
    """     
    p[0] = Parameter(p[2])

    
