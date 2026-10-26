import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';

extension SessionContext on BuildContext {
  Session get session => read<Session>();
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

// ------------------------------------------------------------------ brand
class KvLogo extends StatelessWidget {
  const KvLogo({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [BoxShadow(color: fade(Kv.brand, 0.35), blurRadius: size * 0.3, offset: Offset(0, size * 0.08))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
      ),
    );
  }
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22, this.suffix});
  final double size;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Kora', style: TextStyle(fontWeight: FontWeight.w900, color: context.kv.text)),
        const TextSpan(text: 'Vuba', style: TextStyle(fontWeight: FontWeight.w900, color: Kv.brandLight)),
        if (suffix != null) TextSpan(text: ' $suffix', style: TextStyle(fontWeight: FontWeight.w800, color: context.kv.text)),
      ]),
      style: TextStyle(fontSize: size, letterSpacing: -0.5),
    );
  }
}

// ------------------------------------------------------------------ cards
class KvCard extends StatelessWidget {
  const KvCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.gradient,
    this.onTap,
    this.radius = 24,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? kv.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? kv.border),
        boxShadow: kv.isDark ? null : [BoxShadow(color: fade(Kv.s900, 0.05), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return box;
  }
}

/// Monospace outlined tag ("5 km", "KV-CLEAN-00147", "Top Verified Staff").
class MonoTag extends StatelessWidget {
  const MonoTag(this.text, {super.key, this.color = Kv.emerald, this.size = 11, this.icon});
  final String text;
  final Color color;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fade(color, 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: fade(color, 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: size + 2, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: Kv.mono, fontSize: size, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Kv.emerald, this.icon, this.solid = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? color : fade(color, 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: solid ? Colors.white : color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: solid ? Colors.white : color)),
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  static (String, Color) info(String s) => switch (s) {
        'pending' => ('Pending', Kv.amber),
        'accepted' => ('En Route', Kv.blue),
        'in_progress' => ('In Progress', Kv.purple),
        'completed' => ('Completed', Kv.emerald),
        'cancelled_by_client' => ('Cancelled', Kv.red),
        'cancelled_by_provider' => ('Declined', Kv.red),
        'cancelled_by_admin' => ('Cancelled by HQ', Kv.red),
        'no_show' => ('No Show', Kv.red),
        'paid' => ('Paid', Kv.emerald),
        'processing' => ('Deposit Paid', Kv.blue),
        'refunded' => ('Refunded', Kv.s400),
        'failed' => ('Failed', Kv.red),
        'active' || 'approved' || 'verified' || 'resolved' => (Fmt.title(s), Kv.emerald),
        'suspended' || 'rejected' || 'dismissed' => (Fmt.title(s), Kv.red),
        'investigating' || 'escalated' || 'open' => (Fmt.title(s), Kv.amber),
        _ => (Fmt.title(s), Kv.s400),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = info(status);
    return Pill(label, color: color);
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.unit, this.color = Kv.emerald, this.foot, this.icon});
  final String label;
  final String value;
  final String? unit;
  final Color color;
  final String? foot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return KvCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 6)],
          Expanded(
            child: Text(label.toUpperCase(),
                maxLines: 2,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: kv.muted)),
          ),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: value, style: TextStyle(fontFamily: Kv.mono, fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            if (unit != null) TextSpan(text: ' $unit', style: TextStyle(fontFamily: Kv.mono, fontSize: 12, color: kv.muted)),
          ])),
        ),
        if (foot != null) ...[
          const SizedBox(height: 6),
          Text(foot!, style: TextStyle(fontSize: 11.5, color: kv.muted)),
        ],
      ]),
    );
  }
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: children[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
        ]),
      ));
      if (i + 2 < children.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.icon, this.color = Kv.emerald, this.subtitle, this.trailing});
  final String title;
  final IconData? icon;
  final Color color;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: fade(color, 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kv.text)),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: TextStyle(fontSize: 12.5, color: kv.muted, height: 1.35)),
          ],
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

// ------------------------------------------------------------------ inputs
class KvButton extends StatelessWidget {
  const KvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Kv.emerald,
    this.textColor,
    this.icon,
    this.loading = false,
    this.outlined = false,
    this.expand = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color? textColor;
  final IconData? icon;
  final bool loading;
  final bool outlined;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? (outlined ? color : (color == Kv.amber || color == Kv.emerald ? Kv.s950 : Colors.white));
    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: fg)),
            ),
          ]);
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(Size(expand ? double.infinity : 0, height)),
      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 18)),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      backgroundColor: WidgetStateProperty.resolveWith(
          (s) => outlined ? fade(color, 0.08) : (s.contains(WidgetState.disabled) ? fade(color, 0.4) : color)),
      side: WidgetStateProperty.all(outlined ? BorderSide(color: fade(color, 0.6)) : BorderSide.none),
      elevation: WidgetStateProperty.all(0),
      overlayColor: WidgetStateProperty.all(fade(Colors.white, 0.08)),
    );
    return TextButton(onPressed: loading ? null : onPressed, style: style, child: child);
  }
}

