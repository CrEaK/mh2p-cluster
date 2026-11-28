# navhook.sh - the navigation hook's part of install.sh and uninstall.sh.
# Copyright (c) 2026 CrEaK (https://github.com/CrEaK). GPL-3.0-or-later.
#
# Sourced, not run. Needs print, note(), $MOD_PATH and $BACKUP_DIR from the
# script that sources it.
#
# What it installs: dog.so (src/navhook/komo_hook.c) next to the navigation's
# libwatchdog.so, and "dog.so" as one more dependency of that library, so the
# navigation process loads the hook when it starts. The library on the unit is
# changed in place by the helper addneeded (src/navhook/addneeded.c); no copy
# of Audi's file is shipped. The original is kept next to it as
# libwatchdog.so.orig and on the card as Backup/libwatchdog.so.original, and
# taking the dependency out again gives the original bytes back.
#
# Order matters: a library that names dog.so without dog.so next to it stops
# the navigation from starting. So dog.so goes in before the dependency and
# comes out after it, and it stays whenever this script cannot tell.

NAVHOOK_DIR=/mnt/app/navigation
NAVHOOK_LIB="$NAVHOOK_DIR/libwatchdog.so"
NAVHOOK_DOG="$NAVHOOK_DIR/dog.so"
NAVHOOK_ORIG="$NAVHOOK_DIR/libwatchdog.so.orig"
NAVHOOK_PROGRAM="$NAVHOOK_DIR/navStartup"
# The builds of the navigation program the hook knows (builds[] in
# src/navhook/komo_hook.c): P2711, HERE build MIB2P_MAIN_19_39_5, and P2873,
# MIB2P_MAIN_21_26_3. The hook checks the code it changes when it loads; this
# is the same check one step earlier, so nothing is installed for another build.
NAVHOOK_PROGRAM_SIZES="47516812 47923536"
NAVHOOK_TOOL="/tmp/cluster_addneeded.$$"
NAVHOOK_WORK="/tmp/cluster_watchdog.$$"
NAVHOOK_FAILS=/mnt/ota/modkit/komo_hook_fails

navhook_size() {
    ls -l "$1" 2>/dev/null | awk '{ print $5; exit }'
}

# The helper is copied to /tmp (the card may not allow running a program) and
# has to prove that it runs here: comparing a file with itself gives 0.
navhook_tool() {
    [[ -f "$MOD_PATH/navhook/addneeded" ]] || return 1
    cp "$MOD_PATH/navhook/addneeded" "$NAVHOOK_TOOL" 2>/dev/null || return 1
    chmod 755 "$NAVHOOK_TOOL" 2>/dev/null
    "$NAVHOOK_TOOL" same "$NAVHOOK_TOOL" "$NAVHOOK_TOOL" >/dev/null 2>&1
}

navhook_same() {
    "$NAVHOOK_TOOL" same "$1" "$2" >/dev/null 2>&1
}

# navhook_put SRC DST: DST appears complete or not at all (same folder, mv).
navhook_put() {
    cp "$1" "$2.new" 2>/dev/null && chmod 755 "$2.new" 2>/dev/null && mv "$2.new" "$2" 2>/dev/null && return 0
    rm -f "$2.new" 2>/dev/null
    return 1
}

navhook_tidy() {
    rm -f "$NAVHOOK_TOOL" "$NAVHOOK_WORK.add" "$NAVHOOK_WORK.back" 2>/dev/null
}

