import 'package:flutter/material.dart';

/// A small filled circle for a bike profile's colour. Always drawn with a
/// subtle mid-grey border so light colours (white, silver) stay visible
/// against a same-colour background, in any app theme — a plain
/// `CircleAvatar(backgroundColor: ...)` with no border disappears entirely
/// when the swatch colour matches the page behind it.
class BikeColorDot extends StatelessWidget {
  const BikeColorDot({
    super.key,
    required this.colorArgb,
    this.radius = 8,
    this.child,
  });

  final int colorArgb;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(colorArgb),
          border: Border.all(color: Colors.grey.shade600),
        ),
        child: child,
      );
}

/// Black or white — whichever reads clearly on top of [colorArgb] — for a
/// checkmark/icon drawn on a colour swatch.
Color bikeColorContrast(int colorArgb) =>
    Color(colorArgb).computeLuminance() > 0.5 ? Colors.black : Colors.white;
