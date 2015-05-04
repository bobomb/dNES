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
        this.status = new StatusRegister; 
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

    //immediate address mode is the operand is a 1 byte constant following the opcode
    //so read the constant, increment pc by 1 and return it
    ubyte addressImmediate()
    {
        return Console.memory.read(this.pc++);
    }
    unittest
    {
        Console.initialize();
        Console.processor.pc = 0xC0;
        Console.memory.write(0xC0, 0x7D);
        assert(Console.processor.addressImmediate() == 0x7D);
        assert(Console.processor.pc == 0xC1);
    }

    //zero page address indicates that byte following the operand is an address from
    //0x0000 to 0x00FF (256 bytes). in this case we read in the address then use it
    //to read the memory and return the value
    ubyte addressZeroPage()
    {
        ubyte address = Console.memory.read(this.pc++);
        return Console.memory.read(address);
    }
    unittest
    {
        Console.initialize();
        //set memory 0x007D to arbitrary value
        Console.memory.write(0x007D, 0x55);
        //set PC to 0xC0
        Console.processor.pc = 0xC0;
        //write address 0x7D to PC
        Console.memory.write(0xC0, 0x7D);
        //zero page addressing mode will read address stored at 0xC0 which is
        //0x7D, then read the value stored in memory at 0x007D which should be 0x55
        assert(Console.processor.addressZeroPage() == 0x55);
        assert(Console.processor.pc == 0xC1);
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
