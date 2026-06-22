import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? glowColor;
  final bool animatePulse;

  const GlassCard({
    Key? key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    this.glowColor,
    this.animatePulse = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget cardContent = Container(
      padding: padding ?? const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppTheme.glassBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AppTheme.glassBorder,
          width: 1.0,
        ),
      ),
      child: child,
    );

    // Apply BackdropFilter for glass blur
    Widget glassEffect = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppTheme.glassBlur, sigmaY: AppTheme.glassBlur),
        child: cardContent,
      ),
    );

    // Apply shadow/glow if needed
    if (glowColor != null) {
      return Container(
        margin: margin ?? EdgeInsets.zero,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: AppTheme.getGlow(glowColor!),
        ),
        child: glassEffect,
      );
    }

    return margin != null
        ? Padding(
            padding: margin!,
            child: glassEffect,
          )
        : glassEffect;
  }
}
