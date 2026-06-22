import 'package:flutter/material.dart';

class LineChartWidget extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double height;

  const LineChartWidget({
    Key? key,
    required this.data,
    required this.color,
    this.height = 200.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: LineChartPainter(data: data, color: color),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  LineChartPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double w = size.width;
    final double h = size.height;
    
    const double padL = 8.0;
    const double padR = 28.0;
    const double padT = 16.0;
    const double padB = 24.0;

    final double chartW = w - padL - padR;
    final double chartH = h - padT - padB;

    final double minVal = data.reduce((a, b) => a < b ? a : b) * 0.998;
    final double maxVal = data.reduce((a, b) => a > b ? a : b) * 1.002;
    final double range = maxVal - minVal == 0 ? 1 : maxVal - minVal;

    // 1. Draw Grid lines & Y-axis labels
    final Paint gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final double y = padT + (i / 4) * chartH;
      canvas.drawLine(Offset(padL, y), Offset(w - padR, y), gridPaint);

      // Y-axis value
      final double val = maxVal - (i / 4) * range;
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: val.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 9.0,
            color: Colors.white.withOpacity(0.25),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(w - padR + 4, y - tp.height / 2));
    }

    // Calculate data point locations
    final List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      final double x = padL + (i / (data.length - 1)) * chartW;
      final double y = padT + (1.0 - (data[i] - minVal) / range) * chartH;
      points.add(Offset(x, y));
    }

    // Helper path for bezier curve
    Path getBezierPath(List<Offset> pts) {
      final Path path = Path();
      if (pts.isEmpty) return path;
      path.moveTo(pts[0].dx, pts[0].dy);
      
      for (int i = 1; i < pts.length; i++) {
        final double prevX = pts[i - 1].dx;
        final double prevY = pts[i - 1].dy;
        final double currX = pts[i].dx;
        final double currY = pts[i].dy;
        
        final double cpX = (prevX + currX) / 2;
        path.quadraticBezierTo(prevX, prevY, cpX, (prevY + currY) / 2);
      }
      path.lineTo(pts[pts.length - 1].dx, pts[pts.length - 1].dy);
      return path;
    }

    // 2. Draw Area fill
    final Path areaPath = getBezierPath(points);
    areaPath.lineTo(points[points.length - 1].dx, h - padB);
    areaPath.lineTo(points[0].dx, h - padB);
    areaPath.close();

    final Paint areaPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withOpacity(0.18), color.withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, padT, w, chartH))
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(areaPath, areaPaint);

    // 3. Draw Bezier line with glow shadow
    final Path linePath = getBezierPath(points);
    final Paint glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    
    canvas.drawPath(linePath, glowPaint);

    final Paint linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    
    canvas.drawPath(linePath, linePaint);

    // 4. Draw Animated/Pulsing Dot at the end
    final Offset last = points[points.length - 1];
    
    // Outer glow ring
    canvas.drawCircle(
      last, 
      7.0, 
      Paint()
        ..color = color.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
    );

    // Inner filled dot
    canvas.drawCircle(
      last, 
      4.0, 
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
    );

    // 5. Draw Bottom Labels (T2 to CN or days of week)
    final List<String> labels = data.length <= 7
        ? ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
        : List.generate(data.length, (index) => (index % 2 == 0) ? '${index + 1}' : '');

    for (int i = 0; i < labels.length; i++) {
      if (labels[i].isEmpty) continue;
      final double x = padL + (i / (labels.length - 1)) * chartW;
      
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 9.0,
            color: Colors.white.withOpacity(0.25),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, h - padB + 6));
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
