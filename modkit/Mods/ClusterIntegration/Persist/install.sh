#!/bin/ksh
#
# Copyright (c) 2026 fifthBro
# https://fifthbro.github.io
#
# Licensed under CC BY-NC-SA 4.0
# https://creativecommons.org/licenses/by-nc-sa/4.0/
# NOT FOR COMMERCIAL USE
#
# cluster.sh
#

# The gal wrapper starts the daemon too when AA comes up before this runs.
# Two daemons race for /tmp/cluster_ctl and drop commands (blank cockpit until
# a reconnect, native map not restored after unplug), so only one may run.
# Whoever starts it records its pid in /tmp/cluster_daemon.pid. The check uses
# shell built-ins only (read, test): pidin/grep are not reliably reachable this
# early in boot, and kill -0 fails across users, but /proc/<pid> is visible to
# everyone. One line per decision goes to /tmp/cluster_daemon_start.log.
DAEMON_PID=/tmp/cluster_daemon.pid
DAEMON_LOG=/tmp/cluster_daemon_start.log
if [[ -x "/eso/bin/apps/cluster/cluster" ]]; then
        if { read p < "$DAEMON_PID" && [[ -n "$p" && -d "/proc/$p" ]]; } 2>/dev/null; then
                print "persist: daemon already running, pid $p" >> "$DAEMON_LOG" 2>/dev/null
        else
                # verbose=2 (cluster_daemon.log) only with the marker the
                # installer sets from Mods/ClusterIntegration/daemon_log.txt
                V=""
                [[ -f /eso/bin/apps/cluster/daemon_verbose ]] && V="verbose=2"
                # cockpit size the installer wrote from cockpit_size.txt
                # ("xres=W yres=H"); anything else in the file is ignored
                S=""
                [[ -f /eso/bin/apps/cluster/daemon_size ]] && read S < /eso/bin/apps/cluster/daemon_size
                case "$S" in xres=+([0-9])\ yres=+([0-9])) ;; *) S="" ;; esac
                /eso/bin/apps/cluster/cluster daemon $V $S >/dev/null 2>&1 &
                p=$!
                print $p > "$DAEMON_PID" 2>/dev/null
                print "persist: started daemon pid $p (pid file written: $?) args '$V $S'" >> "$DAEMON_LOG" 2>/dev/null
        fi
fi

# CarPlay cluster video (enable_carplay_altscreen.txt): the iPhone streams it
# to TCP 6031, which Audi's packet filter blocks. The script waits for the
# filter and then keeps the port open, so it runs in the background.
if [[ -x "/eso/bin/apps/cluster/altscreen_pf.sh" ]]; then
        /eso/bin/apps/cluster/altscreen_pf.sh >/dev/null 2>&1 &
        print "persist: started altscreen_pf.sh pid $!" >> "$DAEMON_LOG" 2>/dev/null
fi

# Daemon log keeper (daemon_log.txt). Without a writable stick the daemon
# writes cluster_daemon.log to /tmp, which is gone after the next boot, and
# some cars start the ModKit update as soon as the install stick goes in, so
# the stick cannot stay plugged in for the log. Keep the start of the log next
# to the other ModKit logs: the next ModKit run copies that folder to Logs/ on
# the card. Shell built-ins do the reading; nothing is written before the log
# holds a "display size" line (a map has run in this boot) or is KEEP_MAX lines
# long, so a boot without a map keeps the copy of the last one. The loop ends
# at KEEP_MAX lines.
KEEP_SRC=/tmp/cluster_daemon.log
KEEP_TMP=/tmp/cluster_daemon.keep
KEEP_DST=/mnt/ota/modkit/Logs/cluster_daemon.log
KEEP_MAX=1500
if [[ -f /eso/bin/apps/cluster/daemon_verbose ]]; then
        (
                last=0
                while :; do
                        sleep 20
                        [[ -s "$KEEP_SRC" ]] || continue
                        n=0
                        seen=0
                        while IFS= read -r line; do
                                print -r -- "$line"
                                case "$line" in *"display size:"*) seen=1 ;; esac
                                n=$((n + 1))
                                [[ $n -ge $KEEP_MAX ]] && break
                        done < "$KEEP_SRC" > "$KEEP_TMP"
                        [[ $n -ge $KEEP_MAX ]] && seen=1
                        [[ $seen -eq 1 && $n -ne $last ]] || continue
                        cp -f "$KEEP_TMP" "$KEEP_DST" && last=$n
                        [[ $n -ge $KEEP_MAX ]] && break
                done
        ) >/dev/null 2>&1 &
        print "persist: started daemon log keeper pid $!" >> "$DAEMON_LOG" 2>/dev/null
fi

