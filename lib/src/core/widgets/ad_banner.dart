import 'package:flutter/material.dart';

/// Reusable banner slot. Displays a neutral placeholder until an ad unit ID
/// and the ad SDK are configured.
class AdBanner extends StatelessWidget {
  const AdBanner({
    super.key,
    this.height = 60,
    this.aspectRatio,
    this.maxWidth,
  });

  final double height;
  final double? aspectRatio;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slot = Semantics(
      label: 'Iklan',
      child: Container(
        width: double.infinity,
        height: aspectRatio == null ? height : null,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Text(
          'Iklan',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: .4,
          ),
        ),
      ),
    );
    if (aspectRatio == null) return slot;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        child: AspectRatio(aspectRatio: aspectRatio!, child: slot),
      ),
    );
  }
}
