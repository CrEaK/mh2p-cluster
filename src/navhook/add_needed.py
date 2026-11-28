#!/usr/bin/env python3
"""add_needed.py - add one DT_NEEDED entry to a 32-bit little-endian ELF library
without changing its layout. GPL-3.0-or-later, (c) 2026 CrEaK.

    add_needed.py <in.so> <out.so> <name>
    add_needed.py check <lib> <name> | add <in> <out> <name> | remove <in> <out> <name>
    add_needed.py same <a> <b>

The second form is what addneeded.c does on the head unit (same exit codes:
check gives 0 when the dependency is there, 1 when it can be added, 2 when
not); the installer tests use it as a stand-in for that binary.

The name of the new dependency has to exist in the library's dynamic string
table already; the tail of an existing string is enough (strings end with a
zero byte, so "dog.so" is found inside "libwatchdog.so"). The dynamic section
needs a spare DT_NULL slot behind its terminating one: the entries after the
existing DT_NEEDED block move down by one slot and the new entry takes the gap,
so the dependencies stay together at the top as a linker writes them. Nothing
else in the file changes, its size included.

Used for the navigation hook: libwatchdog.so in /mnt/app/navigation gets
"dog.so" (the hook library, placed next to it; the library's RPATH is $ORIGIN).
"""
import struct
import sys

DT_NULL, DT_NEEDED, DT_STRTAB, DT_STRSZ = 0, 1, 5, 10
PT_LOAD, PT_DYNAMIC = 1, 2


def patch(data, name):
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        raise SystemExit("not a 32-bit little-endian ELF file")
    phoff, = struct.unpack_from("<I", data, 0x1C)
    phentsize, phnum = struct.unpack_from("<HH", data, 0x2A)
    loads, dyn = [], None
    for i in range(phnum):
        p_type, off, vaddr, _, filesz, _, _, _ = struct.unpack_from("<8I", data, phoff + i * phentsize)
        if p_type == PT_LOAD:
            loads.append((vaddr, off, filesz))
        elif p_type == PT_DYNAMIC:
            dyn = (off, filesz)
    if dyn is None:
        raise SystemExit("no dynamic section")

    def file_offset(vaddr):
        for v, o, size in loads:
            if v <= vaddr < v + size:
                return o + vaddr - v
        raise SystemExit("address %#x is not in the file" % vaddr)

    count = dyn[1] // 8
    entries = [list(struct.unpack_from("<II", data, dyn[0] + 8 * i)) for i in range(count)]
    first_null = next(i for i, e in enumerate(entries) if e[0] == DT_NULL)
    if any(e != [0, 0] for e in entries[first_null:]):
        raise SystemExit("entries after the first DT_NULL are not empty")
    if count - first_null < 2:
        raise SystemExit("no spare slot in the dynamic section")
    strtab = file_offset(next(e[1] for e in entries if e[0] == DT_STRTAB))
    strsz = next(e[1] for e in entries if e[0] == DT_STRSZ)
    table = data[strtab:strtab + strsz]
    needle = name.encode("ascii") + b"\0"
    pos = table.find(needle)
    if pos < 0:
        raise SystemExit("%r is not the tail of a string in the dynamic string table" % name)

    def text(offset):
        return table[offset:table.index(b"\0", offset)].decode("latin1")

    needed = [text(e[1]) for e in entries if e[0] == DT_NEEDED]
    if name in needed:
        raise SystemExit("%r is a dependency already" % name)
    last_needed = max(i for i, e in enumerate(entries) if e[0] == DT_NEEDED)
    if any(e[0] != DT_NEEDED for e in entries[:last_needed + 1]):
        raise SystemExit("the DT_NEEDED entries are not one block at the top")
    new = entries[:last_needed + 1] + [[DT_NEEDED, pos]] + entries[last_needed + 1:first_null] \
        + [[0, 0]] * (count - first_null - 1)
    assert len(new) == count and new[-1] == [0, 0]
    out = bytearray(data)
    for i, (tag, value) in enumerate(new):
        struct.pack_into("<II", out, dyn[0] + 8 * i, tag, value)
    return bytes(out), needed, dyn, last_needed + 1, first_null


