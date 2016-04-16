// vim: set foldmethod=syntax foldlevel=1  textwidth=80 ts=4 sts=4 expandtab autoindent smartindent cindent ft=d :
/* mos6502.d
 * Copyright © 2016 dNES contributors. All Rights Reserved.
 * License: GPL v3.0
 *
 * This file is part of dNES.
 *
 * dNES is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * dNES is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 */

module cpu.mos6502;
import cpu.registers;
import cpu.exceptions;
import cpu.decoder;
import console;
import memory;


class MOS6502
{
    public this()
    {
        _status = new StatusRegister;
        _registers = new Registers;
        _decoder = new Decoder(this);

        _pageBoundaryWasCrossed = false;
    }

    // From http://wiki.nesdev.com/w/index.php/CPU_power_up_state
    public void powerOn()
    {
        _status.asWord = 0x34;
        _registers.a = _registers.x = _registers.y = 0;
        _registers.sp = 0xFD;

        if (Console.ram is null)
        {
            // Ram will only be null if a prior emulation has ended or if we are
            // unit-testing. Normally, console will allocate this on program
            // start.
            Console.ram = new RAM;
        }
        _registers.pc = 0xC000;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        assert(cpu._status.asWord == 0x34);
        assert(cpu._registers.a == 0);
        assert(cpu._registers.x == 0);
        assert(cpu._registers.y == 0);
        assert(cpu._registers.pc == 0xC000);

        // Do not test the Console.ram constructor here, it should be tested
        // in ram.d
    }

    public @property const(Registers) registers()
    {
        return _registers;
    }

    // From http://wiki.nesdev.com/w/index.php/CPU_power_up_state
    // After reset
    //    A, X, Y were not affected
    //    S was decremented by 3 (but nothing was written to the stack)
    //    The I (IRQ disable) flag was set to true (_status ORed with $04)
    //    The internal memory was unchanged
    //    APU mode in $4017 was unchanged
    //    APU was silenced ($4015 = 0)
    package void reset()
    {
        _registers.sp -= 0x03;
        _status.asWord = _status.asWord | 0x04;
        // TODO: Console.MemoryMapper.Write(0x4015, 0);
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        cpu._status.asWord = 0x01;
        cpu._registers.a = cpu._registers.x = cpu._registers.y = 55;
        cpu._registers.sp = 0xF4;
        cpu._registers.pc= 0xF000;
        cpu.reset();

        assert(cpu._registers.sp == (0xF4 - 0x03));
        assert(cpu._status.asWord == (0x21 | 0x04)); // bit 6 (0x20) is always on
    }

    package ubyte fetch()
    {
        return Console.ram.read(_registers.pc++);
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        // Case 1: pc register properly incremented
        auto instruction = cpu.fetch();
        assert(cpu._registers.pc == 0xC001);

        // Case 2: Instruction is properly read
        Console.ram.write(cpu._registers.pc, 0xFF);  // TODO: Find a way to replace with a MockRam class
        instruction = cpu.fetch();
        assert(cpu._registers.pc == 0xC002);
        assert(instruction == 0xFF);
    }

    /*
    package void delegate(ubyte) decode(Instruction operation)
    {
        switch (opcode)
        {
        // JMP
        case 0x4C:
        case 0x6C:
            return &JMP;
        // ADC
        case 0x69:
        case 0x65:
        case 0x75:
        case 0x6D:
        case 0x7D:
        case 0x79:
        case 0x61:
        case 0x71:
            return &ADC;
        case 0x78:
            return &CLI;
        case 0x88:
            return &DEY;
        case 0xCA:
            return &DEX;
        case 0xEA:
            return &NOP;
        default:
            throw new InvalidOpcodeException(opcode);
        }
    }
    // TODO: Write unit test before writing implementation (TDD)
    unittest
    {
        import std.file, std.stdio;

        // Load a test ROM
        auto ROMBytes = cast(ubyte[])read("libdnes/specs/nestest.nes");
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
     */

    //perform another cpu cycle of emulation
    package void cycle()
    {
        //Priority: Reset > NMI > IRQ
        if (_rst)
        {
            handleReset();
        }
        if (_nmi)
        {
            handleNmi();
        }
        if (_irq)
        {
            handleIrq();
        }
        //Fetch
        ubyte opcode = fetch();
        //Decode
        auto instruction = _decoder.getInstruction(opcode);
        //Execute
        instruction.execute();
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto savedCycles = cpu._cycleCount;
        auto ram = Console.ram;
        //Check if RST is handled
        cpu.setReset();
        //set reset vector memory

        ram.write16(cpu._resetAddress, 0x00); //write address 00 to reset vector
        ram.write(0x00, 0xEA); //write  NOP instruction to address 0x00

        cpu.cycle();

        assert(cpu._rst == false);
        assert(cpu._cycleCount == savedCycles + 7 + 2); //2 cycles for NOP
    }



    private void handleReset()
    {
        auto resetVectorAddress = Console.ram.read16(_resetAddress);
        _registers.pc = resetVectorAddress;
        _rst = false;
        _cycleCount += 7;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        auto savedCycles = cpu._cycleCount;
        ram.write16(cpu._resetAddress, 0xFC10); //write interrupt handler address
        cpu._rst = true;
        cpu.handleReset();
        assert(cpu._cycleCount == savedCycles + 7);
        assert(cpu._registers.pc == 0xFC10);
        assert(cpu._rst == false);
    }

    private void handleNmi()
    {
        pushStack(cast(ubyte)(_registers.pc >> 8)); //write PC high byte to stack
        pushStack(cast(ubyte)(_registers.pc));
        pushStack(_status.asWord);
        auto _nmiVectorAddress = Console.ram.read16(_nmiAddress);
        _registers.pc = _nmiVectorAddress;
        _nmi = false;
        _cycleCount += 7;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        auto savedCycles = cpu._cycleCount;
        auto savedPC = cpu._registers.pc;
        auto savedStatus = cpu._status.asWord;
        ram.write16(cpu._nmiAddress, 0x1D42); //write interrupt handler address
        cpu.handleNmi();
        assert(cpu.popStack() == savedStatus); //check _status _registers
        ushort previousPC = cpu.popStack() | (cpu.popStack() << 8); //verify pc write
        assert(cpu._cycleCount == savedCycles + 7);
        assert(cpu._registers.pc == 0x1D42);
        assert(previousPC == savedPC);

    }

    private void handleIrq()
    {
        if(_status.i)
            return; //don't do anything if interrupt disable is set

        pushStack(cast(ubyte)(_registers.pc >> 8)); //write PC high byte to stack
        pushStack(cast(ubyte)(_registers.pc));
        pushStack(_status.asWord);
        auto _irqVectorAddress = Console.ram.read16(_irqAddress);
        _registers.pc = _irqVectorAddress;
        _cycleCount +=7;
    }
    unittest
    {
        //case 1 : interrupt disable bit is not set
        auto cpu = new MOS6502;
        cpu.powerOn();
        cpu._status.i = false;
        auto ram = Console.ram;
        auto savedCycles = cpu._cycleCount;
        auto savedPC = cpu._registers.pc;
        auto savedStatus = cpu._status.asWord;
        ram.write16(cpu._irqAddress, 0xC296); //write interrupt handler address
        cpu.handleIrq();
        assert(cpu.popStack() == savedStatus); //check _status _registers
        ushort previousPC = cpu.popStack() | (cpu.popStack() << 8); //verify pc write
        assert(cpu._cycleCount == savedCycles + 7);
        assert(cpu._registers.pc == 0xC296);
        assert(previousPC == savedPC);
        //case 2 : interrupt disable bit is set
        cpu._status.i = true;
        savedCycles = cpu._cycleCount;
        ram.write16(cpu._irqAddress, 0x1111); //write interrupt handler address
        cpu.handleIrq();
        assert(cpu._cycleCount == savedCycles + 0);
        assert(cpu._registers.pc == 0xC296);
    }

