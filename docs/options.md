# Options: files on the card and settings

Everything is switched with files in `Mods/ClusterIntegration/` on the card, next to the folder `Update`. Most are empty files whose name is the switch. Change the files, insert the card again, and the installer applies the difference: a file that is gone takes its part out again.

"Since" says where a file first works: a release, or "after beta 4" for what is in this repository and in test packages but in no release yet.

## Switches

| File | What it does | Since |
|---|---|---|
| `enable_carplay_altscreen.txt` | CarPlay map in the cockpit (the iPhone's instrument-cluster video). In the package by default. | beta 1 |
| `uninstall.txt` | Runs the uninstaller instead: restores every file from `Update/Backup` on the card. | upstream |
| `nav_box.txt` | Trial, P2711 and P2873: the phone's next turn in Audi's own cockpit box. Installs a hook in the navigation process. With CarPlay it needs `carplay_turns.txt`. | after beta 4 |
| `nav_box_tabs.txt` | Trial, with `nav_box.txt`: the box makes way while the cockpit shows the phone's map (CarPlay or Android Auto) and is there in the other tabs. | after beta 4 |
| `hud_arrows.txt` | Trial: the phone's next turn on the head-up display. On P2711 and P2873 with arrow and distance (same hook as the box), elsewhere the street name only. A `2` as the first character adds side streets. | after beta 4 |
| `nav_flag.txt` | Trial, with `nav_box.txt` or `hud_arrows.txt` on P2711 and P2873: Audi's picture with the flag for the last 200 m. | after beta 4 |
| `carplay_turns.txt` | Trial, with `enable_carplay_altscreen.txt`: loads the turn-by-turn hook next to the map hook, so CarPlay's turn data reaches the box and the head-up display. | after beta 4 |
| `cockpit_size.txt` | One line `WIDTHxHEIGHT`, for example `1920x722`, for cars where the picture ends too early (Q3 with the Virtual Cockpit Plus). | after beta 4 |
| `daemon_log.txt` | The cluster daemon writes a detailed log (`cluster_daemon.log`). | upstream fork |
| `diag.txt` | Diagnostic mode: the hooks only log, nothing is added to the phone connection. | upstream |
| `force_install.txt` | Skips the check of brand and software version. | upstream |
| `no_stub.txt` | Audi: do not install the stand-in for a class only Porsche units have. | upstream fork |
| `enable_carplay.txt`, `enable_carplay_hook.txt` | The original project's CarPlay turn hook on Audi, without the map. `enable_carplay.txt` is known not to work on Audi. | upstream fork |

Hook files and switches on P2711 and P2873 only: the hook in the navigation process is written for the two builds of the navigation program it knows. On any other build the installer says so and changes nothing there.

## Settings files

| File | For | Template in the package |
|---|---|---|
| `altscreen_conf.txt` | The CarPlay map | `altscreen_conf.example.txt` |
| `config_overrides.txt` | Android Auto map and turn-by-turn (`cluster_config.json`) | `config_overrides.example.txt` |
| `gal_env.txt` | The Android Auto hook's environment | `gal_env.example.txt` |

Each is plain `key=value`, one per line, `#` starts a comment. Your own files on the card win over the package's defaults and survive an update. An `altscreen_conf.txt` without any setting removes the installed settings again.

### `altscreen_conf.txt` (CarPlay map)

The iPhone reads these when it connects, so after the card ran, reconnecting is enough.

| Key | Default | Meaning |
|---|---|---|
| `large` | `500,155,940,410` | Picture area in the large-map view: left, top, width, height in the 1920x720 picture. The iPhone keeps its cards inside. |
| `small` | `624,158,672,400` | The same for the view with the large gauges. |
| `sport_large`, `sport_small` | `500,155,940,380`, `54,155,480,370` | The same for cockpits with the dial in the centre (Sport, Performance, e-tron). |
| `phys` | `384,144` | Size of the picture in mm as told to the iPhone. Larger numbers make its cards and texts smaller. |
| `zoom_invert` | `1` | Direction of the steering-wheel roller. |
| `zoom_restore`, `zoom_max` | `1`, `10` | Remember the zoom across restarts, and the largest step count kept. |
| `zoom_per_view` | `1` | One zoom per cockpit view, or one for both (`0`). |
| `zoom_step_ms` | `600` | Pause between two zoom steps after a view change, 50 to 2000. After beta 4. |
| `speedlimit` | `1` | Ask the iPhone for its speed limit sign. |
| `eta`, `turncard` | `1`, `1` | The iPhone's arrival line and turn card on the cockpit map. `0` leaves the map alone, useful with `nav_box.txt`. After beta 4. |
| `keyframe_ms` | `3000` | How often a full picture is requested; a damaged picture heals within that time. |
| `ports` | `6100,6200,7100` | Ports the iPhone may send the cockpit video to, tried in this order; Audi's firewall passes them anyway. When none is free the mod uses 6031, which it has to open itself. `0` goes straight to 6031. After beta 4. |

Fitting the picture: a card or the arrival line hidden at the bottom, lower the last number in steps of 20. Cut off on the left, raise the first number. Cut off on the right, lower the third.

### `config_overrides.txt` and `gal_env.txt` (Android Auto)

The package sets what the Audi cockpit needs (`gal_h264.codecRes=1080`, `gal_h264.mode="fill"`, `gal_h264.panY=0`, `GAL_CLUSTER_RES=1080`). The example files explain the rest; the reasons are in [audi-notes.md](audi-notes.md#fitting-the-map-to-the-e-trons-cockpit) and the keys of the turn-by-turn bridge in [porsche.md](porsche.md#configuration).

## Logs

The car copies its logs into `Logs` on the card whenever the card is inserted.

| File | From |
|---|---|
| `ClusterIntegration.log` | The installer: what it found and changed. Contains data about your MMI. |
| `altscreen-sessions.log` | The CarPlay map hook: one block per connection. |
| `altscreen-pf.log` | The watcher that opens the port for the cockpit video. |
| `hud-feed.log` | Turn box and head-up display (with the trial switches). |
| `_ModKit_Update.log` | LawPaul's ModKit. |
