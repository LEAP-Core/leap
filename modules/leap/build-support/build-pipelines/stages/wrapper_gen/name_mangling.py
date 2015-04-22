##
## default_clock and default_reset have their names mangled to satisfy the
## Bluespec compiler.
##
def clockMangle(clock):
    if (clock == 'default_clock'):
        return 'default_clk'
    return clock

def resetMangle(reset):
    if (reset == 'default_reset'):
        return 'default_rst'
    return reset
