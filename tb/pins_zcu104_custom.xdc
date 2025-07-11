###########TIMING#####################
##Create constraint for the clock input of the zcu104 board
#create_clock -period 8.000 -name ref_clk [get_ports ref_clk_p]
#set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets ref_clk]

##JTAG
#create_clock -period 100.000 -name tck -waveform {0.000 50.000} [get_ports tck_i]
#set_input_jitter tck 1.000
#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets tck_i]

## minimize routing delay
#set_input_delay -clock tck -clock_fall 5.000 [get_ports td_i]
#set_input_delay -clock tck -clock_fall 5.000 [get_ports tms_i]
#set_output_delay -clock tck 5.000 [get_ports td_o]

#set_max_delay -to [get_ports td_o] 20.000
#set_max_delay -from [get_ports tms_i] 20.000
#set_max_delay -from [get_ports td_i] 20.000



##################IN-OUT#####################
### Sys clock
#set_property -dict {PACKAGE_PIN E23 IOSTANDARD LVDS} [get_ports ref_clk_n]
#set_property -dict {PACKAGE_PIN F23 IOSTANDARD LVDS} [get_ports ref_clk_p]
### Reset
#set_property -dict { PACKAGE_PIN M11 IOSTANDARD LVCMOS33 } [get_ports {nrst_btn}]


### User JTAG (marked as USR_JTAG on schematic)
#set_property -dict { PACKAGE_PIN H8 IOSTANDARD LVCMOS33 } [get_ports td_i];
#set_property -dict { PACKAGE_PIN G7 IOSTANDARD LVCMOS33 } [get_ports td_o];
#set_property -dict { PACKAGE_PIN G8 IOSTANDARD LVCMOS33 } [get_ports tms_i];
#set_property -dict { PACKAGE_PIN H7 IOSTANDARD LVCMOS33 } [get_ports tck_i];


### UART
#set_property -dict { PACKAGE_PIN C19 IOSTANDARD LVCMOS18 } [get_ports ser0_tx];
#set_property -dict { PACKAGE_PIN A20 IOSTANDARD LVCMOS18 } [get_ports ser0_rx];
### LEDs
#set_property -dict { PACKAGE_PIN D5    IOSTANDARD LVCMOS33 } [get_ports { LED[0] }]; #IO_L24N_T3_35 Sch=led[4]
#set_property -dict { PACKAGE_PIN D6    IOSTANDARD LVCMOS33 } [get_ports { LED[1] }]; #IO_25_35 Sch=led[5]
#set_property -dict { PACKAGE_PIN A5    IOSTANDARD LVCMOS33 } [get_ports { LED[2] }]; #IO_L24P_T3_A01_D17_14 Sch=led[6]
#set_property -dict { PACKAGE_PIN B5   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }]; #IO_L24N_T3_A00_D16_14 Sch=led[7]

##set_property CFGBVS VCCO [current_design]
##set_property CONFIG_VOLTAGE 3.3 [current_design]
##set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

##OLED
#set_property -dict { PACKAGE_PIN J9    IOSTANDARD LVCMOS33 } [get_ports { DISP_CTRL[0] }]; #IO_L2P_T0_AD12P_35 Sch=ad_p[12]
#set_property -dict { PACKAGE_PIN K9    IOSTANDARD LVCMOS33 } [get_ports { DISP_CTRL[1] }]; #IO_L2N_T0_AD12N_35 Sch=ad_n[12]
#set_property -dict { PACKAGE_PIN K8    IOSTANDARD LVCMOS33 } [get_ports { DISP_CTRL[2] }]; #IO_L5P_T0_AD13P_35 Sch=ad_p[13]
#set_property -dict { PACKAGE_PIN L8    IOSTANDARD LVCMOS33 } [get_ports { SPI_TX }]; #IO_L5N_T0_AD13N_35 Sch=ad_n[13]
#set_property -dict { PACKAGE_PIN L10    IOSTANDARD LVCMOS33 } [get_ports { SPI_SCK }]; #IO_L8P_T1_AD14P_35 Sch=ad_p[14]
#set_property -dict { PACKAGE_PIN M10    IOSTANDARD LVCMOS33 } [get_ports { DISP_CTRL[3] }]; #IO_L8N_T1_AD14N_35 Sch=ad_n[14]