    /*
    private ushort delegate(Instruction) decodeAddressMode(Instruction operation)
    {
        _pageBoundaryWasCrossed = false; //reset the page boundry crossing flag each time we decode the next address mode
        Decoder.AddressingMode addressModeCode =
            cast(Decoder.AddressingMode)(_addressModeTable[opcode]);

        switch (addressModeCode)
        {
        case Decoder.AddressingMode.IMPLIED:
            return null;
        case Decoder.AddressingMode.IMMEDIATE:
            return &(immediateAddressMode);
        case Decoder.AddressingMode.ACCUMULATOR:
        goto case Decoder.AddressingMode.IMPLIED;
        case Decoder.AddressingMode.ZEROPAGE:
        case Decoder.AddressingMode.ZEROPAGE_X:
        case Decoder.AddressingMode.ZEROPAGE_Y:
            return &(zeroPageAddressMode);
        case Decoder.AddressingMode.RELATIVE:
            return &(relativeAddressMode);
        case Decoder.AddressingMode.ABSOLUTE:
        case Decoder.AddressingMode.ABSOLUTE_X:
        case Decoder.AddressingMode.ABSOLUTE_Y:
            return &(absoluteAddressMode);
        case Decoder.AddressingMode.INDIRECT:
            return &(indirectAddressMode);
        case Decoder.AddressingMode.INDEXED_INDIRECT:
            return &(indexedIndirectAddressMode);
        case Decoder.AddressingMode.INDIRECT_INDEXED:
            return &(indirectIndexedAddressMode);
        default:
            throw new InvalidAddressingModeException(instruction, opcode);
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        // Case 1: Implied & Accumulator
        // Case 2: Immediate
        // Case 3: Zero Page
        // Case 4: Absolute
        // Case 5: Indirect
        // Case 6: failure
        try
        {
            cpu.decodeAddressMode("KIL", 0x2A); // Invalid opcode
        }
        catch (InvalidAddressingModeException e)
        {} // this exception is expected; suppress it.
    }*/

