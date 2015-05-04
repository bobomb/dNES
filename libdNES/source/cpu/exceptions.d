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
        formattedWrite(writer, "An invalid opcode was encountered: $%#d",
                                                                    opcode);
        super(writer.data);
    }    

}
// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
