module memory.imemory;

public interface IMemory
{
    ubyte   read(ushort address);
    ubyte[] read(ushort address, ubyte length);
    void write(ushort address, ubyte value);
    void  write(ushort address, ubyte[] values);
}