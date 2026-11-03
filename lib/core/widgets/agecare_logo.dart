import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AgeCareLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final Color? textColor;

  const AgeCareLogo({
    super.key,
    this.size = 30.0,
    this.showText = true,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/images/logo_icon.svg',
          width: size,
          height: size,
        ),
        if (showText) ...[
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: size * 0.9,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: textColor ?? const Color(0xFF163B35),
              ),
              children: [
                const TextSpan(
                  text: 'age',
                ),
                const TextSpan(
                  text: 'care',
                  style: TextStyle(color: Color(0xFF19B6A4)),
                ),
                TextSpan(
                  text: '.',
                  style: TextStyle(
                    color: const Color(0xFFFF7A3D),
                    fontSize: size * 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
