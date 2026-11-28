#!/usr/bin/env python3
"""fake_watchdog.py OUT [SPARE] - a small 32-bit little-endian ELF file shaped
like the navigation's libwatchdog.so, for the installer tests: one dependency,
the soname "libwatchdog.so" (so "dog.so" is in the string table as its tail)
and SPARE empty slots behind the end of the dynamic section (default 4)."""
import struct
import sys

out = sys.argv[1]
spare = int(sys.argv[2]) if len(sys.argv) > 2 else 4
strings = b"\0libc.so.3\0libwatchdog.so\0"
str_off = 52 + 2 * 32
dyn_off = (str_off + len(strings) + 3) & ~3
entries = [(1, 1), (14, 11), (5, str_off), (10, len(strings))] + [(0, 0)] * (1 + spare)
dyn = b"".join(struct.pack("<II", t, v) for t, v in entries)
size = dyn_off + len(dyn) + 64
header = b"\x7fELF\x01\x01\x01" + b"\0" * 9 + struct.pack("<HHIIIIIHHHHHH", 3, 40, 1, 0, 52, 0, 0, 52, 32, 2, 40, 0, 0)
load = struct.pack("<8I", 1, 0, 0, 0, size, size, 5, 0x1000)
dynamic = struct.pack("<8I", 2, dyn_off, dyn_off, dyn_off, len(dyn), len(dyn), 6, 4)
data = header + load + dynamic + strings
data += b"\0" * (dyn_off - len(data)) + dyn + bytes(range(64))
assert len(header) == 52 and len(data) == size
open(out, "wb").write(data)
