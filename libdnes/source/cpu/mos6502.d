// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
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
        import std.file;

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
    ubyte immediateAddressMode()
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
    // and return it
    ubyte zeroPageAddressMode()
    {
        ubyte address = Console.ram.read(this.pc++);
        return address;
    }
    // @region unittest zeroPageAddressMode()
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        // write address 0x7D to PC
        Console.ram.write(cpu.pc, 0x7D);
        // zero page addressing mode will read address stored at cpu.pc which is
        // 0x7D, then return the value stored in ram at 0x007D which should be 
        // 0x55
        assert(cpu.zeroPageAddressMode() == 0x7D);
        assert(cpu.pc == 0xC001);
    }
    // @endregion
    
    // zero page index address indicates that byte following the operand is an address
    // from 0x0000 to 0x00FF (256 bytes). in this case we read in the address 
    // then offset it by the value in a specified register (X, Y, etc)
    // when calling this function you must provide the value to be indexed by
    // for example an instruction that is 
    // STY Operand, Y
    // Means we will take operand, offset it by the value in Y register
    // and correctly round it and return it as a zero page memory address
    ubyte zeroPageIndexedAddressMode(ubyte indexValue)
    {
        ubyte address = Console.ram.read(this.pc++);
        address += indexValue;
        return address;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        //pc is 0xC000 after powerOn()
        // set ram at PC to a zero page indexed address, indexing y register
        Console.ram.write(cpu.pc, 0xFF);
        //set Y register to 5
        cpu.y = 5;
        // example STY will add operand to y register, and return that
        // FF + 5 = overflow to 0x04
        assert(cpu.zeroPageIndexedAddressMode(cpu.y) == 0x04);
        assert(cpu.pc == 0xC001);
    }

    // for relative address mode we will calculate an adress that is
    // between -128 to +127 from the PC + 1
    // used only for branch instructions
    // first byte after the opcode is the relative offset as a 
    // signed byte. the offset is calculated from the position after the 
    // operand so it is in actuality -126 to +129 from where the opcode 
    // resides
    ushort relativeAddressMode()
    {
	    byte offset = cast(byte)(Console.ram.read(this.pc++));
	    int finalAddress = (cast(int)this.pc + offset);
	    return cast(ushort)(finalAddress);
    }
    // @region unittest relativeAddressMode()
    unittest
    {
        auto cpu = new MOS6502;
        ushort result = 0;
        cpu.powerOn();
        // Case 1 & 2 : Relative Addess forward
        // relative offset will be +1
        Console.ram.write(cpu.pc, 0x01);
        result = cpu.relativeAddressMode();
        assert(cpu.pc == 0xC001); 
        assert(result == 0xC002);
        //relative offset will be +3
        Console.ram.write(cpu.pc, 0x03);
        result = cpu.relativeAddressMode();
        assert(cpu.pc == 0xC002);
        assert(result == 0xC005);
        // Case 3: Relative Addess backwards
        // relative offset will be -6 from 0xC003
        // offset is from 0xC003 because the address mode
        // decode function increments PC by 1 before calculating
        // the final position
        ubyte off = cast(ubyte)-6;
        Console.ram.write(cpu.pc, off ); 
        result = cpu.relativeAddressMode();
        assert(cpu.pc == 0xC003);
        assert(result == 0xBFFD);
        // Case 4: Relative address backwards underflow when PC = 0
        // Result will underflow as 0 - 6 = -6 = 
        cpu.pc = 0x0;
        Console.ram.write(cpu.pc, off);
        result = cpu.relativeAddressMode();
        assert(result == 0xFFFB);
        // Case 5: Relative address forwards oferflow when PC = 0xFFFE
        // and address is + 2
        cpu.pc = 0xFFFE;
        Console.ram.write(cpu.pc, 0x02);
        result = cpu.relativeAddressMode();
        assert(result == 0x01);
    }
    // @endregion

    //absolute address mode reads 16 bytes so increment pc by 2
    ushort absoluteAddressMode()
    {
        ushort data = Console.ram.read16(this.pc);
        this.pc += 0x2;
        return data;
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
        assert(cpu.pc == 0xC002);
    }
    // @endregion
    //absolute indexed address mode reads 16 bytes so increment pc by 2
    ushort absoluteIndexedAddressMode(ubyte indexValue)
    {
        ushort data = Console.ram.read16(this.pc);
        this.pc += 0x2;
        data += indexValue;
        return data;
    }
    // @region unittest absoluteIndexedAddressMode();
    unittest 
    {
        auto cpu = new MOS6502;
        ushort result = 0;
        cpu.powerOn();

        // Case 1: Absolute indexed addressing is dead-simple. The argument of the 
        // in this case is the address stored in the next two bytes, which is added
        // to third argument which in the index, which is usually X or Y register
        // write address 0x7D00 to PC
        Console.ram.write16(cpu.pc, 0x7D00);
        cpu.y = 5;
        result = cpu.absoluteIndexedAddressMode(cpu.y);
        assert(result == 0x7D05);
        assert(cpu.pc == 0xC002);
    }
    // @endregion

    //remember to increment pc by 2 bytes when reading 2 bytes
    ushort  indirectAddressMode()
    {
        ushort effectiveAddress = Console.ram.read16(this.pc); 
        this.pc += 0x2;
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
        assert(cpu.pc == 0xC002);

        // Case 2:
        // 6502 has a bug with the JMP instruction in indirect mode. If
        // the lower byte of the argument is $10FF, it will read the lower byte
        // of the real address from $10FF, and the high byte from $1000 instead
        // of $1100 like it should.

        // Place the high and low bytes of the operand in the proper places;
        Console.ram.write(0x10FF, 0x55); // low byte
        Console.ram.write(0x1000, 0x7D); // misplaced high byte
        
        // Set up the program counter to read from $10FF and trigger the "bug"
        Console.ram.write16(cpu.pc, 0x10FF);

        assert(cpu.indirectAddressMode() == 0x7D55);
        assert(cpu.pc == 0xC004);
    }

    // indexed indirect mode is a mode where the byte following the opcode is a zero page address
    // which is then added to the X register (passed in). This memory address will then be read
    // to get the final memory address and returned
    // This mode does zero page wrapping 
    // Additionally it will read the target address as 16 bytes
    ushort indexedIndirectAddressMode(ubyte indexValue)
    {
        ubyte zeroPageAddress = Console.ram.read(this.pc++);
        ubyte targetAddress = cast(ubyte)(zeroPageAddress + indexValue);
        return Console.ram.read16(cast(ushort)targetAddress);
    }
    unittest 
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        // Case 1 : no zero page wrapping
        //write zero page addres 0x0F to PC
        Console.ram.write(cpu.pc, 0x0F);
        //write address 0xCDAB to zero page addres 0x0F+7 (bytes 0x16 and 0x17)
        Console.ram.write(0x16, 0xAB);
        Console.ram.write(0x17, 0xCD);
        //indexed indirect with an idex of 7
        ushort address = cpu.indexedIndirectAddressMode(0x7);
        assert(address == 0xCDAB);

        // Case 1 : zero page wrapping
        //write zero page addres 0xFF to PC
        Console.ram.write(cpu.pc, 0xFF);
        //write address 0xCDAB to zero page addres 0xFF+7 (bytes 0x06 and 0x07)
        Console.ram.write(0x06, 0xAB);
        Console.ram.write(0x07, 0xCD);
        //indexed indirect with an idex of 7
        address = cpu.indexedIndirectAddressMode(0x7);
        assert(address == 0xCDAB);
    }
    // @endregion

    // indirect indexed is similar to indexed indirect, except the index offset
    // is added to the final memory value instead of to the zero page address
    // so this mode will read a zero page address as the next byte after the operand,
    // look up a 16 bit value in the zero page, add the index to that and return it
    // as the final address. note that there is no zero page address wrapping
    ushort indirectIndexedAddressMode(ubyte indexValue)
    {
        ubyte zeroPageAddress = Console.ram.read(this.pc++);
        ushort targetAddress = Console.ram.read16(cast(ushort) zeroPageAddress);
        return cast(ushort) (targetAddress + indexValue);
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        // Case 1 : no wrapping around address space
        //write zero page addres 0x0F to PC
        Console.ram.write(cpu.pc, 0x0F);
        //write address 0xCDAB to zero page addres 0x0F and 0x10
        Console.ram.write(0x0F, 0xAB);
        Console.ram.write(0x10, 0xCD);
        //indirect indexed with an idex of 7
        ushort address = cpu.indirectIndexedAddressMode(0x7);
        assert(address == 0xCDAB + 0x7);
        // Case 2 : wrapping around the 16 bit address space
        //write zero page addres 0x0F to PC
        Console.ram.write(cpu.pc, 0x0F);
        //write address 0xFFFE to zero page addres 0x0F and 0x10
        Console.ram.write(0x0F, 0xFE);
        Console.ram.write(0x10, 0xFF);
        //indirect indexed with an idex of 7
        address = cpu.indirectIndexedAddressMode(0x7);
        assert(address == cast(ushort)(0xFFFE + 7));
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


