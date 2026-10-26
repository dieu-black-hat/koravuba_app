import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/models.dart';
import '../../data/notify.dart';
import '../../data/org_repo.dart';
import '../../widgets/common.dart';
import '../../widgets/role_shell.dart';
import '../client/activities.dart';
import '../shared/booking_detail.dart';
import '../shared/call.dart';
import '../shared/notifications.dart';
import '../shared/profile.dart';

class CompanyShell extends StatelessWidget {
  const CompanyShell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final userId = s.user!.id;
    final entityId = s.entityId!;
    return RoleShell(
      accent: Kv.blue,
      roleLabel: 'COMPANY',
      tabs: [
        const ShellTab(icon: Icons.space_dashboard_outlined, label: 'Overview', page: CompanyOverview()),
        ShellTab(
          icon: Icons.groups_outlined,
          label: 'Workers',
          page: const CompanyWorkers(),
          badge: () async => (await CompanyRepo.stats(entityId))['pending'].toInt(),
        ),
        ShellTab(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          page: const NotificationsPage(accent: Kv.blue),
          badge: () => Notify.unread(userId),
        ),
        ShellTab(
          icon: Icons.receipt_long_outlined,
          label: 'Bookings',
          page: ActivitiesPage(viewer: Viewer.company, accent: Kv.blue, loader: () => BookingRepo.forEntity(entityId)),
        ),
        ShellTab(
          icon: Icons.apartment_rounded,
          label: 'Company',
          page: ProfilePage(accent: Kv.blue, roleTag: 'COMPANY ADMIN', extra: [_CompanyCard(entityId: entityId)]),
        ),
      ],
    );
  }
}

class _Overview {
  _Overview(this.company, this.stats, this.recent);
  final Company company;
  final Stats stats;
  final List<Booking> recent;
}

class CompanyOverview extends StatelessWidget {
  const CompanyOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final entityId = context.session.entityId!;
    final kv = context.kv;
    return DataView<_Overview>(
      load: () async => _Overview(
        (await CompanyRepo.company(entityId))!,
        await CompanyRepo.stats(entityId),
        (await BookingRepo.forEntity(entityId)).take(5).toList(),
      ),
      builder: (context, d, reload) {
        final c = d.company;
        final st = d.stats;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              KvCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [fade(Kv.blue, kv.isDark ? 0.28 : 0.14), kv.card],
                ),
                borderColor: fade(Kv.blue, 0.45),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kv.text)),
                  const SizedBox(height: 4),
                  Text(c.address, style: TextStyle(color: kv.muted, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: c.code));
                        showSnack(context, 'Company ID copied — share it with your workers');
                      },
                      child: MonoTag('ID: ${c.code}', color: Kv.blueLight, icon: Icons.copy_rounded),
                    ),
                    StatusChip(c.status),
                    MonoTag('TIN ${c.tin}', color: kv.muted, size: 10),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              StatGrid(children: [
                StatTile(label: 'Verified workers', value: '${st['workers']}', color: Kv.blueLight, foot: '${st['online']} online now', icon: Icons.groups_rounded),
                StatTile(label: 'Active jobs', value: '${st['active']}', color: Kv.amberLight, foot: '${st['bookings']} bookings total', icon: Icons.bolt_rounded),
                StatTile(label: 'Gross revenue', value: Fmt.compact(st['gross']), unit: 'RWF', color: Kv.emerald, foot: '${st['completed']} completed jobs'),
                StatTile(label: 'Net payout (91%)', value: Fmt.compact(st['net']), unit: 'RWF', color: Kv.emeraldLight, foot: 'Paid out: ${Fmt.compact(st['paid_out'])} RWF'),
              ]),
              const SizedBox(height: 14),
              if (st['pending'] > 0)
                KvCard(
                  borderColor: fade(Kv.amber, 0.5),
                  onTap: () => context.findAncestorStateOfType<RoleShellState>()?.go(1),
                  child: Row(children: [
                    const Icon(Icons.how_to_reg_rounded, color: Kv.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${st['pending']} worker application${st['pending'] == 1 ? '' : 's'} waiting for your approval',
                          style: TextStyle(fontWeight: FontWeight.w800, color: kv.text)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: kv.muted),
                  ]),
                ),
              const SizedBox(height: 14),
              KvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Daily 19:00 payout', icon: Icons.account_balance_rounded, color: Kv.emerald),
                  const SizedBox(height: 10),
                  InfoRow('Platform fee', '9% retained by KoraVuba HQ'),
                  InfoRow('Your share', '91% of every completed job'),
                  InfoRow('Payout account', c.payout.isEmpty ? '—' : c.payout, mono: true),
                  InfoRow('Average worker rating', (st['rating']).toStringAsFixed(2), mono: true, valueColor: Kv.amberLight),
                ]),
              ),
              const SizedBox(height: 14),
              const SectionTitle('Latest bookings', icon: Icons.receipt_long_outlined, color: Kv.blue),
              const SizedBox(height: 10),
              if (d.recent.isEmpty)
                const EmptyState(icon: Icons.inbox_outlined, title: 'No bookings yet', message: 'Bookings for your workers appear here.'),
              for (final b in d.recent)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: BookingCard(booking: b, viewer: Viewer.company, accent: Kv.blue)),
            ],
          ),
        );
      },
    );
  }
}

