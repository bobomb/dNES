/* console.d
 * Container used to simulate "bus" communication?
 * Copyright (c) 2015 dNES Team;
 * License: GPL 3.0
 */

import cpu.mos6502;
import memory;

class Console
{
    this()
    {
        
    }

	static void initialize()
	{
		processor  = new MOS6502();
        memory     = new RAM;   
	}

    void loadROM(string filename)
    {
        // open file handle
        // foreach byte, dump into memory
    }

    void startEmulation()
    {
        this.processor.powercycle(); 
    }

    void endEmulation()
    {
        this.memory = null;
    }

    static MOS6502 processor;
    static RAM  memory;
}

// ex: set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
