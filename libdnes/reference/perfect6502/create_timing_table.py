# Copyright (c) 2015 Saul D Beniquez 
# used to parse the output of perfect6502's measure test program and generate
# a table cycle timings per opcode

import re  #regular expressions
import sys # stdio

timing = [int(-1)] * 256
lines = list()

# Load file
with open("measure.log") as f:
    lines = (l.strip() for l in f.readlines())

# Parse file
for line in lines:
    if line:
        print line
        regex = \
                re.compile(r"^\$([A-Za-z0-9][A-Za-z0-9]):(\s)((bytes:\s(\d|\D)(\s*)(cycles:)(\s)(\d)(.*))|(CRASH$))");
        match = regex.match(line)

        opcode_str = match.group(1)
        cycles_str =  match.group(9) if (opcode_str != "00") else "7"
        #print("[0x{0}] = {1}".format(opcode_str, cycles_str))

        opcode = int(opcode_str,16)
        cycles = int(cycles_str, 16) if (cycles_str != None) else 0;

        timing[opcode] = cycles;
        
# Output several c-style array definition
sys.stdout.write("uint cycleCountTable[256] = [\n");

for index in range(0x00, 0x100):
    if ((index & 0xF0) == index):
        sys.stdout.write('    ') # indentation

    sys.stdout.write("{0}".format(timing[index]));

    if ((index & 0x0F) == 0x0F):
        if (index == 0xFF):
            sys.stdout.write(" ];\n");
        else:
            sys.stdout.write(",\n")
    else:
        sys.stdout.write(", ")

sys.stdout.write("\n");

