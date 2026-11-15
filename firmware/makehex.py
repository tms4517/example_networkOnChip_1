#!/usr/bin/env python3
# Copyright (c) 2026 Tej Sanghavi.
"""Convert a flat little-endian binary into a $readmemh word image.

Usage: makehex.py firmware.bin DEPTH_WORDS > firmware.hex
"""

import sys


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as binary:
        image = binary.read()
    depth = int(sys.argv[2], 0)
    image += bytes(-len(image) % 4)
    words = len(image) // 4
    if words > depth:
        sys.exit("makehex: image is %d words, RAM holds %d" % (words, depth))
    for i in range(depth):
        word = image[4 * i:4 * i + 4] if i < words else bytes(4)
        print("%08x" % int.from_bytes(word, "little"))


if __name__ == "__main__":
    main()