# navhook_install: 0 = the hook is in place, 1 = nothing of it is (the reason
# is printed). Never leaves the library changed without dog.so next to it.
navhook_install() {
    typeset rc sz why bk dog_new want known
    if [[ ! -f "$NAVHOOK_LIB" || ! -f "$NAVHOOK_PROGRAM" ]]; then
        print "nav box:           skipped (no navigation under $NAVHOOK_DIR)"
        return 1
    fi
    sz=$(navhook_size "$NAVHOOK_PROGRAM")
    known=0
    for want in $NAVHOOK_PROGRAM_SIZES; do
        [[ "$sz" == "$want" ]] && known=1
    done
    if [[ $known -eq 0 ]]; then
        print "nav box:           skipped (the navigation program is none of the builds the hook was written for: ${sz:-?} bytes, known are $NAVHOOK_PROGRAM_SIZES; nothing changed)"
        return 1
    fi
    if [[ ! -f "$MOD_PATH/navhook/dog.so" ]]; then
        print "nav box:           skipped (navhook/dog.so is missing on the card)"
        return 1
    fi
    if ! navhook_tool; then
        print "nav box:           skipped (the helper navhook/addneeded does not run on this unit; nothing changed)"
        navhook_tidy
        return 1
    fi
    why=$("$NAVHOOK_TOOL" check "$NAVHOOK_LIB" dog.so 2>&1); rc=$?
    if [[ $rc -ne 0 && $rc -ne 1 ]]; then
        print "nav box:           skipped (libwatchdog.so cannot take the dependency: ${why:-no answer from the helper}; nothing changed)"
        navhook_tidy
        return 1
    fi

    # dog.so first
    dog_new=0
    if ! navhook_same "$MOD_PATH/navhook/dog.so" "$NAVHOOK_DOG"; then
        [[ -f "$NAVHOOK_DOG" ]] || dog_new=1
        if ! navhook_put "$MOD_PATH/navhook/dog.so" "$NAVHOOK_DOG" || ! navhook_same "$MOD_PATH/navhook/dog.so" "$NAVHOOK_DOG"; then
            print -u2 "ERROR: nav box: could not write $NAVHOOK_DOG"
            # with the dependency in place (rc 0) an older dog.so has to stay
            [[ $rc -eq 1 ]] && rm -f "$NAVHOOK_DOG" 2>/dev/null
            navhook_tidy
            return 1
        fi
        print "install:           $NAVHOOK_DOG"
        [[ $dog_new -eq 1 ]] && note "add $NAVHOOK_DOG"
    else
        print "skip identical:    $NAVHOOK_DOG"
    fi

    if [[ $rc -eq 0 ]]; then
        print "nav box:           libwatchdog.so names dog.so already"
        navhook_tidy
        return 0
    fi

    # Build the changed library in /tmp and prove it before it goes anywhere:
    # the dependency is in, the size is the same, and taking it out again
    # gives the unit's file back byte for byte.
    "$NAVHOOK_TOOL" add "$NAVHOOK_LIB" "$NAVHOOK_WORK.add" dog.so >/dev/null 2>&1 \
        && "$NAVHOOK_TOOL" check "$NAVHOOK_WORK.add" dog.so >/dev/null 2>&1 \
        && [[ "$(navhook_size "$NAVHOOK_WORK.add")" == "$(navhook_size "$NAVHOOK_LIB")" ]] \
        && "$NAVHOOK_TOOL" remove "$NAVHOOK_WORK.add" "$NAVHOOK_WORK.back" dog.so >/dev/null 2>&1 \
        && navhook_same "$NAVHOOK_WORK.back" "$NAVHOOK_LIB"
    if [[ $? -ne 0 ]]; then
        print "nav box:           skipped (the changed libwatchdog.so did not pass its check; nothing changed)"
        [[ $dog_new -eq 1 ]] && rm -f "$NAVHOOK_DOG" 2>/dev/null
        navhook_tidy
        return 1
    fi

    # The original, on the card and next to the library.
    bk="$BACKUP_DIR/libwatchdog.so.original"
    if ! navhook_same "$NAVHOOK_LIB" "$bk"; then
        [[ -f "$bk" ]] && mv "$bk" "$bk.$(ts)" 2>/dev/null
        cp "$NAVHOOK_LIB" "$bk" 2>/dev/null
    fi
    if ! navhook_same "$NAVHOOK_LIB" "$NAVHOOK_ORIG"; then
        cp "$NAVHOOK_LIB" "$NAVHOOK_ORIG" 2>/dev/null
    fi
    if ! navhook_same "$NAVHOOK_LIB" "$bk" || ! navhook_same "$NAVHOOK_LIB" "$NAVHOOK_ORIG"; then
        print -u2 "ERROR: nav box: could not keep a verified copy of libwatchdog.so; nothing changed"
        [[ $dog_new -eq 1 ]] && rm -f "$NAVHOOK_DOG" 2>/dev/null
        navhook_tidy
        return 1
    fi
    print "backup target:     $NAVHOOK_LIB -> $bk (and $NAVHOOK_ORIG)"

    if ! navhook_put "$NAVHOOK_WORK.add" "$NAVHOOK_LIB" || ! navhook_same "$NAVHOOK_WORK.add" "$NAVHOOK_LIB"; then
        print -u2 "ERROR: nav box: writing $NAVHOOK_LIB failed, putting the original back"
        if navhook_put "$NAVHOOK_ORIG" "$NAVHOOK_LIB" && navhook_same "$NAVHOOK_ORIG" "$NAVHOOK_LIB"; then
            print "restore original:  $NAVHOOK_ORIG -> $NAVHOOK_LIB"
            [[ $dog_new -eq 1 ]] && rm -f "$NAVHOOK_DOG" 2>/dev/null
        else
            print -u2 "ERROR: nav box: $NAVHOOK_LIB is not what it should be; the original is $bk"
        fi
        navhook_tidy
        return 1
    fi
    note "replace $NAVHOOK_LIB backup=$bk"
    print "install:           $NAVHOOK_LIB (one more dependency: dog.so; checked on this unit, taking it out gives the original back)"
    navhook_tidy
    return 0
}

