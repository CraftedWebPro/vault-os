import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class AppWindowFrame extends StatelessWidget {
  const AppWindowFrame({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return child;
    }

    return Column(
      children: <Widget>[
        const AppCustomTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}

class AppCustomTitleBar extends StatefulWidget {
  const AppCustomTitleBar({super.key});

  @override
  State<AppCustomTitleBar> createState() => _AppCustomTitleBarState();
}

class _AppCustomTitleBarState extends State<AppCustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncWindowState();
  }

  Future<void> _syncWindowState() async {
    final maximized = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() {
      _isMaximized = maximized;
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    debugPrint('[window-titlebar] onWindowMaximize');
    if (!mounted) return;
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    debugPrint('[window-titlebar] onWindowUnmaximize');
    if (!mounted) return;
    setState(() {
      _isMaximized = false;
    });
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32, // Dropped down to absolute native utility standards
      color: const Color(0xFFF9FAFB), // Clean, crisp bone-white 
      child: Row(
        children: <Widget>[
          // Drag surface & Minimal branding
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximize,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    // Tiny, low-profile status pulse indicator instead of a double logo
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981), 
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'VAULT OS',
                      style: TextStyle(
                        color: Color(0xFF6B7280), // Muted charcoal for zero distraction
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Clean window controls built right into the right layout edge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TitleBarButton(
                icon: const _WindowIconPainter(type: _IconType.minimize),
                onTap: () => windowManager.minimize(),
              ),
              _TitleBarButton(
                icon: _WindowIconPainter(
                  type: _isMaximized ? _IconType.restore : _IconType.maximize,
                ),
                onTap: _toggleMaximize,
              ),
              _TitleBarButton(
                icon: const _WindowIconPainter(type: _IconType.close),
                danger: true,
                onTap: () => windowManager.close(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final Widget icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.danger 
        ? const Color(0xFFE81123) 
        : const Color(0xFFF0F2F5); 

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          width: 46,
          height: double.infinity,
          alignment: Alignment.center,
          color: _isHovered ? hoverColor : Colors.transparent,
          child: DefaultTextStyle(
            style: TextStyle(
              color: _isHovered && widget.danger 
                  ? Colors.white 
                  : const Color(0xFF1F2937),
            ),
            child: widget.icon,
          ),
        ),
      ),
    );
  }
}

enum _IconType { minimize, maximize, restore, close }

// Replaced Material Icons with crisp, pixel-perfect structural canvas drawings
class _WindowIconPainter extends StatelessWidget {
  const _WindowIconPainter({required this.type});

  final _IconType type;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ?? const Color(0xFF1F2937);
    
    return SizedBox(
      width: 10,
      height: 10,
      child: CustomPaint(
        painter: _IconCustomPainter(type: type, color: color),
      ),
    );
  }
}

class _IconCustomPainter extends CustomPainter {
  _IconCustomPainter({required this.type, required this.color});

  final _IconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    switch (type) {
      case _IconType.minimize:
        canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
        break;
      case _IconType.maximize:
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
        break;
      case _IconType.restore:
        canvas.drawRect(Rect.fromLTWH(0, 2, size.width - 2, size.height - 2), paint);
        canvas.drawLine(const Offset(2, 0), const Offset(8, 0), paint);
        canvas.drawLine(const Offset(8, 0), const Offset(8, 6), paint);
        canvas.drawLine(const Offset(2, 2), const Offset(2, 0), paint);
        canvas.drawLine(const Offset(8, 6), const Offset(6, 6), paint);
        break;
      case _IconType.close:
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _IconCustomPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color;
}
