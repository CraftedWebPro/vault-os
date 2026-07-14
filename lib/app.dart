import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'controllers/vault_app_controller.dart';
import 'screens/loading_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/vault_home_screen.dart';
import 'screens/vault_picker_screen.dart';
import 'screens/vault_setup_details_screen.dart';
import 'theme/vault_theme.dart';
import 'widgets/custom_title_bar.dart';
import 'widgets/vault_backdrop.dart';

class VaultOsApp extends StatefulWidget {
  const VaultOsApp({super.key});

  @override
  State<VaultOsApp> createState() => _VaultOsAppState();
}

class _VaultOsAppState extends State<VaultOsApp> {
  late final VaultAppController _controller;
  late final AppLifecycleListener _lifecycleListener;
  bool _startupComplete = false;

  @override
  void initState() {
    super.initState();
    _controller = VaultAppController();
    _bootstrap();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        final locked = await _controller.autoLockIfNeeded();
        return locked ? ui.AppExitResponse.exit : ui.AppExitResponse.cancel;
      },
    );
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[
      _controller.initialize(),
      Future<void>.delayed(const Duration(milliseconds: 2400)),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      _startupComplete = true;
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vault OS',
      debugShowCheckedModeBanner: false,
      theme: VaultTheme.themeData(),
      builder: (context, child) {
        return AppWindowFrame(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          late final Widget screen;
          if (!_startupComplete) {
            screen = LoadingScreen(message: _controller.statusMessage);
          } else if (_controller.isLoading) {
            screen = LoadingScreen(message: _controller.statusMessage);
          } else if (!_controller.hasVaults) {
            screen = VaultSetupDetailsScreen(
              controller: _controller,
              allowReuseCurrentSecurity: false,
            );
          } else if (!_controller.hasSelectedVault) {
            screen = VaultPickerScreen(controller: _controller);
          } else if (!_controller.isUnlocked) {
            screen = UnlockScreen(controller: _controller);
          } else {
            screen = VaultHomeScreen(controller: _controller);
          }

          return VaultBackdrop(
            wallpaperAsset: _startupComplete ? _controller.wallpaperAsset : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey<String>(
                  !_startupComplete
                      ? 'startup-splash'
                      : _controller.isLoading
                      ? 'loading'
                      : !_controller.hasVaults
                      ? 'setup'
                      : !_controller.hasSelectedVault
                      ? 'picker'
                      : !_controller.isUnlocked
                      ? 'unlock'
                      : 'home',
                ),
                child: screen,
              ),
            ),
          );
        },
      ),
      routes: <String, WidgetBuilder>{
        SettingsScreen.routeName: (_) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return VaultBackdrop(
              wallpaperAsset: _controller.wallpaperAsset,
              child: SettingsScreen(controller: _controller),
            );
          },
        ),
      },
    );
  }
}