class _WorkersData {
  _WorkersData(this.workers, this.apps);
  final List<Worker> workers;
  final List<Application> apps;
}

class CompanyWorkers extends StatefulWidget {
  const CompanyWorkers({super.key});

  @override
  State<CompanyWorkers> createState() => _CompanyWorkersState();
}

class _CompanyWorkersState extends State<CompanyWorkers> {
  bool _apps = false;

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final entityId = s.entityId!;
    final kv = context.kv;
    return DataView<_WorkersData>(
      load: () async => _WorkersData(await CompanyRepo.workers(entityId), await CompanyRepo.applications(entityId)),
      builder: (context, d, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Row(children: [
              Expanded(
                child: ChoiceChip(
                  label: Center(child: Text('Team (${d.workers.length})')),
                  selected: !_apps,
                  onSelected: (_) => setState(() => _apps = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: Center(child: Text('Applications (${d.apps.length})')),
                  selected: _apps,
                  onSelected: (_) => setState(() => _apps = true),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            if (!_apps) ...[
              if (d.workers.isEmpty)
                const EmptyState(
                  icon: Icons.group_add_outlined,
                  title: 'No workers yet',
                  message: 'Share your Company ID. Workers register in the app with it and appear in Applications.',
                ),
              for (final w in d.workers) _WorkerRow(worker: w),
            ] else ...[
              if (d.apps.isEmpty)
                const EmptyState(icon: Icons.how_to_reg_outlined, title: 'No pending applications', message: 'New worker sign-ups appear here.'),
              for (final a in d.apps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KvCard(
                    borderColor: fade(Kv.amber, 0.45),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Avatar(name: a.name, color: Kv.amber),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.name, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
                            Text(a.services, style: TextStyle(fontSize: 12.5, color: kv.muted)),
                          ]),
                        ),
                        Text(Fmt.ago(a.submittedAt), style: TextStyle(fontSize: 11, color: kv.faint)),
                      ]),
                      const SizedBox(height: 8),
                      InfoRow('Phone', Fmt.phone(a.phone), mono: true),
                      if (a.documentNumber.isNotEmpty) InfoRow('National ID', a.documentNumber, mono: true),
                      InfoRow('Rate', Fmt.money(a.price), mono: true),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: KvButton(
                            label: 'Reject',
                            color: Kv.red,
                            outlined: true,
                            height: 44,
                            onPressed: () async {
                              final r = await promptText(context, 'Reject ${a.name}?', hint: 'Reason (sent to the applicant)', ok: 'Reject');
                              if (r == null) return;
                              await CompanyRepo.reject(a, s.user!.id, r);
                              s.changed();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: KvButton(
                            label: 'Approve badge',
                            icon: Icons.verified_rounded,
                            color: Kv.blue,
                            height: 44,
                            onPressed: () async {
                              await CompanyRepo.approve(a, s.user!.id);
                              s.changed();
                              if (context.mounted) showSnack(context, '${a.name} approved — they can sign in now');
                            },
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({required this.worker});
  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final w = worker;
    final suspended = w.status == 'suspended';
    final s = context.session;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KvCard(
        padding: const EdgeInsets.all(14),
        borderColor: suspended ? fade(Kv.red, 0.4) : null,
        child: Column(children: [
          Row(children: [
            Avatar(name: w.name, path: w.photo, color: Kv.named(w.categoryColor), online: w.online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.name, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
                Text(w.serviceName, style: TextStyle(fontSize: 12, color: kv.muted)),
                const SizedBox(height: 3),
                Row(children: [
                  Text(w.badgeId, style: const TextStyle(fontFamily: Kv.mono, fontSize: 11, color: Kv.amberLight)),
                  const SizedBox(width: 8),
                  RatingStars(w.rating, size: 11),
                ]),
              ]),
            ),
            if (suspended) const Pill('Muted', color: Kv.red) else Pill(w.online ? 'Online' : 'Offline', color: w.online ? Kv.emerald : Kv.s400),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'mute':
                    if (!await confirm(context, 'Mute ${w.name}?', 'The worker goes offline and stops receiving dispatches.', ok: 'Mute', danger: true)) {
                      return;
                    }
                    await CompanyRepo.setWorkerSuspended(w, true);
                  case 'unmute':
                    await CompanyRepo.setWorkerSuspended(w, false);
                  case 'rate':
                    final r = await promptText(context, 'Rate for ${w.name} (RWF)', initial: w.price.round().toString(), ok: 'Save');
                    final v = double.tryParse(r ?? '');
                    if (v == null || w.serviceId == null) return;
                    await CompanyRepo.setServicePrice(w.serviceId!, v);
                  case 'call':
                    if (context.mounted) await callPhone(context, w.phone);
                    return;
                }
                s.changed();
              },
              itemBuilder: (_) => [
                if (suspended)
                  const PopupMenuItem(value: 'unmute', child: Text('Reactivate badge'))
                else
                  const PopupMenuItem(value: 'mute', child: Text('Mute / suspend')),
                const PopupMenuItem(value: 'rate', child: Text('Edit rate')),
                const PopupMenuItem(value: 'call', child: Text('Call worker')),
              ],
            ),
          ]),
          const Divider(height: 20),
          Row(children: [
            Expanded(child: _mini(kv, 'Jobs', '${w.jobs}')),
            Expanded(child: _mini(kv, 'Earned', Fmt.compact(w.earnings))),
            Expanded(child: _mini(kv, 'Rate', Fmt.compact(w.price))),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(KvColors kv, String label, String value) => Column(children: [
        Text(value, style: TextStyle(fontFamily: Kv.mono, fontWeight: FontWeight.w900, color: kv.text)),
        Text(label, style: TextStyle(fontSize: 11, color: kv.muted)),
      ]);
}

class _CompanyCard extends StatefulWidget {
  const _CompanyCard({required this.entityId});
  final String entityId;

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  Future<void> _edit(Company c) async {
    final phone = TextEditingController(text: c.phone);
    final email = TextEditingController(text: c.email);
    final address = TextEditingController(text: c.address);
    final payout = TextEditingController(text: c.payout);
    final desc = TextEditingController(text: c.description);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Company details', icon: Icons.apartment_rounded, color: Kv.blue),
            const SizedBox(height: 14),
            KvField(label: 'Official phone', controller: phone, accent: Kv.blue, keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            KvField(label: 'Official e-mail', controller: email, accent: Kv.blue, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 10),
            KvField(label: 'Physical address', controller: address, accent: Kv.blue),
            const SizedBox(height: 10),
            KvField(label: 'Payout account', controller: payout, accent: Kv.blue, mono: true),
            const SizedBox(height: 10),
            KvField(label: 'Description', controller: desc, accent: Kv.blue, maxLines: 3),
            const SizedBox(height: 16),
            KvButton(label: 'Save', color: Kv.blue, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await CompanyRepo.updateCompany(c.id,
        phone: phone.text, email: email.text, address: address.text, payout: payout.text, description: desc.text);
    if (mounted) {
      context.session.changed();
      showSnack(context, 'Company details saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DataView<Company?>(
        load: () => CompanyRepo.company(widget.entityId),
        builder: (context, c, _) {
          if (c == null) return const SizedBox.shrink();
          return KvCard(
            borderColor: fade(Kv.blue, 0.45),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle(c.name,
                  icon: Icons.apartment_rounded,
                  color: Kv.blue,
                  trailing: IconButton(onPressed: () => _edit(c), icon: Icon(Icons.edit_outlined, color: kv.muted))),
              const SizedBox(height: 10),
              InfoRow('Company ID', c.code, mono: true, valueColor: Kv.blueLight),
              InfoRow('Status', Fmt.title(c.status), valueColor: c.isActive ? Kv.emerald : Kv.amber),
              InfoRow('TIN', c.tin, mono: true),
              InfoRow('RDB registration', c.rdb, mono: true),
              InfoRow('Phone', c.phone, mono: true),
              InfoRow('E-mail', c.email),
              InfoRow('Address', c.address),
              InfoRow('Payout account', c.payout, mono: true),
              InfoRow('Subscription', '${Fmt.title(c.subscription)} • until ${Fmt.date(c.subscriptionEnd)}'),
            ]),
          );
        },
      ),
    );
  }
}