########## CLOCK CONSTRAINTS ##########
## Clock input (differential) from ZCU104 oscillator
#set_property PACKAGE_PIN F23 [get_ports clk_p]
#set_property PACKAGE_PIN E23 [get_ports clk_n]
#set_property IOSTANDARD LVDS [get_ports {clk_p clk_n}]
#create_clock -period 8.000 -name clk_sys [get_ports clk_p]
#set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets clk_p]

########### RESET BUTTON ##########
## Reset button (active high)
#set_property PACKAGE_PIN M11 [get_ports reset_button]
#set_property IOSTANDARD LVCMOS33 [get_ports reset_button]

########### JTAG INTERFACE ##########
## JTAG user interface
#set_property PACKAGE_PIN H7 [get_ports tck]
#set_property PACKAGE_PIN G8 [get_ports tms]
#set_property PACKAGE_PIN H8 [get_ports tdi]
#set_property PACKAGE_PIN G7 [get_ports tdo]
##set_property PACKAGE_PIN F8 [get_ports trst_n] ; # bạn có thể thay đổi chân nếu cần

#set_property IOSTANDARD LVCMOS33 [get_ports {tck tms tdi tdo}]

## Define TCK as JTAG clock
#create_clock -period 100.000 -name tck_clk [get_ports tck]
#set_input_jitter tck_clk 1.000

### Optional: timing constraints cho JTAG (nên dùng nếu tổng hợp debug)
##set_input_delay -clock tck_clk -clock_fall 5.000 [get_ports tdi]
##set_input_delay -clock tck_clk -clock_fall 5.000 [get_ports tms]
##set_output_delay -clock tck_clk 5.000 [get_ports tdo]

#set_max_delay -to [get_ports tdo] 20.000
#set_max_delay -from [get_ports tdi] 20.000
#set_max_delay -from [get_ports tms] 20.000

########### LED OUTPUTS ##########
## LED status outputs
#set_property PACKAGE_PIN D5 [get_ports led_pass] ; # LED 0
#set_property PACKAGE_PIN D6 [get_ports led_fail] ; # LED 1
#set_property IOSTANDARD LVCMOS33 [get_ports {led_pass led_fail}]

########## CLOCK CONSTRAINTS ##########
set_property PACKAGE_PIN F23 [get_ports clk_p]
set_property PACKAGE_PIN E23 [get_ports clk_n]
set_property IOSTANDARD LVDS [get_ports {clk_p clk_n}]
create_clock -period 8.000 -name clk_sys [get_ports clk_p]
set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets clk_p]

########## RESET BUTTON ##########
set_property PACKAGE_PIN M11 [get_ports reset_button]
set_property IOSTANDARD LVCMOS33 [get_ports reset_button]

########## JTAG INTERFACE ##########
set_property PACKAGE_PIN H7 [get_ports tck]
set_property PACKAGE_PIN G8 [get_ports tms]
set_property PACKAGE_PIN H8 [get_ports tdi]
set_property PACKAGE_PIN G7 [get_ports tdo]
set_property PACKAGE_PIN G6 [get_ports trst_n]

set_property IOSTANDARD LVCMOS33 [get_ports {tck tms tdi tdo trst_n}]
create_clock -period 100.000 -name tck_clk [get_ports tck]
set_input_jitter tck_clk 1.000

# Allow sub-optimal routing for TCK (avoids BUFG placement error)
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets tck]

set_input_delay -clock tck_clk -clock_fall 5.000 [get_ports tdi]
set_input_delay -clock tck_clk -clock_fall 5.000 [get_ports tms]
set_output_delay -clock tck_clk 5.000 [get_ports tdo]

set_max_delay -to [get_ports tdo] 20.000
set_max_delay -from [get_ports tdi] 20.000
set_max_delay -from [get_ports tms] 20.000


########## LED OUTPUTS ##########
set_property PACKAGE_PIN D5 [get_ports led_pass]
set_property PACKAGE_PIN D6 [get_ports led_fail]
set_property IOSTANDARD LVCMOS33 [get_ports {led_pass led_fail}]

########## CLOCK DOMAIN CROSSING EXCEPTION ##########
# Declare clk_sys and tck_clk as asynchronous clock domains
# This prevents Vivado from reporting false timing violations across these domains
set_clock_groups -asynchronous -group [get_clocks clk_sys] -group [get_clocks tck_clk]






