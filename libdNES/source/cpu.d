/* cpu.d
 * Emulation code for the MOS5602 CPU.
 * Copyright (c) 2015 dNES Team.
 * License: LGPL 3.0
 */

import std.bitmanip;

class MOS6502
{
    //@region union StatusRegister
    union StatusRegister { 
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
    //@endregion

    ubyte a;  // accumulator
    ubyte x;  // x index
    ubyte y;  // y index
    ubyte pc; // program counter
    ubyte sp; // stack pointer
    StatusRegister _status;
	@property
	{
		StatusRegister status()
		{
			return _status;
		}

		StatusRegister status(StatusRegister newStatus)
		{
			if(newStatus.value & (1<<5))
			{
				//do we need handle this case where we are trying to set bit 5 to zero where it indicates it should be 1?
			}
			return _status = newStatus;
		}
	}

	void setCarry()
	{
		_status.c = 0x1;
	}

	void clearCarry()
	{
		_status.c = 0x0;
	}

	ubyte getCarry()
	{
		return _status.c;
	}
	unittest
	{
		auto cpu = new MOS6502;	
		cpu.setCarry();
		assert(cpu._status.c == 0x1);
		assert(cpu.getCarry() == 0x1);
		assert(cpu._status.z == 0x0 && cpu._status.i == 0x0 && cpu._status.d == 0x0 && 
			   cpu._status.b == 0x0 && cpu._status.v == 0x0 && cpu._status.s == 0x0 );
		cpu.clearCarry();
		assert(cpu._status.c == 0x0);
		assert(cpu.getCarry() == 0x0);
		assert(cpu._status.z == 0x0 && cpu._status.i == 0x0 && cpu._status.d == 0x0 && 
			   cpu._status.b == 0x0 && cpu._status.v == 0x0 && cpu._status.s == 0x0 );
	}
}

unittest
{
    auto cpu = new MOS6502;
    cpu._status.c = true;
    assert(cpu._status.value == 0x01);

    cpu._status.value = 0xFF;
    assert(cpu._status.c == 1 && cpu._status.z == 1 && cpu._status.i == 1 && 
           cpu._status.d == 1 && cpu._status.b == 1 && cpu._status.v == 1 && 
                                                     cpu._status.s == 1);
}

// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
