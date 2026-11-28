# CarPlay map in the Virtual Cockpit – test version

This package puts the CarPlay map (Google Maps or Apple Maps) into the Virtual Cockpit, where
the Audi map normally is. Developed and tested in an A6 C8; testers report it working in other
A6, an S6, a Q8, a Q3 and an e-tron. **Use at your own risk.**

## Requirements

- **Check the MMI software version:** in the MMI under *Settings → System information →
  Version* (or similar). It must say `MH2p_…_P2711` or `MH2p_…_P2873`. On other versions,
  please get in touch first. CarPlay keeps working there, but nothing shows up in the cockpit.
- **CarPlay** already works, wireless or by cable. The cockpit map works with both.
- **SD card** (or USB stick, if your car accepts ModKit updates from a stick), formatted as
  FAT32.
- **Included:** LawPaul's *NavCompassIgnore* mod (folder `Mods/NavCompassIgnore`,
  https://github.com/LawPaul/MH2p_NavCompassIgnore). Without it the cockpit switches to the
  compass as soon as a route starts in CarPlay, and then no map is shown. If you already have
  it, it is simply installed again.

## Install

1. Unzip the **contents** of the zip file straight onto the empty card. Afterwards the top
   level holds the folders `Data`, `Logs`, `Meta`, `Mods`.
2. Ignition on (ideally with the engine running), insert the card. The MMI restarts and
   installs. At the end it says it will now restart normally, and the screen goes black. Pull
   the card out at that point. The MMI then starts as usual.
3. **Do not delete or overwrite the card afterwards.** It holds the backups
   (`Mods/ClusterIntegration/Update/Backup`) that are needed to uninstall.

The CarPlay map is on without any setting. Everything else is optional, see *Settings*.

## Update to a new version

Do not uninstall first. Unzip the contents of the new zip onto the **same** card and let it
replace existing files; do not delete `Mods/ClusterIntegration/Update/Backup` (the zip has no such
folder, so it stays). Then insert the card as for the install. The installer sees what is already
installed and only replaces what changed. Your own `settings.txt` stays as it is.

## Use

- Connect the iPhone and open Google Maps or Apple Maps in CarPlay.
- In the cockpit, choose the map view, i.e. where the Audi map usually is. After a few seconds
  the CarPlay map appears.
- The steering-wheel roller zooms the map (Google Maps and Apple Maps; Waze ignores it). Both
  cockpit layouts (large map / large gauges) work.
- The zoom is remembered: after a reconnect or an MMI restart the map zooms back to where you
  left it, a few seconds after it appears. The large map and the map between the big gauges
  each keep their own zoom; after you change the view, the map zooms to that view's level
  within a few seconds.
- The cockpit layouts *Classic*, *Dynamic* and *Performance* (S and RS models) are followed
  automatically; about a second after you change the layout the map fits it.
- The cockpit map switches between day and night together with CarPlay on the MMI.
- The iPhone is asked to show its speed limit sign on the cockpit map. On the test car none
  has appeared so far; whether Maps draws one may depend on region and route. Please report
  what you see.
- The CarPlay map stays in the cockpit while the MMI shows something else, for example the
  radio, the reverse camera or the Audi navigation.
- **Switching in the cockpit:** the cockpit menu *Navigation* has a **Smartphone Map** row
  with a checkbox below "Map" (called "Carplay Map" in earlier versions). It only appears
  while CarPlay or Android Auto shows its map in the cockpit. Checked: the phone's map.
  Unchecked: Audi map. The setting is kept across restarts.
- The Audi map's zoom display at the bottom (magnifier, "400 m"), the traffic logo at the
  bottom left ("TMC") and the satellite map logo ("Google") are hidden while the CarPlay map
  is shown. Altitude, street and compass stay.
- **Android Auto (wired):** Google Maps appears in the cockpit as well, across the full width:
  arrow in the centre, turn card at the top, arrival line at the bottom, clear of the dials
  in both views. The roller does not zoom it; Google Maps zooms by itself there. Android Auto
  has had less testing than CarPlay; reports are welcome.

