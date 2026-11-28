#!/bin/sh
# Builds komo_hook.so (GPL-3.0-or-later, see komo_hook.c) with the QNX 6.5
# ARMv7 toolchain image used for altscreen.so (see ../altscreen/build.sh).
# -init: the library is entered from DT_INIT as well as from DT_INIT_ARRAY,
# whichever the unit's loader runs. No -fexceptions: the navigation is built
# against libcpp-ne, the C++ library without exceptions.
# On the unit the file is installed as /mnt/app/navigation/dog.so, the
# dependency add_needed.py adds to libwatchdog.so.
set -e
cd "$(dirname "$0")"
docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src qnx65-armv7-toolchain:4.9 sh -c '
  arm-unknown-nto-qnx6.5.0eabi-gcc -O2 -Wall -Wextra -fPIC -shared -Wl,-init,komo_hook_init -o komo_hook.so komo_hook.c -lc'
# addneeded: the helper the installer runs on the unit to add dog.so to the
# dependencies of the unit's own libwatchdog.so (and to take it out again).
docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src qnx65-armv7-toolchain:4.9 sh -c '
  arm-unknown-nto-qnx6.5.0eabi-gcc -O2 -Wall -Wextra -o addneeded addneeded.c -lc'
ls -l komo_hook.so addneeded
