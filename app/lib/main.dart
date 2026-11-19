// Woodshed Player (Flutter): Bibliothek (#16), Wiedergabe mit Tempo und Loop über den C++-Kern (#15),
// Metronom (#3), Aufnahme des Systemtons (macOS, #4). Oberfläche im Design «Studio» (#30).
// Desktop und Handy nutzen den Kern über FFI, der Browser den WASM-Kern (#34); der bedingte Import wählt.
import 'package:material_ui/material_ui.dart';

import 'app/app_controller.dart';
import 'app/platform_native.dart'
    if (dart.library.js_interop) 'app/platform_web.dart';
import 'ui/font_licenses.dart';
import 'ui/home_page.dart';
import 'ui/style.dart';

export 'app/platform_native.dart'
    if (dart.library.js_interop) 'app/platform_web.dart'
    show createAppController;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final controller = await createAppController();
  runApp(
    WoodshedApp(controller: controller, recordingButton: recordingButtonFor),
  );
}

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({
    super.key,
    required this.controller,
    this.recordingButton,
  });
  final AppController controller;

  /// Aufnahme-Knopf, wo es Aufnahme gibt (nur macOS); null sonst.
  final Widget? Function(AppController controller)? recordingButton;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woodshed Player',
      theme: woodshedTheme(Brightness.light),
      darkTheme: woodshedTheme(Brightness.dark),
      home: HomePage(
        controller: controller,
        recordingButton: recordingButton?.call(controller),
      ),
    );
  }
}
