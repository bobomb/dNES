module memory.imemory;

public interface IMemory
{
    ubyte  read  (ushort address);
    ushort read16(ushort address);
    
    void write(ushort address, ubyte value);
    void write16(ushort address, ushort value);
}
