# Copyright (c) 2015 Saul D Beniquez 
# used to parse the output of perfect6502's measure test program and generate
# a table cycle timings per opcode

import re  #regular expressions
import sys # stdio

timing_table = [int(-1)] * 256
addressmode_table = [int(-1)] * 256

lines = list()

def address_mode_value(x):
        return {
            'imm' : 0x10,
            'acc': 0xa0,
            'zp' : 0xb0,
            'zpx': 0xb1,
            'zpy': 0xb2,
            'rel': 0xc0,
            'abs': 0xd0,
            'absx': 0xd1,
            'absy': 0xd2,
            'idx' : 0xf0,
            'izy': 0xf1,
            'izx': 0xf2
        }.get(x, 0)

def print_byte_table(table, width = 16, base16 = False):
    
    for j in range(0, 16/width):
        sys.stdout.write('     //')

        for i in range(0, width ):
            val = int(i)
            val =  (int(j) * width) + val
            fmt = '  %01x    '
            if not base16:
                fmt = " %1x "

            sys.stdout.write((fmt % val).upper())
        sys.stdout.write('\n')

    sys.stdout.write('     ')
    width = width -1
    for index in range(0x00, len(table)):
        if table[index] > 0xFF:
            continue
        
        output = str()
        fmt = str()
        fmt = " 0x%02x"

        if not base16:
            fmt = "%d" #if table[index] > -1 else "-%d"

        output = (fmt % table[index]);

        sys.stdout.write(output);
        
        if (index == 0xFF):
                sys.stdout.write(" ]; // F \n");
        else :
            if ((index & width) == width):
                sys.stdout.write((", // %01x\n     " % (index >> 4)).upper())
            else:
                sys.stdout.write(", ")

    sys.stdout.write("\n");

# Load file
with open("measure.log") as f:
    lines = (l.strip() for l in f.readlines())

# Parse file
for line in lines:
    if line:
        print line
        regex = \
                re.compile(r"^\$([A-Za-z0-9][A-Za-z0-9]):\s*(CRASH$|(bytes:\s*(\d|\D)\s*cycles:\s*(\d*)\s*\S*\s*\S*\s*(\w+)$))");
        match = regex.match(line)

        opcode_str = match.group(1)
        cycles_str =  match.group(5) if (opcode_str != "00") else "7"
        addressmode_str = match.group(6)
        #print("[0x{0}] = {1}".format(opcode_str, cycles_str))

        opcode = int(opcode_str,16)
        cycles = int(cycles_str, 16) if (cycles_str != None) else 0;
        addressmode = address_mode_value(addressmode_str)

        timing_table[opcode] = cycles;
        addressmode_table[opcode] = addressmode;

# Output several c-style array definition
sys.stdout.write("ubyte cycleCountTable[256] = [\n");
print_byte_table(timing_table)

sys.stdout.write("ubyte addressModeTable[256] = [\n");
print_byte_table(addressmode_table, 8, True)
