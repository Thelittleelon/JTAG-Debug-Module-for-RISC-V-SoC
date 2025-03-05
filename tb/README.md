Debug Unit plus RI5CY Testbench
=====================

Running the testbench with [verilator](https://www.veripool.org/wiki/verilator)
----------------------
1. Point you environment variable `RISCV` to your RISC-V toolchain. 
2. In `tb` folder run ``make veri-run``
3. In `tb` folder (in new terminal) ``export JTAG_VPI_PORT=9999``  ``openocd -f dm_debug.cfg``
4. To connect with gdb and interact with the testbench:
     In `tb/prog` run ``riscv32-unknown-elf-gdb -x cmds.gdb``

