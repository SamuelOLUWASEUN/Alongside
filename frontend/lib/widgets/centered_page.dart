import 'package:flutter/material.dart';

/// A scrollable content column that vertically centers itself when shorter
/// than the viewport (rather than leaving dead space below, like a plain
/// ListView does), and caps its width on wide screens so content doesn't
/// stretch edge-to-edge on desktop. Still scrolls normally once content is
/// taller than the available height.
class CenteredPage extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final double maxWidth;

  const CenteredPage({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(20),
    this.maxWidth = 560,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - padding.vertical).clamp(0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
