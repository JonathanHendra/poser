import 'dart:typed_data';
import 'package:flutter/material.dart';

class ProductPhoto extends StatelessWidget {
  const ProductPhoto({
    super.key,
    required this.bytes,
    this.size = 48,
    this.fit = BoxFit.contain,
  });
  final Uint8List? bytes;
  final double? size;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: bytes == null
          ? ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.inventory_2_outlined),
            )
          : Image.memory(
              bytes!,
              fit: fit,
              gaplessPlayback: true,
              cacheWidth: size == null
                  ? null
                  : (size! * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(48, 2048),
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            ),
    ),
  );
}
