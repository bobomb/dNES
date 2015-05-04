import std.stdio;
import std.algorithm;

import libdnes;

int main(string[] argv)
{
    writeln("Hello D-World!");
    ubyte[0x10000] data;
    int stuff = sum!(ubyte[])(data[0..$]);
    return 0;
}

int addStuff(int a, int b)
{
    return a + b;
}

unittest
{
    auto result = addStuff(1, 2);
    assert(result == 3);
}

// ex :set foldmethod=marker foldmarker=@region,@endregion expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