def unpatch(data, name):
    """The reverse of patch(): gives the original bytes back."""
    probe = patch_info(data)
    entries, dyn, count, text = probe
    idx = [i for i, e in enumerate(entries) if e[0] == DT_NEEDED and text(e[1]) == name]
    if not idx:
        raise SystemExit("%r is not a dependency" % name)
    new = entries[:idx[0]] + entries[idx[0] + 1:] + [[0, 0]]
    out = bytearray(data)
    for i, (tag, value) in enumerate(new):
        struct.pack_into("<II", out, dyn[0] + 8 * i, tag, value)
    return bytes(out)


def patch_info(data):
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        raise SystemExit("not a 32-bit little-endian ELF file")
    phoff, = struct.unpack_from("<I", data, 0x1C)
    phentsize, phnum = struct.unpack_from("<HH", data, 0x2A)
    loads, dyn = [], None
    for i in range(phnum):
        p_type, off, vaddr, _, filesz, _, _, _ = struct.unpack_from("<8I", data, phoff + i * phentsize)
        if p_type == PT_LOAD:
            loads.append((vaddr, off, filesz))
        elif p_type == PT_DYNAMIC:
            dyn = (off, filesz)
    if dyn is None:
        raise SystemExit("no dynamic section")
    count = dyn[1] // 8
    entries = [list(struct.unpack_from("<II", data, dyn[0] + 8 * i)) for i in range(count)]
    strtab_addr = next(e[1] for e in entries if e[0] == DT_STRTAB)
    strtab = next(o + strtab_addr - v for v, o, size in loads if v <= strtab_addr < v + size)
    strsz = next(e[1] for e in entries if e[0] == DT_STRSZ)
    table = data[strtab:strtab + strsz]

    def text(offset):
        return table[offset:table.index(b"\0", offset)].decode("latin1")

    return entries, dyn, count, text


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "same":
        try:
            rc = 0 if open(sys.argv[2], "rb").read() == open(sys.argv[3], "rb").read() else 1
        except OSError:
            print("addneeded: cannot open a file to compare")
            raise SystemExit(2)
        print("addneeded: same bytes" if rc == 0 else "addneeded: different")
        raise SystemExit(rc)
    # the same commands as addneeded.c, with the same exit codes
    if len(sys.argv) >= 2 and sys.argv[1] in ("check", "add", "remove"):
        mode = sys.argv[1]
        try:
            data = open(sys.argv[2], "rb").read()
            name = sys.argv[-1]
            entries, _, _, text = patch_info(data)
            present = any(e[0] == DT_NEEDED and text(e[1]) == name for e in entries)
            if mode == "check" and len(sys.argv) == 4:
                if present:
                    print("addneeded: %s is a dependency already" % name)
                    raise SystemExit(0)
                patch(data, name)
                print("addneeded: %s can be added" % name)
                raise SystemExit(1)
            if mode == "add" and len(sys.argv) == 5:
                open(sys.argv[3], "wb").write(patch(data, name)[0])
                print("addneeded: added %s, %d bytes written" % (name, len(data)))
                raise SystemExit(0)
            if mode == "remove" and len(sys.argv) == 5:
                open(sys.argv[3], "wb").write(unpatch(data, name))
                print("addneeded: removed %s, %d bytes written" % (name, len(data)))
                raise SystemExit(0)
            print("usage: add_needed.py check <lib> <name> | add <in> <out> <name> | remove <in> <out> <name>")
            raise SystemExit(2)
        except SystemExit as e:
            if isinstance(e.code, str):
                print("addneeded: " + e.code)
                raise SystemExit(2)
            raise
        except (OSError, StopIteration, ValueError, struct.error) as e:
            print("addneeded: cannot read the library (%s)" % e.__class__.__name__)
            raise SystemExit(2)
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    src, dst, name = sys.argv[1:]
    data = open(src, "rb").read()
    out, needed, dyn, slot, first_null = patch(data, name)
    changed = [i for i in range(len(data)) if data[i] != out[i]]
    assert len(out) == len(data)
    assert all(dyn[0] <= i < dyn[0] + dyn[1] for i in changed)
    open(dst, "wb").write(out)
    print("dependencies before: %s" % ", ".join(needed))
    print("added %r as dependency %d; %d bytes differ, all inside the dynamic section (file offset %#x..%#x); size %d unchanged"
          % (name, slot + 1, len(changed), dyn[0], dyn[0] + dyn[1], len(out)))


if __name__ == "__main__":
    main()
