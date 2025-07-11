.section .text
.globl _start

_start:
    li t0, 0x12345678
    li t1, 0x9abcdef0
    add t2, t0, t1
loop:
    j loop

