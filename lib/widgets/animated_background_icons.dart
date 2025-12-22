import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Háttér illusztráció - diák az asztalnál tanul (statikus, animáció nélkül)
class AnimatedBackgroundIcons extends StatelessWidget {
  const AnimatedBackgroundIcons({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        // Fő illusztráció - diák az asztalnál tanul
        // Pozicionálva a háttérben, de láthatóan - jobb oldalt, hogy ne takarja a login panelt
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight, // Jobb oldalt pozicionálva
            child: Opacity(
              opacity: 0.5, // Statikus opacity
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: SizedBox(
                  width: size.width * 0.5, // Kisebb méret, hogy ne takarja el
                  height: size.height * 0.6,
                  child: SvgPicture.asset(
                    'assets/images/student_studying.svg',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