# navhook_remove: takes the dependency out of the library, then removes dog.so
# and the unit's copy of the original. Silent when nothing of the hook is on
# the unit. 0 = nothing of it is left, 1 = something had to stay (printed).
navhook_remove() {
    typeset rc clean copy
    [[ -f "$NAVHOOK_DOG" || -f "$NAVHOOK_ORIG" ]] || return 0
    clean=0
    if [[ ! -f "$NAVHOOK_LIB" ]]; then
        clean=1
    elif navhook_tool; then
        "$NAVHOOK_TOOL" check "$NAVHOOK_LIB" dog.so >/dev/null 2>&1; rc=$?
        if [[ $rc -eq 1 ]]; then
            clean=1
        elif [[ $rc -eq 0 ]]; then
            "$NAVHOOK_TOOL" remove "$NAVHOOK_LIB" "$NAVHOOK_WORK.back" dog.so >/dev/null 2>&1 \
                && [[ "$(navhook_size "$NAVHOOK_WORK.back")" == "$(navhook_size "$NAVHOOK_LIB")" ]] \
                && { "$NAVHOOK_TOOL" check "$NAVHOOK_WORK.back" dog.so >/dev/null 2>&1; [[ $? -eq 1 ]]; } \
                && navhook_put "$NAVHOOK_WORK.back" "$NAVHOOK_LIB" && navhook_same "$NAVHOOK_WORK.back" "$NAVHOOK_LIB"
            if [[ $? -eq 0 ]]; then
                clean=1
                print "restore original:  $NAVHOOK_LIB (dog.so is no dependency any more)"
                note "restore $NAVHOOK_LIB"
            fi
        fi
    fi
    if [[ $clean -eq 0 && -f "$NAVHOOK_LIB" ]]; then
        # No helper, or it failed: a kept copy of the original of the same size.
        for copy in "$NAVHOOK_ORIG" "$BACKUP_DIR/libwatchdog.so.original"; do
            [[ -f "$copy" ]] || continue
            [[ "$(navhook_size "$copy")" == "$(navhook_size "$NAVHOOK_LIB")" ]] || continue
            if navhook_put "$copy" "$NAVHOOK_LIB"; then
                clean=1
                print "restore original:  $copy -> $NAVHOOK_LIB"
                note "restore $NAVHOOK_LIB from=$copy"
                break
            fi
        done
    fi
    if [[ $clean -eq 0 ]]; then
        print "nav box:           WARN could not take dog.so out of $NAVHOOK_LIB; $NAVHOOK_DOG stays (the navigation needs it to start) and does nothing without its switch"
        navhook_tidy
        return 1
    fi
    if [[ -f "$NAVHOOK_DOG" ]]; then
        rm -f "$NAVHOOK_DOG" && print "remove:            $NAVHOOK_DOG" && note "remove $NAVHOOK_DOG"
    fi
    rm -f "$NAVHOOK_ORIG" "$NAVHOOK_FAILS" 2>/dev/null
    navhook_tidy
    return 0
}
