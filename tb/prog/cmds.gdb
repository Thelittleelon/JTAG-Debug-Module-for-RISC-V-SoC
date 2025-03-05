# read binary file
file test.elf

# set logging options
 set logging enabled off
 set logging file gdb_verbose.log
 set logging overwrite on
 set logging enabled on

# set gdb to show packets and serial data
set debug remote 1
#set debug serial 1

set remotetimeout 20

target extended-remote localhost:3333
monitor reset halt
load
break main
c
step
quit
