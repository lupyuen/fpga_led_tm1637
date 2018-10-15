
#Begin clock constraint
define_clock -name {LED_TM1637|clk_50M[0]} {p:LED_TM1637|clk_50M[0]} -period 10.000 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 5.000 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {LED_TM1637|cnt_derived_clock[3]} {n:LED_TM1637|cnt_derived_clock[3]} -period 10.000 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 5.000 -route 0.000 
#End clock constraint
