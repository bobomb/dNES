/* cpu.d
 * Emulation code for the MOS5602 CPU.
 * Copyright (c) 2015 dNES Team.
 * License: GPL 3.0
 */
module cpu.exceptions;

import core.stdc.stdio;
import std.format;
import std.array;

class InvalidOpcodeException : Exception
{
    this(ubyte opcode)
    {
        auto writer = appender!string();
        formattedWrite(writer, "An invalid opcode was encountered: %#x",
                                                                    opcode);
        super(writer.data);
    }    
}


class InvalidAddressingModeException : Exception
{
    this(string instruction, ubyte opcode)
    {
        auto writer = appender!string();
        formattedWrite(writer, "Decoded opcode %#x ", opcode);
        formattedWrite(writer, "as '%s' but was unable to ", instruction);
        formattedWrite(writer, "determine addressing mode");
        super(writer.data);
    }    
}


class InvalidAddressIndexException : Exception
{
    this(string instruction, ubyte opcode)
    {
        auto writer = appender!string();
        formattedWrite(writer, "Decoded opcode %#x ", opcode);
        formattedWrite(writer, "as '%s' but was unable to ", instruction);
        formattedWrite(writer, "determine proper indexed addressing mode index");
        super(writer.data);
    }    
}

// ex: set foldmethod=syntax foldlevel=1 expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
