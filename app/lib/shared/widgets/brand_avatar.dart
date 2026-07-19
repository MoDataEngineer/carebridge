import 'package:flutter/material.dart';

/// Doctor photo / clinic logo avatar with a graceful fallback: when no image
/// URL is set (or it fails to load), show the initials on the primary
/// container — never a broken-image glyph. Minimum 44px tap-friendly sizing.
class BrandAvatar extends StatelessWidget {
  const BrandAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 22,
    this.square = false, // logos read better square-ish; people round
  });

  final String name;
  final String? imageUrl;
  final double radius;
  final bool square;

  String get _initials {
    final parts = name
        .replaceAll(RegExp(r'^(Dr\.?|Dr)\s+', caseSensitive: false), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Center(
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
    final content = (imageUrl == null || imageUrl!.isEmpty)
        ? fallback
        : Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            width: radius * 2,
            height: radius * 2,
            errorBuilder: (_, __, ___) => fallback,
          );
    return Container(
      width: radius * 2,
      height: radius * 2,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(radius * 0.35) : null,
      ),
      child: content,
    );
  }
}
