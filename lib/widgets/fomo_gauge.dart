import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FomoGauge extends StatefulWidget {
  final double value;
  final double height;
  final String label;

  const FomoGauge({
    Key? key,
    required this.value,
    this.height = 160.0,
    this.label = '',
  }) : super(key: key);

  @override
  State<FomoGauge> createState() => _FomoGaugeState();
}

class _FomoGaugeState extends State<FomoGauge> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: widget.value).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant FomoGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animation = Tween<double>(begin: _animation.value, end: widget.value).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(double.infinity, widget.height),
                painter: _GaugePainter(
                  value: _animation.value,
                ),
              ),
              Positioned(
                bottom: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _animation.value.round().toString(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Text(
                      '/ 100',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;

  _GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    
    // Center point of arc is bottom middle
    final double cx = w / 2;
    final double cy = h - 20.0;
    
    final double radius = min(cx, cy) * 0.95;
    final double strokeWidth = radius * 0.16;

    // Background track (Gray arc)
    final Paint trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      pi,
      pi,
      false,
      trackPaint,
    );

    // Colored Segments
    final List<Color> colors = [
      AppTheme.colorSafe,
      AppTheme.colorWarm,
      AppTheme.colorHot,
      AppTheme.colorDanger,
    ];

    final double segmentAngle = pi / 4;

    for (int i = 0; i < 4; i++) {
      final Paint segPaint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        pi + (i * segmentAngle),
        segmentAngle,
        false,
        segPaint,
      );
    }

    // Segment dividers
    final Paint dividerPaint = Paint()
      ..color = AppTheme.bgPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 1; i < 4; i++) {
      final double angle = pi + (i * segmentAngle);
      final double x1 = cx + (radius - strokeWidth / 2 - 2) * cos(angle);
      final double y1 = cy + (radius - strokeWidth / 2 - 2) * sin(angle);
      final double x2 = cx + (radius + strokeWidth / 2 + 2) * cos(angle);
      final double y2 = cy + (radius + strokeWidth / 2 + 2) * sin(angle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), dividerPaint);
    }

    // Tick marks
    for (int i = 0; i <= 20; i++) {
      final double angle = pi + (i / 20) * pi;
      final bool isMajor = i % 5 == 0;
      final double innerR = radius + strokeWidth / 2 + 4;
      final double outerR = innerR + (isMajor ? 8.0 : 4.0);

      final double x1 = cx + innerR * cos(angle);
      final double y1 = cy + innerR * sin(angle);
      final double x2 = cx + outerR * cos(angle);
      final double y2 = cy + outerR * sin(angle);

      final Paint tickPaint = Paint()
        ..color = isMajor ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isMajor ? 1.5 : 1.0;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), tickPaint);
    }

    // Draw Labels (AN TOÀN, ẤM, ĐỘT BIẾN, NGUY HIỂM)
    final List<String> labels = ['AN TOÀN', 'ẤM', 'ĐỘT BIẾN', 'NGUY HIỂM'];
    final List<Color> labelColors = [
      AppTheme.colorSafe,
      AppTheme.colorWarm,
      AppTheme.colorHot,
      AppTheme.colorDanger,
    ];
    final List<double> labelPositions = [0.125, 0.375, 0.625, 0.875];

    for (int i = 0; i < 4; i++) {
      final double angle = pi + labelPositions[i] * pi;
      final double labelR = radius - strokeWidth / 2 - 14;
      final double lx = cx + labelR * cos(angle);
      final double ly = cy + labelR * sin(angle);

      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: labelColors[i],
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }

    // Needle Drawing
    final double needleAngle = pi + (value / 100) * pi;
    final double needleLength = radius * 0.72;

    final Path needlePath = Path();
    needlePath.moveTo(
      cx + 6 * cos(needleAngle + pi / 2),
      cy + 6 * sin(needleAngle + pi / 2),
    );
    needlePath.lineTo(
      cx + needleLength * cos(needleAngle),
      cy + needleLength * sin(needleAngle),
    );
    needlePath.lineTo(
      cx + 6 * cos(needleAngle - pi / 2),
      cy + 6 * sin(needleAngle - pi / 2),
    );
    needlePath.close();

    // Needle Shadow
    final Paint needleShadow = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(needlePath, needleShadow);

    // Needle Fill
    final Paint needlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(needlePath, needlePaint);

    // Center circular hub
    canvas.drawCircle(Offset(cx, cy), 12.0, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx, cy), 7.0, Paint()..color = AppTheme.bgPrimary);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value;
  }
}
