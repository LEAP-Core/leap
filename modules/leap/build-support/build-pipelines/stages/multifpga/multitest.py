import ply.lex as lex
import ply.yacc as yacc
from multilex import *
from multiparse import *

lex.lex()
yacc.yacc()

errors = [1,1,1,1,1,1]

platform0 = ' platform FPGA0 fpga0.apm; FPGA1 -> drivers.fromfpga1; FPGA1 <- drivers.tofpga1; endplatform '

platform1 = ' platform FPGA1 fpga1.apm; FPGA0 -> drivers.fromfpga0; FPGA0 <- drivers.fromfpga0;endplatform '

try:
    res = yacc.parse(platform0)
except (IndexError,SyntaxError):
    errors[0] = 0 
    
try:
    res = yacc.parse(platform0 + platform1)
except (IndexError,SyntaxError):
    print ''
    

# if we got this far, we've likely parsed things correctly
if(res.getPathLength('FPGA0','FPGA1') == 1):
    errors[1] = 0

platform0 = ' platform FPGA0 fpga0.apm; FPGA1 -> drivers.fromfpga1; FPGA2 <- drivers.tofpga2; endplatform\n '

platform1 = ' platform FPGA1 fpga1.apm; FPGA0 <- drivers.tofpga0; FPGA2 -> drivers.fromfpga2;endplatform\n '

platform2 = ' platform FPGA2 fpga2.apm; FPGA0 -> drivers.fromfpga0; FPGA1 <- drivers.tofpga1; endplatform\n '

res = yacc.parse(platform0 + platform1 + platform2)



if(res.getPathLength('FPGA0','FPGA1') == 2 and
   res.getPathLength('FPGA2','FPGA0') == 2 and
   res.getPathLength('FPGA0','FPGA2') == 1):
    errors[2] = 0

if(res.getPathLength('FPGA0','FPGA1') == 2 and
   res.getPathLength('FPGA2','FPGA0') == 2 and
   res.getPathLength('FPGA0','FPGA2') == 1):
    errors[3] = 0

# Add a fourth link in the ring

platform0 = ' platform FPGA0 fpga0.apm; FPGA1 -> drivers.fromfpga1; FPGA3 <- drivers.tofpga3; endplatform\n '

platform1 = ' platform FPGA1 fpga1.apm; FPGA2 -> drivers.fromfpga2; FPGA0 <- drivers.tofpga0; endplatform\n '

platform2 = ' platform FPGA2 fpga2.apm; FPGA3 -> drivers.fromfpga3; FPGA1 <- drivers.tofpga1; endplatform\n '

platform3 = ' platform FPGA3 fpga3.apm; FPGA0 -> drivers.fromfpga0; FPGA2 <- drivers.tofpga2; endplatform\n '

res = yacc.parse(platform0 + platform1 + platform2 + platform3)

if(res.getPathLength('FPGA0','FPGA1') == 3 and
   res.getPathLength('FPGA2','FPGA0') == 2 and
   res.getPathLength('FPGA0','FPGA2') == 1):
    errors[2] = 0

tables = res.buildTransitTables()


if(tables[0]['FPGA1']['FPGA2'] == 'drivers.tofpga0' and
   tables[0]['FPGA1']['FPGA3'] == 'drivers.tofpga0' and
   tables[0]['FPGA1']['FPGA0'] == 'drivers.tofpga0'):
    errors[4] = 0


# check that frontend correctly handles 

platform0 = ' platform unknown unknown.apm; FPGA1 -> drivers.fromfpga1; FPGA2 <- drivers.tofpga2; endplatform\n '

platform1 = ' platform FPGA1 fpga1.apm; unknown <- drivers.tofpga0; FPGA2 -> drivers.fromfpga2;endplatform\n '

platform2 = ' platform FPGA2 fpga2.apm; unknown -> drivers.fromfpga0; FPGA1 <- drivers.tofpga1; endplatform\n '

try:
    res = yacc.parse(platform0 + platform1 + platform2)
except (IndexError,SyntaxError):
    errors[5] = 0 


count = 1
for error in errors:
    if(error == 1):
        print 'Test %d Failed\n' % count
    else:
        print 'Test %d Passed\n' % count
    count = count + 1

