import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/geo.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// Orbital radar: you in the centre, providers placed by real bearing and
/// distance, rings at 1/3 and full radius, a rotating sweep.
class OrbitalRadar extends StatefulWidget {
  const OrbitalRadar({super.key, required this.center, required this.radiusKm, required this.workers, required this.onTap, required this.label});
  final LatLng center;
  final double radiusKm;
  final List<Worker> workers;
  final ValueChanged<Worker> onTap;
  final String label;

  @override
  State<OrbitalRadar> createState() => _OrbitalRadarState();
}

class _OrbitalRadarState extends State<OrbitalRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Offset _pos(Worker w, Size size) {
    final r = size.shortestSide / 2 * 0.86;
    final d = (w.distanceKm ?? 0).clamp(0, widget.radiusKm) / widget.radiusKm;
    final b = bearing(widget.center.lat, widget.center.lng, w.lat ?? widget.center.lat, w.lng ?? widget.center.lng);
    final c = size.center(Offset.zero);
    final dist = math.max(0.16, d) * r;
    return c + Offset(math.sin(b) * dist, -math.cos(b) * dist);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxWidth);
        return GestureDetector(
          onTapUp: (d) {
            Worker? best;
            var bestD = 30.0;
            for (final w in widget.workers) {
              final dd = (_pos(w, size) - d.localPosition).distance;
              if (dd < bestD) {
                bestD = dd;
                best = w;
              }
            }
            if (best != null) widget.onTap(best);
          },
          child: AnimatedBuilder(
            animation: _ctl,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _RadarPainter(
                t: _ctl.value,
                radiusKm: widget.radiusKm,
                dots: [
                  for (final w in widget.workers) (_pos(w, size), Kv.named(w.categoryColor), w.online, w.name.split(' ').first),
                ],
                label: widget.label,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.t, required this.radiusKm, required this.dots, required this.label, required this.dark});
  final double t;
  final double radiusKm;
  final List<(Offset, Color, bool, String)> dots;
  final String label;
  final bool dark;

  void _text(Canvas canvas, String s, Offset at, Color color, {double size = 10, Color? bg, bool center = true}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w800, fontFamily: Kv.mono)),
      textDirection: TextDirection.ltr,
    )..layout();
    final o = center ? at - Offset(tp.width / 2, tp.height / 2) : at;
    if (bg != null) {
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 8, o.dy - 4, tp.width + 16, tp.height + 8), const Radius.circular(10));
      canvas.drawRRect(rect, Paint()..color = bg);
      canvas.drawRRect(rect, Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: 0.6));
    }
    tp.paint(canvas, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.86;
    final bg = dark ? Kv.s950 : Kv.s50;

    // glow
    canvas.drawCircle(
        c,
        r * 1.08,
        Paint()
          ..shader = RadialGradient(colors: [Kv.emerald.withValues(alpha: 0.10), Colors.transparent])
              .createShader(Rect.fromCircle(center: c, radius: r * 1.08)));

    // rings
    final rings = [(1 / 3, Kv.amber), (2 / 3, Kv.emerald), (1.0, Kv.pink)];
    for (final (f, color) in rings) {
      canvas.drawCircle(
          c,
          r * f,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.55));
    }

    // sweep
    final sweepRect = Rect.fromCircle(center: c, radius: r);
    final angle = t * 2 * math.pi;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = SweepGradient(
            colors: [Colors.transparent, Kv.emerald.withValues(alpha: 0.0), Kv.emerald.withValues(alpha: 0.28)],
            stops: const [0, 0.75, 1],
          ).createShader(sweepRect));
    canvas.restore();

    // ring labels
    for (final (f, color) in rings) {
      final km = radiusKm * f;
      final label = km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1)} km';
      _text(canvas, label, c + Offset(r * f * 0.72, -r * f * 0.70), color, bg: bg);
    }

    // centre
    canvas.drawCircle(
        c,
        r * 0.17,
        Paint()
          ..shader = SweepGradient(colors: const [Kv.pink, Kv.purple, Kv.blue, Kv.emerald, Kv.pink])
              .createShader(Rect.fromCircle(center: c, radius: r * 0.17)));
    canvas.drawCircle(c, r * 0.15, Paint()..color = bg);
    _text(canvas, 'You', c, dark ? Colors.white : Kv.s900, size: 13);
    _text(canvas, label, c + Offset(0, r * 0.31), Kv.emeraldLight, size: 10.5, bg: bg);

    // providers
    for (final (p, color, online, name) in dots) {
      if (online) {
        final pulse = (t * 2) % 1;
        canvas.drawCircle(p, 8 + pulse * 10, Paint()..color = color.withValues(alpha: (1 - pulse) * 0.35));
      }
      canvas.drawCircle(p, 8, Paint()..color = online ? color : Kv.s500);
      canvas.drawCircle(
          p,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = bg);
      _text(canvas, name, p + const Offset(0, 16), dark ? Kv.s200 : Kv.s700, size: 9.5);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}

