# JTAG Debug Module for RISC-V SoC

This repository contains the implementation and verification environment of a **JTAG Debug Module** designed for **RISC-V SoC platforms**. The project was developed as part of my **undergraduate thesis** in Electronics and Telecommunications Engineering, with a focus on digital IC design and on-chip debugging techniques.

# Overview

The goal of this project is to design a JTAG-based Debug Module that adheres to the RISC-V Debug Specification, enabling features such as:

- Halting/resuming core execution
- Reading and writing CPU registers and memory
- Communicating with debug tools like OpenOCD and GDB via DMI over JTAG

The source code is written in SystemVerilog, with simulation and verification performed using Verilator and GDB.

# Testing

- RTL source files are located in the `rtl/` directory.
- The `tb/` folder contains the testbench environment, including simulation files, waveform dumps, and OpenOCD integration tests.
- The module has been tested using both direct Verilator simulation and remote debugging via OpenOCD.

# Academic Note

This project was completed as part of my graduation thesis in 2025. It reflects my interest and training in hardware design, SoC development, and RISC-V open architecture.

# License

This repository is provided for academic and educational purposes.
