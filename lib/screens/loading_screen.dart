import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../theme/vault_theme.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    this.message,
  });

  final String? message;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  late final Future<String> _versionFuture;

  static const List<String> _fallbackLines = <String>[
    'Getting things ready...',
    'Checking the lock...',
    'Waking up the vault...',
    'Still local. Still private.',
  ];

  @override
  void initState() {
    super.initState();
    _versionFuture = _loadVersion();
  }

  Future<String> _loadVersion() async {
    try {
      final source = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(
        r'^version:\s*([^\s]+)',
        multiLine: true,
      ).firstMatch(source);
      if (match != null) {
        return 'v${match.group(1)}';
      }
    } catch (_) {
      // Use fallback below.
    }
    return 'v1.0.0';
  }

  @override
  Widget build(BuildContext context) {
    final resolvedMessage =
        widget.message ?? _fallbackLines[DateTime.now().second % _fallbackLines.length];

    return Scaffold(
      backgroundColor: const Color(0xFF11161C),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const _SplashBackground(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B222B).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 30,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 76,
                        height: 76,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222B36),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/images/vault logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Vault OS',
                        style: TextStyle(
                          color: Color(0xFFF5F7FA),
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A simple local vault for your files.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD3D9E2),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'No cloud. No account. Less nonsense.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF97A3B6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 96,
                        child: Lottie.asset(
                          'assets/json/splash.json',
                          fit: BoxFit.contain,
                          repeat: true,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        resolvedMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFE6EAF0),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: const LinearProgressIndicator(
                          minHeight: 6,
                          backgroundColor: Color(0xFF2D3744),
                          valueColor: AlwaysStoppedAnimation<Color>(VaultTheme.brass),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'If this takes too long, Windows is probably thinking about it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF98A4B5),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _VersionLabel(versionFuture: _versionFuture),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel({required this.versionFuture});

  final Future<String> versionFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: versionFuture,
      builder: (context, snapshot) {
        final version = snapshot.data ?? 'v...';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF222B36),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            version,
            style: const TextStyle(
              color: Color(0xFFBAC4D3),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

class _SplashBackground extends StatelessWidget {
  const _SplashBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Color(0xFF0F141A),
                Color(0xFF141B22),
                Color(0xFF1A232C),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  VaultTheme.brass.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -70,
          child: Container(
            width: 220,
            height: 220,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  Color(0x1228D7C4),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
