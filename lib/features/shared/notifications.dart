import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/notify.dart';
import '../../widgets/common.dart';

/// "Account Notifications & Live Event Feed".
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.accent});
  final Color accent;

  static (IconData, Color) look(String type) => switch (type) {
        'new_booking' || 'booking_created' => (Icons.receipt_long_rounded, Kv.emerald),
        'booking_status' => (Icons.check_circle_outline_rounded, Kv.emerald),
        'booking_cancelled' => (Icons.cancel_outlined, Kv.red),
        'new_message' => (Icons.chat_bubble_outline_rounded, Kv.blue),
        'new_review' || 'review_response' => (Icons.star_outline_rounded, Kv.amber),
        'promo' => (Icons.auto_awesome_rounded, Kv.purple),
        'application' || 'application_approved' => (Icons.verified_user_outlined, Kv.blue),
        'application_rejected' => (Icons.block_rounded, Kv.red),
        'dispute_created' || 'dispute_update' || 'dispute_resolved' => (Icons.gavel_rounded, Kv.amber),
        _ => (Icons.notifications_none_rounded, Kv.emerald),
      };

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final user = s.user!;
    final kv = context.kv;
    return DataView<List<Notice>>(
      load: () => Notify.list(user.id),
      builder: (context, list, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            KvCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle('Account Notifications & Live Event Feed', icon: Icons.notifications_none_rounded, color: Kv.amber),
                const SizedBox(height: 8),
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'Real-time notifications for ', style: TextStyle(color: kv.muted)),
                  TextSpan(text: Fmt.phone(user.phone), style: TextStyle(color: accent, fontFamily: Kv.mono, fontWeight: FontWeight.w700)),
                  TextSpan(text: ' about dispatches, payments and progress.', style: TextStyle(color: kv.muted)),
                ]), style: const TextStyle(fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 12),
                Row(children: [
                  _SmallBtn(
                    icon: Icons.done_all_rounded,
                    label: 'Mark All Read',
                    color: kv.muted,
                    onTap: () async {
                      await Notify.markAllRead(user.id);
                      s.changed();
                    },
                  ),
                  const SizedBox(width: 8),
                  _SmallBtn(
                    icon: Icons.delete_outline_rounded,
                    label: 'Clear',
                    color: Kv.red,
                    onTap: () async {
                      if (!await confirm(context, 'Clear notifications?', 'All notifications will be removed.', ok: 'Clear', danger: true)) return;
                      await Notify.clearAll(user.id);
                      s.changed();
                    },
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const EmptyState(icon: Icons.notifications_off_outlined, title: 'All caught up', message: 'New events will appear here.'),
            for (final n in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KvCard(
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  borderColor: n.isRead ? null : fade(accent, 0.5),
                  onTap: n.isRead
                      ? null
                      : () async {
                          await Notify.markRead(n.id);
                          s.changed();
                        },
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Builder(builder: (_) {
                      final (icon, color) = look(n.type);
                      return Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: fade(color, 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: fade(color, 0.35)),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      );
                    }),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n.title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: kv.text)),
                        const SizedBox(height: 4),
                        Text(n.message, style: TextStyle(fontSize: 13, color: kv.muted, height: 1.4)),
                        const SizedBox(height: 6),
                        Text(Fmt.ago(n.createdAt), style: TextStyle(fontSize: 11, fontFamily: Kv.mono, color: kv.faint)),
                      ]),
                    ),
                    if (!n.isRead)
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kv.isDark ? Kv.s950 : Kv.s50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kv.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color == Kv.red ? Kv.red : kv.text)),
        ]),
      ),
    );
  }
}
