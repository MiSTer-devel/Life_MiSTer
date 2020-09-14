#!/usr/bin/python3

import sys
import matplotlib.pyplot as plt
import numpy as np

output = []

for char in open(sys.argv[1], 'rb').read():
    value, repeat = 255 * (char >> 7), (char & 0x7f)
    output.extend([value] * (repeat+1))

print("Expected / actual: ", 1125*2200, len(output))
output = bytearray(output + (1125*2200 - len(output))*[0])
plt.imshow(np.array(output).reshape(1125, 2200))
plt.savefig("matplotlib.png", dpi=1200)