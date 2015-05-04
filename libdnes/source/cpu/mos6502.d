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
    //Read 1 byte opcode, increment program counter by 1
    ubyte fetch() 
    {
        return Console.memory.read(this.pc++);
    }
    unittest
    {
        Console.initialize();
        auto instruction = Console.processor.fetch();
        assert(Console.processor.pc == 0x01);
        Console.memory.write(Console.processor.pc, 0xFF);
        instruction = Console.processor.fetch();
        assert(Console.processor.pc == 0x02);
        assert(instruction == 0xFF);
        
    }

	void reset()
	{
		this.a = 0x00;
		this.x = 0x00;
		this.y = 0x00;
		this.pc = 0x00;
		this.sp = 0x00; //FIXME
        this.status.reset();
	}
    unittest
    {
        auto cpu = new MOS6502;
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
