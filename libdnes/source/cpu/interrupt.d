module cpu.interrupt;

class Interrupt
{
    immutable ushort nmiAddress = 0xFFFA;
    immutable ushort resetAddress = 0xFFFC;
    immutable ushort irqAddress = 0xFFFE;

    @safe nothrow this()
    {
        irq = false;
        nmi = false;
        reset = false;
    }

    private
    {
        bool irq;
        bool nmi;
        bool reset;
    }
}