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
        Console.ram.write(cpu.pc, 0xFF);  // TODO: Find a way to replace with a MockRam class
        instruction = cpu.fetch();
        assert(cpu.pc == 0xC002);
        assert(instruction == 0xFF);
    } 
    // @endregion

   
    void delegate(ubyte) decode(ubyte opcode)
    {
        switch (opcode)
        {
            case 0x4C:
            case 0x6C:
                return (&JMP);
            // TODO: detect each opcode and return one of 128,043,00 functions :S
            default:
                throw new InvalidOpcodeException(opcode);
        }
    }
    // TODO: Write unit test before writing implementation (TDD)
    // @region unittest decode(ubyte) 
    unittest 
    {
        import std.file, std.stdio;

        // Load a test ROM
        auto ROMBytes = cast(ubyte[])read("libdnes/nestest.nes");
        auto cpu     = new MOS6502;
        cpu.powerOn();

        {
            ushort address = 0xC000;
            for (uint i = 0x10; i < ROMBytes.length; ++i) {
                Console.ram.write(address, ROMBytes[i]);
                ++address;
            }
        }
        
        auto resultFunc = cpu.decode(cpu.fetch());
        void delegate(ubyte) expectedFunc = &(cpu.JMP);
        assert(resultFunc == expectedFunc);
    }
    // @endregion
    

    ushort delegate() decodeAddressMode(string instruction, ubyte opcode)
    {
        switch (opcode)
        {
            case 0x4C:
                return &(absoluteAddressMode);
            case 0x6C:
                return &(indirectAddressMode);
            default:
                throw new InvalidAddressingModeException(instruction, opcode);
        }
    }

    // @region Instruction impl functions
    // TODO: Add tracing so we can compare against nestest.log
    private void JMP(ubyte opcode)
    {
        auto addressModeFunction = decodeAddressMode("JMP", opcode);
        ushort finalAddress = addressModeFunction();

        this.pc = finalAddress;
    }

    unittest //@region unittest JMP(ubyte)
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;

        ram.write(0xC000, 0x4C);     // JMP, absolute addressmode
        ram.write16(0xC001, 0xC005); // argument

        ram.write(0xC005, 0x6C);     // JMP, indirect address
        ram.write16(0xC006, 0xC00D); // address of address
        ram.write16(0xC00D, 0xC00F); // final address

        cpu.JMP(ram.read(cpu.pc++));
        assert(cpu.pc == 0xC005);
        cpu.JMP(ram.read(cpu.pc++));
        assert(cpu.pc == 0xC00F);
    }
    // @endregion
    // @endregion

    // @region AddressingMode Functions
    // immediate address mode is the operand is a 1 byte constant following the
    // opcode so read the constant, increment pc by 1 and return it
    ushort immediateAddressMode()
    {
        return Console.ram.read(this.pc++);
    }
    // @region unittest immediateAddressMode
    unittest
    {
        ubyte result = 0;
        auto cpu = new MOS6502;
        cpu.powerOn();

        Console.ram.write(cpu.pc+0, 0x7D);
        result = cast(ubyte)(cpu.immediateAddressMode());
        assert(result == 0x7D);
        assert(cpu.pc == 0xC001);
    }
    // @endregion

    // zero page address indicates that byte following the operand is an address
    // from 0x0000 to 0x00FF (256 bytes). in this case we read in the address 
    // then use it to read the ram and return the value
    ushort zeroPageAddressMode()
    {
        ubyte address = Console.ram.read(this.pc++);
        return Console.ram.read(address);
    }
    // @region unittest zeroPageAddressMode()
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        // set ram 0x007D to arbitrary value
        Console.ram.write(0x007D, 0x55);
        // write address 0x7D to PC
        Console.ram.write(cpu.pc, 0x7D);
        // zero page addressing mode will read address stored at cpu.pc which is
        // 0x7D, then return the value stored in ram at 0x007D which should be 
        // 0x55
        assert(cpu.zeroPageAddressMode() == 0x55);
        assert(cpu.pc == 0xC001);
    }
    // @endregion

    ushort absoluteAddressMode()
    {
        return Console.ram.read16(this.pc++);
    }
    // @region unittest absoluteAddressMode();
    unittest 
    {
        auto cpu = new MOS6502;
        ushort result = 0;
        cpu.powerOn();

        // Case 1: Absolute addressing is dead-simple. The argument of the 
        // in this case is the address stored in the next two byts. 

        // write address 0x7D00 to PC
        Console.ram.write16(cpu.pc, 0x7D00);

        result = cpu.absoluteAddressMode();
        assert(result == 0x7D00);
        assert(cpu.pc == 0xC001);
    }
    // @endregion

    ushort  indirectAddressMode()
    {
        ushort effectiveAddress = Console.ram.read16(this.pc++); 
        ushort returnAddress = 0;

        if ( (effectiveAddress & 0x00FF) == 0x00FF ) 
        {
            ubyte low = Console.ram.read(effectiveAddress);
            ubyte high = Console.ram.read(effectiveAddress & 0xFF00);
            returnAddress = (high << 8) | low;
        }
        else
        {
            returnAddress = Console.ram.read16(effectiveAddress);
        }

        return returnAddress;
    }
    // @region unittest indirectAddressMode()
    unittest 
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        // Case1: Straightforward indirection.
        // Argument is an address contianing an address.
        Console.ram.write16(cpu.pc, 0x0D10);
        Console.ram.write16(0xD10, 0x1FFF);
        assert(cpu.indirectAddressMode() == 0x1FFF);
        assert(cpu.pc == 0xC001);

        // Case 2:
        // 6502 has a bug with the JMP instruction in indirect mode. If
        // the argument is $10FF, it will read the lower byte as $FF, and 
        // then fail to increment the higher byte from $10 to $11, 
        // resulting in a read from $1000 rather than $1100 when loading the
        // second byte

        // Place the high and low bytes of the operand in the proper places;
        Console.ram.write(0x10FF, 0x55); // low byte
        Console.ram.write(0x1000, 0x7D); // misplaced high byte
        
        // Set up the program counter to read from $10FF and trigger the "bug"
        Console.ram.write16(cpu.pc, 0x10FF);

        assert(cpu.indirectAddressMode() == 0x7D55);
        assert(cpu.pc == 0xC002);
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
