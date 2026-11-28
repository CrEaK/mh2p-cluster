# CarPlay-Karte im Virtual Cockpit – Testversion

Mit diesem Paket zeigt das Virtual Cockpit die CarPlay-Karte (Google Maps oder Apple Karten) an
der Stelle der Audi-Karte. Entwickelt und getestet in einem A6 C8; Tester melden es auch in
weiteren A6, einem S6, einem Q8, einem Q3 und einem e-tron als funktionierend. **Alles auf
eigene Gefahr.**

## Voraussetzungen

- **MMI-Softwareversion prüfen:** im MMI unter *Einstellungen → Systeminformationen → Version*
  (oder ähnlich). Dort muss `MH2p_…_P2711` oder `MH2p_…_P2873` stehen. Bei anderen Versionen
  bitte erst melden. CarPlay läuft dort zwar weiter, aber im Cockpit kommt nichts an.
- **CarPlay** funktioniert schon, kabellos oder per Kabel. Die Cockpit-Karte geht mit beidem.
- **SD-Karte** (oder USB-Stick, falls dein Auto ModKit-Updates vom Stick annimmt), FAT32
  formatiert.
- **Liegt bei:** LawPauls Mod *NavCompassIgnore* (Ordner `Mods/NavCompassIgnore`,
  https://github.com/LawPaul/MH2p_NavCompassIgnore). Ohne ihn schaltet das Cockpit auf den
  Kompass, sobald in CarPlay eine Navigation startet, dann ist keine Karte zu sehen. Wer ihn
  schon hat, bekommt ihn einfach noch einmal installiert.

## Installieren

1. Den **Inhalt** der Zip-Datei direkt auf die leere Karte entpacken. Danach liegen auf der
   obersten Ebene die Ordner `Data`, `Logs`, `Meta`, `Mods`.
2. Zündung an (am besten Motor laufen lassen), Karte einstecken. Das MMI startet neu und
   installiert. Am Ende meldet es, dass es jetzt normal neu startet, und der Bildschirm wird
   schwarz. Dann die Karte herausziehen. Das MMI startet danach normal.
3. **Die Karte danach nicht löschen oder überschreiben.** Auf ihr liegen die Sicherungen
   (`Mods/ClusterIntegration/Update/Backup`), die zum Deinstallieren gebraucht werden.

Die CarPlay-Karte ist ohne jede Einstellung an. Alles Weitere ist freiwillig, siehe
*Einstellungen*.

## Auf eine neue Version aktualisieren

Nicht vorher deinstallieren. Den Inhalt der neuen Zip-Datei auf **dieselbe** Karte entpacken und
vorhandene Dateien ersetzen lassen; den Ordner `Mods/ClusterIntegration/Update/Backup` dabei nicht
löschen (die Zip-Datei enthält keinen, er bleibt also stehen). Dann die Karte wie beim
Installieren einstecken. Der Installer erkennt, was schon installiert ist, und ersetzt nur, was
sich geändert hat. Deine eigene `settings.txt` bleibt, wie sie ist.

## Benutzen

- iPhone verbinden, in CarPlay Google Maps oder Apple Karten öffnen.
- Im Cockpit die Kartenansicht wählen, also dort, wo sonst die Audi-Karte ist. Nach ein paar
  Sekunden erscheint die CarPlay-Karte.
- Lenkrad-Rädchen zoomt die Karte (Google Maps und Apple Karten; Waze reagiert nicht darauf).
  Beide Cockpit-Ansichten (große Karte / große Tachos) gehen.
- Der Zoom wird gemerkt: Nach einem Neuverbinden oder MMI-Neustart zoomt die Karte ein paar
  Sekunden nach dem Erscheinen wieder dorthin, wo du sie gelassen hast. Die große Karte und
  die Karte zwischen den großen Tachos merken sich je einen eigenen Zoom; nach einem Wechsel
  der Ansicht zoomt die Karte in ein paar Sekunden auf den Wert dieser Ansicht.
- Die Cockpit-Layouts *Classic*, *Dynamic* und *Performance* (S- und RS-Modelle) werden
  automatisch erkannt; etwa eine Sekunde nach einem Layoutwechsel passt die Karte dazu.
- Die Cockpit-Karte wechselt zusammen mit CarPlay auf dem MMI zwischen Tag und Nacht.
- Das iPhone wird um sein Tempolimit-Schild auf der Cockpit-Karte gebeten. Im Testauto ist
  bisher keins erschienen; ob die Karten-App eins zeichnet, hängt womöglich von Region und
  Route ab. Bitte melden, was ihr seht.
- Die CarPlay-Karte bleibt im Cockpit, auch wenn das MMI etwas anderes zeigt, zum Beispiel
  Radio, Rückfahrkamera oder die Audi-Navigation.
- **Umschalten im Cockpit:** Im Cockpit-Menü *Navigation* steht unter „Karte“ die Zeile
  **Smartphone Map** mit Häkchen (in früheren Versionen „Carplay Map“). Sie erscheint nur,
  solange CarPlay oder Android Auto seine Karte im Cockpit zeigt. Häkchen an: Karte vom
  Handy. Häkchen aus: Audi-Karte. Die Einstellung bleibt nach einem Neustart erhalten.
- Die Zoomanzeige der Audi-Karte unten (Lupe, „400 m“), das Verkehrslogo links unten („TMC“)
  und das Logo der Satellitenkarte („Google“) sind ausgeblendet, solange die CarPlay-Karte
  läuft. Höhe, Straße und Kompass bleiben stehen.
- **Android Auto (per Kabel):** Google Maps erscheint ebenfalls im Cockpit, über die volle
  Breite: Pfeil in der Mitte, Abbiegekarte oben, Ankunftszeile unten, in beiden Ansichten frei
  neben den Rundinstrumenten. Das Rädchen zoomt dort nicht; Google Maps zoomt selbst. Android
  Auto ist weniger getestet als CarPlay; Rückmeldungen sind willkommen.

## Einstellungen (freiwillig)

Eine Datei stellt alles ein. Kopiere auf der Karte `Mods/ClusterIntegration/settings.example.txt`
nach `settings.txt` im selben Ordner. Jede Einstellung ist eine Zeile mit einem `#` davor: das
`#` entfernen, den Wert setzen, speichern und die Karte wie beim Installieren noch einmal
einstecken. Die Datei erklärt jeden Wert (auf Englisch), und das Log des Installers
(`Logs/ClusterIntegration.log`) nennt, was er gelesen hat.

Eine Zeile, die auskommentiert bleibt, ändert nichts. Ein Update überschreibt deine
`settings.txt` nicht. Die einzelnen Dateien früherer Versionen (`enable_carplay_altscreen.txt`,
`altscreen_conf.txt`) gelten weiter; eine Zeile in `settings.txt` hat Vorrang.

### Der nächste Abbiegehinweis in Audis Kasten und im Head-up-Display (neu)

Für die Software `P2711` und `P2873`. Aus, bis du es einschaltest:

| Zeile in `settings.txt` | Was du bekommst |
|---|---|
| `turn_box=1` | Den nächsten Abbiegehinweis des Handys in Audis eigenem Kasten neben dem rechten Rundinstrument: Pfeil, Entfernung, Straße und Ankunftszeit. Mit CarPlay und mit Android Auto. |
| `turn_box_on_map=0` | Der Kasten macht Platz, solange das Cockpit die Karte vom Handy zeigt (das iPhone zeichnet dort seine eigene Abbiegekarte), und steht auf den anderen Reitern. Mit `1` steht er auf jedem Reiter. |
| `hud_navigation=1` | Pfeil und Entfernung im Head-up-Display. |
| `destination_flag=1` | Audis Bild mit der Flagge auf den letzten 200 m vor dem Ziel. |

- Dafür kommt ein kleiner Haken in Audis Navigationsprogramm. Verhält sich die Audi-Navigation
  danach anders als vorher: die Zeilen wieder auf `0` stellen und die Karte noch einmal
  einstecken, dann ist der Haken wieder draußen.
- Bisher getestet: Kasten und Flagge in einem A6 C8 mit P2711, der Pfeil im Head-up-Display in
  einem Q8 mit P2711. Auf P2873 ist es noch in keinem Auto bestätigt; bitte melden, wie es
  läuft.
- Android Auto liefert keine Ankunftszeit, der Kasten zeigt dort nur Pfeil und Entfernung.
- Auf anderen Softwareversionen zeigt `hud_navigation=1` nur den Straßennamen, und der Kasten
  bleibt weg.

### Das CarPlay-Bild

- **Karte freiräumen:** Mit dem Kasten sagen die Abbiegekarte und die Ankunftszeile des iPhones
  dasselbe noch einmal. `map_turn_card=0` und `map_arrival_line=0` lassen die Karte frei.
- **Bild anpassen:** Verdeckt das Cockpit deines Modells einen Teil der Karten-Anzeigen des
  iPhones, dann `map_area_large` und `map_area_small` setzen (links, oben, Breite, Höhe), wie
  in der Datei beschrieben.
- **Bild endet zu früh** (Audi Q3 mit Virtual Cockpit Plus): `cockpit_size=1920x722`.

## Rückmeldung

Am meisten helfen:

- Fotos vom Cockpit.
- Der Ordner `Logs` von der Karte, vor allem `ClusterIntegration.log` und
  `altscreen-sessions.log`, mit Kasten oder Head-up-Display auch `hud-feed.log`. Bitte vor dem
  Verschicken durchsehen, die erste Datei enthält Daten über dein MMI. Das Auto kopiert seine
  Logs immer dann auf die Karte, wenn sie eingesteckt wird; bei einem Problem während der
  Fahrt die Karte danach also noch einmal einstecken.
- Kurz beschreiben: Auto, MMI-Version, Handy und dessen Softwareversion und was passiert oder
  nicht passiert.

Falls das Cockpit nach dem Verbinden länger als ein paar Sekunden die Audi-Karte zeigt, obwohl
CarPlay läuft: bitte Bescheid geben, wie lange es gedauert hat.

## Wieder entfernen

- **Nur die CarPlay-Karte abschalten:** `carplay_map=0` in `settings.txt`, dann die Karte wie
  bei der Installation noch einmal einstecken.
- **Nur Kasten oder Head-up-Display abschalten:** ihre Zeilen in `settings.txt` auf `0` stellen
  und die Karte noch einmal einstecken.
- **Alles entfernen:** im Ordner `Mods/ClusterIntegration` eine leere Datei `uninstall.txt`
  anlegen und die Karte noch einmal einstecken. Danach ist das MMI wieder im
  Auslieferungszustand, was diesen Mod angeht. NavCompassIgnore bleibt installiert; wer ihn
  auch loswerden will, legt zusätzlich in `Mods/NavCompassIgnore` eine `uninstall.txt` an
  (nicht, wenn er schon vorher drauf war).

Kostenlos, nicht für den Verkauf (CC BY-NC-SA 4.0 bzw. GPL-3.0). NavCompassIgnore und das
MH2p SD ModKit sind von LawPaul (https://github.com/LawPaul), CC BY-NC-SA 4.0, unverändert
beigelegt.

- Download (neueste Version): https://github.com/CrEaK/mh2p-cluster/releases
- Fehler und Fragen: https://github.com/CrEaK/mh2p-cluster/issues
- Projektseite und getestete Fahrzeuge: https://github.com/CrEaK/mh2p-cluster
