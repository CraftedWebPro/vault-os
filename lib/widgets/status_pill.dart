import 'package:flutter/material.dart';

import '../theme/vault_theme.dart';

enum PillTone { neutral, brass, success, danger, warning }

/// A compact status badge — used instead of big colored banner boxes.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.icon,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;

  Color get _color {
    switch (tone) {
      case PillTone.brass:
        return VaultTheme.brass;
      case PillTone.success:
        return VaultTheme.success;
      case PillTone.danger:
        return VaultTheme.danger;
      case PillTone.warning:
        return VaultTheme.warning;
      case PillTone.neutral:
        return VaultTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}