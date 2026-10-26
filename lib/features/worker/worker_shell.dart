import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/chat_repo.dart';
import '../../data/models.dart';
import '../../data/notify.dart';
import '../../data/worker_repo.dart';
import '../../widgets/common.dart';
import '../../widgets/role_shell.dart';
import '../client/activities.dart';
import '../shared/booking_detail.dart';
import '../shared/messages.dart';
import '../shared/notifications.dart';
import '../shared/profile.dart';

class WorkerShell extends StatelessWidget {
  const WorkerShell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final userId = s.user!.id;
    final profileId = s.profileId!;
    return RoleShell(
      accent: Kv.amber,
      roleLabel: 'WORKER',
      tabs: [
        ShellTab(
          icon: Icons.dashboard_outlined,
          label: 'Dispatch',
          page: const WorkerDashboard(),
          badge: () async => (await WorkerRepo.stats(profileId))['pending']?.toInt() ?? 0,
        ),
        ShellTab(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          page: const MessagesPage(accent: Kv.amber),
          badge: () => ChatRepo.unreadTotal(userId: userId, providerProfileId: profileId),
        ),
        ShellTab(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          page: const NotificationsPage(accent: Kv.amber),
          badge: () => Notify.unread(userId),
        ),
        ShellTab(
          icon: Icons.history_rounded,
          label: 'Job history',
          page: ActivitiesPage(viewer: Viewer.worker, accent: Kv.amber, loader: () => BookingRepo.forProvider(profileId)),
        ),
        ShellTab(
          icon: Icons.badge_outlined,
          label: 'Profile',
          page: ProfilePage(accent: Kv.amber, roleTag: 'VERIFIED WORKER', extra: [_ServiceCard(profileId: profileId)]),
        ),
      ],
    );
  }
}

class _DashData {
  _DashData(this.me, this.stats, this.bookings);
  final Worker me;
  final Map<String, num> stats;
  final List<Booking> bookings;
}

