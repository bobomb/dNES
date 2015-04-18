/* cpu.d
 * Emulation code for the MOS5602 CPU.
 * Copyright (c) 2015 dNES Team.
 * License: LGPL 3.0
 */

import std.bitmanip;

class MOS6502
{
    struct StatusRegister
    {
        union {
            ubyte value;
            mixin(bitfields!(
                ubyte, "c", 1,   // carry flag
                ubyte, "z", 1,   // zero  flag
                ubyte, "i", 1,   // interrupt disable flag
                ubyte, "d", 1,   // decimal mode status (unused in NES)
                ubyte, "b", 1,   // software interrupt flag (BRK)
                ubyte, "",  1,   // not used. Must be logical 1 at all times.
                ubyte, "v", 1,   // overflow flag
                ubyte, "s", 1)); // sign     flag
        }
    }

    ubyte a;  // accumulator
    ubyte x;  // x index
    ubyte y;  // y index
    ubyte pc; // program counter
    ubyte sp; // stack pointer
    StatusRegister status;
}

unittest
{
    auto cpu = new MOS6502;
    cpu.status.c = true;
    assert(cpu.status.value == 0x01);

    cpu.status.value = 0xFF;
    assert(cpu.status.c == 1 &&
           cpu.status.z == 1 &&
           cpu.status.i == 1 &&
           cpu.status.d == 1 &&
           cpu.status.b == 1 && 
           cpu.status.v == 1 &&
           cpu.status.s == 1);
}

// ex: set expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 

