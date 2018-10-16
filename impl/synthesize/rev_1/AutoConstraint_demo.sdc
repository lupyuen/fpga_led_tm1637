
#Begin clock constraint
define_clock -name {demo|clk_50M} {p:demo|clk_50M} -period 10.337 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 5.169 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {demo|clk_led_derived_clock} {n:demo|clk_led_derived_clock} -period 10.337 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 5.169 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {demo|rd_spi_derived_clock[0]} {n:demo|rd_spi_derived_clock[0]} -period 10.337 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 5.169 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {demo|wr_spi_derived_clock[0]} {n:demo|wr_spi_derived_clock[0]} -period 10.337 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 5.169 -route 0.000 
#End clock constraint
