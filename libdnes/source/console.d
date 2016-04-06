// vim: set foldmethod=syntax foldlevel=1 expandtab ts=4 sts=4 expandtab sw=4 filetype=d :
/* console.d
 * Container used to simulate "bus" communication?
 * Copyright (c) 2015 dNES Team;
 * License: GPL 3.0
 */

import cpu.mos6502;
import memory;

class Console
{
    public this()
    {

    }

    public static void initialize()
    {
        processor  = new MOS6502();
        ram     = new RAM;
    }

    public void loadROM(string filename)
    {
        // open file handle
        // foreach byte, dump into memory
    }

    public void startEmulation()
    {
        this.processor.powerOn();
    }

    public void endEmulation()
    {
        this.memoryMapper = null;
        this.ram = null;
    }

    // @TODO: This doesnt necessarily have to be public. Just in case for now.
    public static MOS6502 processor;
    public static IMemory ram;
    public static IMemory memoryMapper;
}

// ex: set foldmethod=syntax foldlevel=1 expandtab ts=4 sts=4 expandtab sw=4 filetype=d :
