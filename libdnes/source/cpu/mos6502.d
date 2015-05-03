/* cpu.d
 * Emulation code for the MOS5602 CPU.
 * Copyright (c) 2015 dNES Team.
 * License: GPL 3.0
 */

module cpu.mos6502;

import statusregister;

class MOS6502
{
    this()
    {
        status = new StatusRegister; 
    }

    ubyte a;  // accumulator
    ubyte x;  // x index
    ubyte y;  // y index
    ubyte pc; // program counter
    ubyte sp; // stack pointer
    StatusRegister status;

	void reset()
	{
		a = 0x00;
		x = 0x00;
		y = 0x00;
		pc = 0x00;
		sp = 0x00; //FIXME
	}
    
}



// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
