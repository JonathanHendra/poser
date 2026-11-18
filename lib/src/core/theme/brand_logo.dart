import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 150});
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width / 3.3,
    child: ClipRect(
      child: OverflowBox(
        alignment: Theme.of(context).brightness == Brightness.dark
            ? Alignment.centerRight
            : Alignment.centerLeft,
        maxWidth: width * 2,
        maxHeight: width * 2 / 3,
        child: Image.asset(
          'assets/images/logo.png',
          width: width * 2,
          height: width * 2 / 3,
          fit: BoxFit.fill,
        ),
      ),
    ),
  );
}
