/* cpu/stackregister.d
 * submodule for the NES status register. Needed to hide data.
 * Copyright (c) 2015 dNES Team.
 * License: LGPL 3.0
 */
module cpu.statusregister;

import std.bitmanip;

class StatusRegister
{
    // Insert getters/setters here

    private union  { 
        ubyte value;
        mixin(bitfields!(
            ubyte, "c", 1,   // carry flag
            ubyte, "z", 1,   // zero  flag
            ubyte, "i", 1,   // interrupt disable flag
            ubyte, "d", 1,   // decimal mode _status (unused in NES)
            ubyte, "b", 1,   // software interrupt flag (BRK)
            ubyte, "",  1,   // not used. Must be logical 1 at all times.
            ubyte, "v", 1,   // overflow flag
            ubyte, "s", 1)); // sign     flag
    }
}

// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
