import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

Future<void> _logWindowState(String stage) async {
  if (!Platform.isWindows) {
    return;
  }

  final maximized = await windowManager.isMaximized();
  final visible = await windowManager.isVisible();
  final bounds = await windowManager.getBounds();
  final message =
      '[window-startup] $stage visible=$visible maximized=$maximized bounds=$bounds';

  debugPrint(message);

  final logFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}vault_os_window_startup.log',
  );
  await logFile.writeAsString('$message\n', mode: FileMode.append, flush: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1366, 768),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      fullScreen: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await _logWindowState('before-show');
      await windowManager.show();
      await _logWindowState('after-show');
      await windowManager.maximize();
      await _logWindowState('after-maximize');
      await windowManager.focus();
      await _logWindowState('after-focus');
    });

    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      await _logWindowState('delayed-check');
    });
  }

  runApp(const VaultOsApp());
}
