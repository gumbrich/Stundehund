import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'storage.dart';
import 'tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1120, 820),
      minimumSize: Size(760, 600),
      center: true,
      title: 'Stundehund',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0xFFF5F4F0),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  try {
    final directory = await getApplicationSupportDirectory();
    final store = FileStore(Directory('${directory.path}/Stundehund'));
    final tracker = Tracker(await store.load(), store);
    await tracker.recover();
    if (tracker.error != null) {
      throw FileSystemException(tracker.error!);
    }
    runApp(
      StundehundApp(
        tracker: tracker,
        desktop: true,
        dataPath: store.directory.path,
        onQuit: () async {
          await store.close();
          await windowManager.destroy();
        },
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('de', 'CH')],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pets_rounded, size: 48),
                  const SizedBox(height: 24),
                  const Text(
                    'Stundehund konnte nicht starten',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 16),
                  SelectableText('$error'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => windowManager.destroy(),
                    child: const Text('Schliessen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
