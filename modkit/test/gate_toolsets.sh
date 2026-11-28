#!/usr/bin/env bash
# gate_test4.sh SCRATCH REPO TOOLSET : installer behaviour on a simulated Audi unit
set -u
SCR="$1"; REPO="$2"; TS="$3"; export PATH="$SCR/stubs:$PATH"
M="$SCR/mkshwrap_$TS/mksh"
SYMS_SO=$SCR/zip34/Mods/ClusterIntegration/Update/gal_cluster.so
AA=de/audi/app/terminalmode/smartphone/androidauto2/AndroidAuto2Subsystem
SM=de/audi/app/car/adi/legacy/sportchrono/StorageMountHandler
CP=de/audi/app/terminalmode/smartphone/carplay/CarPlayDSIManager
res() { printf '%-60s %s\n' "$1" "$2"; }
mkjar() { # out.jar big? classes...   (central directory at the end, > 8 MB when big)
  local out="$1" big="$2"; shift 2; rm -rf "$SCR/jarsrc"; mkdir -p "$SCR/jarsrc"
  (cd "$SCR/jarsrc"; for c in "$@"; do mkdir -p "$(dirname "$c")"; head -c 300 /dev/urandom > "$c"; done
   [[ "$big" == 1 ]] && head -c 10485760 /dev/urandom > pad.bin
   rm -f "$out"; zip -q -0 -r "$out" . )
}
setup() { # $1 release  $2 lsd.jar: none|aa|aa+sm  $3 jxe: none|aa|aa+sm  $4 markers
  rm -rf /mnt/app /fs /ifs; mkdir -p /mnt/app/armle/usr/bin /mnt/app/armle/bin /mnt/app/eso/hmi/lsd/jars /mnt/app/eso/bin/apps /mnt/app/eso/lib /ifs
  ln -sf /usr/bin/wc /mnt/app/armle/usr/bin/wc      # the unit keeps wc here, off the ModKit PATH
  printf 'GALBIN\n' > /mnt/app/eso/bin/apps/gal; printf 'DIOBIN\n' > /mnt/app/eso/bin/apps/dio_manager; chmod 755 /mnt/app/eso/bin/apps/*
  printf '#!/bin/sh\nprintf "%%060d%%s\\n" 0 "'"$1"'"\n' > /mnt/app/armle/usr/bin/pc; chmod 755 /mnt/app/armle/usr/bin/pc
  # five small plugin jars like the unit's, none with the classes
  for j in AppDevelopment diag xEventRecorder xTcpKeyPanel xTcpLog; do mkjar /mnt/app/eso/hmi/lsd/jars/$j.jar 0 de/audi/plugins/$j/Plugin.class; done
  case "$2" in aa) mkjar /mnt/app/eso/hmi/lsd/lsd.jar 1 $AA.class $CP.class ;; aa+sm) mkjar /mnt/app/eso/hmi/lsd/lsd.jar 1 $AA.class $CP.class $SM.class ;; esac
  case "$3" in aa) { head -c 4000 /dev/urandom; printf '%s' "$AA"; head -c 4000 /dev/urandom; } > /ifs/lsd.jxe ;;
               aa+sm) { head -c 4000 /dev/urandom; printf '%s' "$AA"; head -c 100 /dev/urandom; printf '%s' "$SM"; head -c 4000 /dev/urandom; } > /ifs/lsd.jxe ;; esac
  { head -c 200 /dev/urandom; readelf --dyn-syms -W $SYMS_SO | awk '$7!="UND" && $4=="FUNC" && $5=="GLOBAL" {print $8}' | grep '^_ZN' | grep -v sendChannelOpenResp; head -c 200 /dev/urandom; } > /mnt/app/eso/lib/libautoreceiver.so
  rm -rf "$SCR/fakesd"; mkdir -p "$SCR/fakesd/Mods/ClusterIntegration"; cp -r "$REPO/modkit/Mods/ClusterIntegration/Update" "$SCR/fakesd/Mods/ClusterIntegration/"
  cp "$SCR/zip34/Mods/ClusterIntegration/Update/ClusterIntegration_v0034_beta2_candidate_90d0b76.jar" "$SCR/fakesd/Mods/ClusterIntegration/Update/"
  for f in cluster gal_cluster.so dio_cluster.so; do printf 'payload %s\n' "$f" > "$SCR/fakesd/Mods/ClusterIntegration/Update/$f"; done
  printf 'payload aa cluster\n' > "$SCR/fakesd/Mods/ClusterIntegration/Update/aa_only/cluster"
  cp $SCR/zip34/Mods/ClusterIntegration/Update/cluster_config.json "$SCR/fakesd/Mods/ClusterIntegration/Update/"
  # keep the restricted PATH: the unit's /usr/bin is QNX, the harness box's is not
  sed -i 's|^export PATH=.*|export PATH="$PATH:/mnt/app/armle/usr/bin:/mnt/app/armle/bin"|' "$SCR/fakesd/Mods/ClusterIntegration/Update/install.sh" "$SCR/fakesd/Mods/ClusterIntegration/Update/uninstall.sh"
  for m in $4; do touch "$SCR/fakesd/Mods/ClusterIntegration/$m"; done
  export MOD_PATH="$SCR/fakesd/Mods/ClusterIntegration/Update"
}
STUB=/mnt/app/eso/hmi/lsd/jars/ClusterIntegration_StorageMountHandler_stub.jar
run() { "$M" "$MOD_PATH/install.sh" 2>&1; }
echo "##### toolset $TS"
echo "=== A: Audi, lsd.jar has AA but not SM, jxe has AA only"
setup MH2p_ER_AUG35_P2873 aa aa "diag.txt"; out=$(run); rc=$?
echo "$out" | grep -E 'tools missing|file compare|binary search|stock AA|hmi class|stand-in|hook symbols|backup verified|hmi reference|ERROR' | sed 's/^/    | /'
[[ $rc == 0 ]] && res "A install exit 0" PASS || res "A install exit 0" "FAIL ($rc)"
echo "$out" | grep -q 'tools missing:.* wc' && res "A wc found via armle PATH" FAIL || res "A wc found via armle PATH" PASS
if echo "$out" | grep -q 'binary search:     none'; then
  [[ -f $STUB ]] && res "A stub installed by default when unknown" PASS || res "A stub installed by default when unknown" FAIL
  echo "$out" | grep -q 'hook symbols:      skipped' && res "A symbols skipped (no binary search)" PASS || res "A symbols skipped" FAIL
else
  echo "$out" | grep -q 'stock AA class:    AndroidAuto2Subsystem found in: lsd/lsd.jar' && res "A control class found in lsd.jar tail" PASS || res "A control class found in lsd.jar tail" FAIL
  echo "$out" | grep -q 'StorageMountHandler NOT found' && [[ -f $STUB ]] && res "A SM not found -> stub installed" PASS || res "A SM not found -> stub installed" FAIL
  echo "$out" | grep -q 'hook symbols:      13/14' && res "A symbols 13/14 via self-tested search" PASS || res "A symbols 13/14" FAIL
  echo "$out" | grep -q 'hmi reference:     the shadowed classes are in /mnt/app/eso/hmi/lsd/lsd.jar' && res "A lsd.jar named for signature check" PASS || res "A lsd.jar named" FAIL
fi
grep -q "add $STUB" "$MOD_PATH/Backup/manifest.txt" && res "A stub recorded as add in manifest" PASS || res "A stub recorded" FAIL
[[ -f /mnt/app/eso/hmi/lsd/jars/ClusterIntegration_v0034_beta2_candidate_90d0b76_aa.jar && ! -f /mnt/app/eso/hmi/lsd/jars/ClusterIntegration_v0034_beta2_candidate_90d0b76.jar ]] && res "A aa_only jar installed, full jar not" PASS || res "A aa_only jar" FAIL
[[ ! -f /tmp/cluster_lsdtail.* ]] 2>/dev/null; ls /tmp/cluster_lsdtail.* >/dev/null 2>&1 && res "A tail temp file removed" FAIL || res "A tail temp file removed" PASS
echo "=== A2: re-run is idempotent (no stub churn)"
sleep 1; out=$(run)
echo "$out" | grep -q "skip identical:    $STUB" && res "A2 stub skip identical on re-run" PASS || res "A2 stub skip identical" FAIL
churn=$(ls "$MOD_PATH/Backup" | grep -E '^(ClusterIntegration_.*\.jar|cluster|gal_cluster\.so|dio_cluster\.so)\.backup\.' | wc -l)
[[ $churn -eq 0 ]] && res "A2 unchanged files not re-backed-up on re-run" PASS || res "A2 unchanged files re-backed-up ($churn)" FAIL
echo "$out" | grep -c 'skip identical' | awk '{ if ($1 >= 4) print "PASS"; else print "FAIL" }' | sed 's/^/A2 skip identical lines on re-run                             /'
echo "=== B: no_stub.txt removes an installed stub"
touch "$SCR/fakesd/Mods/ClusterIntegration/no_stub.txt"; out=$(run)
echo "$out" | grep -q 'stand-in class:    OFF' && [[ ! -f $STUB ]] && res "B no_stub.txt -> stub removed" PASS || res "B no_stub.txt" FAIL
echo "$out" | grep -q "remove stand-in:   $STUB" && res "B removal logged" PASS || res "B removal logged" FAIL
rm -f "$SCR/fakesd/Mods/ClusterIntegration/no_stub.txt"
echo "=== C: uninstall removes everything incl. stub"
run >/dev/null; out=$("$M" "$MOD_PATH/uninstall.sh" 2>&1)
[[ ! -f $STUB && ! -f /mnt/app/eso/bin/apps/gal.real && "$(cat /mnt/app/eso/bin/apps/gal)" == "GALBIN" && -z "$(ls /mnt/app/eso/hmi/lsd/jars | grep ClusterIntegration)" ]] && res "C uninstall clean" PASS || res "C uninstall clean" FAIL
echo "=== D: lsd.jar provides SM -> stub not needed (and removed if present)"
setup MH2p_ER_AUG35_P2873 aa+sm aa+sm ""; touch $STUB; out=$(run)
if echo "$out" | grep -q 'binary search:     none'; then
  [[ -f $STUB ]] && res "D (no search) stub kept by default" PASS || res "D (no search) stub kept" FAIL
else
  echo "$out" | grep -q 'stand-in class:    not needed' && [[ ! -f $STUB ]] && res "D SM found -> stub not installed, stale one removed" PASS || res "D SM found" FAIL
fi
echo "=== E: jxe only (no lsd.jar), grep toolsets search it"
setup MH2p_ER_AUG35_P2873 none aa+sm ""; out=$(run)
echo "$out" | grep -E 'binary search|stock AA|hmi class|stand-in' | sed 's/^/    | /'
if echo "$out" | grep -q 'binary search:     grep'; then
  echo "$out" | grep -q 'found in: /ifs/lsd.jxe' && res "E classes found in jxe" PASS || res "E classes found in jxe" FAIL
else
  echo "$out" | grep -q 'stand-in class:    ON' && res "E no grep -> stub on (unknown)" PASS || res "E stub on" FAIL
fi
echo "=== F: control class invisible -> SM negative treated as unknown"
setup MH2p_ER_AUG35_P2873 none none ""; out=$(run)
echo "$out" | grep -q 'stand-in class:    ON (presence of StorageMountHandler could not be checked' && res "F unknown -> default stub" PASS || res "F unknown -> default stub" FAIL
echo "=== G: Porsche never gets the stub"
setup MH2p_US_PO416_P2870 aa aa ""; out=$(run)
[[ ! -f $STUB ]] && ! echo "$out" | grep -q 'stand-in class:' && res "G Porsche: no stub line, no stub" PASS || res "G Porsche no stub" FAIL
! echo "$out" | grep -q 'audi default' && [[ ! -f /mnt/app/eso/bin/apps/cluster/gal_env ]] && grep -q '"gal_h264": { "codecRes": 720,  "mode": "letter"' /mnt/app/eso/bin/apps/cluster/cluster_config.json && res "G Porsche: no Audi defaults (gal_h264 as shipped, no gal_env)" PASS || res "G Porsche: no Audi defaults" FAIL
echo "$out" | grep -q 'WARNING: StorageMountHandler not found in this Porsche' && res "G Porsche warning when SM missing (search worked)" PASS || res "G Porsche warning (or skipped)" "n/a"
echo "=== H: backup verification path"
setup MH2p_ER_AUG35_P2873 aa aa ""; run >/dev/null; printf 'changed\n' > "$MOD_PATH/aa_only/cluster"; out=$(run)
echo "$out" | grep -E 'file compare|backup verified|backup target.*cluster ' | sed 's/^/    | /'
echo "$out" | grep -q 'backup target:     /mnt/app/eso/bin/apps/cluster/cluster ->' && res "H changed file backed up and replaced" PASS || res "H changed file replaced" FAIL
if echo "$out" | grep -q 'file compare:      wc'; then echo "$out" | grep -q 'backup verified:   by size, line and word counts' && res "H wc fingerprint verification reported" PASS || res "H wc fingerprint reported" FAIL; elif echo "$out" | grep -q 'file compare:      size only'; then echo "$out" | grep -q 'backup verified:   by size only' && res "H size-only verification reported" PASS || res "H size-only reported" FAIL; else res "H content comparator used" PASS; fi
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc"
echo "=== I: block.key overrides and gal_env.txt"
setup MH2p_ER_AUG35_P2873 aa aa ""
printf 'gal_h264.mode="stretch"\r\ngal_h264.codecRes=1080\r\ngal_h264.zoomY=1.5\r\nmirror.panX=0.25\r\nforceRHD=true\r\nconfig.bad=1\r\ngal_h264.nested={1}\r\n' > "$SCR/fakesd/Mods/ClusterIntegration/config_overrides.txt"
printf '# insets\r\nGAL_CLUSTER_INSET_TOP=180\r\nGAL_CLUSTER_INSET_BOTTOM=180  # band\r\nGAL_CLUSTER_LOG=1\r\nPATH=/evil\r\nGAL_CLUSTER_X=a b\r\n' > "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"
out=$(run); echo "$out" | grep -E 'config override|gal env' | sed 's/^/    | /'
python3 - /mnt/app/eso/bin/apps/cluster/cluster_config.json <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
g=c["config"]["gal_h264"]; m=c["config"]["mirror"]
def res(n,ok): print(("PASS " if ok else "FAIL ")+n)
res("I gal_h264.mode stretch", g["mode"]=="stretch")
res("I gal_h264.codecRes 1080", g["codecRes"]==1080)
res("I gal_h264.zoomY 1.5", g["zoomY"]==1.5)
res("I mirror.panX 0.25, other mirror keys intact", m["panX"]==0.25 and m["mode"]=="fill" and m["zoomX"]==1.0)
res("I forceRHD still works", c["config"]["forceRHD"] is True)
res("I carConfig untouched", all(v["gal_h264"]["mode"]=="letter" for v in c["carConfig"].values()))
PY
echo "$out" | grep -q "config override:   WARN 'config.bad'" && res "I unknown block.key ignored" PASS || res "I unknown block.key ignored" FAIL
echo "$out" | grep -q "WARN 'gal_h264.nested' value" && res "I non-scalar value rejected" PASS || res "I non-scalar value rejected" FAIL
GE=/mnt/app/eso/bin/apps/cluster/gal_env
[[ "$(cat $GE)" == $'GAL_CLUSTER_INSET_TOP=180\nGAL_CLUSTER_INSET_BOTTOM=180\nGAL_CLUSTER_LOG=1\nGAL_CLUSTER_RES=1080' ]] && res "I gal_env holds only valid lines (CR/comments/PATH/spaces dropped) plus the Audi default" PASS || { res "I gal_env content" FAIL; cat $GE; }
echo "$out" | grep -q 'audi default:      GAL_CLUSTER_RES=1080 (gal env)' && res "I Audi default GAL_CLUSTER_RES logged" PASS || res "I Audi default GAL_CLUSTER_RES logged" FAIL
echo "$out" | grep -q 'audi default:      gal_h264.panY = 0.0' && res "I Audi gal_h264 defaults logged (overrides applied after them)" PASS || res "I Audi gal_h264 defaults logged" FAIL
grep -q "add $GE" "$MOD_PATH/Backup/manifest.txt" && res "I gal_env recorded as add" PASS || res "I gal_env recorded as add" FAIL
printf '#!/bin/sh\necho "TOP=$GAL_CLUSTER_INSET_TOP LOG=$GAL_CLUSTER_LOG MERGE=${GAL_CLUSTER_MERGE:-unset}"\n' > /mnt/app/eso/bin/apps/gal.real; chmod 755 /mnt/app/eso/bin/apps/gal.real
mksh /mnt/app/eso/bin/apps/gal 2>/dev/null | grep -q 'TOP=180 LOG=1 MERGE=unset' && res "I wrapper exports gal_env (live mode)" PASS || res "I wrapper exports gal_env" FAIL
grep -q 'gal env: GAL_CLUSTER_LOG=1' /tmp/gal_preload.log && res "I wrapper logs the env lines" PASS || res "I wrapper logs env" FAIL
rm -f "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"; out=$(run)
[[ "$(cat $GE 2>/dev/null)" == 'GAL_CLUSTER_RES=1080' ]] && ! echo "$out" | grep -q 'remove gal env:' && res "I gal_env holds only the Audi default when gal_env.txt is gone" PASS || { res "I gal_env without gal_env.txt" FAIL; cat $GE; }
printf 'GAL_CLUSTER_RES=720\n' > "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"; out=$(run)
[[ "$(cat $GE)" == 'GAL_CLUSTER_RES=720' ]] && ! echo "$out" | grep -q 'audi default:      GAL_CLUSTER_RES' && res "I GAL_CLUSTER_RES from gal_env.txt wins over the Audi default" PASS || { res "I GAL_CLUSTER_RES from gal_env.txt wins" FAIL; cat $GE; }
printf 'GAL_CLUSTER_LOG=1\n' > "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"; run >/dev/null; "$M" "$MOD_PATH/uninstall.sh" >/dev/null 2>&1
[[ ! -f $GE && ! -d /mnt/app/eso/bin/apps/cluster ]] && res "I uninstall removes gal_env via manifest" PASS || res "I uninstall removes gal_env" FAIL
printf 'on\n' > "$SCR/fakesd/Mods/ClusterIntegration/daemon_log.txt"; out=$(run)
DV=/mnt/app/eso/bin/apps/cluster/daemon_verbose
[[ -f $DV ]] && echo "$out" | grep -q 'daemon log:        ON' && res "I daemon_log.txt installs the daemon_verbose marker" PASS || res "I daemon_log.txt marker" FAIL
rm -f "$SCR/fakesd/Mods/ClusterIntegration/daemon_log.txt"; out=$(run)
[[ ! -f $DV ]] && echo "$out" | grep -q 'daemon log:        OFF' && res "I daemon_verbose removed when daemon_log.txt is gone" PASS || res "I daemon_verbose removed" FAIL
DS=/mnt/app/eso/bin/apps/cluster/daemon_size
echo "$out" | grep -q 'cockpit size:      detected by the daemon (cockpit_size=1920x722 in settings.txt' && [[ ! -f $DS ]] && res "I no cockpit_size.txt: daemon detects the size" PASS || res "I no cockpit_size.txt" FAIL
printf '1920x722\r\n' > "$SCR/fakesd/Mods/ClusterIntegration/cockpit_size.txt"; out=$(run)
[[ "$(cat $DS 2>/dev/null)" == 'xres=1920 yres=722' ]] && echo "$out" | grep -q 'cockpit size:      xres=1920 yres=722 (cockpit_size.txt' && res "I cockpit_size.txt installs daemon_size (CR dropped)" PASS || { res "I cockpit_size.txt installs daemon_size" FAIL; cat $DS; }
grep -q "add $DS" "$MOD_PATH/Backup/manifest.txt" && res "I daemon_size recorded as add" PASS || res "I daemon_size recorded as add" FAIL
out=$(run); echo "$out" | grep -q "skip identical:    $DS" && res "I unchanged cockpit size is not rewritten" PASS || res "I unchanged cockpit size" FAIL
printf '# Q3\n  1280 X 640   # first valid line wins\n1540x720\n' > "$SCR/fakesd/Mods/ClusterIntegration/cockpit_size.txt"; out=$(run)
[[ "$(cat $DS 2>/dev/null)" == 'xres=1280 yres=640' ]] && res "I cockpit size: comments and blanks dropped, first valid line wins" PASS || { res "I cockpit size comments" FAIL; cat $DS; }
printf 'xres=1920 yres=722; rm -rf /\n32x722\n1920x5000\n1920\n' > "$SCR/fakesd/Mods/ClusterIntegration/cockpit_size.txt"; out=$(run)
[[ ! -f $DS ]] && echo "$out" | grep -q 'cockpit size:      WARN cockpit_size.txt has no line like 1920x722' && echo "$out" | grep -q "cockpit size:      detected by the daemon (removed $DS)" && res "I invalid cockpit_size.txt is ignored and daemon_size removed" PASS || { res "I invalid cockpit_size.txt" FAIL; cat $DS; }
printf '1920x722\n' > "$SCR/fakesd/Mods/ClusterIntegration/cockpit_size.txt"; run >/dev/null; rm -f "$SCR/fakesd/Mods/ClusterIntegration/cockpit_size.txt"; out=$(run)
[[ ! -f $DS ]] && echo "$out" | grep -q "cockpit size:      detected by the daemon (removed $DS)" && res "I daemon_size removed when cockpit_size.txt is gone" PASS || res "I daemon_size removed" FAIL
printf '1920x722\n' > "$SCR/fakesd/Mods/ClusterIntegration/cockpit_size.txt"; run >/dev/null; rm -f "$MOD_PATH/Backup/manifest.txt"; "$M" "$MOD_PATH/uninstall.sh" >/dev/null 2>&1
[[ ! -f $DS ]] && res "I uninstall removes daemon_size without a manifest" PASS || res "I uninstall removes daemon_size" FAIL
rm -f "$SCR/fakesd/Mods/ClusterIntegration/cockpit_size.txt"
HF=/mnt/app/eso/bin/apps/cluster/hud_feed
out=$(run)
echo "$out" | grep -q 'hud arrows:        OFF (trial; hud_navigation=1 in settings.txt' && [[ ! -f $HF ]] && res "I no hud_arrows.txt: head-up trial off" PASS || res "I no hud_arrows.txt" FAIL
: > "$SCR/fakesd/Mods/ClusterIntegration/hud_arrows.txt"; out=$(run)
[[ "$(cat $HF 2>/dev/null)" == 1 ]] && echo "$out" | grep -q 'hud arrows:        ON, level 1' && res "I empty hud_arrows.txt installs hud_feed with level 1" PASS || { res "I hud_arrows.txt installs hud_feed" FAIL; cat $HF; }
grep -q "add $HF" "$MOD_PATH/Backup/manifest.txt" && res "I hud_feed recorded as add" PASS || res "I hud_feed recorded as add" FAIL
out=$(run); echo "$out" | grep -q "skip identical:    $HF" && res "I unchanged hud level is not rewritten" PASS || res "I unchanged hud level" FAIL
printf '2\r\nside streets too\n' > "$SCR/fakesd/Mods/ClusterIntegration/hud_arrows.txt"; out=$(run)
[[ "$(cat $HF 2>/dev/null)" == 2 ]] && echo "$out" | grep -q 'hud arrows:        ON, level 2' && res "I hud_arrows.txt starting with 2 sets level 2 (CR ignored)" PASS || { res "I hud level 2" FAIL; cat $HF; }
printf 'yes; rm -rf /\n' > "$SCR/fakesd/Mods/ClusterIntegration/hud_arrows.txt"; out=$(run)
[[ "$(cat $HF 2>/dev/null)" == 1 ]] && res "I any other hud_arrows.txt content means level 1" PASS || { res "I hud level from other content" FAIL; cat $HF; }
rm -f "$SCR/fakesd/Mods/ClusterIntegration/hud_arrows.txt"; out=$(run)
[[ ! -f $HF ]] && echo "$out" | grep -q "hud arrows:        OFF (removed $HF)" && res "I hud_feed removed when hud_arrows.txt is gone" PASS || res "I hud_feed removed" FAIL
: > "$SCR/fakesd/Mods/ClusterIntegration/hud_arrows.txt"; run >/dev/null; rm -f "$MOD_PATH/Backup/manifest.txt"; "$M" "$MOD_PATH/uninstall.sh" >/dev/null 2>&1
[[ ! -f $HF ]] && res "I uninstall removes hud_feed without a manifest" PASS || res "I uninstall removes hud_feed" FAIL
rm -f "$SCR/fakesd/Mods/ClusterIntegration/hud_arrows.txt"
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" /tmp/gal_preload.log
echo "=== J: review fixes (stub kept without audi/, weak comparator + mtime)"
setup MH2p_ER_AUG35_P2873 aa aa ""; run >/dev/null; [[ -f $STUB ]] || res "J precondition stub installed" FAIL
rm -rf "$MOD_PATH/audi"; out=$(run)
[[ -f $STUB ]] && echo "$out" | grep -q 'stand-in class:    kept' && res "J stub kept when the card has no audi/ folder" PASS || res "J stub kept without audi/" FAIL
setup MH2p_ER_AUG35_P2873 aa aa ""; run >/dev/null
# same-size edit on the card (2000 -> 3000): must be installed
sed -i 's/"heartbeatInterval": 2000/"heartbeatInterval": 3000/' "$MOD_PATH/cluster_config.json"; out=$(run)
grep -q '"heartbeatInterval": 3000' /mnt/app/eso/bin/apps/cluster/cluster_config.json && echo "$out" | grep -q 'backup target:     /mnt/app/eso/bin/apps/cluster/cluster_config.json' && res "J same-size config edit installed (not skipped)" PASS || res "J same-size config edit installed" FAIL
# same-size, same-counts binary with a new mtime: must be installed
printf 'payload cluster\n' > "$MOD_PATH/aa_only/cluster"; run >/dev/null; printf 'payloae cluster\n' > "$MOD_PATH/aa_only/cluster"; out=$(run)
[[ "$(cat /mnt/app/eso/bin/apps/cluster/cluster)" == "payloae cluster" ]] && res "J same-size same-counts binary installed" PASS || { res "J same-size binary installed" FAIL; echo "$out" | grep cluster/cluster; }
# unchanged file: still skipped on the next run
out=$(run); echo "$out" | grep -q 'skip identical:    /mnt/app/eso/bin/apps/cluster/cluster$' && res "J unchanged file still skipped" PASS || res "J unchanged file still skipped" FAIL
# backup verification still passes with cp -p copies
printf 'payloaf cluster\n' > "$MOD_PATH/aa_only/cluster"; out=$(run); echo "$out" | grep -q 'ERROR: backup verify' && res "J backup verify ok with mtime rule" FAIL || res "J backup verify ok with mtime rule" PASS
echo "=== K: signature check ignores the mod's own jars"
rm -rf "$SCR/refk" && mkdir -p "$SCR/refk/Update/audi" && cp "$REPO/modkit/Mods/ClusterIntegration/Update/audi/ClusterIntegration_StorageMountHandler_stub.jar" "$SCR/refk/Update/audi/" && mkjar "$SCR/refk/lsd.jar" 0 $AA.class
out=$(JAVA_TOOL_OPTIONS= bash "$REPO/modkit/check_hmi_signatures.sh" "$SCR/zip34/Mods/ClusterIntegration/Update/ClusterIntegration_v0034_beta2_candidate_90d0b76.jar" "$SCR/refk" 2>&1)
echo "$out" | grep -q '^ABSENT' && res "K stub jar on the card is not counted as stock" PASS || { res "K stub jar not counted" FAIL; echo "$out" | head -3; }
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" "$SCR/refk" /tmp/gal_preload.log
echo "=== L: fresh Audi install without the stand-in jar aborts; jxe-only hit treated as unknown; UNKNOWN verdict"
setup MH2p_ER_AUG35_P2873 aa aa ""; rm -rf "$MOD_PATH/audi"; out=$(run); rc=$?
[[ $rc == 4 && ! -f /mnt/app/eso/bin/apps/gal.real && -z "$(ls /mnt/app/eso/hmi/lsd/jars | grep ClusterIntegration)" ]] && echo "$out" | grep -q 'no stand-in is installed on this unit. Aborting' && res "L abort before any change without stand-in source" PASS || res "L abort without stand-in source" "FAIL (rc=$rc)"
setup MH2p_ER_AUG35_P2873 aa aa+sm ""; out=$(run)
if echo "$out" | grep -q 'binary search:     grep'; then
  echo "$out" | grep -q 'only /ifs/lsd.jxe matched' && [[ -f $STUB ]] && res "L jxe-only hit with lsd.jar lacking the class -> unknown, stub kept" PASS || { res "L jxe-only hit -> unknown" FAIL; echo "$out" | grep -E 'hmi class|stand-in'; }
else
  res "L jxe-only hit -> unknown" "n/a (no grep search on this toolset)"
fi
rm -rf "$SCR/refl" && mkdir -p "$SCR/refl" && mkjar "$SCR/refl/plugin.jar" 0 de/audi/plugins/x/P.class
out=$(JAVA_TOOL_OPTIONS= bash "$REPO/modkit/check_hmi_signatures.sh" "$SCR/zip34/Mods/ClusterIntegration/Update/ClusterIntegration_v0034_beta2_candidate_90d0b76.jar" "$SCR/refl" 2>&1)
echo "$out" | grep -q '^UNKNOWN' && res "L signature check: UNKNOWN without the stock classes" PASS || { res "L UNKNOWN verdict" FAIL; echo "$out" | head -3; }
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" "$SCR/refl" /tmp/gal_preload.log
echo "=== M: reinstall.sh runs the installer from its own folder"
setup MH2p_ER_AUG35_P2873 aa aa ""; unset MOD_PATH; out=$(cd / && "$M" "$SCR/fakesd/Mods/ClusterIntegration/Update/reinstall.sh" 2>&1); rc=$?
[[ $rc == 0 && -f /mnt/app/eso/hmi/lsd/jars/ClusterIntegration_v0034_beta2_candidate_90d0b76_aa.jar ]] && echo "$out" | grep -q 'Backups:' && res "M reinstall.sh installs without MOD_PATH" PASS || res "M reinstall.sh" "FAIL (rc=$rc)"
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" /tmp/gal_preload.log
echo "=== N: FAT-like backup timestamps must not fail verification"
setup MH2p_ER_AUG35_P2873 aa aa ""; printf 'GAL_CLUSTER_LOG=1\n' > "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"; run >/dev/null
sed -i 's/"heartbeatInterval": 2000/"heartbeatInterval": 2500/' "$MOD_PATH/cluster_config.json"
printf 'GAL_CLUSTER_LOG=1\nGAL_CLUSTER_INSET_LEFT=480\n' > "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"
out=$(run)
echo "$out" | grep -q 'ERROR: backup verify failed' && { res "N no backup verify errors with FAT-like times" FAIL; echo "$out" | grep ERROR; } || res "N no backup verify errors with FAT-like times" PASS
grep -q '"heartbeatInterval": 2500' /mnt/app/eso/bin/apps/cluster/cluster_config.json && res "N changed config installed" PASS || res "N changed config installed" FAIL
grep -q 'GAL_CLUSTER_INSET_LEFT=480' /mnt/app/eso/bin/apps/cluster/gal_env && res "N changed gal_env installed" PASS || res "N changed gal_env installed" FAIL
out=$(run); echo "$out" | grep -q 'skip identical:    /mnt/app/eso/bin/apps/cluster/gal_env' && res "N unchanged gal_env skipped by content" PASS || res "N unchanged gal_env skipped" FAIL
ls "$MOD_PATH/Backup" | grep -q 'cluster_config.json.backup' && res "N backup of the replaced config exists" PASS || res "N backup exists" FAIL
echo "=== P: a same-length edit of a staged text file is a change"
setup MH2p_ER_AUG35_P2711 aa aa "enable_carplay_altscreen.txt"
printf 'GAL_CLUSTER_INSET_LEFT=480\n' > "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"
printf 'large=500,155,940,360\n' > "$SCR/fakesd/Mods/ClusterIntegration/altscreen_conf.txt"
run >/dev/null
printf 'GAL_CLUSTER_INSET_LEFT=490\n' > "$SCR/fakesd/Mods/ClusterIntegration/gal_env.txt"
printf 'large=500,155,940,390\r\n' > "$SCR/fakesd/Mods/ClusterIntegration/altscreen_conf.txt"
out=$(run)
grep -q 'GAL_CLUSTER_INSET_LEFT=490' /mnt/app/eso/bin/apps/cluster/gal_env && res "P gal_env: 480 -> 490 installed" PASS || res "P gal_env: 480 -> 490 installed" FAIL
[[ "$(cat /mnt/app/eso/bin/apps/cluster/altscreen.conf 2>/dev/null)" == 'large=500,155,940,390' ]] && res "P altscreen.conf: 360 -> 390 installed" PASS || res "P altscreen.conf: 360 -> 390 installed" FAIL
out=$(run)
echo "$out" | grep -q 'skip identical:    /mnt/app/eso/bin/apps/cluster/gal_env' && echo "$out" | grep -q 'skip identical:    /mnt/app/eso/bin/apps/cluster/altscreen.conf' && res "P unchanged files skipped on the next run" PASS || res "P unchanged files skipped on the next run" FAIL
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" /tmp/gal_preload.log
echo "=== Q: navigation box (nav_box.txt): dog.so and one more dependency in the navigation's libwatchdog.so"
NV=/mnt/app/navigation; AC=/mnt/app/eso/bin/apps/cluster; NB="$SCR/fakesd/Mods/ClusterIntegration/nav_box.txt"
PY="$(command -v python3)"; RABS="$(cd "$REPO" && pwd)"
navsetup() { # $1 release  $2 spare slots  $3 size of the navigation program
  setup "$1" aa aa ""; mkdir -p $NV; "$PY" "$RABS/modkit/test/fake_watchdog.py" $NV/libwatchdog.so "$2"; chmod 755 $NV/libwatchdog.so
  "$PY" -c 'import sys; open(sys.argv[1], "wb").truncate(int(sys.argv[2]))' $NV/navStartup "$3"; cp $NV/libwatchdog.so "$SCR/wd.orig"
}
standin() { printf '#!/bin/sh\nexec %s %s/src/navhook/add_needed.py "$@"\n' "$PY" "$RABS" > "$MOD_PATH/navhook/addneeded"; }
broken() { printf '#!/bin/sh\nexit 126\n' > "$MOD_PATH/navhook/addneeded"; }
needs() { "$PY" "$RABS/src/navhook/add_needed.py" check $NV/libwatchdog.so dog.so >/dev/null 2>&1; }
noswitch() { [[ ! -f $AC/komo_feed && ! -f $AC/komo_show && ! -f $AC/komo_hook ]]; }
navsetup MH2p_ER_AUG35_P2711 4 47516812; out=$(run)
echo "$out" | grep -q 'nav box:           OFF (trial, Audi P2711 and P2873; turn_box=1 in settings.txt' && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so ]] && noswitch && res "Q no nav_box.txt: off, navigation untouched" PASS || res "Q no nav_box.txt" FAIL
touch "$NB"; out=$(run)
echo "$out" | grep -q 'nav box:           skipped (the helper navhook/addneeded does not run on this unit; nothing changed)' && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so && ! -f $NV/libwatchdog.so.orig ]] && noswitch && res "Q the unit's helper does not run here: skipped, nothing changed" PASS || { res "Q helper does not run" FAIL; echo "$out" | grep 'nav box'; }
standin; out=$(run)
echo "$out" | grep -q 'nav box:           ON (trial' && needs && cmp -s "$MOD_PATH/navhook/dog.so" $NV/dog.so && res "Q installed: dog.so in place and named by libwatchdog.so" PASS || { res "Q installed" FAIL; echo "$out" | grep -E 'nav box|ERROR'; }
cmp -s $NV/libwatchdog.so.orig "$SCR/wd.orig" && cmp -s "$MOD_PATH/Backup/libwatchdog.so.original" "$SCR/wd.orig" && res "Q original kept next to the library and on the card" PASS || res "Q original kept" FAIL
[[ -f $AC/komo_feed && -f $AC/komo_show && -f $AC/komo_hook ]] && res "Q the three switches are set" PASS || res "Q switches set" FAIL
grep -q "replace $NV/libwatchdog.so backup=$MOD_PATH/Backup/libwatchdog.so.original" "$MOD_PATH/Backup/manifest.txt" && grep -q "add $NV/dog.so" "$MOD_PATH/Backup/manifest.txt" && grep -q "add $AC/komo_hook" "$MOD_PATH/Backup/manifest.txt" && res "Q recorded in the manifest" PASS || res "Q manifest" FAIL
[[ "$(ls -l $NV/libwatchdog.so | awk '{print $5}')" == "$(ls -l "$SCR/wd.orig" | awk '{print $5}')" && -x $NV/libwatchdog.so && -x $NV/dog.so ]] && res "Q same size, both readable and executable" PASS || res "Q size and mode" FAIL
ls /tmp/cluster_addneeded.* /tmp/cluster_watchdog.* $NV/*.new >/dev/null 2>&1 && res "Q no work files left" FAIL || res "Q no work files left" PASS
cp $NV/libwatchdog.so "$SCR/wd.patched"; out=$(run)
echo "$out" | grep -q 'nav box:           libwatchdog.so names dog.so already' && echo "$out" | grep -q "skip identical:    $NV/dog.so" && cmp -s $NV/libwatchdog.so "$SCR/wd.patched" && cmp -s $NV/libwatchdog.so.orig "$SCR/wd.orig" && res "Q second run changes nothing" PASS || { res "Q second run" FAIL; echo "$out" | grep -E 'nav box|dog.so'; }
rm -f "$NB"; out=$(run)
cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so && ! -f $NV/libwatchdog.so.orig ]] && noswitch && echo "$out" | grep -q "restore original:  $NV/libwatchdog.so" && res "Q without nav_box.txt: original bytes back, dog.so and switches gone" PASS || { res "Q removed with the file" FAIL; echo "$out" | grep -E 'nav box|restore|dog.so'; }
touch "$NB"; run >/dev/null; needs || res "Q precondition: installed again" FAIL
rm -f "$MOD_PATH/Backup/manifest.txt"; "$M" "$MOD_PATH/uninstall.sh" >/dev/null 2>&1
cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so && ! -f $NV/libwatchdog.so.orig ]] && noswitch && res "Q uninstall: original bytes back, dog.so and switches gone (no manifest)" PASS || res "Q uninstall" FAIL
run >/dev/null; needs || res "Q precondition: installed a third time" FAIL
broken; out=$("$M" "$MOD_PATH/uninstall.sh" 2>&1)
cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so ]] && echo "$out" | grep -q "restore original:  $NV/libwatchdog.so.orig -> $NV/libwatchdog.so" && res "Q uninstall without a working helper: the kept original goes back" PASS || { res "Q uninstall without helper" FAIL; echo "$out" | grep -E 'nav box|restore'; }
standin; : > "$NB"; run >/dev/null; needs || res "Q precondition: installed a fourth time" FAIL
broken; rm -f $NV/libwatchdog.so.orig "$MOD_PATH/Backup"/libwatchdog.so.original*; out=$("$M" "$MOD_PATH/uninstall.sh" 2>&1)
needs && cmp -s "$MOD_PATH/navhook/dog.so" $NV/dog.so && noswitch && echo "$out" | grep -q "nav box:           WARN could not take dog.so out of $NV/libwatchdog.so" && res "Q no helper and no copy: dog.so stays with the library that needs it, switches gone" PASS || { res "Q dog.so stays" FAIL; echo "$out" | grep -E 'nav box|restore'; }
standin; out=$("$M" "$MOD_PATH/uninstall.sh" 2>&1)
cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so ]] && res "Q a later uninstall with a working helper finishes the job" PASS || res "Q later uninstall" FAIL
navsetup MH2p_ER_AUG35_P2711 4 48000000; touch "$NB"; standin; out=$(run)
echo "$out" | grep -q 'nav box:           skipped (the navigation program is none of the builds the hook was written for: 48000000 bytes, known are 47516812 47923536' && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so ]] && noswitch && res "Q another navigation build: skipped, nothing changed" PASS || { res "Q another build" FAIL; echo "$out" | grep 'nav box'; }
navsetup MH2p_ER_AUG35_P2711 0 47516812; touch "$NB"; standin; out=$(run)
echo "$out" | grep -q 'nav box:           skipped (libwatchdog.so cannot take the dependency: addneeded: no spare slot' && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so ]] && noswitch && res "Q library without a spare slot: skipped, nothing changed" PASS || { res "Q no spare slot" FAIL; echo "$out" | grep 'nav box'; }
navsetup MH2p_ER_AUG35_P2873 4 47923536; touch "$NB"; standin; out=$(run)
echo "$out" | grep -q 'nav box:           ON (trial' && needs && cmp -s "$MOD_PATH/navhook/dog.so" $NV/dog.so && cmp -s $NV/libwatchdog.so.orig "$SCR/wd.orig" && [[ -f $AC/komo_feed && -f $AC/komo_show && -f $AC/komo_hook ]] && res "Q P2873 with its navigation build: installed like on P2711" PASS || { res "Q P2873 installed" FAIL; echo "$out" | grep -E 'nav box|ERROR'; }
rm -f "$NB"; out=$(run)
cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so && ! -f $NV/libwatchdog.so.orig ]] && noswitch && res "Q P2873 without nav_box.txt: original bytes back" PASS || { res "Q P2873 removed" FAIL; echo "$out" | grep -E 'nav box|ERROR'; }
navsetup MH2p_ER_AUG35_P2873 4 48000000; touch "$NB"; standin; out=$(run)
echo "$out" | grep -q 'nav box:           skipped (the navigation program is none of the builds' && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so ]] && noswitch && res "Q P2873 with an unknown navigation build: skipped, nothing changed" PASS || { res "Q P2873 unknown build" FAIL; echo "$out" | grep 'nav box'; }
HA="$SCR/fakesd/Mods/ClusterIntegration/hud_arrows.txt"; HF2=/mnt/app/eso/bin/apps/cluster/hud_feed
navsetup MH2p_ER_AUG35_P2711 4 47516812; touch "$HA"; standin; out=$(run)
echo "$out" | grep -q 'hud scene:         ON (the navigation hook draws the arrow on the head-up display, without the box in the cockpit)' && needs && cmp -s "$MOD_PATH/navhook/dog.so" $NV/dog.so && [[ -f $AC/komo_hook && -f $HF2 && ! -f $AC/komo_feed && ! -f $AC/komo_show ]] && echo "$out" | grep -q 'nav box:           OFF (trial' && res "Q hud_arrows.txt alone: hook and its switch, no box switches" PASS || { res "Q hud_arrows alone" FAIL; echo "$out" | grep -E 'nav box|hud|ERROR'; }
touch "$NB"; out=$(run)
echo "$out" | grep -q 'hud scene:         ON (the navigation hook draws the arrow on the head-up display, with the box in the cockpit)' && echo "$out" | grep -q 'nav box:           ON (trial' && [[ -f $AC/komo_hook && -f $AC/komo_feed && -f $AC/komo_show ]] && needs && res "Q hud_arrows.txt and nav_box.txt: all three switches" PASS || { res "Q hud and box" FAIL; echo "$out" | grep -E 'nav box|hud|ERROR'; }
rm -f "$NB"; out=$(run)
[[ -f $AC/komo_hook && ! -f $AC/komo_feed && ! -f $AC/komo_show ]] && needs && echo "$out" | grep -q "nav box:           removed $AC/komo_show" && res "Q nav_box.txt taken away, hud_arrows.txt stays: box switches go, the hook stays" PASS || { res "Q box off, hud stays" FAIL; echo "$out" | grep -E 'nav box|hud|ERROR'; }
touch "$NB"; rm -f "$HA"; out=$(run)
[[ -f $AC/komo_hook && -f $AC/komo_feed && -f $AC/komo_show && ! -f $HF2 ]] && needs && ! echo "$out" | grep -q 'hud scene' && res "Q hud_arrows.txt taken away, nav_box.txt stays: the box as before, no hud line" PASS || { res "Q hud off, box stays" FAIL; echo "$out" | grep -E 'nav box|hud|ERROR'; }
rm -f "$NB"; out=$(run)
cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so && ! -f $NV/libwatchdog.so.orig ]] && noswitch && res "Q neither file: original bytes back, everything gone" PASS || { res "Q neither" FAIL; echo "$out" | grep -E 'nav box|hud|ERROR'; }
navsetup MH2p_ER_AUG35_P2718 4 47516812; touch "$HA"; standin; out=$(run)
echo "$out" | grep -q 'hud scene:         OFF (the arrow on the head-up display needs the navigation hook, Audi software P2711 and P2873 only, this is oem=AU sw=2718' && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so && -f $HF2 ]] && noswitch && res "Q hud_arrows.txt on another Audi software: feed on, no hook, said so" PASS || { res "Q hud on P2718" FAIL; echo "$out" | grep -E 'nav box|hud|ERROR'; }
navsetup MH2p_ER_AUG35_P2711 4 48000000; touch "$HA"; standin; out=$(run)
echo "$out" | grep -q 'hud scene:         OFF (the navigation hook could not be installed' && [[ ! -f $NV/dog.so ]] && noswitch && res "Q hud_arrows.txt with an unknown navigation build: no hook, said so" PASS || { res "Q hud unknown build" FAIL; echo "$out" | grep -E 'nav box|hud|ERROR'; }
rm -f "$HA"
NT="$SCR/fakesd/Mods/ClusterIntegration/nav_box_tabs.txt"; NF="$SCR/fakesd/Mods/ClusterIntegration/nav_flag.txt"
navsetup MH2p_ER_AUG35_P2711 4 47516812; touch "$NB"; standin; out=$(run)
echo "$out" | grep -q 'nav box tabs:      OFF (trial; the box stays over' && echo "$out" | grep -q 'nav flag:          OFF (trial; destination_flag=1 in settings.txt' && [[ ! -f $AC/komo_tab && ! -f $AC/komo_dest ]] && res "Q box without nav_box_tabs.txt and nav_flag.txt: both off, said so" PASS || { res "Q tabs and flag off" FAIL; echo "$out" | grep -E 'nav box|nav flag'; }
touch "$NT" "$NF"; out=$(run)
echo "$out" | grep -q 'nav box tabs:      ON (trial' && echo "$out" | grep -q 'nav flag:          ON (trial' && [[ -f $AC/komo_tab && -f $AC/komo_dest ]] && grep -q "add $AC/komo_tab" "$MOD_PATH/Backup/manifest.txt" && grep -q "add $AC/komo_dest" "$MOD_PATH/Backup/manifest.txt" && res "Q nav_box_tabs.txt and nav_flag.txt with the box: both switches set and recorded" PASS || { res "Q tabs and flag on" FAIL; echo "$out" | grep -E 'nav box|nav flag'; }
echo test > $AC/komo_dest; out=$(run)
[[ "$(cat $AC/komo_dest)" == test ]] && echo "$out" | grep -q 'nav flag:          ON (trial' && res "Q a switch that is there keeps its content" PASS || res "Q switch content kept" FAIL
rm -f "$NB"; touch "$HA"; out=$(run)
[[ ! -f $AC/komo_tab && -f $AC/komo_dest ]] && echo "$out" | grep -q "nav box tabs:      removed $AC/komo_tab" && echo "$out" | grep -q 'nav box tabs:      ignored (turn_box_on_map=0 needs the box in the cockpit' && echo "$out" | grep -q 'nav flag:          ON (trial' && res "Q head-up display without the box: the flag stays, the tab switch goes and is called ignored" PASS || { res "Q flag with hud only" FAIL; echo "$out" | grep -E 'nav box|nav flag'; }
rm -f "$HA"; out=$(run)
[[ ! -f $AC/komo_tab && ! -f $AC/komo_dest ]] && echo "$out" | grep -q "nav flag:          removed $AC/komo_dest" && echo "$out" | grep -q 'nav flag:          ignored (destination_flag needs the navigation hook' && res "Q neither box nor head-up display: the flag switch goes and is called ignored" PASS || { res "Q flag without hook" FAIL; echo "$out" | grep -E 'nav box|nav flag'; }
touch "$NB"; run >/dev/null; rm -f "$NT" "$NF"; out=$(run)
[[ ! -f $AC/komo_tab && ! -f $AC/komo_dest && -f $AC/komo_show ]] && echo "$out" | grep -q "nav box tabs:      removed $AC/komo_tab" && echo "$out" | grep -q "nav flag:          removed $AC/komo_dest" && res "Q the two files taken away: switches removed, the box stays" PASS || { res "Q tabs and flag removed" FAIL; echo "$out" | grep -E 'nav box|nav flag'; }
touch "$NT" "$NF"; run >/dev/null; [[ -f $AC/komo_tab && -f $AC/komo_dest ]] || res "Q precondition: tab and flag switches set again" FAIL
rm -f "$MOD_PATH/Backup/manifest.txt"; "$M" "$MOD_PATH/uninstall.sh" >/dev/null 2>&1
[[ ! -f $AC/komo_tab && ! -f $AC/komo_dest ]] && noswitch && res "Q uninstall removes the tab and flag switches (no manifest)" PASS || res "Q uninstall tab and flag" FAIL
navsetup MH2p_ER_AUG35_P2718 4 47516812; touch "$NB" "$NT" "$NF"; standin; out=$(run)
echo "$out" | grep -q 'nav box tabs:      ignored' && echo "$out" | grep -q 'nav flag:          ignored' && [[ ! -f $AC/komo_tab && ! -f $AC/komo_dest ]] && res "Q another Audi software: tab and flag files ignored" PASS || { res "Q tabs and flag on P2718" FAIL; echo "$out" | grep -E 'nav box|nav flag'; }
rm -f "$NT" "$NF"
navsetup MH2p_ER_AUG35_P2718 4 47516812; touch "$NB"; standin; out=$(run)
echo "$out" | grep -q 'nav box:           ignored (turn_box works on Audi software P2711 and P2873 only, this is oem=AU sw=2718)' && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && [[ ! -f $NV/dog.so ]] && noswitch && res "Q another Audi software (P2718): ignored, nothing changed" PASS || { res "Q P2718 ignored" FAIL; echo "$out" | grep 'nav box'; }
setup MH2p_ER_AUG35_P2711 aa aa "nav_box.txt"; standin; out=$(run)
echo "$out" | grep -q "nav box:           skipped (no navigation under $NV)" && res "Q no navigation folder: skipped" PASS || { res "Q no navigation folder" FAIL; echo "$out" | grep 'nav box'; }
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" "$SCR/wd.orig" "$SCR/wd.patched" /tmp/gal_preload.log
echo "=== S: settings.txt: one file for the switches and the CarPlay map; the single files count where it is silent"
SD="$SCR/fakesd/Mods/ClusterIntegration"; SF="$SD/settings.txt"; SC=$AC/altscreen.conf; DS=$AC/daemon_size
navsetup MH2p_ER_AUG35_P2711 4 47516812; standin; out=$(run)
echo "$out" | grep -q 'settings:          no settings.txt on the card, the single files count' && res "S no settings.txt: said so, the single files count" PASS || res "S no settings.txt" FAIL
rm -f /tmp/settings_pwn
printf '# my car\r\nturn_box = 1   # the box\r\nturn_box_on_map=0\r\nhud_navigation=2\r\ndestination_flag=1\r\ncarplay_map=1\r\nmap_turn_card=0\r\nmap_arrival_line=0\r\nmap_area_large=500,155,940,390\r\nzoom_max=12\r\nturnbox=1\r\nhud_navigation=7\r\nPATH=/evil\r\nturn_box=1;touch /tmp/settings_pwn\r\nmap_ports=$(touch /tmp/settings_pwn)\r\n' > "$SF"; out=$(run)
echo "$out" | grep -q 'settings:          settings.txt: turn_box=1 turn_box_on_map=0 hud_navigation=2 destination_flag=1 carplay_map=1 map_turn_card=0 map_arrival_line=0 map_area_large=500,155,940,390 zoom_max=12$' && res "S settings.txt read: CR, blanks and comments dropped, the keys listed" PASS || { res "S settings.txt read" FAIL; echo "$out" | grep 'settings:'; }
[[ $(echo "$out" | grep -c 'settings:          WARN line ignored') -eq 5 ]] && echo "$out" | grep -q 'WARN line ignored (no known key=value): turnbox=1' && echo "$out" | grep -q 'WARN line ignored (no known key=value): hud_navigation=7' && [[ ! -e /tmp/settings_pwn ]] && [[ "$PATH" != /evil ]] && res "S unknown keys and bad values are named and ignored, nothing is run" PASS || { res "S bad lines" FAIL; echo "$out" | grep 'settings:'; ls -la /tmp/settings_pwn 2>&1; }
echo "$out" | grep -q 'nav box:           ON (trial' && echo "$out" | grep -q 'nav box tabs:      ON (trial' && echo "$out" | grep -q 'nav flag:          ON (trial' && [[ -f $AC/komo_show && -f $AC/komo_tab && -f $AC/komo_dest && -f $NV/dog.so ]] && res "S turn_box, turn_box_on_map=0, destination_flag: box, tab switch and flag set" PASS || { res "S box, tabs, flag from settings.txt" FAIL; echo "$out" | grep -E 'nav box|nav flag'; }
[[ "$(cat $HF2 2>/dev/null)" == 2 ]] && echo "$out" | grep -q 'hud arrows:        ON, level 2' && echo "$out" | grep -q 'hud scene:         ON' && res "S hud_navigation=2: head-up display with side streets" PASS || { res "S hud_navigation" FAIL; echo "$out" | grep hud; }
[[ -f $AC/altscreen.so ]] && echo "$out" | grep -q 'carplay altscreen: ON' && res "S carplay_map=1: the map hook is installed without enable_carplay_altscreen.txt" PASS || { res "S carplay_map" FAIL; echo "$out" | grep 'carplay'; }
[[ -f $AC/carplay_turns ]] && echo "$out" | grep -q 'carplay turns:     ON' && res "S CarPlay turn data comes with the box, without a line of its own" PASS || { res "S carplay turns follow the box" FAIL; echo "$out" | grep 'carplay turns'; }
[[ "$(cat $SC 2>/dev/null)" == $'turncard=0\neta=0\nlarge=500,155,940,390\nzoom_max=12' ]] && res "S map_ and zoom_ keys become altscreen.conf under the hook's names" PASS || { res "S map keys" FAIL; cat $SC; }
out=$(run); echo "$out" | grep -q "skip identical:    $SC" && echo "$out" | grep -q "skip identical:    $HF2" && res "S a second run changes nothing" PASS || { res "S second run" FAIL; echo "$out" | grep -E 'altscreen conf|skip identical'; }
printf 'large=1,2,3,4\nphys=300,100\n' > "$SD/altscreen_conf.txt"; out=$(run)
[[ "$(cat $SC 2>/dev/null)" == $'large=500,155,940,390\nphys=300,100\nturncard=0\neta=0\nzoom_max=12' ]] && res "S altscreen_conf.txt and settings.txt together: one line per key, settings.txt wins" PASS || { res "S conf merge" FAIL; cat $SC; }
rm -f "$SD/altscreen_conf.txt"; printf 'turn_box=1\ncarplay_map=1\ncarplay_turns=0\n' > "$SF"; out=$(run)
[[ ! -f $SC ]] && echo "$out" | grep -q 'altscreen conf:    settings.txt has no setting, removed' && res "S settings.txt without a map key: altscreen.conf removed, defaults again" PASS || { res "S conf removed" FAIL; echo "$out" | grep 'altscreen conf'; }
[[ ! -f $AC/carplay_turns && ! -f $AC/komo_tab && ! -f $AC/komo_dest && ! -f $HF2 && -f $AC/komo_show ]] && res "S lines taken out: flag, tab switch, head-up display go, carplay_turns=0 overrules, the box stays" PASS || { res "S lines taken out" FAIL; ls $AC; }
touch "$SD/nav_box.txt" "$SD/nav_box_tabs.txt" "$SD/nav_flag.txt" "$SD/hud_arrows.txt" "$SD/enable_carplay_altscreen.txt" "$SD/carplay_turns.txt" "$SD/daemon_log.txt"; printf '1920x722\n' > "$SD/cockpit_size.txt"
printf '# nothing set\n' > "$SF"; out=$(run)
echo "$out" | grep -q 'settings:          settings.txt: no setting' && [[ -f $AC/komo_show && -f $AC/komo_tab && -f $AC/komo_dest && -f $AC/carplay_turns && -f $AC/altscreen.so && -f $AC/daemon_verbose ]] && [[ "$(cat $HF2)" == 1 && "$(cat $DS)" == 'xres=1920 yres=722' ]] && res "S an empty settings.txt: every single file counts as before" PASS || { res "S single files count" FAIL; ls $AC; }
printf 'turn_box_on_map=1\ndestination_flag=0\nhud_navigation=0\ndaemon_log=0\ncockpit_size=auto\n' > "$SF"; out=$(run)
[[ -f $AC/komo_show && ! -f $AC/komo_tab && ! -f $AC/komo_dest && ! -f $HF2 && ! -f $AC/daemon_verbose && ! -f $DS && -f $AC/altscreen.so ]] && res "S settings.txt wins over the single files, key by key" PASS || { res "S settings.txt wins" FAIL; ls $AC; echo "$out" | grep -E 'nav box|nav flag|hud|daemon log|cockpit size'; }
printf 'turn_box=0\ncarplay_map=0\n' > "$SF"; out=$(run)
[[ -f $NV/dog.so && -f $AC/komo_hook && ! -f $AC/komo_show && ! -f $AC/komo_feed && ! -f $AC/altscreen.so && ! -f $AC/carplay_turns ]] && [[ "$(cat $HF2 2>/dev/null)" == 1 ]] && echo "$out" | grep -q 'hud scene:         ON (the navigation hook draws the arrow on the head-up display, without the box' && res "S turn_box=0 and carplay_map=0 with the files on the card: box and map out, the head-up file still counts" PASS || { res "S switches off" FAIL; ls $AC $NV; echo "$out" | grep -E 'nav box|carplay|hud'; }
rm -f "$SD"/nav_box.txt "$SD"/nav_box_tabs.txt "$SD"/nav_flag.txt "$SD"/hud_arrows.txt "$SD"/enable_carplay_altscreen.txt "$SD"/carplay_turns.txt "$SD"/daemon_log.txt "$SD"/cockpit_size.txt
printf 'cockpit_size=1920X722\ndaemon_log=1\n' > "$SF"; out=$(run)
[[ "$(cat $DS 2>/dev/null)" == 'xres=1920 yres=722' && -f $AC/daemon_verbose ]] && echo "$out" | grep -q 'cockpit size:      xres=1920 yres=722 (cockpit_size in settings.txt' && res "S cockpit_size and daemon_log from settings.txt" PASS || { res "S cockpit_size, daemon_log" FAIL; echo "$out" | grep -E 'cockpit size|daemon log'; }
printf 'cockpit_size=32x722\n' > "$SF"; out=$(run)
[[ ! -f $DS ]] && echo "$out" | grep -q 'cockpit size:      WARN cockpit_size=32x722 in settings.txt is out of range' && res "S a cockpit size out of range is refused" PASS || { res "S cockpit size out of range" FAIL; echo "$out" | grep 'cockpit size'; }
navsetup MH2p_ER_AUG35_P2718 4 47516812; standin; printf 'turn_box=1\nturn_box_on_map=0\ndestination_flag=1\n' > "$SF"; out=$(run)
echo "$out" | grep -q 'nav box:           ignored (turn_box works on Audi software P2711 and P2873 only' && echo "$out" | grep -q 'carplay turns:     OFF' && noswitch && cmp -s $NV/libwatchdog.so "$SCR/wd.orig" && res "S another Audi software: the box from settings.txt is ignored, nothing changed" PASS || { res "S P2718" FAIL; echo "$out" | grep -E 'nav box|carplay turns'; }
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" "$SCR/wd.orig" /tmp/gal_preload.log /tmp/settings_pwn
echo "=== O: gal wrapper starts the cluster daemon when it is missing"
setup MH2p_ER_AUG35_P2873 aa aa ""; run >/dev/null
printf '#!/bin/sh\necho "daemon-stub $*"\nsleep 20\n' > "$MOD_PATH/aa_only/cluster"; run >/dev/null   # a daemon stand-in that stays alive
printf '#!/bin/sh\nexit 0\n' > /mnt/app/eso/bin/apps/gal.real; chmod 755 /mnt/app/eso/bin/apps/gal.real /mnt/app/eso/bin/apps/cluster/cluster
pkill -f '^/bin/sh /mnt/app/eso/bin/apps/cluster/cluster daemon' 2>/dev/null; rm -f /tmp/gal_preload.log
PATH="$SCR/stubs:$PATH" mksh /mnt/app/eso/bin/apps/gal >/dev/null 2>&1; sleep 1
grep -q 'cluster daemon: not running, started by the gal wrapper' /tmp/gal_preload.log && pgrep -f 'cluster daemon verbose=2' >/dev/null && res "O wrapper starts a missing daemon" PASS || { res "O wrapper starts a missing daemon" FAIL; cat /tmp/gal_preload.log; }
PATH="$SCR/stubs:$PATH" mksh /mnt/app/eso/bin/apps/gal >/dev/null 2>&1; sleep 1
[[ $(grep -c 'started by the gal wrapper' /tmp/gal_preload.log) -eq 1 && $(pgrep -fc 'cluster daemon verbose=2') -le 2 ]] && res "O running daemon not started twice" PASS || { res "O daemon not started twice" FAIL; grep -c 'started by' /tmp/gal_preload.log; pgrep -fa 'cluster daemon'; }
pkill -f '^/bin/sh /mnt/app/eso/bin/apps/cluster/cluster daemon' 2>/dev/null; pkill -f '^sleep 20$' 2>/dev/null
rm -rf /mnt/app /fs /ifs "$SCR/jarsrc" /tmp/gal_preload.log
