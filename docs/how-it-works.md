# How it works

A short map of the parts. The detailed record, with what was seen on which car, is in [audi-notes.md](audi-notes.md); the original project's design for the turn-by-turn bridge is in [porsche.md](porsche.md#architecture).

## The unit

The MH2p head unit runs QNX. Its user interface (the HMI) is a Java program on an old Java machine (class files at Java 1.4 level), organised in OSGi bundles. Three properties make the mod possible:

- Every jar in `/mnt/app/eso/hmi/lsd/jars/` is put in front of the HMI's own classes. A class in the mod's jar with the same name as a stock class replaces it.
- The programs that talk to the phone (`gal` for Android Auto, `dio_manager` for CarPlay) are ordinary files on a writable partition. The installer puts a small start script in their place that loads one extra library into the original program.
- The cockpit shows numbered picture sources ("displayables"). The mod's video goes to one of its own, and the HMI is asked to show that one in place of the Audi map.

Nothing in the cockpit itself is changed, and Audi's own files are only ever wrapped or shadowed, never patched in place, with one exception named below.

## Android Auto map

1. The library `gal_cluster.so` in the Android Auto receiver adds a second video sink, the instrument cluster, to what the car offers the phone.
2. The phone then sends a second H.264 stream with the map laid out for a cluster. The library copies it into shared memory.
3. The cluster daemon (`cluster`) decodes it with the unit's hardware decoder and shows it on its displayable.
4. In the HMI, `KombiMapGuard` notices that the video runs and asks the display manager to show the video in place of the Audi map, and back when it stops.

These parts are the original project's; this fork fitted the layout to the Audi cockpit.

## CarPlay map

CarPlay has the same idea under another name: a second screen stream ("altScreen") for the instrument cluster.

1. The library `altscreen.so` in `dio_manager` adds the cluster screen to what the car offers the iPhone, with its size and the areas the cockpit really shows.
2. The iPhone opens a second video stream to the car. The library accepts it on its own port, decrypts it and hands the H.264 to the same cluster daemon.
3. Audi's firewall only lets the main screen's port through, so a small watcher (`altscreen_pf.sh`) copies that rule for the second port.
4. The same guard in the HMI switches the cockpit to the video.

Around that: the steering-wheel roller's zoom steps are passed to the iPhone, the cockpit's view changes (large map, large gauges, the layouts) are passed on so the iPhone moves its cards, day and night are repeated for the cluster screen, and a checkbox in the cockpit's navigation menu switches back to the Audi map.

## Turn data, the box and the head-up display (optional, since beta 5)

The original project sends the phone's next manoeuvre to the cockpit over BAP, the car's protocol between head unit and cluster. On the Audi units tested here the cockpit draws nothing from that alone. Audi's own turn box and the head-up display picture are drawn by the navigation program, from its own route.

- `nav/HudTurnFeed` sits between the phone integrations and the HMI's navigation service. It forwards everything and also hands the phone's manoeuvre, distance, street and arrival time to the handlers that feed the cockpit box and the head-up display.
- A small library in the navigation process (`dog.so`) makes the navigation's renderer draw its arrow scene, or the destination scene with the flag, for that manoeuvre although Audi has no route. This is the one place where a file of Audi's is changed: the navigation's `libwatchdog.so` gets one more dependency, so the library is loaded. The original is kept and put back on uninstall, byte for byte.
- The library knows the two builds of the navigation program it was written for (P2711, P2873) and does nothing on any other. If the navigation restarts several times in a row with it, it stays off.

## Installing and removing

LawPaul's SD ModKit is a signed update the unit accepts from a card; it runs the mod's `Update/install.sh` and, at every boot, `Persist/install.sh`. The installer backs up every file it touches to `Update/Backup` on the card and lists it in `manifest.txt`; `uninstall.sh` restores from that. The unit's tool set is small (no `cmp`, no `grep -a`, an old shell), which is why the installer is written the way it is and why [the tests](development.md) run it under three simulated tool sets.
