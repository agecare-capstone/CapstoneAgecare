import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Aviso legal: AgeCare organiza y recuerda medicamentos, pero no reemplaza a
/// un profesional de la salud. Se muestra en Inicio y en las pantallas de
/// medicamentos.
class MedicalDisclaimer extends StatelessWidget {
  const MedicalDisclaimer({super.key, this.forElder = false});

  /// Versión para el adulto mayor: frases más cortas y letra más grande.
  final bool forElder;

  static const text =
      'AgeCare te ayuda a organizar y recordar los medicamentos, pero no '
      'reemplaza la indicación de un médico ni de otro profesional de la '
      'salud. No inicies, cambies ni suspendas un tratamiento sin '
      'consultarlo. Ante una emergencia, llama al 131.';

  static const elderText =
      'Esta app te recuerda tus remedios, pero no reemplaza a tu médico. '
      'No cambies ni dejes de tomar un remedio sin preguntarle. '
      'En una emergencia, llama al 131.';

  @override
  Widget build(BuildContext context) {
    final body = forElder ? elderText : text;
    return Semantics(
      container: true,
      label: 'Aviso importante. $body',
      child: ExcludeSemantics(
        child: Container(
          key: const Key('medical-disclaimer'),
          padding: EdgeInsets.all(forElder ? 16 : 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: .25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.primaryDark, size: forElder ? 30 : 20),
              SizedBox(width: forElder ? 12 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importante',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: forElder ? 22 : 14,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: forElder ? 20 : 13,
                        height: 1.35,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
