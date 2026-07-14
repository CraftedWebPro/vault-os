import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/vault_theme.dart';

/// Vault OS's signature glyph — a brass combination-lock dial.
/// Ring and ticks spin gently while [spinning] is true; the lock
/// icon at the center stays put, like a dial being turned.
class VaultMark extends StatefulWidget {
  const VaultMark({super.key, this.size = 32, this.spinning = false});

  final double size;
  final bool spinning;

  @override
  State<VaultMark> createState() => _VaultMarkState();
}

class _VaultMarkState extends State<VaultMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VaultMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          RotationTransition(
            turns: _controller,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _DialPainter(),
            ),
          ),
          Icon(Icons.lock_outline, size: widget.size * 0.4, color: VaultTheme.brass),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;

    final ring = Paint()
      ..color = VaultTheme.brass.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawCircle(center, radius, ring);

    final tick = Paint()
      ..color = VaultTheme.brass.withValues(alpha: 0.6)
      ..strokeWidth = 1.4;
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * pi;
      final len = i % 3 == 0 ? 4.5 : 2.5;
      final outer = center + Offset(cos(angle), sin(angle)) * radius;
      final inner = center + Offset(cos(angle), sin(angle)) * (radius - len);
      canvas.drawLine(outer, inner, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) => false;
}