## Settings (optional)

One file sets everything. On the card, copy `Mods/ClusterIntegration/settings.example.txt` to
`settings.txt` in the same folder. Each setting is a line with a `#` in front; remove the `#`,
set the value, save, and insert the card again as for the install. The file explains every
value, and the installer's log (`Logs/ClusterIntegration.log`) lists what it read.

A line that stays commented out changes nothing. An update does not overwrite your
`settings.txt`. The single files of earlier versions (`enable_carplay_altscreen.txt`,
`altscreen_conf.txt`) keep working; a line in `settings.txt` wins over them.

### The next turn in Audi's box and on the head-up display (new)

For software `P2711` and `P2873`. Off until you switch it on:

| Line in `settings.txt` | What you get |
|---|---|
| `turn_box=1` | The phone's next turn in Audi's own box next to the right dial: arrow, distance, street and arrival time. With CarPlay and with Android Auto. |
| `turn_box_on_map=0` | The box makes way while the cockpit shows the phone's map (the iPhone draws its own turn card there) and is there in the other cockpit tabs. With `1` it shows in every tab. |
| `hud_navigation=1` | Arrow and distance on the head-up display. |
| `destination_flag=1` | Audi's picture with the flag for the last 200 m before the destination. |

- These put a small hook into Audi's navigation program. If the Audi navigation does not
  behave as before, set the lines back to `0` and insert the card again; that takes the hook
  out.
- Tested so far: the box and the flag in an A6 C8 on P2711, the head-up display arrow in a
  Q8 on P2711. On P2873 it has not been confirmed on a car yet; please report how it goes.
- Android Auto gives no arrival time, so the box shows arrow and distance only there.
- On other software versions `hud_navigation=1` shows the street name only, and the box is
  left out.

### The CarPlay picture

- **Free the map:** with the box on, the iPhone's own turn card and arrival line say the same
  thing twice. `map_turn_card=0` and `map_arrival_line=0` leave the map alone.
- **Fit the picture:** if the cockpit of your model hides part of the iPhone's cards, set
  `map_area_large` and `map_area_small` (left, top, width, height) as described in the file.
- **Picture ends too early** (Audi Q3 with the Virtual Cockpit Plus): `cockpit_size=1920x722`.

## Feedback

Most helpful:

- Photos of the cockpit.
- The folder `Logs` from the card, above all `ClusterIntegration.log` and
  `altscreen-sessions.log`, with the turn box or the head-up display also `hud-feed.log`.
  Please look through them before sending, the first one contains data about your MMI. The
  car copies its logs to the card whenever the card is inserted, so for a problem while
  driving insert the card once more afterwards.
- A short description: car, MMI version, phone and its software version, and what happens or
  doesn't.

If the cockpit keeps showing the Audi map for more than a few seconds after connecting even
though CarPlay is running: please let me know how long it took.

## Remove

- **Turn off only the CarPlay map:** `carplay_map=0` in `settings.txt`, then insert the card
  again, as for the install.
- **Turn off only the box or the head-up display:** set their lines in `settings.txt` to `0`
  and insert the card again.
- **Remove everything:** create an empty file `uninstall.txt` in the folder
  `Mods/ClusterIntegration` and insert the card again. Afterwards the MMI is back to factory
  state as far as this mod is concerned. NavCompassIgnore stays installed; to remove it too,
  put an `uninstall.txt` in `Mods/NavCompassIgnore` as well (skip that if you had it before).

Free, not for sale (CC BY-NC-SA 4.0 / GPL-3.0). NavCompassIgnore and the MH2p SD ModKit are by
LawPaul (https://github.com/LawPaul), CC BY-NC-SA 4.0, included unchanged.

- Download (latest version): https://github.com/CrEaK/mh2p-cluster/releases
- Bugs and questions: https://github.com/CrEaK/mh2p-cluster/issues
- Project page and tested vehicles: https://github.com/CrEaK/mh2p-cluster
