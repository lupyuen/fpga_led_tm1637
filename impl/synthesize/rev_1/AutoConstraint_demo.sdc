
#Begin clock constraint
define_clock -name {demo|clk_50M} {p:demo|clk_50M} -period 6.666 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 3.333 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {demo|clk_led_derived_clock} {n:demo|clk_led_derived_clock} -period 6.666 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 3.333 -route 0.000 
#End clock constraint
