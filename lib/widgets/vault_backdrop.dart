import 'package:flutter/material.dart';

import '../theme/vault_theme.dart';

class VaultBackdrop extends StatelessWidget {
  const VaultBackdrop({super.key, required this.child, this.wallpaperAsset});

  final Widget child;
  final String? wallpaperAsset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (wallpaperAsset != null && wallpaperAsset!.isNotEmpty)
          Image.asset(
            wallpaperAsset!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const _FallbackBackdrop(),
          )
        else
          const _FallbackBackdrop(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Colors.black.withValues(alpha: 0.56),
                Colors.black.withValues(alpha: 0.68),
                VaultTheme.bg.withValues(alpha: 0.94),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Colors.black.withValues(alpha: 0.46),
                Colors.black.withValues(alpha: 0.16),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.center,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.12,
              colors: <Color>[
                Colors.transparent,
                Colors.black.withValues(alpha: 0.20),
                Colors.black.withValues(alpha: 0.38),
              ],
              stops: const <double>[0.0, 0.72, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -40,
          child: _GlowOrb(
            color: VaultTheme.brass.withValues(alpha: 0.18),
            size: 280,
          ),
        ),
        Positioned(
          bottom: -140,
          left: -60,
          child: _GlowOrb(
            color: const Color(0xFF9AD4FF).withValues(alpha: 0.14),
            size: 320,
          ),
        ),
        child,
      ],
    );
  }
}

class _FallbackBackdrop extends StatelessWidget {
  const _FallbackBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color(0xFF0A1213),
            Color(0xFF111821),
            Color(0xFF090A0D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
