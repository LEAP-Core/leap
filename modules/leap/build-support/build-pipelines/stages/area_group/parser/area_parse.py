import sys
import ply.yacc as yacc
import area_group
from area_group_location import *
from area_group_size import *
from area_group_path import *
from area_group_resource import *
from area_group_relationship import *
from area_group_attribute import *

def p_constraint_list(p):
    """
    constraint_list :
    constraint_list : comment                  constraint_list
    constraint_list : group_statement          constraint_list
    constraint_list : in_statement             constraint_list
    constraint_list : location_statement       constraint_list
    constraint_list : dimension_statement      constraint_list
    constraint_list : chip_dimension_statement constraint_list
    constraint_list : path_statement           constraint_list
    constraint_list : resource_statement       constraint_list
    constraint_list : lower_left_statement     constraint_list
    constraint_list : upper_right_statement    constraint_list
    constraint_list : attribute_statement      constraint_list
    """

    # Since we'll be generating some constraints elsewhere, that code
    # will be building the AST. So we just pass a list back. 

    if(len(p) > 1):
        p[0] = [p[1]] + p[2]
    else:
        p[0] = []
    

def p_group_statement(p):
    """
    group_statement : AREAGROUP NAME EQUAL STRING SEMICOLON
    group_statement : AREAGROUP NAME EQUAL NONE   SEMICOLON
    """

    p[0] = area_group.AreaGroup(p[2], eval(p[4]))

def p_path_statement(p):
    """
    path_statement : PATH NAME EQUAL STRING SEMICOLON
    """

    p[0] = AreaGroupPath(p[2], eval(p[4]))

def p_resource_statement(p):
    """
    resource_statement : RESOURCE NAME NAME EQUAL INT SEMICOLON
    """

    p[0] = AreaGroupResource(p[2], p[3], eval(p[5]))


def p_in_statement(p):
    """
    in_statement : NAME IN NAME SEMICOLON
    """

    p[0] = AreaGroupRelationship(p[3], p[1])

def p_location_statement(p):
    """
    location_statement : LOCATION NAME INT COMMA INT SEMICOLON
    """

    p[0] = AreaGroupLocation(p[2], eval(p[3]), eval(p[5]))


def p_dimension_statement(p):
    """
    dimension_statement : DIMENSION NAME INT COMMA INT SEMICOLON
    """

    p[0] = AreaGroupSize(p[2], eval(p[3]), eval(p[5]))

def p_chip_dimension_statement(p):
    """
    chip_dimension_statement : DIMENSION FPGA INT COMMA INT SEMICOLON
    """

    p[0] = AreaGroupSize(p[2], eval(p[3]), eval(p[5]))

def p_lower_left_statement(p):
    """
    lower_left_statement : LOWERLEFT NAME INT COMMA INT SEMICOLON
    """

    p[0] = AreaGroupLowerLeft(p[2], eval(p[3]), eval(p[5]))

def p_upper_right_statement(p):
    """
    upper_right_statement : UPPERRIGHT NAME INT COMMA INT SEMICOLON
    """

    p[0] = AreaGroupUpperRight(p[2], eval(p[3]), eval(p[5]))

def p_attribute_statement(p):
    """
    attribute_statement : ATTRIBUTE NAME STRING EQUAL STRING SEMICOLON
    attribute_statement : ATTRIBUTE NAME STRING EQUAL INT    SEMICOLON
    """

    p[0] = AreaGroupAttribute(p[2], eval(p[3]), eval(p[5]))

def p_comment(p):
    """
    comment : COMMENT
    """
    #We aren't supposed to get here.
    p[0]  = None

