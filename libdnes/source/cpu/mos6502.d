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

    // From http://wiki.nesdev.com/w/index.php/CPU_power_up_state
    void powerOn()
    {
        this.status.value = 0x34;
        this.a = this.x = this.y = 0;
        this.sp = 0xFD;

        if (Console.ram is null)
        {
            // Ram will only be null if a prior emulation has ended or if we are
            // unit-testing. Normally, console will allocate this on program 
            // start.
            Console.ram = new RAM; 
        }
        this.pc = 0xC000;
    }
    // @region unittest powerOn()
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        assert(cpu.status.value == 0x34);
        assert(cpu.a == 0);
        assert(cpu.x == 0);
        assert(cpu.y == 0);
        assert(cpu.pc == 0xC000);

        // Do not test the Console.ram constructor here, it should be tested
        // in ram.d
    }
    // @endregion

    // From http://wiki.nesdev.com/w/index.php/CPU_power_up_state
    // After reset
    //    A, X, Y were not affected
    //    S was decremented by 3 (but nothing was written to the stack)
    //    The I (IRQ disable) flag was set to true (status ORed with $04)
    //    The internal memory was unchanged
    //    APU mode in $4017 was unchanged
    //    APU was silenced ($4015 = 0)
	void reset()
	{
		this.sp -= 0x03;
        this.status.value = this.status.value | 0x04;
        // TODO: Console.MemoryMapper.Write(0x4015, 0);
	}
    // @region unittest reset()
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        
        cpu.status.value = 0x01;
        cpu.a = cpu.x = cpu.y = 55;
        cpu.sp = 0xF4;
        cpu.pc= 0xF000;
        cpu.reset();

        assert(cpu.sp == (0xF4 - 0x03));
        assert(cpu.status.value == (0x21 | 0x04)); // bit 6 (0x20) is always on
    }
    //@endregion

    ubyte fetch() 
    {
        return Console.ram.read(this.pc++);
    }
    // @region unittest fetch() 
    unittest 
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        // Case 1: pc register properly incremented
        auto instruction = cpu.fetch();
        assert(cpu.pc == 0xC001);

        // Case 2: Instruction is properly read
        Console.ram.write(cpu.pc, 0xFF);
        instruction = cpu.fetch();
        assert(cpu.pc == 0xC002);
        assert(instruction == 0xFF);
    } 
    // @endregion

    void function(ubyte) decode(ubyte opcode)
    {
        switch (opcode)
        {
            // TODO: detect each opcode and return one of 128,043,00 functions :S
            default:
                throw new InvalidOpcodeException(opcode);
        }
    }
    // TODO: Write unit test before writing implementation (TDD)



    // @region Instruction impl functions

    // @endregion

    // @region AddressingMode Functions
    //immediate address mode is the operand is a 1 byte constant following the opcode
    //so read the constant, increment pc by 1 and return it
    ubyte addressImmediate()
    {
        return Console.ram.read(this.pc++);
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        Console.ram.write(cpu.pc, 0x7D);
        assert(cpu.addressImmediate() == 0x7D);
        assert(cpu.pc == 0xC001);
    }

    //zero page address indicates that byte following the operand is an address from
    //0x0000 to 0x00FF (256 bytes). in this case we read in the address then use it
    //to read the ram and return the value
    ubyte addressZeroPage()
    {
        ubyte address = Console.ram.read(this.pc++);
        return Console.ram.read(address);
    }
    unittest
    {
        Console.initialize();
        //set ram 0x007D to arbitrary value
        Console.ram.write(0x007D, 0x55);
        //set PC to 0xC0
        Console.processor.pc = 0xC0;
        //write address 0x7D to PC
        Console.ram.write(0xC0, 0x7D);
        //zero page addressing mode will read address stored at 0xC0 which is
        //0x7D, then read the value stored in ram at 0x007D which should be 0x55
        assert(Console.processor.addressZeroPage() == 0x55);
        assert(Console.processor.pc == 0xC1);
    }
    // @endregion

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


// ex :set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
