#!/bin/ksh
# altscreen (CarPlay instrument-cluster video): opens TCP 6031 in Audi's packet
# filter. Installed as cluster/altscreen_pf.sh with enable_carplay_altscreen.txt
# and started in the background at every boot by Persist/install.sh. It needs
# root for pfctl: started from the dio_manager wrapper (user carplay) it could
# not open the port (seen on an A6 C8, 2026-11-26), so only the boot script
# starts it.
# GPL-3.0-or-later, see src/altscreen/altscreen.c.
#
# The iPhone sends the cluster stream to TCP 6031 (the dio_manager hook's
# port next to the main screen's 6030). Audi's packet filter passes only a
# fixed port list on the hotspot interfaces bcm0/bcm1, so the 6030 rules are
# copied for 6031 and only the filter part is reloaded (pfctl -R, atomic: a
# failed load changes nothing). The system loads its rules again when the
# hotspot comes up (seen 30-60 s after boot on an A6 C8), right when the
# iPhone connects, so the loop checks every 2 s for the first 5 minutes and
# every 30 s after that. One line per change goes to
# /mnt/ota/modkit/Logs/altscreen-pf.log.
#
# A check that cannot open the port says why, once per reason: on an A6 C8,
# 2026-11-27, the port was shut from 38 s to 47 s after boot, the iPhone
# connected at 37 s and did not try again, and the log held one "reload
# failed ... Resource busy" for those nine seconds although four more checks
# fell into them. The line that opens the port then says how many checks had
# failed before it.
export PATH="$PATH:/mnt/app/armle/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin:/sbin:/usr/sbin"
LOG=/mnt/ota/modkit/Logs/altscreen-pf.log
PIDFILE=/tmp/altscreen_pf.pid
fails=0
bad=0           # failed checks in a row
noted=0         # failure lines written in this boot
why=""          # why the last check failed
last_why=""

# Only one watcher. Whoever runs records its pid (first this script, then
# the loop it leaves behind); a second start sees it through /proc/<pid>
# (shell built-ins only, see Persist/install.sh) and leaves.
if { read p < "$PIDFILE" && [[ -n "$p" && -d "/proc/$p" ]]; } 2>/dev/null; then
    echo "altscreen: pf watcher already running (pid $p)"
    exit 0
fi
echo $$ > "$PIDFILE" 2>/dev/null

# lines of a file, with the shell alone (wc is not on every unit's PATH)
count_lines() {
    typeset n=0 l
    while read -r l; do n=$((n + 1)); done < "$1" 2>/dev/null
    echo $n
}

apply_pf() {
    typeset rc t0=$SECONDS first=""
    why=""
    pfctl -sr 2>/dev/null | grep -q "port = 6031" && return 0
    pfctl -sr > /tmp/altscreen_pf_before.txt 2>/tmp/altscreen_pf_err.txt; rc=$?
    if ! grep -q "port = 6030 keep state" /tmp/altscreen_pf_before.txt 2>/dev/null; then
        read -r first < /tmp/altscreen_pf_err.txt 2>/dev/null
        why="no 6030 rule to copy (pfctl -sr: rc $rc, $(count_lines /tmp/altscreen_pf_before.txt) rule lines${first:+, $first})"
        echo "$(date) pf: $why, check took $((SECONDS - t0)) s"
        return 2
    fi
    sed -e "/port = 6030 keep state/p" \
        -e "s/port = 6030 keep state/port = 6031 keep state/" \
        /tmp/altscreen_pf_before.txt > /tmp/altscreen_pf_new.txt || { why="sed failed"; echo "$(date) pf: $why"; return 2; }
    if pfctl -R -f /tmp/altscreen_pf_new.txt > /tmp/altscreen_pf_load.txt 2>&1; then
        echo "$(date) pf: 6031 opened"
        return 0
    fi
    read -r first < /tmp/altscreen_pf_load.txt 2>/dev/null
    why="reload failed: $first"
    echo "$(date) pf: reload failed, check took $((SECONDS - t0)) s"
    cat /tmp/altscreen_pf_load.txt
    return 2
}

check() {
    if apply_pf >> /tmp/altscreen_pf_last.txt 2>&1; then
        if [[ $bad -gt 0 && -s /tmp/altscreen_pf_last.txt ]]; then
            echo "$(date) pf: $bad check(s) had failed before that" >> /tmp/altscreen_pf_last.txt
        fi
        cat /tmp/altscreen_pf_last.txt >> "$LOG" 2>/dev/null
        bad=0
        last_why=""
    else
        fails=$((fails + 1))
        bad=$((bad + 1))
        # one line per reason, and a filter that never takes the rule must not fill the flash log
        if [[ "$why" != "$last_why" && $noted -lt 20 ]]; then
            noted=$((noted + 1))
            cat /tmp/altscreen_pf_last.txt >> "$LOG" 2>/dev/null
        fi
        last_why="$why"
    fi
    rm -f /tmp/altscreen_pf_last.txt
}

mkdir -p /mnt/ota/modkit/Logs 2>/dev/null
echo "=== boot $(date)" >> "$LOG"
waitfor /tmp/pf_ready 30 2>/dev/null
sleep 10
check
( n=0; while true; do
      if [[ $n -lt 150 ]]; then sleep 2; n=$((n + 1)); else sleep 30; fi
      check
  done ) &
echo $! > "$PIDFILE" 2>/dev/null
echo "altscreen: pf watcher started"