class KvField extends StatelessWidget {
  const KvField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboard,
    this.validator,
    this.mono = false,
    this.suffix,
    this.maxLines = 1,
    this.trailingLabel,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.enabled = true,
    this.accent = Kv.emerald,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final bool mono;
  final Widget? suffix;
  final int maxLines;
  final Widget? trailingLabel;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kv.text))),
        if (trailingLabel != null) trailingLabel!,
      ]),
      const SizedBox(height: 7),
      TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        validator: validator,
        maxLines: maxLines,
        enabled: enabled,
        onChanged: onChanged,
        textCapitalization: textCapitalization,
        style: TextStyle(fontFamily: mono ? Kv.mono : null, color: mono ? accent : kv.text, fontWeight: mono ? FontWeight.w700 : null),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          suffixIcon: suffix,
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 1.4)),
        ),
      ),
    ]);
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.path = '', this.size = 44, this.color = Kv.emerald, this.online});
  final String name;
  final String path;
  final double size;
  final Color color;
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final file = path.isNotEmpty && !path.startsWith('http') && !path.contains('profile_images/') ? File(path) : null;
    final hasFile = file != null && file.existsSync();
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        color: fade(color, 0.15),
        border: Border.all(color: fade(color, 0.5)),
        image: hasFile ? DecorationImage(image: FileImage(file), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: hasFile
          ? null
          : Text(Fmt.initials(name), style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: size * 0.34)),
    );
    if (online == null) return circle;
    return Stack(clipBehavior: Clip.none, children: [
      circle,
      Positioned(
        right: -2,
        bottom: -2,
        child: Container(
          width: size * 0.3,
          height: size * 0.3,
          decoration: BoxDecoration(
            color: online! ? Kv.emerald : Kv.s500,
            shape: BoxShape.circle,
            border: Border.all(color: context.kv.card, width: 2),
          ),
        ),
      ),
    ]);
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 14, this.showValue = true});
  final double rating;
  final double size;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: size + 2, color: Kv.amberLight),
      if (showValue) ...[
        const SizedBox(width: 3),
        Text(rating <= 0 ? 'New' : rating.toStringAsFixed(rating == rating.roundToDouble() ? 1 : 2),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: context.kv.text)),
      ],
    ]);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return KvCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
      color: kv.isDark ? Kv.s950 : kv.card,
      child: Column(children: [
        Icon(icon, size: 46, color: kv.faint),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kv.text)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kv.muted, height: 1.4)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.mono = false, this.valueColor, this.bold = false});
  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(label, style: TextStyle(fontSize: 13, color: kv.muted))),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? Kv.mono : null,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                color: valueColor ?? kv.text,
              )),
        ),
      ]),
    );
  }
}

/// Loads data and reloads it whenever the session signals a change.
class DataView<T> extends StatefulWidget {
  const DataView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<DataView<T>> createState() => _DataViewState<T>();
}

class _DataViewState<T> extends State<DataView<T>> {
  T? _data;
  bool _has = false;
  Object? _error;
  int _rev = -1;

  Future<void> _load() async {
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _has = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rev = context.select<Session, int>((s) => s.revision);
    if (rev != _rev) {
      _rev = rev;
      Future.microtask(_load);
    }
    if (!_has) {
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Something went wrong',
              message: '$_error',
              action: KvButton(label: 'Try again', expand: false, onPressed: _load),
            ),
          ),
        );
      }
      return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
    }
    return widget.builder(context, _data as T, _load);
  }
}

// ------------------------------------------------------------------ dialogs
void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: error ? Kv.red : Kv.emeraldLight, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok, style: TextStyle(color: danger ? Kv.red : Kv.emerald, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title, {String hint = '', String ok = 'Save', String initial = '', int maxLines = 1}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      content: TextField(controller: ctl, autofocus: true, maxLines: maxLines, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

// ------------------------------------------------------------------ icons
IconData categoryIcon(String code) => switch (categoryType(code)) {
      'car_taxi' => Icons.local_taxi_rounded,
      'moto_taxi' => Icons.two_wheeler_rounded,
      'cleaner' => Icons.cleaning_services_rounded,
      'driver' => Icons.directions_car_filled_rounded,
      'plumber' => Icons.plumbing_rounded,
      'electrician' => Icons.electrical_services_rounded,
      'nanny' => Icons.child_friendly_rounded,
      'chef' => Icons.restaurant_rounded,
      'tutor' => Icons.school_rounded,
      'barber' => Icons.content_cut_rounded,
      _ => Icons.handyman_rounded,
    };

/// The kind of a category code: HQ-created categories get codes like `cleaner_2`.
String categoryType(String code) => code.replaceFirst(RegExp(r'_\d+$'), '');

/// Category kinds HQ can choose from (icon, badge prefix, transport or not).
const categoryTypes = <(String, String)>[
  ('car_taxi', 'Car taxi'),
  ('moto_taxi', 'Moto taxi'),
  ('driver', 'Driver / transport'),
  ('cleaner', 'Cleaning'),
  ('plumber', 'Plumbing'),
  ('electrician', 'Electrical'),
  ('nanny', 'Childcare'),
  ('chef', 'Cooking / catering'),
  ('tutor', 'Tutoring'),
  ('barber', 'Hair & beauty'),
  ('other', 'Other service'),
];
