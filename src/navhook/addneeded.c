/*
 * addneeded - add or remove one DT_NEEDED entry in a 32-bit little-endian ELF
 * library without changing its layout.
 * Copyright (c) 2026 CrEaK (https://github.com/CrEaK). GPL-3.0-or-later.
 *
 *   addneeded check  <lib> <name>         0: <name> is a dependency already
 *                                         1: it is not and can be added
 *                                         2: it cannot (reason on stdout)
 *   addneeded add    <in> <out> <name>    writes <out> with the dependency
 *   addneeded remove <in> <out> <name>    writes <out> without it
 *   addneeded same   <a> <b>              0: the two files hold the same bytes
 *                                         1: they do not, 2: one cannot be read
 *
 * Runs on the head unit, so the installer changes the unit's own library and
 * no copy of it has to be shipped. The name has to be in the library's dynamic
 * string table already; the tail of an existing string is enough ("dog.so"
 * inside "libwatchdog.so"). Adding moves the entries behind the DT_NEEDED
 * block down by one of the spare DT_NULL slots; removing moves them back up,
 * which gives the original file again, byte for byte. Nothing outside the
 * dynamic section changes, the size included. add_needed.py next to this file
 * is the same in Python (used on the build machine and by the tests).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DT_NULL   0
#define DT_NEEDED 1
#define DT_STRTAB 5
#define DT_STRSZ  10
#define PT_LOAD    1
#define PT_DYNAMIC 2
#define MAX_LOADS 16

static unsigned char *data;
static long size;
static unsigned long dyn_off, dyn_count, str_off, str_size;
static struct { unsigned long vaddr, off, filesz; } loads[MAX_LOADS];
static int nloads;

static unsigned long u32(unsigned long off)
{
    return (unsigned long)data[off] | (unsigned long)data[off + 1] << 8
            | (unsigned long)data[off + 2] << 16 | (unsigned long)data[off + 3] << 24;
}

static unsigned u16(unsigned long off)
{
    return (unsigned)data[off] | (unsigned)data[off + 1] << 8;
}

static void put32(unsigned long off, unsigned long v)
{
    data[off] = (unsigned char)v;
    data[off + 1] = (unsigned char)(v >> 8);
    data[off + 2] = (unsigned char)(v >> 16);
    data[off + 3] = (unsigned char)(v >> 24);
}

static int fail(const char *why)
{
    printf("addneeded: %s\n", why);
    return 2;
}

static int file_offset(unsigned long vaddr, unsigned long *off)
{
    int i;
    for (i = 0; i < nloads; ++i) {
        if (vaddr >= loads[i].vaddr && vaddr < loads[i].vaddr + loads[i].filesz) {
            *off = loads[i].off + (vaddr - loads[i].vaddr);
            return 1;
        }
    }
    return 0;
}

static int load(const char *path)
{
    FILE *f = fopen(path, "rb");
    unsigned long phoff, i, strtab = 0;
    unsigned phentsize, phnum;
    int have_dyn = 0, have_tab = 0, have_size = 0;

    if (f == NULL) {
        return fail("cannot open the library");
    }
    if (fseek(f, 0, SEEK_END) != 0 || (size = ftell(f)) < 0x34 || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return fail("cannot read the library");
    }
    data = (unsigned char *)malloc((size_t)size);
    if (data == NULL || fread(data, 1, (size_t)size, f) != (size_t)size) {
        fclose(f);
        return fail("cannot read the library");
    }
    fclose(f);
    if (memcmp(data, "\177ELF", 4) != 0 || data[4] != 1 || data[5] != 1) {
        return fail("not a 32-bit little-endian ELF file");
    }
    phoff = u32(0x1c);
    phentsize = u16(0x2a);
    phnum = u16(0x2c);
    if (phentsize < 32 || phoff + (unsigned long)phentsize * phnum > (unsigned long)size) {
        return fail("program headers are outside the file");
    }
    for (i = 0; i < phnum; ++i) {
        unsigned long p = phoff + i * phentsize;
        unsigned long type = u32(p), off = u32(p + 4), vaddr = u32(p + 8), filesz = u32(p + 16);
        if (off > (unsigned long)size || filesz > (unsigned long)size - off) {
            return fail("a segment is outside the file");
        }
        if (type == PT_LOAD && nloads < MAX_LOADS) {
            loads[nloads].vaddr = vaddr;
            loads[nloads].off = off;
            loads[nloads].filesz = filesz;
            ++nloads;
        } else if (type == PT_DYNAMIC) {
            dyn_off = off;
            dyn_count = filesz / 8;
            have_dyn = 1;
        }
    }
    if (!have_dyn || dyn_count == 0) {
        return fail("no dynamic section");
    }
    for (i = 0; i < dyn_count; ++i) {
        unsigned long tag = u32(dyn_off + 8 * i), value = u32(dyn_off + 8 * i + 4);
        if (tag == DT_NULL) {
            break;
        }
        if (tag == DT_STRTAB) {
            strtab = value;
            have_tab = 1;
        } else if (tag == DT_STRSZ) {
            str_size = value;
            have_size = 1;
        }
    }
    if (!have_tab || !have_size || !file_offset(strtab, &str_off)
            || str_size > (unsigned long)size - str_off) {
        return fail("no usable dynamic string table");
    }
    return 0;
}

/* index of the first DT_NULL; the entries behind it have to be empty */
static int first_null(unsigned long *idx)
{
    unsigned long i, k;
    for (i = 0; i < dyn_count; ++i) {
        if (u32(dyn_off + 8 * i) == DT_NULL) {
            for (k = i; k < dyn_count; ++k) {
                if (u32(dyn_off + 8 * k) != 0 || u32(dyn_off + 8 * k + 4) != 0) {
                    return 0;
                }
            }
            *idx = i;
            return 1;
        }
    }
    return 0;
}