/// Simplified street map (no map SDK / API key needed): Kigali-like grid,
/// your position, the search radius and provider pins by real coordinates.
class StreetMap extends StatelessWidget {
  const StreetMap({super.key, required this.center, required this.radiusKm, required this.workers, required this.onTap, required this.label});
  final LatLng center;
  final double radiusKm;
  final List<Worker> workers;
  final ValueChanged<Worker> onTap;
  final String label;

  Offset _pos(double lat, double lng, Size size) {
    final kmPerPx = (radiusKm * 2.4) / size.width;
    final dx = (lng - center.lng) * 111.32 * math.cos(center.lat * math.pi / 180) / kmPerPx;
    final dy = -(lat - center.lat) * 110.57 / kmPerPx;
    return size.center(Offset.zero) + Offset(dx, dy);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxWidth);
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            CustomPaint(size: size, painter: _MapPainter(dark: dark, radiusPx: radiusKm / ((radiusKm * 2.4) / size.width), seed: (center.lat * 1000).round())),
            for (final w in workers)
              if (w.lat != null && w.lng != null)
                Builder(builder: (_) {
                  final p = _pos(w.lat!, w.lng!, size);
                  if (p.dx < 0 || p.dy < 0 || p.dx > size.width || p.dy > size.height) return const SizedBox.shrink();
                  final color = w.online ? Kv.named(w.categoryColor) : Kv.s500;
                  return Positioned(
                    left: p.dx - 16,
                    top: p.dy - 34,
                    child: GestureDetector(
                      onTap: () => onTap(w),
                      child: Column(children: [
                        Icon(Icons.location_on_rounded, color: color, size: 32),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: dark ? Kv.s900 : Colors.white, borderRadius: BorderRadius.circular(5)),
                          child: Text(w.name.split(' ').first, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: color)),
                        ),
                      ]),
                    ),
                  );
                }),
            Positioned(
              left: size.width / 2 - 13,
              top: size.height / 2 - 13,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Kv.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [BoxShadow(color: Kv.blue.withValues(alpha: 0.5), blurRadius: 14)],
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: dark ? Kv.s900 : Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Text('📍 $label', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Kv.emerald)),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.dark, required this.radiusPx, required this.seed});
  final bool dark;
  final double radiusPx;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF0B1426) : const Color(0xFFE8EEF3));
    final rnd = math.Random(seed);
    // green areas
    for (var i = 0; i < 6; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height, 40 + rnd.nextDouble() * 70, 30 + rnd.nextDouble() * 60),
            const Radius.circular(18)),
        Paint()..color = (dark ? const Color(0xFF0F2A22) : const Color(0xFFCFE8D6)),
      );
    }
    final minor = Paint()
      ..color = dark ? const Color(0xFF1A2740) : Colors.white
      ..strokeWidth = 5;
    for (var x = 18.0; x < size.width; x += 34 + rnd.nextDouble() * 20) {
      canvas.drawLine(Offset(x, 0), Offset(x + rnd.nextDouble() * 30 - 15, size.height), minor);
    }
    for (var y = 18.0; y < size.height; y += 34 + rnd.nextDouble() * 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + rnd.nextDouble() * 30 - 15), minor);
    }
    final major = Paint()
      ..color = dark ? const Color(0xFF3A3420) : const Color(0xFFFFE8A3)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * 0.62)
      ..quadraticBezierTo(size.width * 0.45, size.height * 0.48, size.width, size.height * 0.30);
    canvas.drawPath(path, major..style = PaintingStyle.stroke);
    final path2 = Path()
      ..moveTo(size.width * 0.30, 0)
      ..quadraticBezierTo(size.width * 0.52, size.height * 0.55, size.width * 0.42, size.height);
    canvas.drawPath(path2, major);
    // radius
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, radiusPx, Paint()..color = Kv.emerald.withValues(alpha: 0.08));
    canvas.drawCircle(
        c,
        radiusPx,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Kv.emerald.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.dark != dark || old.radiusPx != radiusPx || old.seed != seed;
}
