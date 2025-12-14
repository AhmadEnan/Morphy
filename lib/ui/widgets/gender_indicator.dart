import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Gender types for the indicator
enum Gender { male, female, unknown }

/// Non-interactive gender indicator icon
class GenderIndicator extends StatelessWidget {
  final Gender gender;
  final double size;
  final double? confidence;

  const GenderIndicator({
    super.key,
    this.gender = Gender.unknown,
    this.size = 24,
    this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (gender) {
      Gender.male => Icons.male_rounded,
      Gender.female => Icons.female_rounded,
      Gender.unknown => Icons.person_outline_rounded,
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.overlayLight,
      ),
      child: Icon(icon, color: AppColors.iconActive, size: size),
    );
  }
}
