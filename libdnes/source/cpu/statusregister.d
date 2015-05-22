/* cpu/stackregister.d
 * submodule for the NES status register. Needed to hide data.
 * Copyright (c) 2015 dNES Team.
 * License: GPL 3.0
 */
module cpu.statusregister;

import std.bitmanip;

class StatusRegister
{
    @safe nothrow this() 
    {
        _value = _immutableBits; // bit 6 must be logical 1 at all times. 
    }
    unittest
    {
        auto register = new StatusRegister;
        
        // Verify sixth, unused bit is where its supposed to be
        assert(register._unused == 0b1);

        // Verify that the bits are packed with correct endinanness
        register._value = 0b0010_0001;
        assert(register._c == 0b1);
        assert(register._n == 0b0);
        register._value = 0b1010_0000;
        assert(register._n == 0b1);
        assert(register._c == 0b0);
    } 

    
    @safe nothrow {

    @property ubyte value() { return this._value; }
    unittest 
    {
        auto register = new StatusRegister;
        assert(register.value() == _immutableBits);
    } 

    @property ubyte value(ubyte value) 
    {
        return _value = (value | _immutableBits);
    }
    unittest 
    {
        ubyte testInput = 0b1000_0110;
        auto register   = new StatusRegister;
        auto result     = register.value(testInput);

        /* CASE 1: Ensure the 6th bit cannot be overwritten */
        assert(result == register._value); // correct data was actually returned
        assert(result != testInput);    // data was set with modification
                                        // immutable bits were not changed
        assert((result & _immutableBits) == _immutableBits ); 
        assert( result == (testInput | (1 << 5)) ); // ensure other bits were set

        /* CASE 2: Make sure *all* other bits can be replaced. */
        testInput = 0b1101_1111;
        result    = register.value(testInput);
        assert(result == register._value); // correct data was actually returned

        assert(result == (testInput | _immutableBits));
        assert((result & _immutableBits) == _immutableBits ); 
    } 

    @property bool c() { return this._c; }
    unittest 
    {   
        auto register = new StatusRegister;
        assert (register.c == 0);
        register.value = 0b1010_0101;
        assert (register.c > 0);
        register.value = 0b1010_0100;
        assert (register.c  == 0);
    } 
    
    @property bool c(bool value) 
    { 
        this._c = value; 
        return this._c;
    }
    unittest 
    {   
        auto register   = new StatusRegister;
        bool result;

        assert (register._c == 0);
        assert (register._value == _immutableBits);

        result = (register.c = 1);
        assert (register._c == 1);
        assert (register.c == register._c);
        assert (register.value == (register._immutableBits | 0b0000_0001));

    } 

    @property bool z() { return this._z; }
    unittest 
    {   
        auto register = new StatusRegister;
        assert (register.z == 0);
        register.value = 0b1010_0110;
        assert (register.z > 0);
        register.value = 0b1010_0100;
        assert (register.z  == 0);
    } 
    
    @property bool z(bool value) 
    { 
        this._z = value; 
        return this._z;
    }
    unittest 
    {   
        auto register   = new StatusRegister;
        bool result;

        assert (register._z == 0);
        assert (register._value == _immutableBits);

        result = (register.z = 1);
        assert (register._z == 1);
        assert (register.z == register._z);
        assert (register.value == (register._immutableBits | 0b0000_0010));

    } 

    @property bool i() { return this._i; }
    unittest 
    {   
        auto register = new StatusRegister;
        assert (register.i == 0);
        register.value = 0b1010_0110;
        assert (register.i > 0);
        register.value = 0b1010_0010;
        assert (register.i  == 0);
    } 
    
    @property bool i(bool value) 
    { 
        this._i = value; 
        return this._i;
    }
    unittest 
    {   
        auto register   = new StatusRegister;
        bool result;

        assert (register._i == 0);
        assert (register._value == _immutableBits);

        result = (register.i = 1);
        assert (register._i == 1);
        assert (register.i == register._i);
        assert (register.value == (register._immutableBits | 0b0000_0100));

    } 

    @property bool d() { return this._d; }
    unittest 
    {   
        auto register = new StatusRegister;
        assert (register.d == 0);
        register.value = 0b1010_1010;
        assert (register.d > 0);
        register.value = 0b1010_0010;
        assert (register.d  == 0);
    } 
    
    @property bool d(bool value) 
    { 
        this._d = value; 
        return this._d;
    }
    unittest 
    {   
        auto register   = new StatusRegister;
        bool result;

        assert (register._d == 0);
        assert (register._value == _immutableBits);

        result = (register.d = 1);
        assert (register._d == 1);
        assert (register.d == register._d);
        assert (register.value == (register._immutableBits | 0b0000_1000));

    } 

    @property bool b() { return this._b; }
    unittest 
    {   
        auto register = new StatusRegister;
        assert (register.b == 0);
        register.value = 0b1011_1010;
        assert (register.b > 0);
        register.value = 0b1010_1010;
        assert (register.b  == 0);
    } 
    
    @property bool b(bool value) 
    { 
        this._b = value; 
        return this._b;
    }
    unittest 
    {   
        auto register   = new StatusRegister;
        bool result;

        assert (register._b == 0);
        assert (register._value == _immutableBits);

        result = (register.b = 1);
        assert (register._b == 1);
        assert (register.b == register._b);
        assert (register.value == (register._immutableBits | 0b0001_0000));

    } 

    /// The unused bit only has a getter, no setter.
    @property bool unused() { return this._unused; }
    unittest 
    {   
        auto register = new StatusRegister;

        /* CASE1: Nothing has made an illegal modification to this  bit.
         *        Its value is still one. */
        assert (register.unused > 0);

        /* CASE2: Something horrible has given this bit an illegal value */
        register._value = 0b1000_0101; // Access the private variable directly 
                                       // and @#$! it
        assert (register.unused == 0); // the getter should display the value
    } 


    @property bool v() { return this._v; }
    unittest 
    {   
        auto register = new StatusRegister;
        assert (register.v == 0);
        register.value = 0b1110_0110;
        assert (register.v > 0);
        register.value = 0b1010_0100;
        assert (register.v  == 0);
    } 
    
    @property bool v(bool value) 
    { 
        this._v = value; 
        return this._v;
    }
    unittest 
    {   
        auto register   = new StatusRegister;
        bool result;

        assert (register._v == 0);
        assert (register._value == _immutableBits);

        result = (register.v = 1);
        assert (register._v == 1);
        assert (register.v == register._v);
        assert (register.value == (register._immutableBits | 0b0100_0000));

    } 

    @property bool n() { return this._n; }
    unittest 
    {   
        auto register = new StatusRegister;
        assert (register.n == 0);
        register.value = 0b1110_0110;
        assert (register.n > 0);
        register.value = 0b0110_0100;
        assert (register.n  == 0);
    } 
    
    @property bool n(bool value) 
    { 
        this._n = value; 
        return this._n;
    }
    unittest 
    {   
        auto register   = new StatusRegister;
        bool result;

        assert (register._n == 0);
        assert (register._value == _immutableBits);

        result = (register.n = 1);
        assert (register._n == 1);
        assert (register.n == register._n);
        assert (register.value == (register._immutableBits | 0b1000_0000));

    } 
    } 

    private union  { 
        ubyte _value;
        mixin(bitfields!(
            bool, "_c",      1,   // carry flag
            bool, "_z",      1,   // zero  flag
            bool, "_i",      1,   // interrupt disable flag
            bool, "_d",      1,   // decimal mode _status (unused in NES)
            bool, "_b",      1,   // software interrupt flag (BRK)
            bool, "_unused", 1,   // not used. Must be logical 1 at all times.
            bool, "_v",      1,   // overflow flag
            bool, "_n",      1)); // sign/negative flag
    }

    /** Do not change this constant.
      * Defines which status bits are constantly set to 1. */
    private static immutable ubyte _immutableBits = 0b0010_0000;  
}

// ex: set foldmethod=syntax foldlevel=1 expandtab ts=4 sts=4 expandtab sw=4 filetype=d : 
