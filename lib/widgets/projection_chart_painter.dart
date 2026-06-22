import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProjectionChart extends StatelessWidget {
  final double height;

  const ProjectionChart({
    Key? key,
    this.height = 200.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _ProjectionPainter(),
    );
  }
}

class _ProjectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    const double padL = 8.0;
    const double padR = 12.0;
    const double padT = 24.0;
    const double padB = 24.0;

    final double chartW = w - padL - padR;
    final double chartH = h - padT - padB;

    // Scenarios data
    final List<double> optimistic = [200, 230, 265, 290, 320, 360];
    final List<double> realistic  = [200, 210, 220, 225, 235, 245];
    final List<double> pessimistic = [200, 185, 170, 160, 155, 150];

    final List<double> allVals = [...optimistic, ...realistic, ...pessimistic];
    final double minVal = allVals.reduce((a, b) => a < b ? a : b) * 0.95;
    final double maxVal = allVals.reduce((a, b) => a > b ? a : b) * 1.05;
    final double range = maxVal - minVal;

    final List<String> months = ['T7', 'T8', 'T9', 'T10', 'T11', 'T12'];

    // 1. Draw horizontal grid lines
    final Paint gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final double y = padT + (i / 4) * chartH;
      canvas.drawLine(Offset(padL, y), Offset(w - padR, y), gridPaint);
    }

    // 2. Draw month labels at bottom
    for (int i = 0; i < months.length; i++) {
      final double x = padL + (i / (months.length - 1)) * chartW;
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: months[i],
          style: TextStyle(
            fontSize: 9.5,
            color: Colors.white.withOpacity(0.3),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, h - padB + 6));
    }

    // Convert list values to coordinate points
    List<Offset> toPoints(List<double> data) {
      final List<Offset> pts = [];
      for (int i = 0; i < data.length; i++) {
        final double x = padL + (i / (data.length - 1)) * chartW;
        final double y = padT + (1.0 - (data[i] - minVal) / range) * chartH;
        pts.add(Offset(x, y));
      }
      return pts;
    }

    final List<Offset> optPts = toPoints(optimistic);
    final List<Offset> realPts = toPoints(realistic);
    final List<Offset> pesPts = toPoints(pessimistic);

    // 3. Draw background shaded fill between optimistic and pessimistic
    final Path rangePath = Path();
    rangePath.moveTo(optPts[0].dx, optPts[0].dy);
    for (var p in optPts) {
      rangePath.lineTo(p.dx, p.dy);
    }
    for (int i = pesPts.length - 1; i >= 0; i--) {
      rangePath.lineTo(pesPts[i].dx, pesPts[i].dy);
    }
    rangePath.close();

    final Paint rangePaint = Paint()
      ..color = AppTheme.colorWarm.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    canvas.drawPath(rangePath, rangePaint);

    // 4. Draw Lines
    void drawCurveLine(List<Offset> pts, Color color, bool isDashed) {
      final Paint linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final Path path = Path();
      path.moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }

      if (isDashed) {
        // Simple manual dash drawing
        final Path dashPath = Path();
        double dashWidth = 6.0;
        double gapWidth = 4.0;
        
        for (int i = 0; i < pts.length - 1; i++) {
          final Offset start = pts[i];
          final Offset end = pts[i + 1];
          final double dx = end.dx - start.dx;
          final double dy = end.dy - start.dy;
          final double distance = (end - start).distance;
          
          double currentDist = 0.0;
          while (currentDist < distance) {
            final double nextDist = currentDist + dashWidth;
            final double startPct = currentDist / distance;
            final double endPct = nextDist > distance ? 1.0 : nextDist / distance;
            
            dashPath.moveTo(start.dx + dx * startPct, start.dy + dy * startPct);
            dashPath.lineTo(start.dx + dx * endPct, start.dy + dy * endPct);
            
            currentDist += dashWidth + gapWidth;
          }
        }
        canvas.drawPath(dashPath, linePaint);
      } else {
        canvas.drawPath(path, linePaint);
      }
    }

    drawCurveLine(pesPts, AppTheme.colorDanger, true);
    drawCurveLine(realPts, AppTheme.colorWarm, false);
    drawCurveLine(optPts, AppTheme.colorSafe, true);

    // 5. Draw Legend
    final List<Map<String, dynamic>> legends = [
      {'color': AppTheme.colorSafe, 'label': 'Tươi sáng', 'offset': 0.0},
      {'color': AppTheme.colorWarm, 'label': 'Thực tế', 'offset': 90.0},
      {'color': AppTheme.colorDanger, 'label': 'Rủi ro', 'offset': 170.0},
    ];

    for (var leg in legends) {
      final double startX = padL + leg['offset'];
      
      // Legend Circle indicator
      canvas.drawCircle(
        Offset(startX + 5.0, padT - 12.0),
        3.0,
        Paint()..color = leg['color'] as Color
      );

      // Legend Label Text
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: leg['label'] as String,
          style: TextStyle(
            fontSize: 9.5,
            color: Colors.white.withOpacity(0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(startX + 12.0, padT - 12.0 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ProjectionPainter oldDelegate) {
    return false;
  }
}
