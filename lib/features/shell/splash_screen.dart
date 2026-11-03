import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/agecare_logo.dart';

/// Pantalla de arranque mientras se restaura la sesión (AuthLoading).
/// El router redirige a /login o /home cuando el estado se resuelve.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AgeCareLogo(
              size: 64,
              textColor: Colors.white,
            ),
            SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
