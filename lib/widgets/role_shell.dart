import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../core/theme.dart';
import 'common.dart';

class ShellTab {
  const ShellTab({required this.icon, required this.label, required this.page, this.badge});
  final IconData icon;
  final String label;
  final Widget page;

  /// Optional badge counter (reloaded on every data change).
  final Future<int> Function()? badge;
}

/// Role screen: header + the selected page + the floating icon navigation
/// bar at the bottom (no drawer / side bar).
class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.tabs, required this.accent, required this.roleLabel, this.headerAction});
  final List<ShellTab> tabs;
  final Color accent;
  final String roleLabel;
  final Widget? headerAction;

  @override
  State<RoleShell> createState() => RoleShellState();
}

class RoleShellState extends State<RoleShell> {
  int index = 0;
  List<int> _badges = [];
  int _rev = -1;
  Timer? _timer;

  void go(int i) => setState(() => index = i);

  @override
  void initState() {
    super.initState();
    _badges = List.filled(widget.tabs.length, 0);
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _loadBadges());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadBadges() async {
    final next = <int>[];
    for (final t in widget.tabs) {
      try {
        next.add(t.badge == null ? 0 : await t.badge!());
      } catch (_) {
        next.add(0);
      }
    }
    if (mounted) setState(() => _badges = next);
  }

  @override
  Widget build(BuildContext context) {
    final rev = context.select<Session, int>((s) => s.revision);
    if (rev != _rev) {
      _rev = rev;
      Future.microtask(_loadBadges);
    }
    final kv = context.kv;
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: kv.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kv.border),
                boxShadow: [BoxShadow(color: fade(Colors.black, kv.isDark ? 0.45 : 0.10), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < widget.tabs.length; i++)
                    _NavIcon(
                      tab: widget.tabs[i],
                      selected: i == index,
                      badge: i < _badges.length ? _badges[i] : 0,
                      accent: widget.accent,
                      badgeColor: i == 1 ? Kv.red : Kv.amber,
                      onTap: () => go(i),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 6),
              child: Row(children: [
                const KvLogo(size: 34),
                const SizedBox(width: 10),
                const Wordmark(size: 20),
                const SizedBox(width: 8),
                MonoTag(widget.roleLabel, color: widget.accent, size: 9.5),
                const Spacer(),
                if (widget.headerAction != null) widget.headerAction!,
                IconButton(
                  tooltip: 'Light / dark',
                  onPressed: () => context.read<Session>().toggleTheme(),
                  icon: Icon(kv.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: kv.muted),
                ),
              ]),
            ),
            Expanded(
              child: IndexedStack(index: index, children: [for (final t in widget.tabs) t.page]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.tab, required this.selected, required this.badge, required this.accent, required this.badgeColor, required this.onTap});
  final ShellTab tab;
  final bool selected;
  final int badge;
  final Color accent;
  final Color badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Tooltip(
      message: tab.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 46,
          height: 38,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected ? [BoxShadow(color: fade(accent, 0.35), blurRadius: 14)] : null,
          ),
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Icon(tab.icon, size: 22, color: selected ? (accent == Kv.emerald || accent == Kv.amber ? Kv.s950 : Colors.white) : kv.muted),
            if (badge > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(9)),
                  child: Text(badge > 99 ? '99+' : '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 60,
          child: Text(tab.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w900 : FontWeight.w600, color: selected ? accent : kv.muted)),
        ),
        ]),
      ),
    );
  }
}