    private ubyte decodeIndex(string instruction, ubyte opcode)
    {
        Instruction operation = _decoder.getInstruction(opcode);
        return _decoder.decodeIndex(operation);
    }

    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        cpu._registers.x = 0x11;
        cpu._registers.y = 0x45;
        // Case 1: Non-indexed
        assert(cpu.decodeIndex("ADC",0x69) == 0x00);
        // Case 2: X-indexed
        assert (cpu.decodeIndex("ADC", 0x7D) == cpu._registers.x);
        // case 3: Y-indexed
        assert (cpu.decodeIndex("ADC", 0x79) == cpu._registers.y);
        //case 4: failure
        try
        {
            cpu.decodeIndex("KIL", 0x2A); // Invalid opcode
        }
        catch (InvalidAddressIndexException e)
        {} // this exception is expected; suppress it.
    }

    //***** Instruction Implementation *****//
    // TODO: Add tracing so we can compare against nestest.log
    private void JMP(Instruction operation)
    {
        _registers.pc = operation.addressModeDelegate()(operation);
        _cycleCount += operation.baseCycleCount;
    }
    unittest
    {
        import std.stdio;
        auto cpu = new MOS6502;
        auto ram = Console.ram;
        cpu.powerOn();

        cpu._registers.pc = 0xC000;
        // Case 1: Absolute addressing
        ram.write(0xC000, 0x4C);     // JMP, absolute
        ram.write16(0xC001, 0xC005); // argument

        //cpu.JMP(ram.read(cpu._registers.pc++));
        cpu._decoder.getInstruction(cpu.fetch()).execute();
        assert(cpu._registers.pc == 0xC005);

        // Case 2: Indirect addressing, page not boundary
        ram.write(0xC005, 0x6C);     // JMP, indirect address
        ram.write16(0xC006, 0xC00C); // address of final address
        ram.write16(0xC00C, 0xEE00);

        cpu._decoder.getInstruction(cpu.fetch()).execute();
        assert(cpu._registers.pc == 0xEE00);
    }

    private void KIL(Instruction operation)
    {
        import std.stdio;
        writeln("CRASH");

        throw new ExecutionException(operation);
    }

    private void ADC(Instruction operation)
    {
        auto ram = Console.ram;

        ushort a; // a = accumulator value
        ushort m; // m = operand
        ushort c; // c = carry value

        a = _registers.a;
        c = _status.c;

        if (operation.addressingMode == Decoder.AddressingMode.IMMEDIATE)
        {
            m = operation.fetchOperand();
        }
        else
        {
            m = ram.read(operation.fetchOperand());
        }

        auto result = cast(ushort)(a+m+c);
        // Check for overflow
        if (result > 255)
        {
            _registers.a = cast(ubyte)(result - 255);
            _status.c = 1;
        }
        else
        {
            _registers.a = cast(ubyte)(result);
            _status.c = 0;
        }

        checkAndSetZero(_registers.a);

        checkAndSetNegative(_registers.a);

        if (((_registers.a^m) & 0x80) == 0 && ((a^_registers.a) & 0x80) != 0)
        {
            _status.v = 1;
        }
        else
        {
            _status.v = 0;
        }

        _cycleCount += operation.baseCycleCount;

        if (isIndexedMode(operation) &&
                (operation.addressingMode != Decoder.AddressingMode.INDIRECT_INDEXED) &&
                (operation.addressingMode != Decoder.AddressingMode.ZEROPAGE_X))
        {
            _cycleCount += operation.extraIndexingCycles;

            if (_pageBoundaryWasCrossed)
            {
                _cycleCount += operation.extraPageBoundaryCycles;
            }
        }

    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        cpu.powerOn();
        assert(cpu._registers.a == 0);
        auto ram = Console.ram;
        ulong cycles_start = 0;
        ulong cycles_end = 0;

        // Case 1: Immediate
        cycles_start = cpu._cycleCount;
        cpu._registers.pc = 0x0101;          // move to new page
        cpu._registers.a = 0x20;             // give an initial value other than 0
        cpu._status.c = 0;         // reset to 0
        ram.write(cpu._registers.pc, 0x40);  // write operand to memory

        auto testInstruction = decoder.getInstruction(0x69);

        cpu.ADC(testInstruction);            // execute ADC immediate
        cycles_end  = cpu._cycleCount; // get cycle count
        assert(cpu._registers.a == 0x60);    // 0x20 + 0x40 = 0x60
        assert((cycles_end - cycles_start) == 2); // verify cycles taken

        // Trigger overflow
        ram.write(cpu._registers.pc, 0xA0);
        cpu.ADC(testInstruction);
        assert(cpu._registers.a == 0x01);
        assert(cpu._status.c == 1);
        ram.write(cpu._registers.pc, 0x02);
        cpu.ADC(testInstruction);
        assert(cpu._status.c == 0);

        // @TODO continue testing each addressing mode

        // Case 4: Absolute
        testInstruction = decoder.getInstruction(0x6D);
        cycles_start = cpu._cycleCount;
        cpu._registers.a = 0;
        cpu._registers.pc = 0x0400;
        ram.write16(cpu._registers.pc, 0xB00B);
        ram.write(0xB00B, 0x7D);
        cpu.ADC(testInstruction);
        cycles_end  = cpu._cycleCount;
        assert(cpu._registers.a == 0x7D);
        assert((cycles_end - cycles_start) == 4);
    }

    private void AND(Instruction operation)
    {
        auto ram = Console.ram;

        ubyte operand;

        if (operation.addressingMode == Decoder.AddressingMode.IMMEDIATE)
        {
            operand = cast(ubyte)(operation.fetchOperand());
        }

        _registers.a = (_registers.a & operand);
        _status.z = (_registers.a == 0   ? 1 : 0);
        _status.n = (_registers.a >= 128 ? 1 : 0);

        _cycleCount += operation.baseCycleCount;
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto ram = Console.ram;
        cpu.powerOn();

        assert(cpu._registers.a == 0);

        ulong cycles_start = 0;
        ulong cycles_end = 0;

        // Case 1: Immediate
        uint expected_cycles = 2;
        ubyte expected_result;

        cycles_start = cpu._cycleCount;
        cpu._registers.pc = 0x0101;

        auto testInstruction = decoder.getInstruction(0x29);

        // iterate through all possible register/memory values and test them
        for (ushort op1 = 0; op1 < 256; op1++) { // operand1
            for (ushort op2 = 0; op2 < 256; op2++) { // operand 2
                cpu._status.z = 0;
                cpu._status.n = 0;
                cpu._registers.a = cast(ubyte)op1;
                ram.write(cpu._registers.pc, cast(ubyte)op2);

                cycles_start = cpu._cycleCount;

                cpu.AND(testInstruction);
                cycles_end = cpu._cycleCount;
                expected_result = cast(ubyte)op1 & cast(ubyte)op2;

                //writef("0b%.8b & 0b%.8b = 0b%.8b\n", op1, op2, expected_result);
                assert((cycles_end - cycles_start) == expected_cycles);
                assert(cpu._registers.a == expected_result);
                assert(cpu._registers.a == 0  ? cpu._status.z == 1 : cpu._status.z == 0);
                assert(cpu._registers.a >= 128 ? cpu._status.n == 1 : cpu._status.n == 0);
            }
        }
    }

    private void NOP(Instruction operation)
    {
        _cycleCount += 2;
    }

    //If the negative flag is set then add the relative displacement to the program counter to cause a branch to a new location.

    // @TODO: Branch Instructions all increment the cycle count like this. Let's
    // make the actual branching a function that takes a predicate as the
    // condition.
    private void BMI(Instruction operation)
    {
        _cycleCount += 2;

        //Relative only
        ushort finalAddress = operation.fetchOperand();

        if(_status.n)
        {
            if((_registers.pc / 0xFF) == (finalAddress / 0xFF))
            {
                _registers.pc = finalAddress;
                _cycleCount++;
            }
            else
            {
                _registers.pc = finalAddress;
                //goes to a new page
                _cycleCount +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto ram = Console.ram;
        auto testInstruction = decoder.getInstruction(0x30);

        cpu.powerOn();
        //case 1 forward offset, n flag set, jumps page boundary (4 _cycleCount)
        cpu._status.n = 1;
        ram.write(cpu._registers.pc, 0x4C); // argument
        auto savedPC = cpu._registers.pc;
        auto savedCycles = cpu._cycleCount;
        cpu.BMI(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1 + 0x4C);
        assert(cpu._cycleCount == savedCycles + 0x4);
        //case 2 forward offset, n flag is clear, (2 cycles)
        cpu._status.n = 0;
        ram.write(cpu._registers.pc, 0x4C); // argument
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BMI(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu._cycleCount == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, n flag is set, (3 cycles)
        cpu._status.n = 1;
        ram.write(cpu._registers.pc, 0xF1); // (-15)
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BMI(testInstruction);
        assert(cpu._registers.pc == savedPC + 1 - 0xF);
        assert(cpu._cycleCount == savedCycles + 0x3);
        //case 4 negative offset, n flag is clear (1 cycle)
        cpu._status.n = 0;
        ram.write(cpu._registers.pc, 0xF1); // argument
        savedPC = cpu._registers.pc;
        cpu.BMI(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
    }

    //If the zero flag is clear then add the relative displacement to the program counter to cause a branch to a new location.
    private void BNE(Instruction operation)
    {
        _cycleCount += 2;
        //Relative only
        ushort finalAddress = operation.fetchOperand();
        if(!_status.z)
        {
            if((_registers.pc / 0xFF) == (finalAddress / 0xFF))
            {
                _registers.pc = finalAddress;
                _cycleCount++;
            }
            else
            {
                _registers.pc = finalAddress;
                //goes to a new page
                _cycleCount +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0xD0);
        //case 1 forward offset, z flag clear, jumps page boundary (4 cycles)
        cpu._status.z = 0;
        ram.write(cpu._registers.pc, 0x4D); // argument
        auto savedPC = cpu._registers.pc;
        auto savedCycles = cpu._cycleCount;
        cpu.BNE(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1 + 0x4D);
        assert(cpu._cycleCount == savedCycles + 0x4); //branch will cross a page boundary
        //case 2 forward offset, z flag is set, (2 cycles)
        cpu._status.z = 1;
        ram.write(cpu._registers.pc, 0x4D); // argument
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BNE(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu._cycleCount == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, z flag is clear (3 cycles)
        cpu._status.z = 0;
        ram.write(cpu._registers.pc, 0xF1); // (-15)
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BNE(testInstruction);
        assert(cpu._registers.pc == savedPC + 1 - 0xF);
        assert(cpu._cycleCount == savedCycles + 0x3); //branch doesn't cross page boundary
        //case 4 negative offset, z flag is set (1 cycle)
        cpu._status.z = 1;
        ram.write(cpu._registers.pc, 0xF1); // argument
        savedPC = cpu._registers.pc;
        cpu.BNE(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
    }

    //If the negative flag is clear then add the relative displacement to the program counter to cause a branch to a new location.
    private void BPL(Instruction operation)
    {
        _cycleCount += 2;
        //Relative only
        ushort finalAddress = operation.fetchOperand();
        if(!_status.n)
        {
            if((_registers.pc / 0xFF) == (finalAddress / 0xFF))
            {
                _registers.pc = finalAddress;
                _cycleCount++;
            }
            else
            {
                _registers.pc = finalAddress;
                //goes to a new page
                _cycleCount +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x10);

        //case 1 forward offset, n flag clear, jumps page boundary (4 cycles)
        cpu._status.n = 0;
        ram.write(cpu._registers.pc, 0x4D); // argument
        auto savedPC = cpu._registers.pc;
        auto savedCycles = cpu._cycleCount;
        cpu.BPL(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1 + 0x4D);
        assert(cpu._cycleCount == savedCycles + 0x4); //branch will cross a page boundary
        //case 2 forward offset, n flag is set, (2 cycles)
        cpu._status.n = 1;
        ram.write(cpu._registers.pc, 0x4D); // argument
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BPL(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu._cycleCount == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, n flag is clear (3 cycles)
        cpu._status.n = 0;
        ram.write(cpu._registers.pc, 0xF1); // (-15)
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BPL(testInstruction);
        assert(cpu._registers.pc == savedPC + 1 - 0xF);
        assert(cpu._cycleCount == savedCycles + 0x3); //branch doesn't cross page boundary
        //case 4 negative offset, n flag is set (2 cycles)
        cpu._status.n = 1;
        ram.write(cpu._registers.pc, 0xF1); // argument
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BPL(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu._cycleCount == savedCycles + 0x2);
    }

    //forces an interrupt to be fired. the _status register is copied to stack and bit 5 of the stored pc on the stack is set to 1
    private void BRK(Instruction operation)
    {
        //the BRK instruction saves the PC at BRK+2 to stack, so increment PC by 1 to skip next byte
        _registers.pc++;
        pushStack(cast(ubyte)(_registers.pc >> 8)); //write PC high byte to stack
        pushStack(cast(ubyte)(_registers.pc));
        StatusRegister brkStatus = _status;
        //set b flag and write to stack
        brkStatus.b = 1;
        pushStack(brkStatus.asWord);
        auto _irqVectorAddress = Console.ram.read16(_irqAddress);
        _registers.pc = _irqVectorAddress; //brk handled similarly to _irq
        _cycleCount += 7;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        auto savedCycles = cpu._cycleCount;
        auto savedPC = cpu._registers.pc;
        auto savedStatus = cpu._status.asWord;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x00);

        ram.write16(cpu._irqAddress, 0x1744); //write interrupt handler address
        //increment PC by 1 to simulate fetch
        cpu._registers.pc++;
        cpu.BRK(testInstruction);
        assert(cpu.popStack() == (savedStatus | 0b10000)); //check _status _registers
        ushort previousPC = cpu.popStack() | (cpu.popStack() << 8); //verify pc write
        assert(cpu._cycleCount == savedCycles + 7);
        assert(cpu._registers.pc == 0x1744);
        assert(previousPC == savedPC + 2);
    }

    //If the overflow flag is clear then add the relative displacement to the program counter to cause a branch to a new location.
    private void BVC(Instruction operation)
    {
        _cycleCount += 2;
        //Relative only
        ushort finalAddress = operation.fetchOperand();
        if(!_status.v)
        {
            if((_registers.pc / 0xFF) == (finalAddress / 0xFF))
            {
                _registers.pc = finalAddress;
                _cycleCount++;
            }
            else
            {
                _registers.pc = finalAddress;
                //goes to a new page
                _cycleCount +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x50);

        //case 1 forward offset, v flag clear, jumps page boundary (4 cycles)
        cpu._status.v = 0;
        ram.write(cpu._registers.pc, 0x5D); // argument
        auto savedPC = cpu._registers.pc;
        auto savedCycles = cpu._cycleCount;
        cpu.BVC(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1 + 0x5D);
        assert(cpu._cycleCount == savedCycles + 0x4); //branch will cross a page boundary
        //case 2 forward offset, v flag is set, (2 cycles)
        cpu._status.v = 1;
        ram.write(cpu._registers.pc, 0x4D); // argument
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BVC(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu._cycleCount == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, v flag is clear (3 cycles)
        cpu._status.v = 0;
        ram.write(cpu._registers.pc, 0xF1); // (-15)
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BVC(testInstruction);
        assert(cpu._registers.pc == savedPC + 1 - 0xF);
        assert(cpu._cycleCount == savedCycles + 0x3); //branch doesn't cross page boundary
        //case 4 negative offset, v flag is set (2 cycles)
        cpu._status.v = 1;
        ram.write(cpu._registers.pc, 0xF1); // argument
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BVC(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu._cycleCount == savedCycles + 0x2);
    }

    //If the overflow flag is set then add the relative displacement to the program counter to cause a branch to a new location.
    private void BVS(Instruction operation)
    {
        _cycleCount += 2;
        //Relative only
        ushort finalAddress = operation.fetchOperand();
        if(_status.v)
        {
            if((_registers.pc / 0xFF) == (finalAddress / 0xFF))
            {
                _registers.pc = finalAddress;
                _cycleCount++;
            }
            else
            {
                _registers.pc = finalAddress;
                //goes to a new page
                _cycleCount +=2;
            }
        }
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto ram = Console.ram;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x70);
        //case 1 forward offset, v flag set, jumps page boundary (4 cycles)
        cpu._status.v = 1;
        ram.write(cpu._registers.pc, 0x5C); // argument
        auto savedPC = cpu._registers.pc;
        auto savedCycles = cpu._cycleCount;
        cpu.BVS(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1 + 0x5C);
        assert(cpu._cycleCount == savedCycles + 0x4);
        //case 2 forward offset, v flag is clear, (2 cycles)
        cpu._status.v = 0;
        ram.write(cpu._registers.pc, 0x4C); // argument
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BVS(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
        assert(cpu._cycleCount == savedCycles + 0x2); //(2 cycles)
        //case 3 negative offset, v flag is set, (3 cycles)
        cpu._status.v = 1;
        ram.write(cpu._registers.pc, 0xF1); // (-15)
        savedPC = cpu._registers.pc;
        savedCycles = cpu._cycleCount;
        cpu.BVS(testInstruction);
        assert(cpu._registers.pc == savedPC + 1 - 0xF);
        assert(cpu._cycleCount == savedCycles + 0x3);
        //case 4 negative offset, v flag is clear (1 cycle)
        cpu._status.v = 0;
        ram.write(cpu._registers.pc, 0xF1); // argument
        savedPC = cpu._registers.pc;
        cpu.BVS(testInstruction);
        assert(cpu._registers.pc == savedPC + 0x1); //for this case it should not branch
    }

    //Clear carry flag
    private void CLC(Instruction operation)
    {
        _status.c = 0;
        _cycleCount += 2;
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        cpu.powerOn();
        auto savedCycles = cpu._cycleCount;
        auto testInstruction = decoder.getInstruction(0x18);
        cpu._status.c = 1;
        cpu.CLC(testInstruction);
        assert(cpu._status.c == 0);
        assert(cpu._cycleCount == savedCycles + 2);
    }

    //Clear decimal mode flag
    private void CLD(Instruction operation)

    {
        _status.d = 0;
        _cycleCount += 2;
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        cpu.powerOn();
        auto savedCycles = cpu._cycleCount;
        auto testInstruction = decoder.getInstruction(0xD8);
        cpu._status.d = 1;
        cpu.CLD(testInstruction);
        assert(cpu._status.d == 0);
        assert(cpu._cycleCount == savedCycles + 2);
    }

    //Clear interrupt disable flag
    private void CLI(Instruction operation)
    {
        _status.i = 0;
        _cycleCount += 2;
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        cpu.powerOn();
        auto savedCycles = cpu._cycleCount;
        auto testInstruction = decoder.getInstruction(0x78);
        cpu._status.i = 1;
        cpu.CLI(testInstruction);
        assert(cpu._status.i == 0);
        assert(cpu._cycleCount == savedCycles + 2);
    }

    //Clear overflow flag
    private void CLV(Instruction operation)
    {
        _status.v = 0;
        _cycleCount += 2;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0xB8);
        auto savedCycles = cpu._cycleCount;
        cpu._status.v = 1;
        cpu.CLV(testInstruction);
        assert(cpu._status.v == 0);
        assert(cpu._cycleCount == savedCycles + 2);
    }

    //Decrements the X register by 1
    private void DEX(Instruction operation)
    {
        _registers.x--;
        checkAndSetNegative(_registers.x);
        checkAndSetZero(_registers.x);
        _cycleCount += operation.baseCycleCount;
    }
    unittest //0xCA, 1 byte, 2 cycles
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto decoder = cpu._decoder;
        auto savedCycles = cpu._cycleCount;
        auto testInstruction = decoder.getInstruction(0xCA);
        //case 1, x register is 0 and decremented to negative value
        cpu._registers.x = 0;
        cpu.DEX(testInstruction);
        assert(cpu._status.n == 1);
        assert(cpu._status.z == 0);
        assert(cpu._cycleCount == savedCycles + 2);
        //case 2, x register is 1 and decremented to zero
        savedCycles = cpu._cycleCount;
        cpu._registers.x = 0;
        cpu.DEX(testInstruction);
        assert(cpu._status.n == 1);
        assert(cpu._status.z == 0);
        assert(cpu._cycleCount == savedCycles + 2);
        //case 3, x register is positive and decremented to positive value
        savedCycles = cpu._cycleCount;
        cpu._registers.x = 10;
        cpu.DEX(testInstruction);
        assert(cpu._status.n == 0);
        assert(cpu._status.z == 0);
        assert(cpu._cycleCount == savedCycles + 2);
    }

    //Decrements the Y register by 1
    private void DEY(Instruction operation)
    {
        _registers.y--;
        checkAndSetNegative(_registers.y);
        checkAndSetZero(_registers.y);
        _cycleCount += operation.baseCycleCount;
    }
    unittest //0x88, 1 byte, 2 cycles
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        cpu.powerOn();
        auto testInstruction = decoder.getInstruction(0x88);
        auto savedCycles = cpu._cycleCount;
        //case 1, y register is 0 and decremented to negative value
        cpu._registers.y = 0;
        cpu.DEY(testInstruction);
        assert(cpu._status.n == 1);
        assert(cpu._status.z == 0);
        assert(cpu._cycleCount == savedCycles + 2);
        //case 2, y register is 1 and decremented to zero
        savedCycles = cpu._cycleCount;
        cpu._registers.y = 0;
        cpu.DEY(testInstruction);
        assert(cpu._status.n == 1);
        assert(cpu._status.z == 0);
        assert(cpu._cycleCount == savedCycles + 2);
        //case 3, y register is positive and decremented to positive value
        savedCycles = cpu._cycleCount;
        cpu._registers.y = 45;
        cpu.DEY(testInstruction);
        assert(cpu._status.n == 0);
        assert(cpu._status.z == 0);
        assert(cpu._cycleCount == savedCycles + 2);
    }

    //An exclusive OR is performed, bit by bit, on the accumulator contents using the contents of a byte of memory.
    private void EOR(Instruction operation)
    {
        auto addressMode     = operation.addressingMode;
        auto ram = Console.ram;

        ushort a = _registers.a; // a = accumulator value
        ushort m; // m = operand

        if (addressMode == Decoder.AddressingMode.IMMEDIATE)
        {
            m = operation.fetchOperand();
        }
        else
        {
            ushort finalAddress = operation.fetchOperand();
            m = ram.read(finalAddress);

            if (isIndexedMode(operation))
            {
                switch(operation.addressingMode)
                {
                    case Decoder.AddressingMode.ABSOLUTE_X:
                        goto case Decoder.AddressingMode.INDIRECT_INDEXED;
                    case Decoder.AddressingMode.ABSOLUTE_Y:
                        goto case Decoder.AddressingMode.INDIRECT_INDEXED;
                    case Decoder.AddressingMode.INDIRECT_INDEXED:
                        if (_pageBoundaryWasCrossed)
                            _cycleCount++; //_cycleCount += operation.extraPageBoundaryCycles;
                        break;
                    default:
                        break;
                }
            }
        }

        _registers.a = cast(ubyte)(a ^ m);
        checkAndSetZero(_registers.a);
        checkAndSetNegative(_registers.a);
        _cycleCount += operation.baseCycleCount;
    }
    /*
        Immediate 0x49 2
        Zero Page 0x45 3
        Zero Page,X 0x55 4
        Absolute 0x4D 4
        Absolute,X 0x5D 4(+1 if page crossed)
        Absolute,Y 0x59 4(+1 if page crossed)
        (Indirect,X) 0x41 6 <-indexed indirect
        (Indirect),Y 0x51 5(+1 if page crossed) <-indirect indexed
    */
    unittest
    {
        //verify all properties imediate mode (final value of a, zero/negative flags, cycles)
        //then for all subsequent modes just verify the final value of a and cycles
        // 0xF ^ 0xB = 4 (z = 0, n = 0)
        // 0xF ^ 0xF0 = 0xFF (z = 0, n =1)
        // 0xF ^ 0xF = 0 (z = 1, n = 0)
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto ram = Console.ram;
        auto testInstruction = decoder.getInstruction(0x49);
        cpu.powerOn();
        //Case 1 mode 1, immediate mode no flags set
        auto savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        ram.write(cpu._registers.pc, 0xB);
        cpu.EOR(testInstruction); //EOR immediate
        assert(cpu._registers.a == 4);
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 2);
        //Case 2 mode 1, immediate mode negative flag set
        savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        ram.write(cpu._registers.pc, 0xF0);
        cpu.EOR(testInstruction); //EOR immediate
        assert(cpu._registers.a == 0xFF);
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 1);
        assert(cpu._cycleCount == savedCycles + 2);
        //Case 3 mode 1, immediate mode zero flag set
        savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        ram.write(cpu._registers.pc, 0xF);
        cpu.EOR(testInstruction); //EOR immediate
        assert(cpu._registers.a == 0);
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 2);
        //Case 4 mode 2, zero page mode no flags set
        testInstruction = decoder.getInstruction(0x45);
        savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        ram.write(cpu._registers.pc, 0); //write address 0 to offset to zero page address 0
        ram.write(0, 0xB); //write to zero page address 0
        cpu.EOR(testInstruction); //EOR zero page
        assert(cpu._registers.a == 4);
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 3);
        //Case 5 mode 3, zero page indexed no flags set
        testInstruction = decoder.getInstruction(0x55);
        savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        ram.write(cpu._registers.pc, 2); //write address 2 to offset to zero page address 0
        cpu._registers.x = 4; //zero page address offset of 4
        ram.write(2+4, 0xB); //write to zero page address 2 + 4
        cpu.EOR(testInstruction); //EOR zero page indexed
        assert(cpu._registers.a == 4);
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 4);
        //Case 6 mode 4, absolute zero flag set
        savedCycles = cpu._cycleCount;
        testInstruction = decoder.getInstruction(0x4D);
        cpu._registers.a = 0xF;
        ram.write16(cpu._registers.pc, 0x1234); //write address 0x1234 to PC
        ram.write(0x1234, 0xF); //write operand m to address 0x1234
        cpu.EOR(testInstruction); //EOR absolute
        assert(cpu._registers.a == 0);
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 4);
        //Case 7 mode 5, absolute indexed x
        testInstruction = decoder.getInstruction(0x5D);
        savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        ram.write16(cpu._registers.pc, 0x1234); //write address 0x1234 to PC
        cpu._registers.x = 9;
        ram.write(0x1234+9, 0xF); //write operand m to address 0x1234+9
        cpu.EOR(testInstruction); //EOR absolute
        assert(cpu._registers.a == 0);
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 4);
        //Case 8 mode 6, absolute indexed y, page boundary crossed
        testInstruction = decoder.getInstruction(0x59);
        savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        ram.write16(cpu._registers.pc, 0x1234); //write address 0x1234 to PC
        cpu._registers.y = 0xff;
        ram.write(0x1234+0xFF, 0xF); //write operand m to address 0x1234+0xFF
        cpu.EOR(testInstruction); //EOR absolute
        assert(cpu._registers.a == 0);
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        import std.stdio;
        assert(cpu._cycleCount == savedCycles + 5);
        //Case 9 mode 7, indexed indirect (target =
        savedCycles = cpu._cycleCount;
        cpu._registers.a = 0xF;
        cpu._registers.x = 4; //X register is 4. This will be added to the operand m (0xA next line)
        ram.write(cpu._registers.pc, 0xA); //operand is 0xA
        ram.write(0xE, 0xF0); //write value 0xF0 to zero page address 0xA+4 = 0xE, which is what the target
        //address will be resolved to
        testInstruction = decoder.getInstruction(0x41);
        cpu.EOR(testInstruction);
        assert(cpu._registers.a == 0xFF);
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 1);
        assert(cpu._cycleCount == savedCycles + 6);
        //case 10 mode 8, indirect indexed
    }

    //Increment memory address by 1
    //Affects Z and N flags
    private void INC(Instruction operation)
    {
        auto addressMode = operation.addressingMode;

        auto ram = Console.ram;
        ushort a; // a = operand, our case the address to load and increment by 1
        ubyte m; // m = a + 1, stored back into a

        a = operation.fetchOperand();
        m = (ram.read(a) + 1 ) & 0xFF; //gotta round
        ram.write(a, m);
        checkAndSetZero(m);
        checkAndSetNegative(m);
        _cycleCount += operation.baseCycleCount;
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Zero Page       INC $A5        $E6      2     5
        Zero Page,X     INC $A5,X      $F6      2     6
        Absolute        INC $A5B6      $EE      3     6
        Absolute,X      INC $A5B6,X    $FE      3     7
    */
    unittest
    {
        auto cpu = new MOS6502;
        auto ram = Console.ram;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0xE6);
        cpu.powerOn();
        //Case 1 mode 1, zero page, n is set, z is unset
        auto savedCycles = cpu._cycleCount;
        ram.write(cpu._registers.pc, 5); //zero page address 5
        ram.write(5, 0x7F); //0x7F + 1 = 0x80, n flag (bit 7) gets set
        cpu.INC(testInstruction);
        assert(ram.read(5) == cast(ubyte)(0x7F + 1));
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 1);
        assert(cpu._cycleCount == savedCycles + 5);
        //Case 2 mode 1, zero page, z is set, n is unset
        savedCycles = cpu._cycleCount;
        ram.write(cpu._registers.pc, 5); //zero page address 5
        ram.write(5, 0xFF); //0xFF + 1 = 0x00, z flag is set since result is zero
        cpu.INC(testInstruction);
        assert(ram.read(5) == cast(ubyte)(0xFF + 1));
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 5);
        //Case 3 mode 1, zero page, n is unset, z is unset
        savedCycles = cpu._cycleCount;
        ram.write(cpu._registers.pc, 5); //zero page address 5
        ram.write(5, 0x70); //0x70 + 1 = 0x70, z and n flags unset
        cpu.INC(testInstruction);
        assert(ram.read(5) == cast(ubyte)(0x70 + 1));
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 5);
        //Case 4 mode 2, zero page indexed, n is set z is unset
        testInstruction = decoder.getInstruction(0xF6);
        savedCycles = cpu._cycleCount;
        ram.write(cpu._registers.pc, 5); //zero page address 5
        cpu._registers.x = 6; //index is 6
        ram.write(5+6, 0x7F); //0x7F + 1 = 0x80, n flag (bit 7) gets set
        cpu.INC(testInstruction);
        assert(ram.read(5+6) == cast(ubyte)(0x7F + 1));
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 1);
        assert(cpu._cycleCount == savedCycles + 6);
        //Case 5 mode 3, absolute, z is set, n is unset
        testInstruction = decoder.getInstruction(0xEE);
        savedCycles = cpu._cycleCount;
        ram.write16(cpu._registers.pc, 0x1234); //Absolute address 0x1234
        ram.write(0x1234, 0xFF); //0xFF + 1 = 0x00, z flag is set since result is zero
        cpu.INC(testInstruction);
        assert(ram.read(0x1234) == cast(ubyte)(0xFF + 1));
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 6);
        //Case 6 mode 4, absolute indexed, n is set, z is unset
        testInstruction = decoder.getInstruction(0xFE);
        savedCycles = cpu._cycleCount;
        ram.write16(cpu._registers.pc, 0x1234); //Absolute address 0x1234
        cpu._registers.x = 8; //index is 8
        ram.write(0x1234 + 8, 0x7F); //0x7F + 1 = 0x80, n flag (bit 7) gets set
        cpu.INC(testInstruction);
        assert(ram.read(0x1234 + 8) == cast(ubyte)(0x7F + 1));
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 1);
        assert(cpu._cycleCount == savedCycles + 7);
    }

    //Increment X register by 1
    //Affects Z and N flags
    private void INX(Instruction operation)
    {
        auto m = cast(ubyte)(++_registers.x);
        checkAndSetZero(m);
        checkAndSetNegative(m);
        _cycleCount += operation.baseCycleCount;
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Implied         INX            $E8      1     2
    */
    unittest
    {
        auto cpu = new MOS6502;
        auto ram = Console.ram;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0xE8);
        cpu.powerOn();
        //Case 1 mode 1, implied, n is set
        auto savedCycles = cpu._cycleCount;
        cpu._registers.x = 0x7F;
        cpu.INX(testInstruction);
        assert(cpu._registers.x == cast(ubyte)(0x7F + 1));
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 1);
        assert(cpu._cycleCount == savedCycles + 2);
        //Case 2 mode 1, implied, z is set
        savedCycles = cpu._cycleCount;
        cpu._registers.x = 0xFF;
        cpu.INX(testInstruction);
        assert(cpu._registers.x == cast(ubyte)(0xFF + 1));
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 2);

    }

    //Increment Y register by 1
    //Affects Z and N flags
    private void INY(Instruction operation)
    {
        auto m = cast(ubyte)(++_registers.y);
        checkAndSetZero(m);
        checkAndSetNegative(m);
        _cycleCount += operation.baseCycleCount;
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Implied         INY            $C8      1     2
    */
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto ram = Console.ram;
        auto testInstruction = decoder.getInstruction(0xC8);
        cpu.powerOn();
        //Case 1 mode 1, implied, n is set
        auto savedCycles = cpu._cycleCount;
        cpu._registers.y = 0x7F;
        cpu.INY(testInstruction);
        assert(cpu._registers.y == cast(ubyte)(0x7F + 1));
        assert(cpu._status.z == 0);
        assert(cpu._status.n == 1);
        assert(cpu._cycleCount == savedCycles + 2);
        //Case 2 mode 1, implied, z is set
        savedCycles = cpu._cycleCount;
        cpu._registers.y = 0xFF;
        cpu.INY(testInstruction);
        assert(cpu._registers.y == cast(ubyte)(0xFF + 1));
        assert(cpu._status.z == 1);
        assert(cpu._status.n == 0);
        assert(cpu._cycleCount == savedCycles + 2);

    }

    //Pushes A onto stacks, decrements SP by 1
    private void PHA(Instruction operation)
    {
        ushort stackAddress = cast(ushort)(_stackBaseAddress + _registers.sp);
        auto ram = Console.ram;
        ram.write(stackAddress, _registers.a);
        _registers.sp = cast(ubyte)(--_registers.sp);
        _cycleCount += operation.baseCycleCount;
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Implied         PHA            $48      1     3
    */
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto ram = Console.ram;
        auto savedSp = cpu._registers.sp;
        auto testInstruction = decoder.getInstruction(0x48);
        cpu.powerOn();
        //Case 1 mode 1, sp = FF
        auto savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0xFF;
        cpu._registers.a = 0xAB;
        cpu.PHA(testInstruction);
        assert(cpu._registers.sp == 0xFE);
        assert(ram.read(cast(ushort)(cpu._stackBaseAddress + cpu._registers.sp + 1)) == 0xAB);
        assert(cpu._cycleCount == savedCycles + 3);
        //Case 2 mode 1, sp = 0, wraparound to 0xFF
        savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0x00;
        cpu._registers.a = 0xCD;
        cpu.PHA(testInstruction);
        assert(cpu._registers.sp == 0xFF);
        assert(ram.read(cast(ushort)(cpu._stackBaseAddress + cast(ubyte)(cpu._registers.sp + 1))) == 0xCD);
        assert(cpu._cycleCount == savedCycles + 3);
    }

    //Pushes _status register onto stacks, decrements SP by 1
    private void PHP(Instruction operation)
    {
        ushort stackAddress = cast(ushort)(_stackBaseAddress + _registers.sp);
        auto ram = Console.ram;
        ram.write(stackAddress, _status.asWord);
        _registers.sp = cast(ubyte)(--_registers.sp);
        _cycleCount += operation.baseCycleCount;
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Implied         PHP            $08      1     3
    */
    unittest
    {
        auto cpu = new MOS6502;
        auto ram = Console.ram;
        auto savedSp = cpu._registers.sp;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x08);
        cpu.powerOn();
        //Case 1 mode 1, sp = FF
        auto savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0xFF;
        cpu._status.asWord = 0xAB;
        cpu.PHP(testInstruction);
        assert(cpu._registers.sp == 0xFE);
        assert(ram.read(cast(ushort)(cpu._stackBaseAddress + cpu._registers.sp + 1)) == 0xAB);
        assert(cpu._cycleCount == savedCycles + 3);
        //Case 2 mode 1, sp = 0, wraparound to 0xFF
        savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0x00;
        cpu._status.asWord = 0xCD;
        assert(cpu._status.asWord == (0xCD | 0b0010_0000)); //writing to _status register will always cause bit 6 to be set
        cpu.PHP(testInstruction);
        assert(cpu._registers.sp == 0xFF);
        assert(ram.read(cast(ushort)(cpu._stackBaseAddress + cast(ubyte)(cpu._registers.sp + 1))) == (0xCD | 0b0010_0000));
        assert(cpu._cycleCount == savedCycles + 3);
    }

    //Pulls/pops A off the stacks (and into A), increments SP by 1
    //Affects N and Z flags
    private void PLA(Instruction operation)
    {
        _registers.sp = cast(ubyte)(++_registers.sp);
        ushort stackAddress = cast(ushort)(_stackBaseAddress + _registers.sp);
        auto ram = Console.ram;
        _registers.a = ram.read(stackAddress);
        checkAndSetZero(_registers.a);
        checkAndSetNegative(_registers.a);
        _cycleCount += operation.baseCycleCount;
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Implied         PLA            $68      1     4
    */
    unittest
    {
        import std.stdio;

        auto cpu = new MOS6502;
        auto ram = Console.ram;
        auto savedSp = cpu._registers.sp;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x68);
        cpu.powerOn();
        //Case 1 mode 1, sp = FF
        auto savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0xFF;
        cpu._registers.a = 0x00;
        cpu.pushStack(0xAB);
        assert(cpu._registers.sp == 0xFE);
        cpu.PLA(testInstruction);
        assert(cpu._registers.sp == 0xFF);
        assert(cpu._registers.a == 0xAB);
        assert(cpu._cycleCount == savedCycles + 4);
        //Case 2 mode 1, sp = 0, wraparound to 0xFF and then back to 0
        savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0x00;
        cpu._registers.a = 0x00;
        cpu.pushStack(0xCD);
        assert(cpu._registers.sp == 0xFF);
        cpu.PLA(testInstruction);
        assert(cpu._registers.sp == 0x00);
        assert(cpu._registers.a == 0xCD);
        assert(cpu._cycleCount == savedCycles + 4);
    }

    //Pulls/pops _status register off the stacks (and into P), increments SP by 1
    private void PLP(Instruction operation)
    {
        _registers.sp = cast(ubyte)(++_registers.sp);
        ushort stackAddress = cast(ushort)(_stackBaseAddress + _registers.sp);
        auto ram = Console.ram;
        _status.asWord = ram.read(stackAddress);
        _cycleCount += operation.baseCycleCount;
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Implied         PLP            $28      1     4
    */
    unittest
    {
        auto cpu = new MOS6502;
        auto ram = Console.ram;
        auto decoder = cpu._decoder;
        auto savedSp = cpu._registers.sp;
        auto testInstruction = decoder.getInstruction(0x28);
        cpu.powerOn();
        //Case 1 mode 1, sp = FF
        auto savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0xFF;
        cpu._status.asWord = 0x00;
        cpu.pushStack(0xAB);
        assert(cpu._registers.sp == 0xFE);
        cpu.PLP(testInstruction);
        assert(cpu._registers.sp == 0xFF);
        assert(cpu._status.asWord == 0xAB);
        assert(cpu._cycleCount == savedCycles + 4);
        //Case 2 mode 1, sp = 0, wraparound to 0xFF and then back to 0
        savedCycles = cpu._cycleCount;
        cpu._registers.sp = 0x00;
        cpu._status.asWord = 0x00;
        cpu.pushStack(0xCD);
        assert(cpu._registers.sp == 0xFF);
        cpu.PLP(testInstruction);
        assert(cpu._registers.sp == 0x00);
        assert(cpu._status.asWord == (0xCD | 0b0010_0000)); //writing to _status register will always cause bit 6 to be set
        assert(cpu._cycleCount == savedCycles + 4);
    }

    //Rotates a byte by shifting to the left 1 bit. Carry flag is placed into bit 0, Bit 7 is placed into carry flag, and bit 6 is placed
    //into negative flag, and sets z flag with the result of the rotate
    private void ROL(Instruction operation)
    {
        auto addressMode     = operation.addressingMode;

        auto ram = Console.ram;

        ushort operand; // operand for non accumulator modes

        if(addressMode == Decoder.AddressingMode.ACCUMULATOR)
        {
            auto carry = _status.c;
            _status.c = cast(bool)(_registers.a & 0x80); //copy bit 7 into carry
            _status.n = cast(bool)(_registers.a & 0x40); //copy bit 6 into negative
            _registers.a <<= 1; //shift a left by 1 bit (bit 0 should be 1 now)
            _registers.a |= carry; //copy carry to bit 0
            checkAndSetZero(_registers.a);
        }
        else //TODO // (phew)  - bittwiddler1
        {
            operand = operation.fetchOperand();
        }
    }
    /*  Address Mode    Syntax        Opcode  I-Len  T-Cnt
        Accumulator     ROL A          $2A      1    2
        Zero Page       ROL $A5        $26      2    5
        Zero Page,X     ROL $A5,X      $36      2    6
        Absolute        ROL $A5B6      $2E      3    6
        Absolute,X      ROL $A5B6,X    $3E      3    7
    */
    unittest //TODO
    {
    }

    //***** Addressing Modes *****//
    // Immediate address mode is the operand is a 1 byte constant following the
    // opcode so read the constant, increment pc by 1 and return it
    private ushort immediateAddressMode(Instruction operation)
    {
        return Console.ram.read(_registers.pc++);
    }
    unittest
    {
        ubyte result = 0;
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        cpu.powerOn();

        Console.ram.write(cpu._registers.pc+0, 0x7D);
        result = cast(ubyte)(cpu.immediateAddressMode(decoder.getInstruction(0x44)));
        assert(result == 0x7D);
        assert(cpu._registers.pc == 0xC001);
    }

    /* zero page address indicates that byte following the operand is an address
     * from 0x0000 to 0x00FF (256 bytes). this case we read the address
     * and return it
     *
     * zero page index address indicates that byte following the operand is an
     * address from 0x0000 to 0x00FF (256 bytes). this case we read the
     * address then offset it by the value a specified register (X, Y, etc)
     * when calling this function you must provide the value to be indexed by
     * for example an instruction that is STY Operand, Means we will take
     * operand, offset it by the value Y register
     * and correctly round it and return it as a zero page memory address */

    private ushort zeroPageAddressMode(Instruction operation)
    {
        ubyte address = Console.ram.read(_registers.pc++);
        ubyte offset = _decoder.decodeIndex(operation);
        ushort finalAddress = cast(ubyte)(address + offset);
        return finalAddress;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();
        auto decoder = cpu._decoder;
        // write address 0x7D to PC
        Console.ram.write(cpu._registers.pc, 0x7D);
        // zero page addressing mode will read address stored at cpu._registers.pc which is
        // 0x7D, then return the value stored ram at 0x007D which should be
        // 0x55
        assert(cpu.zeroPageAddressMode(decoder.getInstruction(0x65)) == 0x7D);
        assert(cpu._registers.pc == 0xC001);

        // set ram at PC to a zero page indexed address, indexing y register
        Console.ram.write(cpu._registers.pc, 0xFF);
        //set X register to 5
        cpu._registers.x = 5;
        // example STY will add operand to y register, and return that
        // FF + 5 = overflow to 0x04
        assert(cpu.zeroPageAddressMode(decoder.getInstruction(0x75)) == 0x04);
        assert(cpu._registers.pc == 0xC002);
        // set ram at PC to a zero page indexed address, indexing y register
        Console.ram.write(cpu._registers.pc, 0x10);
        //set X register to 5
        cpu._registers.y = 5;
        // example STY will add operand to y register, and return that
        assert(cpu.zeroPageAddressMode(decoder.getInstruction(0xB6)) == 0x15);
        assert(cpu._registers.pc == 0xC003);
    }

    /* zero page index address indicates that byte following the operand is an
     * address from 0x0000 to 0x00FF (256 bytes). this case we read the
     * address then offset it by the value a specified register (X, Y, etc)
     * when calling this function you must provide the value to be indexed by
     * for example an instruction that is
     * STY Operand, Y
     * Means we will take operand, offset it by the value Y register
     * and correctly round it and return it as a zero page memory address */
    /*ushort zeroPageIndexedAddressMode(string instruction, ubyte opcode)
    {
        ubyte indexValue = decodeIndex(instruction, opcode);
        ubyte address = Console.ram.read(_registers.pc++);
        address += indexValue;
        return address;
    } */

    /* for relative address mode we will calculate an adress that is
     * between -128 to +127 from the PC + 1
     * used only for branch instructions
     * fi_rst byte after the opcode is the relative offset as a
     * signed byte. the offset is calculated from the position after the
     * operand so it is actuality -126 to +129 from where the opcode
     * resides */
    private ushort relativeAddressMode(Instruction operation)
    {
        byte offset = cast(byte)(Console.ram.read(_registers.pc++));
        //int finalAddress = (cast(int)_registers.pc + offset);
        ushort finalAddress = cast(ushort)((_registers.pc) + offset);

        checkPageCrossed(_registers.pc, finalAddress);
        return cast(ushort)(finalAddress);
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x10); // BPL
        ushort result = 0;
        cpu.powerOn();
        // Case 1 & 2 : Relative Addess forward
        // relative offset will be +1
        Console.ram.write(cpu._registers.pc, 0x01);
        result = cpu.relativeAddressMode(decoder.getInstruction(0x10)); // parameters dont matter
        assert(cpu._registers.pc == 0xC001);
        assert(result == 0xC002);
        //relative offset will be +3
        Console.ram.write(cpu._registers.pc, 0x03);
        result = cpu.relativeAddressMode(testInstruction);
        assert(cpu._registers.pc == 0xC002);
        assert(result == 0xC005);
        // Case 3: Relative Addess backwards
        // relative offset will be -6 from 0xC003
        // offset is from 0xC003 because the address mode
        // decode function increments PC by 1 before calculating
        // the final position
        ubyte off = cast(ubyte)-6;
        Console.ram.write(cpu._registers.pc, off );
        result = cpu.relativeAddressMode(testInstruction);
        assert(cpu._registers.pc == 0xC003);
        assert(result == 0xBFFD);
        // Case 4: Relative address backwards underflow when PC = 0
        // Result will underflow as 0 - 6 = -6 =
        cpu._registers.pc = 0x0;
        Console.ram.write(cpu._registers.pc, off);
        result = cpu.relativeAddressMode(testInstruction);
        assert(result == 0xFFFB);
        // Case 5: Relative address forwards oferflow when PC = 0xFFFE
        // and address is + 2
        cpu._registers.pc = 0xFFFE;
        Console.ram.write(cpu._registers.pc, 0x02);
        result = cpu.relativeAddressMode(testInstruction);
        assert(result == 0x01);
    }

    //absolute address mode reads 16 bytes so increment pc by 2
    private ushort absoluteAddressMode(Instruction operation)
    {
        ushort address = Console.ram.read16(_registers.pc);
        ubyte offset = _decoder.decodeIndex(operation);
        auto finalAddress = cast(ushort)(address + offset);

        checkPageCrossed(address, finalAddress);
        _registers.pc += 0x2;
        return finalAddress;
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0xCD);

        ushort result = 0;
        cpu.powerOn();

        // Case 1: Absolute addressing is dead-simple. The argument of the
        // this case is the address stored the next two byts.

        // write address 0x7D00 to PC
        Console.ram.write16(cpu._registers.pc, 0x7D00);

        result = cpu.absoluteAddressMode(testInstruction);
        assert(result == 0x7D00);
        assert(cpu._registers.pc == 0xC002);

        // Case 2: Absolute indexed addressing is dead-simple. The argument of the
        // this case is the address stored the next two bytes, which is added
        // to third argument which the index, which is usually X or Y register
        // write address 0x7D00 to PC
        testInstruction = decoder.getInstruction(0xD9); //CMP, Absolute_Y
        Console.ram.write16(cpu._registers.pc, 0x7D00);
        cpu._registers.y = 5;
        result = cpu.absoluteAddressMode(testInstruction);
        assert(result == 0x7D05);
        assert(cpu._registers.pc == 0xC004);
    }

    /* absolute indexed address mode reads 16 bytes so increment pc by 2
    private ushort absoluteIndexedAddressMode(Instruction operation)
    {
        ubyte indexType = _addressModeTable[opcode] & 0xF;
        ubyte indexValue = decodeIndex(instruction, opcode);

        ushort data = Console.ram.read16(_registers.pc);
        _registers.pc += 0x2;
        data += indexValue;
        return data;
    }
    unittest
    {
        auto cpu = new MOS6502;
        ushort result = 0;
        cpu.powerOn();

        // Case 1: Absolute indexed addressing is dead-simple. The argument of the
        // this case is the address stored the next two bytes, which is added
        // to third argument which the index, which is usually X or Y register
        // write address 0x7D00 to PC
        Console.ram.write16(cpu._registers.pc, 0x7D00);
        cpu._registers.y = 5;
        result = cpu.absoluteIndexedAddressMode(cpu._registers.y);
        assert(result == 0x7D05);
        assert(cpu._registers.pc == 0xC002);
    } */

    private ushort  indirectAddressMode(Instruction operation)
    {
        ushort effectiveAddress = Console.ram.read16(_registers.pc);
        ushort returnAddress = Console.ram.buggyRead16(effectiveAddress); // does not increment _registers.pc

        _registers.pc += 0x2;  // increment program counter for fi_rst read16 op
        return returnAddress;
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0x6C);
        cpu.powerOn();

        // Case1: Straightforward indirection.
        // Argument is an address contianing an address.
        Console.ram.write16(cpu._registers.pc, 0x0D10);
        Console.ram.write16(0x0D10, 0x1FFF);
        assert(cpu.indirectAddressMode(testInstruction) == 0x1FFF);
        assert(cpu._registers.pc == 0xC002);

        // Case 2:
        // 6502 has a bug with the JMP instruction indirect mode. If
        // the argument is $10FF, it will read the lower byte as $FF, and
        // then fail to increment the higher byte from $10 to $11,
        // resulting a read from $1000 rather than $1100 when loading the
        // second byte

        // Place the high and low bytes of the operand the proper places;
        Console.ram.write(0x10FF, 0x55); // low byte
        Console.ram.write(0x1000, 0x7D); // misplaced high byte

        // Set up the program counter to read from $10FF and trigger the "bug"
        Console.ram.write16(cpu._registers.pc, 0x10FF);

        assert(cpu.indirectAddressMode(testInstruction) == 0x7D55);
        assert(cpu._registers.pc == 0xC004);
    }

    // indexed indirect mode is a mode where the byte following the opcode is a zero page address
    // which is then added to the X register (passed in). This memory address will then be read
    // to get the final memory address and returned
    // This mode does zero page wrapping
    // Additionally it will read the target address as 16 bytes
    private ushort indexedIndirectAddressMode(Instruction operation)
    {
        ubyte zeroPageAddress = Console.ram.read(_registers.pc++);
        ubyte targetAddress = cast(ubyte)(zeroPageAddress + _registers.x);
        //return Console.ram.read16(cast(ushort)targetAddress);
        return targetAddress;
    }
    unittest
    {

        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0xC1);
        cpu.powerOn();
        // Case 1 : no zero page wrapping
        //write zero page addres 0x0F to PC
        Console.ram.write(cpu._registers.pc, 0x0F);
        //indexed indirect with an idex of 7 will produce: 0x0F + 0x7 = 0x16
        cpu._registers.x = 0x7;
        ushort address = cpu.indexedIndirectAddressMode(testInstruction);
        assert(address == 0x16);

        // Case 1 : zero page wrapping
        //write zero page addres 0xFF to PC
        Console.ram.write(cpu._registers.pc, 0xFF);
        //indexed indirect with an idex of 7 will produce: 0xFF + 0x7 = 0x06
        cpu._registers.x = 0x7;
        address = cpu.indexedIndirectAddressMode(testInstruction);
        assert(address == 0x06);

    }

    // indirect indexed is similar to indexed indirect, except the index offset
    // is added to the final memory value instead of to the zero page address
    // so this mode will read a zero page address as the next byte after the
    // operand, look up a 16 bit value the zero page, add the index to that
    // and return it as the final address. note that there is no zero page
    // address wrapping
    private ushort indirectIndexedAddressMode(Instruction operation)
    {
        ubyte zeroPageAddress = Console.ram.read(_registers.pc++);
        ushort targetAddress = Console.ram.read16(cast(ushort) zeroPageAddress);
        return cast(ushort) (targetAddress + _registers.y);
    }
    unittest
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto testInstruction = decoder.getInstruction(0xD1);
        cpu.powerOn();
        // Case 1 : no wrapping around address space
        //write zero page addres 0x0F to PC
        Console.ram.write(cpu._registers.pc, 0x0F);
        //write address 0xCDAB to zero page addres 0x0F and 0x10
        Console.ram.write(0x0F, 0xAB);
        Console.ram.write(0x10, 0xCD);
        //indirect indexed with an idex of 7
        cpu._registers.y = 0x7;
        ushort address = cpu.indirectIndexedAddressMode(testInstruction);
        assert(address == 0xCDAB + 0x7);
        // Case 2 : wrapping around the 16 bit address space
        //write zero page addres 0x0F to PC
        Console.ram.write(cpu._registers.pc, 0x0F);
        //write address 0xFFFE to zero page addres 0x0F and 0x10
        Console.ram.write(0x0F, 0xFE);
        Console.ram.write(0x10, 0xFF);
        //indirect indexed with an idex of 7
        cpu._registers.y = 0x7;
        address = cpu.indirectIndexedAddressMode(testInstruction);
        assert(address == cast(ushort)(0xFFFE + 7));
    }

    private void setNmi()
    {
        _nmi = true;
    }

    private void setReset()
    {
        _rst = true;
    }

    private void setIrq()
    {
        _irq = true;
    }

    //pushes a byte onto the stack, decrements stack pointer
    private void pushStack(ubyte data)
    {
        ushort stackAddress = cast(ushort)(_stackBaseAddress + _registers.sp);
        //add some logic here to possibly check for stack overflow conditions
        Console.ram.write(stackAddress, data);
        _registers.sp--;
    }
    unittest
    {
    }
    //increments stack pointer and returns the byte from the top of the stack
    private ubyte popStack()
    {
        //remember sp points to the next EMPTY stack location so we increment SP fi_rst
        //to get to the last stack value
        _registers.sp++;
        ushort stackAddress = cast(ushort)(_stackBaseAddress + _registers.sp);
        return Console.ram.read(stackAddress);
    }
    unittest
    {
    }

    private void checkPageCrossed(ushort startingAddress, ushort finalAddress)
    {
        ubyte pageOne = (startingAddress >> 8) & 0x00FF;
        ubyte pageTwo = (finalAddress >> 8) & 0x00FF;

        _pageBoundaryWasCrossed = (pageOne != pageTwo);
    }
    unittest
    {
        auto cpu = new MOS6502;
        assert(cpu._pageBoundaryWasCrossed  == false);

        cpu.checkPageCrossed(0x00FF, 0x0100);
        assert(cpu._pageBoundaryWasCrossed == true);
        cpu.checkPageCrossed(0x00FF, 0x00FF);
        assert(cpu._pageBoundaryWasCrossed  == false);
        cpu.checkPageCrossed(0x0000, 0x00FF);
        assert(cpu._pageBoundaryWasCrossed  == false);
        cpu.checkPageCrossed(0x0000, 0x0100);
        assert(cpu._pageBoundaryWasCrossed  == true);
    }

    // @TODO: move to decoder
    private bool isIndexedMode(ubyte opcode)
    {
       return isIndexedMode(_decoder.getInstruction(opcode));
    }

    private bool isIndexedMode(Instruction operation)
    {
        auto opcode = operation.asByte;
        ubyte addressType = cast(ubyte)(operation.addressingMode);
        ubyte lowerNybble = addressType & 0xF;

        if (addressType == Decoder.AddressingMode.IMMEDIATE) return false;

        return (lowerNybble != 0);
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.powerOn();

        assert(cpu.isIndexedMode(0x6D) == false); // ADC, Absolute
        assert(cpu.isIndexedMode(0x7D) == true);  // ADC, Absolute,X
        assert(cpu.isIndexedMode(0x79) == true);  // ADC, Absolute, Y
    }

    //checks the value to see if we need to set the negative flag
    //by checking bit 7
    private void checkAndSetNegative(byte value)
    {
        if(value & 0x80) //if bit 7 is set then negative flag is set
            _status.n = 1;
        else
            _status.n = 0;
    }
    unittest
    {
        auto cpu = new MOS6502;

        cpu.checkAndSetNegative(5);
        assert(cpu._status.n == 0);
        cpu.checkAndSetNegative(-5);
        assert(cpu._status.n == 1);
        cpu.checkAndSetNegative(45);
        assert(cpu._status.n == 0);
    }

    //checks the value to see if it's zero and sets zero flag appropriately
    private void checkAndSetZero(byte value)
    {
        if(value == 0 )
            _status.z = 1;
        else
            _status.z = 0;
    }
    unittest
    {
        auto cpu = new MOS6502;
        cpu.checkAndSetZero(5);
        assert(cpu._status.z == 0);
        cpu.checkAndSetZero(-5);
        assert(cpu._status.z == 0);
        cpu.checkAndSetZero(0);
        assert(cpu._status.z == 1);
    }

    // Emulator state variables
    private ulong _cycleCount;    // total cycles executed
    private bool _pageBoundaryWasCrossed;
    package Decoder _decoder;

    // hardware implementation variables
    private Registers _registers;
    private StatusRegister _status; // Stored as a bit-field

    private bool _nmi; // non maskable interrupt line
    private bool _rst; // reset interrupt line
    private bool _irq; //software interrupt request line

    private immutable ushort _nmiAddress = 0xFFFA;
    private immutable ushort _resetAddress = 0xFFFC;
    private immutable ushort _irqAddress = 0xFFFE;
    private immutable ushort _stackBaseAddress = 0x0100;
    private immutable ushort _stackTopAddress = 0x01FF;
}
