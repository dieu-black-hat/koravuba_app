import 'dart:math' as math;

/// Formatting helpers (RWF money, dates, relative times).
class Fmt {
  Fmt._();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String number(num v, {int decimals = 0}) {
    final neg = v < 0;
    final fixed = v.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final digits = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    final dec = parts.length > 1 ? '.${parts[1]}' : '';
    return '${neg ? '-' : ''}$buf$dec';
  }

  static String money(num v) => '${number(v.round())} RWF';

  static String compact(num v) {
    final a = v.abs();
    if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)}M';
    if (a >= 1000) return '${(v / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}k';
    return number(v);
  }

  static String two(int v) => v.toString().padLeft(2, '0');

  static String date(DateTime? d) {
    if (d == null) return '—';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  static String dayDate(DateTime? d) {
    if (d == null) return '—';
    return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
  }

  static String time(DateTime? d) {
    if (d == null) return '—';
    return '${two(d.hour)}:${two(d.minute)}';
  }

  static String dateTime(DateTime? d) => d == null ? '—' : '${date(d)} • ${time(d)}';

  static String hhmm(String? t) {
    if (t == null || t.isEmpty) return '—';
    final p = t.split(':');
    return p.length >= 2 ? '${two(int.tryParse(p[0]) ?? 0)}:${two(int.tryParse(p[1]) ?? 0)}' : t;
  }

  static String ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    return date(d);
  }

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  static String km(double v) => v < 1 ? '${(v * 1000).round()} m' : '${v.toStringAsFixed(1)} km';

  /// Rwanda phone number to `+250 788 123 456`.
  static String phone(String? raw) {
    final d = digits(raw);
    if (d.length >= 9) {
      final local = d.substring(d.length - 9);
      return '+250 ${local.substring(0, 3)} ${local.substring(3, 6)} ${local.substring(6)}';
    }
    return raw ?? '';
  }

  static String digits(String? raw) => (raw ?? '').replaceAll(RegExp(r'\D'), '');

  /// The last 9 digits — how phones are compared (0788…, +250788…, 250788…).
  static String phoneKey(String? raw) {
    final d = digits(raw);
    return d.length >= 9 ? d.substring(d.length - 9) : d;
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String title(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
