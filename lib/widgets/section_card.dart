import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/vault_theme.dart';

/// A compact panel with a hairline border — no drop shadows,
/// no double-nested containers. Used as the single wrapping
/// layer per screen, never stacked inside itself.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(VaultTheme.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: VaultTheme.surfaceStrong,
            borderRadius: BorderRadius.circular(VaultTheme.radius),
            border: Border.all(color: VaultTheme.border, width: 1.1),
            gradient: LinearGradient(
              colors: <Color>[
                VaultTheme.glassHighlightStrong,
                Colors.black.withValues(alpha: 0.18),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
