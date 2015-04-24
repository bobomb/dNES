/* RAM.d
 * Emulation code for NES ROM/RAM. Interacts with classes implementing 
 * IRAMMapper to simulate different RAM mappers.
 * Copyright (c) 2015 dNES Team.
 * License: GPL 3.0
 */
module memory.ram;

import memory.imemory;

class RAM : IMemory
{
    ubyte[0x10000] data; // 16KiB addressing range

    // @region unittest: RAM initialization
    unittest
    {
        import std.algorithm;
        auto mem = new RAM;

        // verify data is all 0s at the start
        auto value = sum!(ubyte[])(mem.data);

        assert(value == 0); 
    }
    //@endregion

    ubyte read(ushort address)
    { 
        return data[address];
    }
    // @region unittest read(ubyte, ubyte)
    unittest 
    {
        auto mem = new RAM;
        mem.data[0] = 0x00;
        mem.data[1] = 0xC0;
        mem.data[2] = 0xFF;
        mem.data[3] = 0xEE;

        auto result = mem.read(0x01);
        assert(result ==  0xC0);
        
        result = mem.read(0x03);
        assert(result ==  0xEE);
    }
    //@endregion


    ubyte[] read(ushort address, ubyte length)
    {
        auto start = address;
        auto end   = address + length;

        return data[start..end];
    }
    // @region unittest read(ubyte, ubyte)
    unittest 
    {
        auto mem = new RAM;

        mem.data[0..4] = [ 0x00, 0xC0, 0xFF, 0xEE ];
        auto result = mem.read(0x1, 0x2);
        assert(result[0..2] ==  [ 0xC0, 0xFF ]);

        result = mem.read(0x0, 0x4);
        assert(result[0..4] == mem.data[0..4]);
    }
    //@endregion
    
    void write(ushort address, ubyte value)
    {
        data[address] = value;
    }
    //@region unittest write(ushort, ubyte)
    unittest
    {
        auto mem = new RAM;
        mem.write(0xB00B, 0xB0);
        mem.write(0xB00C, 0x0B);

        assert(mem.data[0xB00B..0xB00D] == [ 0xB0, 0x0B]);
    }
    //@endregion

    void  write(ushort address, ubyte[] values)
    {
        auto start = address;
        auto end   = address + (cast(ushort)values.length);

        data[start..end] = values;
    }
    // @region unittest write(ushort,ubyte[])
    unittest
    {
        auto mem = new RAM;
        mem.write(0xB00B, [0xB0, 0x0B]);
    
        assert(mem.data[0xB00B..0xB00D] == [ 0xB0, 0x0B]);
    }
    //@endregion
}


// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
