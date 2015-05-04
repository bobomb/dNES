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
    this()
    {
        this.status      = new StatusRegister; 
    }

    void powercycle()
    {
        this.status.value = 0x34;
        this.a = this.x = this.y = 0;
        this.sp = 0xFD;

        if (Console.memory is null) {
            Console.initialize();
        }
        this.pc = 0xC000;
    }

    ushort fetch() 
    {
        return Console.memory.read16(pc);
    }

	void reset()
	{
		a = 0x00;
		x = 0x00;
		y = 0x00;
		pc = 0x00;
		sp = 0x00; //FIXME
        this.status.reset();
	}
    unittest
    {
        MOS6502 cpu;
        cpu.reset();
        assert(cpu.a == 0x00);
        assert(cpu.x == 0x00);
        assert(cpu.y == 0x00);
        assert(cpu.pc == 0x00);
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

    private 
    {
        ushort pc; // program counter
        ubyte a;   // accumulator
        ubyte x;   // x index
        ubyte y;   // y index
        ubyte sp;  // stack pointer
        StatusRegister status;
    }
}



// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
