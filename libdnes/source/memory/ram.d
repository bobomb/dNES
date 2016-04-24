// vim: set foldmethod=marker foldmarker=@fold,endfold textwidth=80 ts=4 sts=4 expandtab autoindent smartindent cindent ft=d :
/* ram.d
 * Copyright © 2015-2016 dNES Team. All Rights Reserved.
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
module memory.ram;

import memory.imemory;

class RAM : IMemory
{
    public this()
    {
        for (int i = 0; i != _data.length; ++i) {
            _data[i] = 0xFF;
        }

        _data[0x0008] = 0xF7;
        _data[0x0009] = 0xEF;
        _data[0x000a] = 0xDF;
        _data[0x000f] = 0xBF;

        _data[0x4017] = 0;
        _data[0x4015] = 0;
        for (int i = 0x4000; i <= 0x400F; ++i)
        {
            _data[i] = 0;
        }
    }
    unittest
    {
        auto mem = new RAM;
        for (int i = 0; i != mem._data.length; ++i) {
            switch (i)
            {
            case 0x0008:
                assert(mem._data[i] == 0xF7);
                break;
            case 0x0009:
                assert(mem._data[i] == 0xEF);
                break;
            case 0x000A:
                assert(mem._data[i] == 0xDF);
                break;
            case 0x000F:
                assert(mem._data[i] == 0xBF);
                break;
            case 0x4000:
            case 0x4001:
            case 0x4002:
            case 0x4003:
            case 0x4004:
            case 0x4005:
            case 0x4006:
            case 0x4007:
            case 0x4008:
            case 0x4009:
            case 0x400A:
            case 0x400B:
            case 0x400C:
            case 0x400D:
            case 0x400E:
            case 0x400F:
            case 0x4015:
            case 0x4017:
                assert(mem._data[i] == 0x00);
                break;
            default:
                assert(mem._data[i] == 0xFF);
                break;
            }
        }
    }

    public ubyte read(ushort address)
    {
        return _data[address];
    }
    unittest
    {
        auto mem = new RAM;
        mem._data[0..4] = [ 0x00, 0xC0, 0xFF, 0xEE ];

        auto result = mem.read(0x01);
        assert(result ==  0xC0);

        result = mem.read(0x03);
        assert(result ==  0xEE);
    }

    // performs a 16 bit read on a memory address. Low byte is read first,
    // high-byte second
    public ushort read16(ushort address)
    {
        return ((_data[address+1] << 8) | _data[address]);
    }
    unittest
    {
        auto mem = new RAM;

        mem._data[0..4] = [ 0x00, 0xC0, 0xFF, 0xEE ];
        auto result = mem.read16(0x1);
        assert(result == 0xFFC0 );

        result = mem.read16(0x0);
        assert(result == 0xC000);
    }

    // 6502 has a bug with indirect mode.
    // If the argument is $10FF, it will read the lower byte as $FF, and
    // then fail to increment the higher byte from $10 to $11,
    // resulting in a read from $1000 rather than $1100 when loading the
    // upper byte
    public ushort buggyRead16(ushort address)
    {
        import std.stdio;
        ushort returnValue = 0;

        if ((address & 0x00FF) == 0x00FF)  // If at a page boundary..
        {
            ubyte low = read(address);
            ubyte high = read(address & 0xFF00); // wraparound
            returnValue = ((high << 8) | low);
        }
        else
        {
            returnValue = read16(address);
        }
        return returnValue;
    }
    unittest
    {
        import std.stdio;
        auto mem = new RAM;

        mem._data[0..4] = [ 0x01, 0xC0, 0xFF, 0xEE ];
        mem._data[0xFF..0x101] = [0xF0, 0x44];

        auto result = mem.buggyRead16(0x1);
        assert(result == 0xFFC0 );

        result = mem.buggyRead16(0x00FF);
        assert(result == 0x01F0);
    }


    public void write(ushort address, ubyte value)
    {
        _data[address] = value;
    }
    unittest
    {
        auto mem = new RAM;
        mem.write(0xB00B, 0xB0);
        mem.write(0xB00C, 0x0B);

        assert(mem._data[0xB00B..0xB00D] == [ 0xB0, 0x0B]);
    }


    //write16 will take in a big endian 16 bit value
    //and write it to the NES in little endian form
    public void  write16(ushort address, ushort value)
    {
        _data[address+1] = cast(ubyte)((value & 0xFF00) >> 8);
        _data[address] = cast(ubyte)(value & 0x00FF);
    }
    unittest
    {
        auto mem = new RAM;
        mem.write16(cast(ushort)(0xB00B), cast(ushort)(0xB00B));

        assert(mem._data[0xB00B] == 0x0B);
        assert(mem._data[0xB00C] == 0xB0);
    }


    // Dlang does not automatically convert small int literals to ushort without
    // a cast, which is stupid. Writing an overload to make the API cleaner. -_-
    public void write(uint address, ubyte value)
    {
        write(cast(ushort)(address & 0x0000FFFF), value);
    }
    unittest
    {
        auto mem = new RAM;
        mem.write(0xB00B, 0xB0);
        mem.write(0xB00C, 0x0B);

        assert(mem._data[0xB00B..0xB00D] == [ 0xB0, 0x0B]);
    }


    public void  write16(uint address, ushort value)
    {
        this.write16(cast(ushort)(address), value);
    }
    unittest
    {
        auto mem = new RAM;
        mem.write16(0xB00B, 0xB00B);

        assert(mem._data[0xB00B] == 0x0B);
        assert(mem._data[0xB00C] == 0xB0);
    }

    private ubyte[0x10000] _data; // 16KiB addressing range

}

