/* cpu.d
 * Emulation code for the MOS5602 CPU.
 * Copyright (c) 2015 dNES Team.
 * License: LGPL 3.0
 */

module cpu.mos6502;

import cpu.statusregister;

class MOS6502
{
    this()
    {
        status = new StatusRegister; 
    }

    private:
        ubyte _a;  // accumulator
        ubyte _x;  // x index
        ubyte _y;  // y index
        ubyte _pc; // program counter
        ubyte _sp; // stack pointer
        StatusRegister _status;
    
}
unittest
{
    auto cpu = new MOS6502;	
    cpu.setCarry();
    assert(cpu._status.c == 0x1);
    assert(cpu.getCarry() == 0x1);
    assert(cpu._status.z == 0x0 && cpu._status.i == 0x0 && cpu._status.d == 0x0 && 
           cpu._status.b == 0x0 && cpu._status.v == 0x0 && cpu._status.s == 0x0 );
    cpu.clearCarry();
    assert(cpu._status.c == 0x0);
    assert(cpu.getCarry() == 0x0);
    assert(cpu._status.z == 0x0 && cpu._status.i == 0x0 && cpu._status.d == 0x0 && 
           cpu._status.b == 0x0 && cpu._status.v == 0x0 && cpu._status.s == 0x0 );
}


// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
