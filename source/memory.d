import std.bitmanip;

class Memory
{
	ubyte[0x10000] data; // 16KiB addressing range

	unittest
	{
		import std.algorithm;
		auto mem = new Memory;
		auto value = sum!(ubyte[])(mem.data);

		assert(value == 0); 
	}

	ubyte[] read(ubyte address, ubyte length=1)
	{
		uint start = address;
		uint end   = address + length;

		return data[start..end];
	}
	unittest 
	{
		auto mem = new Memory;

		mem.data[0..4] = [ 0x00, 0xC0, 0xFF, 0xEE ];

		auto result = mem.read(0x1, 0x2);
		assert(result[0..2] ==  [ 0xC0, 0xFF ]);

		result = mem.read(0x0, 0x4);
		assert(result[0..4] == mem.data[0..4]);
	}
	
	void write(ushort address, ubyte value)
	{
		data[address] = value;
	}

	unittest
	{
		auto mem = new Memory;
		mem.write(0xB00B, 0xB0);
		mem.write(0xB00C, 0x0B);

		assert(mem.data[0xB00B..0xB00D] == [ 0xB0, 0x0B]);
	}

	void  write(ushort address, ubyte[] values)
	{
		auto start = address;
		auto end   = address + (cast(ushort)values.length);

		data[start..end] = values;
	}

	unittest
	{
		auto mem = new Memory;
		mem.write(0xB00B, [0xB0, 0x0B]);
	
		assert(mem.data[0xB00B..0xB00D] == [ 0xB0, 0x0B]);
	}
}
