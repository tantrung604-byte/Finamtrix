import 'package:flutter/material.dart';

/// Responsive helpers for a mobile-first UI that also behaves well on large
/// phones, tablets, web and desktop.
///
/// Usage:
///   context.w(150)        // width scaled relative to a 390pt design baseline
///   context.sp(14)        // font size, scaled & clamped for readability
///   context.gap(16)       // scaled spacing
///   context.isTablet      // breakpoint helpers
///   ResponsiveShell(...)  // centers content at phone width on big screens
class Responsive {
  Responsive._();

  /// Design baseline width (iPhone 13/14 logical width).
  static const double baseWidth = 390.0;

  /// Phone content never renders wider than this on tablet/web/desktop.
  static const double maxContentWidth = 520.0;

  static const double tabletBreakpoint = 600.0;
  static const double desktopBreakpoint = 1024.0;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  bool get isTablet => screenWidth >= Responsive.tabletBreakpoint;
  bool get isDesktop => screenWidth >= Responsive.desktopBreakpoint;
  bool get isCompact => screenWidth < 360;

  /// The effective design width (capped so big screens don't over-scale).
  double get _designWidth =>
      screenWidth.clamp(0.0, Responsive.maxContentWidth);

  /// Scale factor relative to the design baseline, clamped to a sane range.
  double get _scale => (_designWidth / Responsive.baseWidth).clamp(0.85, 1.15);

  /// Scaled width/size in logical pixels.
  double w(double value) => value * _scale;

  /// Scaled, readability-clamped font size.
  double sp(double value) => value * _scale.clamp(0.9, 1.1);

  /// Scaled spacing.
  double gap(double value) => value * _scale;

  /// Page horizontal padding that grows a little on wider phones.
  double get pagePadding => isCompact ? 12.0 : 16.0;
}

/// Centers content at phone width on tablet/web/desktop so the app keeps its
/// mobile feel instead of stretching edge-to-edge.
class ResponsiveShell extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveShell({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

