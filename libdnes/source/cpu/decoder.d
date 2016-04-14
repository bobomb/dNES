// vim: set foldmethod=marker foldmarker=@fold,endfold textwidth=80 ts=4 sts=4 expandtab autoindent smartindent cindent ft=d :
/* decoder.d
 * Copyright © 2016 dNES Team. All Rights Reserved.
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

module cpu.decoder;
// @fold  import directives
import cpu.mos6502;
import cpu.exceptions;
import console;
// @endfold

// Helper class to provide the error logging and debugging code enough @fold
// information to identify the instruction we are processing
// @endfold
public class Instruction // @fold
{
    private this(ubyte opcode)
    {
        _asByte = opcode;
    }

    public void execute()
    {
        _implementation(this);
    }

    public ushort fetchOperand()
    {
        return _addressModeDelegate(this);
    }
    // @fold --- Public Properties ---
    public @property void delegate(Instruction) implementation() //@fold
    {
        return _implementation;
    } //@endfold
    public @property ushort delegate(Instruction) addressModeDelegate() //@fold
    {
        return _addressModeDelegate;
    } //@endfold
    public @property string mnemonic() //@fold
    {
        return _mnemonic;
    } //@endfold
    public @property ubyte asByte() //@fold
    {
        return _asByte;
    } //@endfold
    public @property ubyte baseCycleCount() //@fold
    {
        return _baseCycleCount;
    } //@endfold
    public @property ubyte extraPageBoundaryCycles() //@fold
    {
        return _extraIndexingCycles;
    } //@endfold
    public @property ubyte extraIndexingCycles() //@fold
    {
        return _extraPageBoundaryCycles;
    } //@endfold

    public @property AddressingMode addressingMode()
    {
        return _addressingMode;
    }
    // @endfold
    // @fold --- Private Members ---
    private void delegate(Instruction) _implementation;
    private ushort delegate(Instruction) _addressModeDelegate;

    private string _mnemonic;
    private ubyte  _asByte;
    private AddressingMode _addressingMode;

    private ubyte  _baseCycleCount;
    private ubyte  _extraPageBoundaryCycles;
    private ubyte  _extraIndexingCycles;
    // @endfold
    // Helper class
    package enum AddressingMode : ubyte // @fold
    {
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
    } // @endfold
} // @endfold

class Decoder // @fold
{
    alias AddressingMode = Instruction.AddressingMode;
    this(MOS6502 cpu)
    {
        _cpu = cpu;
    }

    public Instruction getInstruction(ubyte opcode) // @fold
    {
        auto retval = new Instruction(opcode);
        _setValues(retval);

        return retval;
    } // @endfold
    unittest  // @fold
    {
        // @TODO: This test should challenge the ability of libdNES to decode
        // Instructions. Change this to a test where each instruction is decoded
        // and make it check against a list of valid instructions!

        import std.file, std.stdio;
        // Load a test ROM
        auto ROMBytes = cast(ubyte[])read("libdnes/specs/nestest.nes");
        auto cpu     = new MOS6502;
        auto decoder = cpu._decoder;

        cpu.powerOn();

        {
            ushort address = 0xC000;
            for (uint i = 0x10; i < ROMBytes.length; ++i) {
                Console.ram.write(address, ROMBytes[i]);
                ++address;
            }
        }

        auto decoded = decoder.getInstruction(cpu.fetch());

        auto resultFunc = decoded.implementation;
        void delegate(Instruction) expectedFunc = &(cpu.JMP);
        assert(resultFunc == expectedFunc);
    } // @endfold

    private void _setValues(Instruction input) //@fold
    {
        ubyte opcode = input._asByte;

        _setImplementation(input);
        input._baseCycleCount  = _cycleCountTable[input._asByte];
        _setAddressModeDelegate(input);
    } // @endfold
    unittest  // @fold _getAddressModeDelegate()
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto testInput = new Instruction(0x6C); // JMP

        decoder._setAddressModeDelegate(testInput);

        auto resultFunc = testInput.addressModeDelegate;
        auto expectedFunc = &(cpu.indirectAddressMode);
        assert(resultFunc == expectedFunc);
         // @todo
    } // @endfold

    

    /** Sets an Instruction's implementation delegate and assigns that
        function's name as the opcode's assembly mnemonic */
    private void _setImplementation(ref Instruction info) // @fold
    {
        auto opcode = info._asByte;

        switch (opcode) //@fold
        {
        //KIL
        case 0x2A:
            info._implementation = &_cpu.KIL;
            info._mnemonic = __traits(identifier, _cpu.KIL);
            break;
        // branch instrucitons
        
        // JMP
        case 0x4C:
        case 0x6C:
            info._implementation = &_cpu.JMP;
            info._mnemonic = __traits(identifier, _cpu.JMP);
            break;
        // ADC
        case 0x69:
        case 0x65:
        case 0x75:
        case 0x6D:
        case 0x7D:
        case 0x79:
        case 0x61:
        case 0x71:
            info._implementation = &_cpu.ADC;

            info._mnemonic = __traits(identifier, _cpu.ADC);
            break;
        case 0x29:
            info._implementation = &_cpu.AND;
            info._mnemonic = __traits(identifier, _cpu.AND);
            break;
        case 0x78:
            info._implementation = &_cpu.CLI;
            info._mnemonic = __traits(identifier, _cpu.CLI);
            break;
        case 0x88:
            info._implementation = &_cpu.DEY;
            info._mnemonic = __traits(identifier, _cpu.DEY);
            break;
        case 0xCA:
            info._implementation = &_cpu.DEX;
            info._mnemonic = __traits(identifier, _cpu.DEX);
            break;
        case 0xEA:
            info._implementation = &_cpu.NOP;
            info._mnemonic = __traits(identifier, _cpu.NOP);
            break;
        default:
            throw new InvalidOpcodeException(opcode);
        } // @endfold
    } // @endfold
    unittest // @fold _setImplementation
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;
        auto testInput = new Instruction(0x6C); // JMP

        decoder._setValues(testInput);

        auto resultFunc = testInput._implementation;
        void delegate(Instruction) expectedFunc = &(cpu.JMP);
        decoder._setImplementation(testInput);
         // @todo
    } // @endfold

    private void _setAddressModeDelegate(Instruction operation) // @fold
    {
        auto opcode = operation._asByte;
        auto addressMode = cast(AddressingMode)(_addressModeTable[opcode]);
        ushort delegate(Instruction) addressModeDelegate;

        switch (addressMode)
        {
        case AddressingMode.IMPLIED:
            addressModeDelegate = null;
            break;
        case AddressingMode.IMMEDIATE:
            addressModeDelegate = &_cpu.immediateAddressMode;
            break;
        case AddressingMode.ACCUMULATOR:
            goto case AddressingMode.IMPLIED;
        case AddressingMode.ZEROPAGE:
            addressModeDelegate = &(_cpu.zeroPageAddressMode);
            break;
        case AddressingMode.ZEROPAGE_X:
            goto case AddressingMode.ZEROPAGE;
        case AddressingMode.ZEROPAGE_Y:
            goto case AddressingMode.ZEROPAGE;
        case AddressingMode.RELATIVE:
            addressModeDelegate = &(_cpu.relativeAddressMode);
            break;
        case AddressingMode.ABSOLUTE:
            addressModeDelegate = &(_cpu.absoluteAddressMode);
            break;
        case AddressingMode.ABSOLUTE_X:
            goto case AddressingMode.ABSOLUTE;
        case AddressingMode.ABSOLUTE_Y:
            goto case AddressingMode.ABSOLUTE;
        case AddressingMode.INDIRECT:
            addressModeDelegate = &(_cpu.indirectAddressMode);
            break;
        case AddressingMode.INDEXED_INDIRECT:
            addressModeDelegate = &(_cpu.indexedIndirectAddressMode);
            break;
        case AddressingMode.INDIRECT_INDEXED:
            addressModeDelegate = &(_cpu.indirectIndexedAddressMode);
            break;
        default:
            throw new InvalidAddressingModeException(operation._mnemonic, opcode);
        }

        operation._addressingMode = addressMode;
        operation._addressModeDelegate = addressModeDelegate;
    }
    // @endfold
    unittest // @fold  _getAddressModeDelegate
    {
        auto cpu = new MOS6502;
        auto decoder = cpu._decoder;

        auto testInput = new Instruction(0x24);
        testInput._mnemonic = "KIL";

        // @TODO: implement all the test cases
        // Case 1: Implied & Accumulator
        // Case 2: Immediate
        // Case 3: Zero Page
        // Case 4: Absolute
        // Case 5: Indirect
        // Case 6: failure
        try
        {
             decoder._setAddressModeDelegate(testInput); // Invalid opcode

        }
        catch (InvalidAddressingModeException e)
        { /* this exception is expected; suppress it. */ }
    } // @endfold

    /** Private Data Members **/ // @fold
    private MOS6502 _cpu;

    private static immutable ubyte[256] _cycleCountTable = [
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


    private static immutable ubyte[256] _addressModeTable= [
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
        0x01,  0xF1,  0x00,  0xF2,  0xB0,  0xB0,  0xB0,  0xB0, // 4
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
// @endfold
} // @endfold
