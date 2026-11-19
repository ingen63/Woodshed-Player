# Woodshed Player – Flutter-Prototyp (GEN-5)

Prototyp für den Umbau (`docs/UMBAUPLAN-FLUTTER.md`): Datei öffnen, Wiedergabe, Tempo 0,1×–2× ohne Tonhöhenänderung,
Loop A–B und auf macOS 14.2+ die Aufnahme des Systemtons (FEA-4). Audio läuft im C++-Kern `../core`,
angebunden über das FFI-Plugin `packages/wp_core`.

```
flutter run -d macos      # oder: flutter run -d <iOS-Simulator>
flutter test
```

Im Browser (#34): erst den WASM-Kern bauen und nach `web/wp_core/` legen, dann wie gewohnt:

```
tool/build_web_core.sh
flutter build web          # oder: flutter run -d chrome
tool/web_core_check.sh     # Prüfseite nach build/web_check, im Browser «Run checks»
```