static int text_is(unsigned long value, const char *name)
{
    size_t n = strlen(name);
    return value < str_size && n < str_size - value && memcmp(data + str_off + value, name, n + 1) == 0;
}

/* -1: not a dependency, else its index in the dynamic section */
static long find_needed(const char *name, unsigned long end)
{
    unsigned long i;
    for (i = 0; i < end; ++i) {
        if (u32(dyn_off + 8 * i) == DT_NEEDED && text_is(u32(dyn_off + 8 * i + 4), name)) {
            return (long)i;
        }
    }
    return -1;
}

/* where the name sits in the string table (as the tail of some string), or -1 */
static long find_name(const char *name)
{
    size_t n = strlen(name) + 1;
    unsigned long i;
    if (n > str_size) {
        return -1;
    }
    for (i = 0; i + n <= str_size; ++i) {
        if (memcmp(data + str_off + i, name, n) == 0) {
            return (long)i;
        }
    }
    return -1;
}

static int save(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (f == NULL) {
        return fail("cannot create the output file");
    }
    if (fwrite(data, 1, (size_t)size, f) != (size_t)size || fclose(f) != 0) {
        return fail("cannot write the output file");
    }
    return 0;
}

/* the unit has no cmp, diff or checksum tool; the installer compares with this */
static int same(const char *a, const char *b)
{
    FILE *fa = fopen(a, "rb"), *fb = fopen(b, "rb");
    int ca, cb, rc = 0;

    if (fa == NULL || fb == NULL) {
        if (fa != NULL) {
            fclose(fa);
        }
        if (fb != NULL) {
            fclose(fb);
        }
        return fail("cannot open a file to compare");
    }
    do {
        ca = getc(fa);
        cb = getc(fb);
        if (ca != cb) {
            rc = 1;
            break;
        }
    } while (ca != EOF);
    if (ferror(fa) || ferror(fb)) {
        rc = 2;
    }
    fclose(fa);
    fclose(fb);
    printf(rc == 0 ? "addneeded: same bytes\n" : rc == 1 ? "addneeded: different\n" : "addneeded: read error\n");
    return rc;
}

int main(int argc, char **argv)
{
    const char *mode = argc > 1 ? argv[1] : "";
    const char *name;
    unsigned long end = 0, last_needed = 0, i;
    long at, pos;
    int rc, block = 1, any = 0;

    if (strcmp(mode, "same") == 0 && argc == 4) {
        return same(argv[2], argv[3]);
    }
    if (!((strcmp(mode, "check") == 0 && argc == 4)
            || ((strcmp(mode, "add") == 0 || strcmp(mode, "remove") == 0) && argc == 5))) {
        printf("usage: addneeded check <lib> <name> | add <in> <out> <name> | remove <in> <out> <name> | same <a> <b>\n");
        return 2;
    }
    name = argv[argc - 1];
    if (name[0] == '\0') {
        return fail("empty name");
    }
    rc = load(argv[2]);
    if (rc != 0) {
        return rc;
    }
    if (!first_null(&end)) {
        return fail("the dynamic section has no clean end");
    }
    for (i = 0; i < end; ++i) {
        if (u32(dyn_off + 8 * i) == DT_NEEDED) {
            if (any && i != last_needed + 1) {
                block = 0;
            }
            last_needed = i;
            any = 1;
        }
    }
    if (!any || !block || u32(dyn_off) != DT_NEEDED) {
        return fail("the dependencies are not one block at the top");
    }
    at = find_needed(name, end);

    if (strcmp(mode, "remove") == 0) {
        if (at < 0) {
            return fail("the name is not a dependency");
        }
        for (i = (unsigned long)at; i + 1 < dyn_count; ++i) {
            put32(dyn_off + 8 * i, u32(dyn_off + 8 * (i + 1)));
            put32(dyn_off + 8 * i + 4, u32(dyn_off + 8 * (i + 1) + 4));
        }
        put32(dyn_off + 8 * (dyn_count - 1), 0);
        put32(dyn_off + 8 * (dyn_count - 1) + 4, 0);
        rc = save(argv[3]);
        if (rc == 0) {
            printf("addneeded: removed %s, %ld bytes written\n", name, size);
        }
        return rc;
    }

    if (at >= 0) {
        if (strcmp(mode, "check") == 0) {
            printf("addneeded: %s is a dependency already\n", name);
            return 0;
        }
        return fail("the name is a dependency already");
    }
    if (dyn_count - end < 2) {
        return fail("no spare slot in the dynamic section");
    }
    pos = find_name(name);
    if (pos < 0) {
        return fail("the name is not the tail of a string in the dynamic string table");
    }
    if (strcmp(mode, "check") == 0) {
        printf("addneeded: %s can be added (%lu spare slots)\n", name, dyn_count - end - 1);
        return 1;
    }
    for (i = end; i > last_needed + 1; --i) {
        put32(dyn_off + 8 * i, u32(dyn_off + 8 * (i - 1)));
        put32(dyn_off + 8 * i + 4, u32(dyn_off + 8 * (i - 1) + 4));
    }
    put32(dyn_off + 8 * (last_needed + 1), DT_NEEDED);
    put32(dyn_off + 8 * (last_needed + 1) + 4, (unsigned long)pos);
    rc = save(argv[3]);
    if (rc == 0) {
        printf("addneeded: added %s, %ld bytes written\n", name, size);
    }
    return rc;
}
