/* cpu.d
 * Emulation code for the MOS5602 CPU.
 * Copyright (c) 2015 dNES Team.
 * License: GPL 3.0
 */

module cpu.mos6502;
import cpu.statusregister;
import cpu.exceptions;
import console;
import memory;

class MOS6502
{
    this(Console console)
    {
        this.status      = new StatusRegister; 
        this.consoleref  = console;
    }

    void powercycle()
    {
        this.status.value = 0x34;
        this.a = this.x = this.y = 0;
        this.sp = 0xFD;

        if (consoleref.memory is null) {
            consoleref.memory = new RAM;
        }
        this.pc = 0xC000;
    }

    ushort fetch() 
    {
        return this.consoleref.memory.read16(pc);
    }

    void function(ubyte) decode(ushort opCodeWithArg)
    {
        auto opcode  = cast(ubyte)(opCodeWithArg >> 8);

        switch (opcode)
        {
            // TODO: detect each opcode and return one of 128,043,00 functions :S
            default:
                throw new InvalidOpcodeException(opcode);
        }
    }
    void reset()
    {
	a = 0x00;
	x = 0x00;
	y = 0x00;
	pc = 0x00;
	sp = 0x00; //FIXME
    }

    private 
    {
        Console consoleref;

        ushort pc; // program counter
        ubyte a;   // accumulator
        ubyte x;   // x index
        ubyte y;   // y index
        ubyte sp;  // stack pointer
        StatusRegister status;


    }
}



// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
