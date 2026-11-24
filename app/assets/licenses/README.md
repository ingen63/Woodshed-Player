# Lizenztexte der Kern-Bibliotheken

Unveränderte Kopien der Lizenzdateien aus `core/third_party/` (#119). Die App zeigt sie unter «Über Woodshed Player» › *Lizenzen ansehen* (`app/lib/ui/core_licenses.dart`). Ein Test (`app/test/core_licenses_test.dart`) prüft, dass jede Bibliothek aus `core/third_party/README.md` hier liegt und der Text mit dem Original übereinstimmt. Nach einem Update in `core/third_party/` die Datei hierher kopieren.

`lame/LICENSE.txt` (#141): LAME liegt nicht in `core/third_party/`, sondern wird von `tools/build-lame.sh` aus der Quelle gebaut und nur in die Mac-App gelegt (LGPL, zur Laufzeit geladen). Die Datei nennt Version, Quelle, Prüfsumme und die austauschbare Datei in der App; darunter steht der Lizenztext (`COPYING` aus der Quelle) unverändert. Ein Test prüft, dass Version und Prüfsumme mit dem Bauskript übereinstimmen.