class WorkerDashboard extends StatelessWidget {
  const WorkerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final profileId = s.profileId!;
    final kv = context.kv;
    return DataView<_DashData>(
      load: () async => _DashData(
        (await WorkerRepo.me(profileId))!,
        await WorkerRepo.stats(profileId),
        await BookingRepo.forProvider(profileId),
      ),
      builder: (context, d, reload) {
        final w = d.me;
        final pending = d.bookings.where((b) => b.status == 'pending').toList();
        final active = d.bookings.where((b) => b.status == 'accepted' || b.status == 'in_progress').toList();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              KvCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [fade(Kv.amber, kv.isDark ? 0.22 : 0.14), kv.card],
                ),
                borderColor: fade(Kv.amber, 0.45),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Avatar(name: w.name, path: w.photo, color: Kv.amber, size: 56, online: w.online),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(w.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: kv.text)),
                        Text(w.serviceName, style: TextStyle(fontSize: 12.5, color: kv.muted)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          MonoTag(w.badgeId, color: Kv.amberLight),
                          MonoTag(w.companyName, color: Kv.blueLight, icon: Icons.verified_rounded),
                        ]),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: kv.isDark ? Kv.s950 : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: w.online ? fade(Kv.emerald, 0.6) : kv.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.circle, size: 12, color: w.online ? Kv.emerald : Kv.s500),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(w.online ? 'ONLINE — receiving dispatches' : 'OFFLINE',
                              style: TextStyle(fontWeight: FontWeight.w900, color: w.online ? Kv.emerald : kv.muted)),
                          Text(w.online ? 'Clients near you can see and book you' : 'Go online to appear on client radars',
                              style: TextStyle(fontSize: 11.5, color: kv.muted)),
                        ]),
                      ),
                      Switch(
                        value: w.online,
                        onChanged: (v) async {
                          await WorkerRepo.setOnline(profileId, v);
                          s.changed();
                        },
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              StatGrid(children: [
                StatTile(label: "Today's earnings", value: Fmt.compact(d.stats['today'] ?? 0), unit: 'RWF', color: Kv.amberLight),
                StatTile(label: 'Total earned', value: Fmt.compact(d.stats['earned'] ?? 0), unit: 'RWF', color: Kv.emerald),
                StatTile(label: 'Jobs completed', value: '${w.jobs}', color: Kv.blueLight),
                StatTile(label: 'Rating', value: w.rating <= 0 ? 'New' : w.rating.toStringAsFixed(2), unit: '★', color: Kv.amberLight, foot: '${w.reviews} reviews'),
              ]),
              const SizedBox(height: 16),
              SectionTitle('Active dispatches', icon: Icons.local_shipping_outlined, color: Kv.amber, trailing: MonoTag('${active.length}', color: Kv.amber)),
              const SizedBox(height: 10),
              if (active.isEmpty)
                const EmptyState(icon: Icons.inbox_outlined, title: 'No active job', message: 'Accepted jobs appear here with a live timer.'),
              for (final b in active)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: BookingCard(booking: b, viewer: Viewer.worker, accent: Kv.amber)),
              const SizedBox(height: 10),
              SectionTitle('Incoming requests', icon: Icons.notifications_active_outlined, color: Kv.amber, trailing: MonoTag('${pending.length}', color: Kv.amber)),
              const SizedBox(height: 10),
              if (pending.isEmpty)
                EmptyState(
                  icon: Icons.radar_rounded,
                  title: w.online ? 'Waiting for dispatches…' : 'You are offline',
                  message: w.online ? 'New bookings from clients appear here instantly.' : 'Switch online above to receive requests.',
                ),
              for (final b in pending) _RequestCard(booking: b),
            ],
          ),
        );
      },
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.booking});
  final Booking booking;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  Future<void> _set(String status) async {
    final s = context.session;
    var reason = '';
    if (status != 'accepted') {
      final r = await promptText(context, 'Decline reason', hint: 'Optional', ok: 'Decline');
      if (r == null) return;
      reason = r;
    }
    setState(() => _busy = true);
    await BookingRepo.setStatus(widget.booking, status, s.user!.id, reason: reason);
    s.changed();
    if (mounted) {
      setState(() => _busy = false);
      showSnack(context, status == 'accepted' ? 'Dispatch accepted — client notified' : 'Dispatch declined');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final kv = context.kv;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KvCard(
        borderColor: fade(Kv.amber, 0.5),
        padding: const EdgeInsets.all(14),
        onTap: () => push(context, BookingDetailScreen(bookingId: b.id, viewer: Viewer.worker, accent: Kv.amber)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bolt_rounded, color: Kv.amber),
            const SizedBox(width: 6),
            Expanded(child: Text('New dispatch • ${b.clientName}', style: TextStyle(fontWeight: FontWeight.w900, color: kv.text))),
            Text(Fmt.ago(b.createdAt), style: TextStyle(fontSize: 11, color: kv.faint)),
          ]),
          const SizedBox(height: 8),
          InfoRow('When', '${Fmt.dayDate(b.scheduledAt)} • ${Fmt.hhmm(b.scheduledTime)}'),
          InfoRow('Where', b.address),
          if (b.clientNotes.isNotEmpty) InfoRow('Notes', b.clientNotes),
          InfoRow('You earn', Fmt.money(b.providerEarnings), mono: true, valueColor: Kv.emerald, bold: true),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: KvButton(label: 'Decline', color: Kv.red, outlined: true, height: 44, loading: _busy, onPressed: () => _set('cancelled_by_provider')),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: KvButton(label: 'Accept', icon: Icons.check_rounded, color: Kv.amber, height: 44, loading: _busy, onPressed: () => _set('accepted')),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.profileId});
  final String profileId;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DataView<Worker?>(
        load: () => WorkerRepo.me(profileId),
        builder: (context, w, reload) {
          if (w == null) return const SizedBox.shrink();
          return KvCard(
            borderColor: fade(Kv.amber, 0.4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('My KoraVuba Badge', icon: Icons.badge_rounded, color: Kv.amber),
              const SizedBox(height: 12),
              InfoRow('Badge ID', w.badgeId, mono: true, valueColor: Kv.amberLight),
              InfoRow('Company', w.companyName),
              if (w.companyCode.isNotEmpty) InfoRow('Company ID', w.companyCode, mono: true),
              InfoRow('Service', w.serviceName),
              InfoRow('Rate', '${Fmt.money(w.price)} ${w.priceUnit}', mono: true),
              InfoRow('Status', Fmt.title(w.status), valueColor: Kv.emerald),
              const SizedBox(height: 6),
              Text('Your rate is set by your company. Contact your supervisor to change it.', style: TextStyle(fontSize: 11.5, color: kv.faint)),
            ]),
          );
        },
      ),
    );
  }
}
