# Options: settings and files on the card

Everything is set on the card, in `Mods/ClusterIntegration/` next to the folder `Update`. Change something, insert the card again, and the installer applies the difference.

"Since" says in which release something first works.

## `settings.txt`: one file for everything (since beta 5)

Copy `settings.example.txt` to `settings.txt`, remove the `#` in front of a line, set the value. The example file explains every value. One `key=value` per line, `#` starts a comment.

- A line in `settings.txt` decides. For anything it does not name, the mod does what it did before: its default, or what one of the single files below says. A card set up for an earlier version keeps working.
- An update does not overwrite your `settings.txt`.
- The installer's log lists what it read and names every line it could not use.

### What is shown

| Key | Values | What it does |
|---|---|---|
| `carplay_map` | `1` on, `0` off | CarPlay map in the cockpit (the iPhone's instrument-cluster video). On in the package. |
| `turn_box` | `1` on, `0` off | Optional, P2711 and P2873: the phone's next turn in Audi's own cockpit box. Installs a hook in the navigation process. |
| `turn_box_on_map` | `0`, `1` | With `turn_box`: `0` = the box makes way while the cockpit shows the phone's map (CarPlay or Android Auto) and is there in the other tabs, `1` = the box in every tab. |
| `hud_navigation` | `0`, `1`, `2` | Optional: the phone's next turn on the head-up display. On P2711 and P2873 with arrow and distance (same hook as the box), elsewhere the street name only. `2` also hands on the other roads of the junction, which Audi draws as short stubs around the arrow (untested on a car). |
| `destination_flag` | `1` on, `0` off | Optional, with `turn_box` or `hud_navigation` on P2711 and P2873: Audi's picture with the flag for the last 200 m. |
| `carplay_turns` | `1`, `0` | CarPlay's turn data for the box and the head-up display. Comes by itself with `turn_box` or `hud_navigation`; the key only overrules that. |
| `cockpit_size` | `1920x722`, `auto` | A fixed size for cars where the picture ends too early (Q3 with the Virtual Cockpit Plus). |
| `daemon_log` | `1` on, `0` off | The cluster daemon writes a detailed log (`cluster_daemon.log`). |

The hook in the navigation process is written for the two builds of the navigation program it knows (P2711, P2873). On any other build the installer says so and changes nothing there.

### The CarPlay map

The iPhone reads these when it connects, so after the card ran, reconnecting is enough.

| Key | Default | Meaning |
|---|---|---|
| `map_turn_card`, `map_arrival_line` | `1`, `1` | The iPhone's turn card and arrival line on the cockpit map. `0` leaves the map alone, useful with `turn_box`. |
| `map_speed_limit` | `1` | Ask the iPhone for its speed limit sign. |
| `map_area_large` | `500,155,940,410` | Picture area in the large-map view: left, top, width, height in the 1920x720 picture. The iPhone keeps its cards inside. |
| `map_area_small` | `624,158,672,400` | The same for the view with the large gauges. |
| `map_area_sport_large`, `map_area_sport_small` | `500,155,940,380`, `54,155,480,370` | The same for cockpits with the dial in the centre (Sport, Performance, e-tron). |
| `map_size_mm` | `384,144` | Size of the picture in mm as told to the iPhone. Larger numbers make its cards and texts smaller. |
| `map_ports` | `6100,6200,7100` | Ports the iPhone may send the cockpit video to, tried in this order; Audi's firewall passes them anyway. When none is free the mod uses 6031, which it has to open itself. `0` goes straight to 6031. |
| `map_keyframe_ms` | `3000` | How often a full picture is requested; a damaged picture heals within that time. |
| `zoom_invert` | `1` | Direction of the steering-wheel roller. |
| `zoom_restore`, `zoom_max` | `1`, `10` | Remember the zoom across restarts, and the largest step count kept. |
| `zoom_per_view` | `1` | One zoom per cockpit view, or one for both (`0`). |
| `zoom_step_ms` | `600` | Pause between two zoom steps after a view change, 50 to 2000. |

Fitting the picture: a card or the arrival line hidden at the bottom, lower the last number in steps of 20. Cut off on the left, raise the first number. Cut off on the right, lower the third.

## Files that start an action

These stay files of their own; they are no setting.

| File | What it does | Since |
|---|---|---|
| `uninstall.txt` | Runs the uninstaller instead: restores every file from `Update/Backup` on the card. | upstream |
| `diag.txt` | Diagnostic mode: the hooks only log, nothing is added to the phone connection, so no map shows. | upstream |
| `force_install.txt` | Skips the check of brand and software version. | upstream |
| `no_stub.txt` | Audi: do not install the stand-in for a class only Porsche units have. | upstream fork |
| `enable_carplay.txt`, `enable_carplay_hook.txt` | The original project's CarPlay turn hook on Audi, without the map. `enable_carplay.txt` is known not to work on Audi. | upstream fork |

## The single files from before

They keep working wherever `settings.txt` does not name the same thing. Most are empty files whose name is the switch; a file that is gone takes its part out again.

| File | Same as | Since |
|---|---|---|
| `enable_carplay_altscreen.txt` (in the package) | `carplay_map=1` | beta 1 |
| `altscreen_conf.txt` (template `altscreen_conf.example.txt`) | the `map_` and `zoom_` keys, under the hook's own names (`large`, `small`, `sport_large`, `sport_small`, `phys`, `turncard`, `eta`, `speedlimit`, `ports`, `keyframe_ms`, `zoom_...`). A file without any setting removes the installed settings. | beta 2 |
| `nav_box.txt` | `turn_box=1` | beta 5 |
| `nav_box_tabs.txt` | `turn_box_on_map=0` | beta 5 |
| `hud_arrows.txt` (a `2` as the first character: with the junction's other roads) | `hud_navigation=1` or `2` | beta 5 |
| `nav_flag.txt` | `destination_flag=1` | beta 5 |
| `carplay_turns.txt` | `carplay_turns=1` | beta 5 |
| `cockpit_size.txt` (one line `WIDTHxHEIGHT`) | `cockpit_size=` | beta 5 |
| `daemon_log.txt` | `daemon_log=1` | upstream fork |

## Android Auto: `config_overrides.txt` and `gal_env.txt`

Two files of the original project with their own formats, not part of `settings.txt`.

| File | For | Template in the package |
|---|---|---|
| `config_overrides.txt` | Android Auto map and turn-by-turn (`cluster_config.json`) | `config_overrides.example.txt` |
| `gal_env.txt` | The Android Auto hook's environment | `gal_env.example.txt` |

The package sets what the Audi cockpit needs (`gal_h264.codecRes=1080`, `gal_h264.mode="fill"`, `gal_h264.panY=0`, `GAL_CLUSTER_RES=1080`). The example files explain the rest; the reasons are in [audi-notes.md](audi-notes.md#fitting-the-map-to-the-e-trons-cockpit) and the keys of the turn-by-turn bridge in [porsche.md](porsche.md#configuration).

## Logs

The car copies its logs into `Logs` on the card whenever the card is inserted.

| File | From |
|---|---|
| `ClusterIntegration.log` | The installer: what it found and changed. Contains data about your MMI. |
| `altscreen-sessions.log` | The CarPlay map hook: one block per connection. |
| `altscreen-pf.log` | The watcher that opens the port for the cockpit video. |
| `hud-feed.log` | Turn box and head-up display (when one of them is on). |
| `_ModKit_Update.log` | LawPaul's ModKit. |
