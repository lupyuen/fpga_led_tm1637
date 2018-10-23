
#Begin clock constraint
define_clock -name {demo|clk_50M} {p:demo|clk_50M} -period 9.214 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 4.607 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {demo|clk_spi_derived_clock} {n:demo|clk_spi_derived_clock} -period 9.214 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 4.607 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {demo|wr_spi_derived_clock[0]} {n:demo|wr_spi_derived_clock[0]} -period 9.214 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 4.607 -route 0.000 
#End clock constraint
