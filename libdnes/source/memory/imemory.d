module memory.imemory;

public interface IMemory
{
    public ubyte  read  (ushort address);
    public ushort read16(ushort address);
   
    void write(uint address, ubyte value);
    public void write(ushort address, ubyte value);
    public void write16(ushort address, ushort value);
    void write16(uint  address, ushort value); 
}
