import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Paleta "Perpetuum"
  static const Color background = Color(0xFF05070A); // Quase preto, azul profundo
  static const Color surface = Color(0xFF10141D);
  static const Color cyanNeon = Color(0xFF00E5FF); // O brilho principal
  static const Color cyanDim = Color(0xFF004D57);
  static const Color textPrimary = Color(0xFFEBEBF5);
  static const Color textSecondary = Color(0xFF8A8F98);

  static TextStyle get titleStyle => GoogleFonts.outfit(
    color: textPrimary,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get bodyStyle => GoogleFonts.outfit(
    color: textSecondary,
  );
}

// O componente chave do Glassmorphism
class GlassCard extends StatelessWidget {
  final Widget child;
  final double opacity;
  final EdgeInsetsGeometry? padding;

  const GlassCard({
    Key? key,
    required this.child,
    this.opacity = 0.07,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.02),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}