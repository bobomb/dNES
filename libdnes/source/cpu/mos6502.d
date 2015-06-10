// ex: set foldmethod=syntax foldlevel=1 foldlevel=1 expandtab ts=4 sts=4  sw=4 filetype=d : 
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
    enum AddressingModeType
    {
        UNKNOWN     = 0x00,
        IMPLIED     = 0x01,
        IMMEDIATE   = 0x10,
        ACCUMULATOR = 0xA0,
        ZEROPAGE    = 0xB0,
        ZEROPAGE_X  = 0xB1,
        ZEROPAGE_Y  = 0xB2,
        RELATIVE    = 0xC0,
        ABSOLUTE    = 0xD0,
        ABSOLUTE_X  = 0xD1,
        ABSOLUTE_Y  = 0xD2,
        INDIRECT    = 0xF0,
        INDEXED_INDIRECT = 0xF1, // INDIRECT_X
        INDIRECT_INDEXED = 0xF2  // INDIRECT_Y
    }


    this()
    {
        status = new StatusRegister; 
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

    ubyte fetch() 
    {
        return Console.ram.read(this.pc++); 
    }
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

    public @property ulong cycleCount() { return this.cycles; }
    unittest
    {
        auto cpu = new MOS6502;
        
        assert(cpu.cycleCount() == 0);

        cpu.cycles = 6543;
        assert(cpu.cycleCount == 6543);
    }
   
    void delegate(ushort) decode(ubyte opcode)
    {
        switch (opcode)
        {
            // JMP
            case 0x4C:
            case 0x6C:
                return cast(void delegate(ushort))(&JMP);
            // ADC
            case 0x69:
            case 0x65:
            case 0x75:
            case 0x6D:
            case 0x7D:
            case 0x79:
            case 0x61:
            case 0x71:
                return cast(void delegate(ushort))(&ADC);
            default:
                throw new InvalidOpcodeException(opcode);
        }
    }
    // TODO: Write unit test before writing implementation (TDD)
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
        void delegate(ushort) expectedFunc = cast(void delegate(ushort))&(cpu.JMP);
        assert(resultFunc == expectedFunc);
    }

    //perform another cpu cycle of emulation
    void cycle()
    {
        //Priority: Reset > NMI > IRQ
        if (this.rst)
        {
            handleReset();
        }
        if (this.nmi)
        {
            handleNmi();
        }
        if (this.irq)
        {
            handleIrq();
        }
        //Fetch
        ubyte opcode = fetch();
        //Decode
        auto instructionFunction = decode(opcode);
        //Execute
        instructionFunction(opcode);
    }
    unittest
    {
        //TODO
    }
    
    void handleReset()
    {
		auto resetVectorAddress = Console.ram.read16(this.resetAddress);
		this.pc = resetVectorAddress;
		this.rst = false;
		this.cycles += 7;
    }
    unittest
    {
		auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
		auto savedCycles = cpu.cycles;
		ram.write16(cpu.resetAddress, 0xFC10); //write interrupt handler address
		cpu.rst = true;
		cpu.handleReset();
		assert(cpu.cycles == savedCycles + 7);
		assert(cpu.pc == 0xFC10);
		assert(cpu.rst == false);
    }

    void handleNmi()
    {
		pushStack(cast(ubyte)(this.pc >> 8)); //write PC high byte to stack
		pushStack(cast(ubyte)(this.pc));
		pushStack(this.status.value);
		auto nmiVectorAddress = Console.ram.read16(this.nmiAddress);
		this.pc = nmiVectorAddress;
		this.nmi = false;
		this.cycles += 7;
    }
    unittest
    {
		auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
		auto savedCycles = cpu.cycles;
		auto savedPC = cpu.pc;
		auto savedStatus = cpu.status.value;
		ram.write16(cpu.nmiAddress, 0x1D42); //write interrupt handler address
		cpu.handleNmi();
		assert(cpu.popStack() == savedStatus); //check status registers
		ushort previousPC = cpu.popStack() | (cpu.popStack() << 8); //verify pc write
		assert(cpu.cycles == savedCycles + 7);
		assert(cpu.pc == 0x1D42);
        assert(previousPC == savedPC);
        
    }

    void handleIrq()
    {
		if(this.status.i)
			return; //don't do anything if interrupt disable is set

		pushStack(cast(ubyte)(this.pc >> 8)); //write PC high byte to stack
		pushStack(cast(ubyte)(this.pc));
		pushStack(this.status.value);
		auto irqVectorAddress = Console.ram.read16(this.irqAddress);
		this.pc = irqVectorAddress;
		this.cycles +=7;
    }
    unittest
    {
        //case 1 : interrupt disable bit is not set
        auto cpu = new MOS6502;
        cpu.powerOn();
        cpu.status.i = false;
        auto ram = Console.ram;
		auto savedCycles = cpu.cycles;
		auto savedPC = cpu.pc;
		auto savedStatus = cpu.status.value;
		ram.write16(cpu.irqAddress, 0xC296); //write interrupt handler address
		cpu.handleIrq();
		assert(cpu.popStack() == savedStatus); //check status registers
		ushort previousPC = cpu.popStack() | (cpu.popStack() << 8); //verify pc write
		assert(cpu.cycles == savedCycles + 7);
		assert(cpu.pc == 0xC296);
        assert(previousPC == savedPC);
        //case 2 : interrupt disable bit is set
        cpu.status.i = true;
        savedCycles = cpu.cycles;
		ram.write16(cpu.irqAddress, 0x1111); //write interrupt handler address
		cpu.handleIrq();
		assert(cpu.cycles == savedCycles + 0);
		assert(cpu.pc == 0xC296);
    }

    ushort delegate() decodeAddressMode(string instruction, ubyte opcode)
    {
        switch (opcode)
        {
            case 0x69:
                return &(immediateAddressMode);
            // *** ABSOLUTE ***//
            case 0x4C: // JMP
            case 0x6D: // ADC
                return &(absoluteAddressMode);
            // *** INDIRECT **//
            case 0x6C: // JMP
                return &(indirectAddressMode);
            default:
                throw new InvalidAddressingModeException(instruction, opcode);
        }
    }

    //***** Instruction Implementation *****//
    // TODO: Add tracing so we can compare against nestest.log
    private void JMP(ubyte opcode)
    {
        auto addressModeFunction = decodeAddressMode("JMP", opcode);
        ushort finalAddress = 0;

        if (addressModeFunction == &absoluteAddressMode)
        {
            this.cycles += 3;
        }
        else if (addressModeFunction == &indirectAddressMode)
        {
            this.cycles += 5;
        }
        finalAddress = addressModeFunction();

        this.pc = finalAddress;
    }
    unittest
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

    private void ADC(ubyte opcode)
    {
        auto addressModeFunction = decodeAddressMode("ADC", opcode);
        bool bPageBoundaryCrossed = false;
        auto ram = Console.ram;

        ushort a; // a = accumulator value
        ushort m; // m = operand
        ushort c; // c = carry value

        a = this.a;
        c = this.status.c;

        if (addressModeFunction == &(immediateAddressMode)) 
        {
            m = addressModeFunction();
        }
        else
        {
            ushort resolvedAddress = addressModeFunction();
            if ((resolvedAddress & 0x00FF)  == 0x00FF) 
            {
                bPageBoundaryCrossed = true;
            }
            m = ram.read(resolvedAddress);
        }

        auto result = cast(ushort)(a+m+c);
        // Check for overflow
        if (result > 255) 
        {
            this.a = cast(ubyte)(result - 255); 
            this.status.c = 1;
        }
        else
        {
            this.a = cast(ubyte)(result);
            this.status.c = 0;
        }

        if (this.a == 0)
            this.status.z = 1;
        else
            this.status.z = 0;

        if ((this.a & 0b1000_0000) == 0b1000_0000) 
            this.status.n = 1; 
        else
            this.status.n = 0;

        if (((this.a^m) & 0x80) == 0 && ((a^this.a) & 0x80) != 0)
        {
            this.status.v = 1;
        }
        else 
        {
            this.status.v = 0;
        }

        this.cycles += cycleCountTable[opcode];
        switch (opcode)
        {
            case 0x71:
            case 0x7D: // Absolute,X
            case 0x79: // Absolute,Y
                if (bPageBoundaryCrossed) 
                    this.cycles++;
                break;
            default:
                { } // do nothing
                break;
        } 
    }
    unittest
    {
        import std.stdio;

        auto cpu = new MOS6502;
        cpu.powerOn();
        assert(cpu.a == 0);
        auto ram = Console.ram;
        auto cycles_start = cpu.cycles;
        auto cycles_end = cpu.cycles;

        // Case 1: Immediate 
        cycles_start = cpu.cycles;
        cpu.pc = 0x0101;          // move to new page
        cpu.a = 0x20;             // give an initial value other than 0
        cpu.status.c = 0;         // reset to 0
        ram.write(cpu.pc, 0x40);  // write operand to memory

        cpu.ADC(0x69);            // execute ADC immediate
        cycles_end  = cpu.cycles; // get cycle count
        assert(cpu.a == 0x60);    // 0x20 + 0x40 = 0x60
        assert((cycles_end - cycles_start) == 2); // verify cycles taken 
       
        // Trigger overflow
        ram.write(cpu.pc, 0xA0);
        cpu.ADC(0x69);
        assert(cpu.a == 0x01);
        assert(cpu.status.c == 1);
        ram.write(cpu.pc, 0x02);
        cpu.ADC(0x69);
        assert(cpu.status.c == 0);

        // @TODO continue testing each addressing mode

        // Case 4: Absolute
        cycles_start = cpu.cycles;
        cpu.a = 0;
        cpu.pc = 0x0400;
        ram.write16(cpu.pc, 0xB00B);
        ram.write(0xB00B, 0x7D);
        cpu.ADC(0x6D);
        cycles_end  = cpu.cycles;
        assert(cpu.a == 0x7D);
        assert((cycles_end - cycles_start) == 4);
    }

    private void BMI()
    {
        this.cycles += 2;
        //Relative only
        ushort finalAddress = relativeAddressMode();
        if(status.n)
        {
            if((this.pc / 0xFF) == (finalAddress / 0xFF))
            {
                this.pc = finalAddress;
                this.cycles++;
            }
            else
            {
                this.pc = finalAddress;
                //goes to a new page
                this.cycles +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        //case 1 forward offset, n flag set, jumps page boundary (4 cycles)
        cpu.status.n = 1;
        ram.write(cpu.pc, 0x4C); // argument
        auto savedPC = cpu.pc;
        auto savedCycles = cpu.cycles;
        cpu.BMI();
        assert(cpu.pc == savedPC + 0x1 + 0x4C);
        assert(cpu.cycles == savedCycles + 0x4); 
        //case 2 forward offset, n flag is clear, (2 cycles)
        cpu.status.n = 0;
        ram.write(cpu.pc, 0x4C); // argument
        savedPC = cpu.pc;
        savedCycles = cpu.cycles;
        cpu.BMI();
        assert(cpu.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu.cycles == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, n flag is set, (3 cycles)
        cpu.status.n = 1;
        ram.write(cpu.pc, 0xF1); // (-15)
        savedPC = cpu.pc;
        savedCycles = cpu.cycles;
        cpu.BMI();
        assert(cpu.pc == savedPC + 1 - 0xF);
        assert(cpu.cycles == savedCycles + 0x3);
        //case 4 negative offset, n flag is clear (1 cycle)
        cpu.status.n = 0;
        ram.write(cpu.pc, 0xF1); // argument
        savedPC = cpu.pc;
        cpu.BMI();
        assert(cpu.pc == savedPC + 0x1); //for this case it should not branch
    }

    //If the zero flag is clear then add the relative displacement to the program counter to cause a branch to a new location.
    private void BNE()
    {
        this.cycles += 2;
        //Relative only
        ushort finalAddress = relativeAddressMode();
        if(!status.z)
        {
            if((this.pc / 0xFF) == (finalAddress / 0xFF))
            {
                this.pc = finalAddress;
                this.cycles++;
            }
            else
            {
                this.pc = finalAddress;
                //goes to a new page
                this.cycles +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        //case 1 forward offset, z flag clear, jumps page boundary (4 cycles)
        cpu.status.z = 0;
        ram.write(cpu.pc, 0x4D); // argument
        auto savedPC = cpu.pc;
        auto savedCycles = cpu.cycles;
        cpu.BNE();
        assert(cpu.pc == savedPC + 0x1 + 0x4D);
        assert(cpu.cycles == savedCycles + 0x4); //branch will cross a page boundary
        //case 2 forward offset, z flag is set, (2 cycles)
        cpu.status.z = 1;
        ram.write(cpu.pc, 0x4D); // argument
        savedPC = cpu.pc;
        savedCycles = cpu.cycles;
        cpu.BNE();
        assert(cpu.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu.cycles == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, z flag is clear (3 cycles)
        cpu.status.z = 0;
        ram.write(cpu.pc, 0xF1); // (-15)
        savedPC = cpu.pc;
        savedCycles = cpu.cycles;
        cpu.BNE();
        assert(cpu.pc == savedPC + 1 - 0xF);
        assert(cpu.cycles == savedCycles + 0x3); //branch doesn't cross page boundary
        //case 4 negative offset, z flag is set (1 cycle)
        cpu.status.z = 1;
        ram.write(cpu.pc, 0xF1); // argument
        savedPC = cpu.pc;
        cpu.BNE();
        assert(cpu.pc == savedPC + 0x1); //for this case it should not branch
    }

    //If the negative flag is clear then add the relative displacement to the program counter to cause a branch to a new location.
    private void BPL()
    {
        this.cycles += 2;
        //Relative only
        ushort finalAddress = relativeAddressMode();
        if(!status.n)
        {
            if((this.pc / 0xFF) == (finalAddress / 0xFF))
            {
                this.pc = finalAddress;
                this.cycles++;
            }
            else
            {
                this.pc = finalAddress;
                //goes to a new page
                this.cycles +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        //case 1 forward offset, n flag clear, jumps page boundary (4 cycles)
        cpu.status.n = 0;
        ram.write(cpu.pc, 0x4D); // argument
        auto savedPC = cpu.pc;
        auto savedCycles = cpu.cycles;
        cpu.BPL();
        assert(cpu.pc == savedPC + 0x1 + 0x4D);
        assert(cpu.cycles == savedCycles + 0x4); //branch will cross a page boundary
        //case 2 forward offset, n flag is set, (2 cycles)
        cpu.status.n = 1;
        ram.write(cpu.pc, 0x4D); // argument
        savedPC = cpu.pc;
        savedCycles = cpu.cycles;
        cpu.BPL();
        assert(cpu.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu.cycles == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, n flag is clear (3 cycles)
        cpu.status.n = 0;
        ram.write(cpu.pc, 0xF1); // (-15)
        savedPC = cpu.pc;
        savedCycles = cpu.cycles;
        cpu.BPL();
        assert(cpu.pc == savedPC + 1 - 0xF);
        assert(cpu.cycles == savedCycles + 0x3); //branch doesn't cross page boundary
        //case 4 negative offset, n flag is set (2 cycles)
        cpu.status.n = 1;
        ram.write(cpu.pc, 0xF1); // argument
        savedPC = cpu.pc;
        savedCycles = cpu.cycles;
        cpu.BPL();
        assert(cpu.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu.cycles == savedCycles + 0x2);
    }

    //forces an interrupt to be fired. the status register is copied to stack and bit 5 of the stored pc on the stack is set to 1
    private void BRK()
    {
        //the BRK instruction saves the PC at BRK+2 to stack, so increment PC by 1 to skip next byte
        this.pc++;
        pushStack(cast(ubyte)(this.pc >> 8)); //write PC high byte to stack
		pushStack(cast(ubyte)(this.pc));
        StatusRegister brkStatus = this.status;
        //set b flag and write to stack
        brkStatus.b = 1;
		pushStack(brkStatus.value);
		auto irqVectorAddress = Console.ram.read16(this.irqAddress);
		this.pc = irqVectorAddress; //brk handled similarly to irq
		this.cycles += 7;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
		auto savedCycles = cpu.cycles;
		auto savedPC = cpu.pc;
		auto savedStatus = cpu.status.value;
		ram.write16(cpu.irqAddress, 0x1744); //write interrupt handler address
        //increment PC by 1 to simulate fetch
        cpu.pc++;
		cpu.BRK();
		assert(cpu.popStack() == (savedStatus | 0b10000)); //check status registers
		ushort previousPC = cpu.popStack() | (cpu.popStack() << 8); //verify pc write
		assert(cpu.cycles == savedCycles + 7);
		assert(cpu.pc == 0x1744);
        assert(previousPC == savedPC + 2);
    }

    //***** Addressing Modes *****//
    // Immediate address mode is the operand is a 1 byte constant following the
    // opcode so read the constant, increment pc by 1 and return it
    ushort immediateAddressMode()
    {
        return Console.ram.read(this.pc++);
    }
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

    // zero page address indicates that byte following the operand is an address
    // from 0x0000 to 0x00FF (256 bytes). in this case we read in the address 
    // and return it
    ubyte zeroPageAddressMode()
    {
        ubyte address = Console.ram.read(this.pc++);
        return address;
    }
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
    
    // zero page index address indicates that byte following the operand is an 
    // address from 0x0000 to 0x00FF (256 bytes). in this case we read in the 
    // address then offset it by the value in a specified register (X, Y, etc)
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

    //absolute address mode reads 16 bytes so increment pc by 2
    ushort absoluteAddressMode()
    {
        ushort data = Console.ram.read16(this.pc);
        this.pc += 0x2;
        return data;
    }
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

    //absolute indexed address mode reads 16 bytes so increment pc by 2
    ushort absoluteIndexedAddressMode(ubyte indexValue)
    {
        ushort data = Console.ram.read16(this.pc);
        this.pc += 0x2;
        data += indexValue;
        return data;
    }
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

    // indirect indexed is similar to indexed indirect, except the index offset
    // is added to the final memory value instead of to the zero page address
    // so this mode will read a zero page address as the next byte after the 
    // operand, look up a 16 bit value in the zero page, add the index to that 
    // and return it as the final address. note that there is no zero page 
    // address wrapping
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

    void setNmi()
    {
        nmi = true;
    }

    void setReset()
    {
        rst = true;
    }

    void setIrq()
    {
        irq = true;
    }

    //pushes a byte onto the stack, decrements stack pointer
    void pushStack(ubyte data)
    {
        ushort stackAddress = cast(ushort)(this.stackBaseAddress + this.sp);
        //add some logic here to possibly check for stack overflow conditions
        Console.ram.write(stackAddress, data);
        this.sp--;
    }
    unittest
    {
    }
    //increments stack pointer and returns the byte from the top of the stack
    ubyte popStack()
    {
        //remember sp points to the next EMPTY stack location so we increment SP first
        //to get to the last stack value
        this.sp++;
        ushort stackAddress = cast(ushort)(this.stackBaseAddress + this.sp);
        return Console.ram.read(stackAddress);
    }
    unittest
    {
    }

    private 
    {
        ushort pc; // program counter
        ubyte a;   // accumulator
        ubyte x;   // x index
        ubyte y;   // y index
        ubyte sp;  // stack pointer
        ulong cycles; // total cycles executed
        bool nmi; // non maskable interrupt line
        bool rst; // reset interrupt line
        bool irq; //software interrupt request line

        StatusRegister status;

        immutable ushort nmiAddress = 0xFFFA;
        immutable ushort resetAddress = 0xFFFC;
        immutable ushort irqAddress = 0xFFFE;
        immutable ushort stackBaseAddress = 0x0100;
        immutable ushort stackTopAddress = 0x01FF;

        
        ubyte[256] cycleCountTable = [
         // 0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F 
         7, 6, 0, 8, 3, 3, 5, 5, 3, 2, 2, 2, 4, 4, 6, 6, // 0
         2, 5, 0, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7, // 1
         6, 6, 0, 8, 3, 3, 5, 5, 4, 2, 2, 2, 4, 4, 6, 6, // 2
         2, 5, 0, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7, // 3
         6, 6, 0, 8, 3, 3, 5, 5, 3, 2, 2, 2, 3, 4, 6, 6, // 4
         2, 5, 0, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7, // 5
         6, 6, 0, 8, 3, 3, 5, 5, 4, 2, 2, 2, 5, 4, 6, 6, // 6
         2, 5, 0, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7, // 7
         2, 6, 2, 6, 3, 3, 3, 3, 2, 2, 2, 2, 4, 4, 4, 4, // 8
         2, 6, 0, 6, 4, 4, 4, 4, 2, 5, 2, 5, 5, 5, 5, 5, // 9
         2, 6, 2, 6, 3, 3, 3, 3, 2, 2, 2, 2, 4, 4, 4, 4, // A
         2, 5, 0, 5, 4, 4, 4, 4, 2, 4, 2, 4, 4, 4, 4, 4, // B
         2, 6, 2, 8, 3, 3, 5, 5, 2, 2, 2, 2, 4, 4, 6, 6, // C
         2, 5, 0, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7, // D
         2, 6, 2, 8, 3, 3, 5, 5, 2, 2, 2, 2, 4, 4, 6, 6, // E
         2, 5, 0, 8, 4, 4, 6, 6, 2, 4, 2, 7, 4, 4, 7, 7 ]; // F 

        ubyte[256] addressModeTable = [
         //  0      1      2      3      4      5      6      7    
         //  8      9      A      B      C      D      E      F    
          0x01,  0xF2,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // 0
          0x01,  0x10,  0xA0,  0x00,  0xD0,  0xD0,  0xD0,  0xD0, // 0
          0xC0,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB1,  0xB1, // 1
          0x01,  0xD2,  0x00,  0xD2,  0xD1,  0xD1,  0xD1,  0xD1, // 1
          0xD0,  0xF2,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // 2
          0x01,  0x10,  0xA0,  0x00,  0xD0,  0xD0,  0xD0,  0xD0, // 2
          0xC2,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB1,  0xB1, // 3
          0x01,  0xD2,  0x00,  0xD2,  0xD1,  0xD1,  0xD1,  0xD1, // 3
          0x01,  0xF2,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // 4
          0x01,  0x10,  0xA0,  0x00,  0xD0,  0xD0,  0xD0,  0xD0, // 4
          0xC0,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB1,  0xB1, // 5
          0x01,  0xD2,  0x00,  0xD2,  0xD1,  0xD1,  0xD1,  0xD1, // 5
          0xF1,  0xF2,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // 6
          0x01,  0x10,  0xA0,  0x00,  0xF0,  0xD0,  0xD0,  0xD0, // 6
          0xC0,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB1,  0xB1, // 7
          0x01,  0xD2,  0x00,  0xD2,  0xD1,  0xD1,  0xD1,  0xD1, // 7
          0x00,  0xF2,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // 8
          0x01,  0x00,  0x01,  0x00,  0xD0,  0xD0,  0xD0,  0xD0, // 8
          0xC0,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB2,  0xB2, // 9
          0x01,  0xD2,  0x01,  0x00,  0xD1,  0xD1,  0xD2,  0xD2, // 9
          0x10,  0xF2,  0x10,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // A
          0x01,  0x10,  0x01,  0x00,  0xD0,  0xD0,  0xD0,  0xD0, // A
          0xC0,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB2,  0xB2, // B
          0x01,  0xD2,  0x01,  0xD2,  0xD1,  0xD1,  0xD2,  0xD2, // B
          0x10,  0xF1,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // C
          0x01,  0x10,  0x01,  0x00,  0xD0,  0xD0,  0xD0,  0xD0, // C
          0xC0,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB1,  0xB1, // D
          0x01,  0xD2,  0x00,  0xD2,  0xD1,  0xD1,  0xD1,  0xD1, // D
          0x10,  0xF2,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // E
          0x01,  0x10,  0x01,  0x00,  0xD0,  0xD0,  0xD0,  0xD0, // E
          0xC0,  0xF1,  0x00,  0xF1,  0xB1,  0xB1,  0xB1,  0xB1, // F
          0x01,  0xD2,  0x00,  0xD2,  0xD1,  0xD1,  0xD1,  0xD1 ]; // F 
            }
}
