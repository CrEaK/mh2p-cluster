#!/usr/bin/env bash
set -u
SCR="$1"; REPO="$2"; export PATH="$SCR/stubs:$PATH"
SYMS_SO=$SCR/zip34/Mods/ClusterIntegration/Update/gal_cluster.so
setup() { # $1 release, $2 with_sportchrono, $3 with_aa_jar
  rm -rf /mnt/app /fs; mkdir -p /mnt/app/armle/usr/bin /mnt/app/eso/hmi/lsd/jars /mnt/app/eso/bin/apps /mnt/app/eso/lib
  printf 'GALBIN\n' > /mnt/app/eso/bin/apps/gal; printf 'DIOBIN\n' > /mnt/app/eso/bin/apps/dio_manager; chmod 755 /mnt/app/eso/bin/apps/*
  printf '#!/bin/sh\nprintf "%%060d%%s\\n" 0 "'"$1"'"\n' > /mnt/app/armle/usr/bin/pc; chmod 755 /mnt/app/armle/usr/bin/pc
  rm -rf $SCR/fakejars && mkdir -p $SCR/fakejars/de/audi/app/terminalmode/smartphone/androidauto2 $SCR/fakejars/de/audi/app/car/adi/legacy/sportchrono
  echo x > $SCR/fakejars/de/audi/app/terminalmode/smartphone/androidauto2/AndroidAuto2Subsystem.class
  (cd $SCR/fakejars && zip -q /mnt/app/eso/hmi/lsd/jars/de.audi.app.terminalmode.jar de/audi/app/terminalmode/smartphone/androidauto2/AndroidAuto2Subsystem.class)
  if [[ "$2" == 1 ]]; then echo y > $SCR/fakejars/de/audi/app/car/adi/legacy/sportchrono/StorageMountHandler.class; (cd $SCR/fakejars && zip -q /mnt/app/eso/hmi/lsd/jars/de.audi.app.car.jar de/audi/app/car/adi/legacy/sportchrono/StorageMountHandler.class); fi
  { head -c 200 /dev/urandom; readelf --dyn-syms -W $SYMS_SO | awk '$7!="UND" && $4=="FUNC" && $5=="GLOBAL" {print $8}' | grep '^_ZN' | grep -v sendChannelOpenResp; head -c 200 /dev/urandom; } > /mnt/app/eso/lib/libautoreceiver.so
  rm -rf "$SCR/fakesd"; mkdir -p "$SCR/fakesd/Mods/ClusterIntegration"; cp -r "$REPO/modkit/Mods/ClusterIntegration/Update" "$SCR/fakesd/Mods/ClusterIntegration/"
  for f in ClusterIntegration_vTEST.jar cluster gal_cluster.so dio_cluster.so; do printf 'payload %s\n' "$f" > "$SCR/fakesd/Mods/ClusterIntegration/Update/$f"; done
  rm -rf "$SCR/fakesd/Mods/ClusterIntegration/Update/aa_only"
  if [[ "$3" == 1 ]]; then mkdir -p "$SCR/fakesd/Mods/ClusterIntegration/Update/aa_only"; printf 'aa\n' > "$SCR/fakesd/Mods/ClusterIntegration/Update/aa_only/ClusterIntegration_vTEST_aa.jar"; printf 'aa cluster\n' > "$SCR/fakesd/Mods/ClusterIntegration/Update/aa_only/cluster"; fi
  cp $SCR/zip34/Mods/ClusterIntegration/Update/cluster_config.json "$SCR/fakesd/Mods/ClusterIntegration/Update/"
  export MOD_PATH="$SCR/fakesd/Mods/ClusterIntegration/Update"
}
CFG=/mnt/app/eso/bin/apps/cluster/cluster_config.json
res() { printf '%-44s %s\n' "$1" "$2"; }
echo "=== overrides: CRLF file, trailing comment, nested key, out-of-block keys, bad value ==="
setup MH2p_ER_AUG35_P2873 1 1
printf 'forceRHD=true  # RHD car\r\nimperialSmallUnit="yards"\r\nzoomX=2.0\r\ndistance=42\r\nimperial=false\r\nname="e-tron"\r\nheartbeatInterval=abc\r\nlogFileSize=25\r\n# comment line\r\n' > "$SCR/fakesd/Mods/ClusterIntegration/config_overrides.txt"
out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -E "config override|hook symbols" | sed 's/^/    | /'
python3 - "$CFG" "$SCR/zip34/Mods/ClusterIntegration/Update/cluster_config.json" <<'PY'
import json,sys
new=json.load(open(sys.argv[1])); old=json.load(open(sys.argv[2],encoding='utf-8'))
def res(n,c): print(("PASS " if c else "FAIL ")+n)
res("valid JSON after overrides", True)
res("forceRHD true (comment stripped)", new["config"]["forceRHD"] is True)
res("imperialSmallUnit yards (CRLF stripped)", new["config"]["imperialSmallUnit"]=="yards")
res("logFileSize 25", new["config"]["logFileSize"]==25)
res("heartbeatInterval unchanged (bad value)", new["config"]["heartbeatInterval"]==old["config"]["heartbeatInterval"])
g=dict(old["config"]["gal_h264"]); g.update({"codecRes":1080,"mode":"fill","panY":0.0})
res("nested mirror untouched, gal_h264 = shipped + Audi defaults (1080, fill, panY 0)", new["config"]["mirror"]==old["config"]["mirror"] and new["config"]["gal_h264"]==g)
res("dynamicThresholds untouched", new["dynamicThresholds"]==old["dynamicThresholds"])
res("countries untouched", new["countries"]==old["countries"])
res("carConfig untouched", new["carConfig"]==old["carConfig"])
res("no CR left in file", b"\r" not in open(sys.argv[1],'rb').read())
PY
grep -c "override" "$MOD_PATH/Backup/manifest.txt" | sed 's/^/    | manifest override lines: /'
echo "=== root cluster_config.json warning ==="; mkdir -p /fs/sda0; cp $CFG /fs/sda0/cluster_config.json; out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q "WARN: /fs/sda0/cluster_config.json exists" && res "root config warning" PASS || res "root config warning" FAIL; rm -rf /fs
echo "=== diag + overrides via apply_override ==="; touch "$SCR/fakesd/Mods/ClusterIntegration/diag.txt"; mksh "$MOD_PATH/install.sh" >/dev/null 2>&1
python3 -c "import json;c=json.load(open('$CFG'))['config'];print(('PASS' if c['enableMapRender'] is False and c['forceRHD'] is True else 'FAIL')+' diag: enableMapRender=false, forceRHD kept')"
rm -f "$SCR/fakesd/Mods/ClusterIntegration/diag.txt"
echo "=== manifest-driven cleanup of an extra 'add' ==="; echo "extra" > /mnt/app/eso/bin/apps/cluster/extra_future_file; echo "20260101_000000 add /mnt/app/eso/bin/apps/cluster/extra_future_file" >> "$MOD_PATH/Backup/manifest.txt"; echo "20260101_000000 add /mnt/app/eso/bin/apps/gal" >> "$MOD_PATH/Backup/manifest.txt"
out=$(mksh "$MOD_PATH/uninstall.sh" 2>&1); [[ ! -f /mnt/app/eso/bin/apps/cluster/extra_future_file && ! -d /mnt/app/eso/bin/apps/cluster && "$(cat /mnt/app/eso/bin/apps/gal)" == "GALBIN" ]] && res "manifest add cleanup (own dirs only)" PASS || res "manifest add cleanup (own dirs only)" FAIL
echo "=== aa_only jar missing on Audi -> abort before change ==="; setup MH2p_ER_AUG35_P2873 1 0; out=$(mksh "$MOD_PATH/install.sh" 2>&1); rc=$?; echo "$out" | grep -E "ERROR" | sed 's/^/    | /'; [[ $rc == 4 && ! -f /mnt/app/eso/bin/apps/gal.real && -z "$(ls /mnt/app/eso/hmi/lsd/jars | grep ClusterIntegration)" ]] && res "abort without aa_only jar" PASS || res "abort without aa_only jar" FAIL
touch "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay.txt"; out=$(mksh "$MOD_PATH/install.sh" 2>&1); [[ -f /mnt/app/eso/hmi/lsd/jars/ClusterIntegration_vTEST.jar ]] && res "enable_carplay.txt allows full jar" PASS || res "enable_carplay.txt allows full jar" FAIL
echo "=== wrappers: no SD-root marker any more ==="; mkdir -p /fs/sda0; touch /fs/sda0/cluster_diag.txt; printf '#!/bin/sh\necho "MERGE=$GAL_CLUSTER_MERGE"\n' > /mnt/app/eso/bin/apps/gal.real; chmod 755 /mnt/app/eso/bin/apps/gal.real; mksh /mnt/app/eso/bin/apps/gal 2>/dev/null | grep -q "MERGE=$" && res "root marker ignored" PASS || res "root marker ignored" FAIL; rm -rf /fs
echo "=== 27xx Audi warning ==="; setup MH2p_ER_AUG35_P2711 1 1; out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q "outside the 28xx window" && res "27xx warning printed" PASS || res "27xx warning printed" FAIL
echo "=== P2711 with altscreen: no Porsche-window warning ==="; setup MH2p_US_AUG35_P2711 1 1; touch "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay_altscreen.txt"; out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q "made and tested on" && ! echo "$out" | grep -q -e "outside the 28xx window" -e "EXPERIMENTAL" && echo "$out" | grep -q "re-run the ModKit" && res "P2711 altscreen: toned-down message" PASS || res "P2711 altscreen: toned-down message" FAIL
echo "=== Audi JAR without its daemon (aa_only/cluster) -> abort before change ==="
setup MH2p_ER_AUG35_P2711 1 1; rm -f "$MOD_PATH/aa_only/cluster"; out=$(mksh "$MOD_PATH/install.sh" 2>&1); rc=$?
[[ $rc == 4 && ! -f /mnt/app/eso/bin/apps/gal.real ]] && echo "$out" | grep -q 'aa_only/cluster not found' && res "abort without aa_only/cluster" PASS || res "abort without aa_only/cluster" "FAIL (rc=$rc)"
echo "=== altscreen: enable_carplay_altscreen.txt ==="
AC=/mnt/app/eso/bin/apps/cluster
setup MH2p_ER_AUG35_P2711 1 1; touch "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay_altscreen.txt"
out=$(mksh "$MOD_PATH/install.sh" 2>&1); rc=$?; echo "$out" | grep -E "carplay|cluster daemon|ERROR" | sed 's/^/    | /'
[[ $rc == 0 && -f $AC/altscreen.so && -x $AC/altscreen_pf.sh && -f /mnt/app/eso/bin/apps/dio_manager.real ]] && res "altscreen: hook, pf script and dio_manager wrapper installed" PASS || res "altscreen: files installed" "FAIL (rc=$rc)"
[[ "$(cat $AC/cluster)" == "aa cluster" ]] && res "altscreen: daemon from aa_only (displayable 62)" PASS || res "altscreen: daemon from aa_only" FAIL
python3 - "$CFG" "$SCR/zip34/Mods/ClusterIntegration/Update/cluster_config.json" <<'PY'
import json,sys
new=json.load(open(sys.argv[1])); old=json.load(open(sys.argv[2],encoding='utf-8'))
def res(n,c): print(("PASS " if c else "FAIL ")+n)
m=dict(old["config"]["mirror"]); m["mode"]="fill capture=h264"
res("altscreen: config mirror.mode = fill capture=h264, rest of mirror kept", new["config"]["mirror"]==m)
g=dict(old["config"]["gal_h264"]); g.update({"codecRes":1080,"mode":"fill","panY":0.0})
res("altscreen: gal_h264 = shipped + Audi defaults, carConfig untouched", new["config"]["gal_h264"]==g and new["carConfig"]==old["carConfig"])
PY
printf '#!/bin/sh\necho "PRELOAD=$LD_PRELOAD"\n' > /mnt/app/eso/bin/apps/dio_manager.real; chmod 755 /mnt/app/eso/bin/apps/dio_manager.real
mkdir -p /mnt/ota/modkit; : > /mnt/ota/modkit/modkit_persist.sh   # a unit where the ModKit set up its start at boot
mksh /mnt/app/eso/bin/apps/dio_manager 2>/dev/null | grep -q "PRELOAD=$AC/altscreen.so$" && res "altscreen: wrapper preloads altscreen.so" PASS || res "altscreen: wrapper preloads altscreen.so" FAIL
out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q "skip identical:    $AC/altscreen.so" && echo "$out" | grep -q 'carplay altscreen: ON' && res "altscreen: re-run idempotent" PASS || res "altscreen: re-run idempotent" FAIL
echo "$out" | grep -q 'modkit boot:       skipped' && res "modkit boot: skipped without a start program" PASS || res "modkit boot: skipped without a start program" FAIL
SMGT=/mnt/app/eso/bin/servicemgrmibhigh
pfclean() { pkill -f 'altscreen_pf.sh' 2>/dev/null; pkill -f '^sleep 10$' 2>/dev/null; pkill -f '^sleep 2$' 2>/dev/null; rm -f /tmp/altscreen_pf.pid; }
cp /bin/ls $SMGT; out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q 'modkit boot:       OK' && res "modkit boot: clean unit reported OK" PASS || res "modkit boot: clean unit" FAIL
mv $SMGT ${SMGT}0; printf '#!/bin/sh\n/eso/bin/servicemgrmibhigh0 &\n' > $SMGT; out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q 'modkit boot:       OK' && res "modkit boot: ModKit's own patch reported OK" PASS || res "modkit boot: ModKit patch" FAIL
mv ${SMGT}0 ${SMGT}99; printf '#!/bin/sh\n# [q3team]\n/eso/bin/servicemgrmibhigh99 &\n' > $SMGT; h1=$(cat $SMGT ${SMGT}99 | cksum); rm -rf /mnt/ota/modkit/Logs
out=$(mksh "$MOD_PATH/install.sh" 2>&1); h2=$(cat $SMGT ${SMGT}99 | cksum)
echo "$out" | grep -q 'modkit boot:       WARN .*unknown patch state' && echo "$out" | grep -q "seems to be ${SMGT}99 (left alone)" && echo "$out" | grep -q 'modkit boot:       the CarPlay map will not show in the cockpit on this unit' && [[ ! -d /mnt/ota/modkit/Logs && "$h1" == "$h2" && ! -e ${SMGT}0 ]] && res "modkit boot: foreign start script reported with its consequence, nothing changed" PASS || { res "modkit boot: foreign start script" FAIL; echo "$out" | grep 'modkit boot'; }
rm -f $SMGT ${SMGT}99
pfclean; rm -f /tmp/dio_preload.log /tmp/cluster_daemon.pid /mnt/ota/modkit/modkit_persist.sh; mksh /mnt/app/eso/bin/apps/dio_manager 2>/dev/null | grep -q "PRELOAD=$AC/altscreen.so" && sleep 1 && [[ ! -f /tmp/altscreen_pf.pid && ! -f /tmp/cluster_daemon.pid ]] && res "wrapper starts nothing of the boot part, with or without the ModKit's boot script" PASS || res "wrapper starts nothing of the boot part" FAIL
mkdir -p /mnt/ota/modkit/Logs; mksh $AC/altscreen_pf.sh >/dev/null 2>&1 & sleep 1; read pfp < /tmp/altscreen_pf.pid 2>/dev/null
[[ -n "$pfp" && -d /proc/$pfp ]] && mksh $AC/altscreen_pf.sh 2>&1 | grep -q "already running (pid $pfp)" && read pfq < /tmp/altscreen_pf.pid && [[ "$pfp" == "$pfq" ]] && res "port watcher: a second start leaves the running one" PASS || res "port watcher: second start" FAIL
pfclean; echo 999999 > /tmp/altscreen_pf.pid; mksh $AC/altscreen_pf.sh >/dev/null 2>&1 & sleep 1; read pfq < /tmp/altscreen_pf.pid
[[ "$pfq" != 999999 && -d /proc/$pfq ]] && res "port watcher: a stale pid file does not block the start" PASS || res "port watcher: stale pid file" FAIL
pfclean; : > /mnt/ota/modkit/modkit_persist.sh
echo "$out" | grep -q 'carplay turns:     OFF (trial' && [[ ! -f $AC/carplay_turns ]] && res "carplay turns: off without carplay_turns.txt" PASS || res "carplay turns: off without carplay_turns.txt" FAIL
touch "$SCR/fakesd/Mods/ClusterIntegration/carplay_turns.txt"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ -f $AC/carplay_turns ]] && echo "$out" | grep -q 'carplay turns:     ON' && grep -q "add $AC/carplay_turns" "$MOD_PATH/Backup/manifest.txt" && res "carplay turns: marker installed and recorded" PASS || res "carplay turns: marker installed" FAIL
mksh /mnt/app/eso/bin/apps/dio_manager 2>/dev/null | grep -q "PRELOAD=$AC/altscreen.so:$AC/dio_cluster.so$" && grep -q "dio_cluster.so as well" /tmp/dio_preload.log && res "carplay turns: wrapper preloads both hooks, map hook first" PASS || res "carplay turns: wrapper preloads both hooks" FAIL
mv $AC/dio_cluster.so $AC/dio_cluster.so.away; mksh /mnt/app/eso/bin/apps/dio_manager 2>/dev/null | grep -q "PRELOAD=$AC/altscreen.so$" && res "carplay turns: map hook alone when dio_cluster.so is missing" PASS || res "carplay turns: missing dio_cluster.so" FAIL; mv $AC/dio_cluster.so.away $AC/dio_cluster.so
rm -f "$SCR/fakesd/Mods/ClusterIntegration/carplay_turns.txt"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ ! -f $AC/carplay_turns ]] && echo "$out" | grep -q "carplay turns:     removed $AC/carplay_turns" && mksh /mnt/app/eso/bin/apps/dio_manager 2>/dev/null | grep -q "PRELOAD=$AC/altscreen.so$" && res "carplay turns: marker removed with the file, wrapper back to the map hook" PASS || res "carplay turns: marker removed" FAIL
echo "=== altscreen_conf.txt: tuning file from the card ==="
ACF=$AC/altscreen.conf; ACS="$SCR/fakesd/Mods/ClusterIntegration/altscreen_conf.txt"
printf '# Performance view\r\nlarge=500,155,940,370  # less high\r\nphys=384,144\r\nurl=maps:/car\r\nsmall=1,2,x,4\r\nPATH=/evil\r\nsport_small=54,155,480,370\r\nzoom_max=12\r\nzoom_per_view=0\r\n' > "$ACS"
out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ "$(cat $ACF)" == $'large=500,155,940,370\nphys=384,144\nsport_small=54,155,480,370\nzoom_max=12\nzoom_per_view=0' ]] && echo "$out" | grep -q 'altscreen conf:    WARN' && echo "$out" | grep -q 'altscreen conf:    large=500,155,940,370' && res "altscreen conf: only valid lines installed (CR, comments, unknown keys dropped)" PASS || res "altscreen conf: only valid lines installed" FAIL
grep -q "add $ACF" "$MOD_PATH/Backup/manifest.txt" && res "altscreen conf: recorded as add" PASS || res "altscreen conf: recorded as add" FAIL
out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q "skip identical:    $ACF" && res "altscreen conf: unchanged file skipped by content" PASS || res "altscreen conf: unchanged file skipped" FAIL
printf 'large=500,155,940,350\n' > "$ACS"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ "$(cat $ACF)" == 'large=500,155,940,350' ]] && echo "$out" | grep -q "backup target:     $ACF" && ! echo "$out" | grep -q 'altscreen conf:    WARN' && res "altscreen conf: changed file replaces the installed one, with backup" PASS || res "altscreen conf: changed file replaces the installed one" FAIL
rm -f "$ACS"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ "$(cat $ACF)" == 'large=500,155,940,350' ]] && echo "$out" | grep -q 'large=500,155,940,350 (installed file, kept)' && res "altscreen conf: kept without altscreen_conf.txt" PASS || res "altscreen conf: kept without altscreen_conf.txt" FAIL
printf '# back to the defaults\n' > "$ACS"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ ! -f $ACF ]] && echo "$out" | grep -q 'has no setting, removed' && ls "$MOD_PATH/Backup" | grep -q '^altscreen.conf.backup' && res "altscreen conf: file without a setting removes altscreen.conf" PASS || res "altscreen conf: file without a setting removes altscreen.conf" FAIL
out=$(mksh "$MOD_PATH/install.sh" 2>&1); echo "$out" | grep -q 'has no setting, the hook uses its defaults' && [[ ! -f $ACF ]] && res "altscreen conf: nothing to remove, defaults reported" PASS || res "altscreen conf: nothing to remove" FAIL
printf 'eta=0\nturncard=0  # the box in the cockpit shows it\nspeedlimit=1\neta=yes\n' > "$ACS"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ "$(cat $ACF)" == $'eta=0\nturncard=0\nspeedlimit=1' ]] && echo "$out" | grep -q 'altscreen conf:    WARN' && res "altscreen conf: eta and turncard are known keys, a word as value is not" PASS || { res "altscreen conf: eta and turncard" FAIL; cat $ACF; }
printf 'ports=6200,7100\nports=six thousand\n' > "$ACS"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
[[ "$(cat $ACF)" == 'ports=6200,7100' ]] && echo "$out" | grep -q 'altscreen conf:    WARN' && res "altscreen conf: ports is a known key, numbers only" PASS || { res "altscreen conf: ports" FAIL; cat $ACF; }
printf '# back to the defaults\n' > "$ACS"; mksh "$MOD_PATH/install.sh" >/dev/null 2>&1; [[ ! -f $ACF ]] || res "altscreen conf: clean-up after the eta test" FAIL
rm -f "$ACS"
touch "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay.txt"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
echo "$out" | grep -q 'enable_carplay_altscreen.txt) needs the Audi JAR' && [[ ! -f $AC/altscreen.so ]] && res "altscreen: ignored and removed with enable_carplay.txt" PASS || res "altscreen: ignored with enable_carplay.txt" FAIL
rm -f "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay.txt"; mksh "$MOD_PATH/install.sh" >/dev/null 2>&1
rm -f "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay_altscreen.txt"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
python3 -c "import json;c=json.load(open('$CFG'))['config'];print(('PASS' if c['mirror']['mode']=='fill' else 'FAIL')+' altscreen off: shipped mirror.mode back')"
[[ ! -f $AC/altscreen.so && ! -f $AC/altscreen_pf.sh && ! -f /mnt/app/eso/bin/apps/dio_manager.real ]] && echo "$out" | grep -q 'remove altscreen:' && res "altscreen off: files removed, stock dio_manager back" PASS || res "altscreen off: files removed" FAIL
touch "$SCR/fakesd/Mods/ClusterIntegration/carplay_turns.txt"; out=$(mksh "$MOD_PATH/install.sh" 2>&1)
echo "$out" | grep -q 'carplay turns:     ignored (carplay_turns needs the CarPlay map' && [[ ! -f $AC/carplay_turns ]] && res "carplay turns: ignored without the map hook" PASS || res "carplay turns: ignored without the map hook" FAIL
touch "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay_altscreen.txt"; mksh "$MOD_PATH/install.sh" >/dev/null 2>&1; rm -f "$MOD_PATH/Backup/manifest.txt"; mksh "$MOD_PATH/uninstall.sh" >/dev/null 2>&1
[[ ! -f $AC/carplay_turns ]] && res "carplay turns: uninstall removes the marker without a manifest" PASS || res "carplay turns: uninstall removes the marker" FAIL
rm -f "$SCR/fakesd/Mods/ClusterIntegration/carplay_turns.txt" "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay_altscreen.txt"; setup MH2p_ER_AUG35_P2711 1 1
touch "$SCR/fakesd/Mods/ClusterIntegration/enable_carplay_altscreen.txt"; mksh "$MOD_PATH/install.sh" >/dev/null 2>&1; echo "phys=384,144" > $AC/altscreen.conf
out=$(mksh "$MOD_PATH/uninstall.sh" 2>&1); [[ ! -d $AC && "$(head -1 /mnt/app/eso/bin/apps/dio_manager)" != "#!/bin/ksh" ]] && ls "$MOD_PATH/Backup" | grep -q '^altscreen.conf.removed' && res "altscreen: uninstall removes everything, keeps altscreen.conf in Backup" PASS || res "altscreen: uninstall" FAIL
rm -rf /mnt/ota
rm -rf /mnt/app /fs /tmp/gal_preload.log /tmp/dio_preload.log
