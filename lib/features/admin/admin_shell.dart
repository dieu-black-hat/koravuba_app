import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/catalog_repo.dart';
import '../../data/models.dart';
import '../../data/org_repo.dart';
import '../../widgets/common.dart';
import '../../widgets/role_shell.dart';
import '../client/activities.dart';
import '../shared/booking_detail.dart';
import '../shared/call.dart';
import '../shared/profile.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      accent: Kv.purple,
      roleLabel: 'HQ ADMIN',
      tabs: [
        ShellTab(
          icon: Icons.insights_rounded,
          label: 'HQ Overview',
          page: const AdminOverview(),
          badge: () async {
            final s = await AdminRepo.stats();
            return (s['companies_pending'] + s['sos']).toInt();
          },
        ),
        const ShellTab(icon: Icons.apartment_rounded, label: 'Companies', page: AdminCompanies()),
        const ShellTab(icon: Icons.badge_outlined, label: 'Workers', page: AdminWorkers()),
        const ShellTab(icon: Icons.receipt_long_rounded, label: 'Ledger', page: AdminLedger()),
        const ShellTab(icon: Icons.settings_outlined, label: 'Control', page: AdminControl()),
      ],
    );
  }
}

// ======================================================================= overview
class _Ov {
  _Ov(this.stats, this.pending, this.sos, this.settings);
  final Stats stats;
  final List<Company> pending;
  final List<SosAlert> sos;
  final Map<String, String> settings;
}

class AdminOverview extends StatefulWidget {
  const AdminOverview({super.key});

  @override
  State<AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<AdminOverview> {
  bool _paying = false;

  Future<void> _payout() async {
    final s = context.session;
    setState(() => _paying = true);
    final (count, total) = await AdminRepo.runPayout(s.user!.id);
    s.changed();
    if (!mounted) return;
    setState(() => _paying = false);
    showSnack(context, count == 0 ? 'Nothing to pay out — no fully-paid completed jobs pending.' : 'Paid out ${Fmt.money(total)} for $count jobs');
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return DataView<_Ov>(
      load: () async => _Ov(
        await AdminRepo.stats(),
        (await AdminRepo.companies()).where((c) => c.status == 'pending' || c.status == 'draft').toList(),
        (await AdminRepo.sosAlerts()).where((a) => a.status == 'open').toList(),
        await AdminRepo.settings(),
      ),
      builder: (context, d, reload) {
        final st = d.stats;
        final fee = d.settings['platform_commission_percent'] ?? '9';
        final net = 100 - (double.tryParse(fee) ?? 9);
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              KvCard(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [fade(Kv.purple, kv.isDark ? 0.35 : 0.16), kv.card],
                ),
                borderColor: fade(Kv.purple, 0.5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Wordmark(size: 24, suffix: 'Executive HQ'),
                  const SizedBox(height: 6),
                  Text('Master B2B2C overseer • Company license verification & revenue distribution control',
                      style: TextStyle(color: kv.muted, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  const Wrap(spacing: 6, runSpacing: 6, children: [
                    MonoTag('● OVERSEER ACTIVE', color: Kv.emerald, size: 10),
                    MonoTag('SECURE GATEWAY', color: Kv.purpleLight, size: 10, icon: Icons.lock_outline_rounded),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              if (d.sos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: KvCard(
                    borderColor: Kv.red,
                    color: fade(Kv.red, 0.08),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SectionTitle('${d.sos.length} open SOS alert${d.sos.length == 1 ? '' : 's'}', icon: Icons.sos_rounded, color: Kv.red),
                      const SizedBox(height: 10),
                      for (final a in d.sos)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${a.raisedBy} • ${a.bookingNumber}', style: TextStyle(fontWeight: FontWeight.w800, color: kv.text, fontSize: 13)),
                                Text(a.message, style: TextStyle(color: kv.muted, fontSize: 12.5)),
                                Text(Fmt.ago(a.createdAt), style: TextStyle(color: kv.faint, fontSize: 11)),
                              ]),
                            ),
                            IconButton(onPressed: () => callPhone(context, a.phone), icon: const Icon(Icons.call_rounded, color: Kv.red)),
                            TextButton(
                              onPressed: () async {
                                await AdminRepo.resolveSos(a.id);
                                if (context.mounted) context.session.changed();
                              },
                              child: const Text('Resolve'),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
              StatGrid(children: [
                StatTile(label: 'Total network GMV', value: Fmt.compact(st['gmv']), unit: 'RWF', color: Kv.emerald, foot: '${st['completed']} completed dispatches'),
                StatTile(label: 'KoraVuba $fee% platform fee', value: Fmt.compact(st['fees']), unit: 'RWF', color: Kv.purpleLight, foot: 'Retained automatically per dispatch'),
                StatTile(label: 'Company net pool (${net.round()}%)', value: Fmt.compact(st['net']), unit: 'RWF', color: Kv.emeraldLight, foot: 'Due now: ${Fmt.compact(st['payout_due'])} RWF'),
                StatTile(label: 'Verified companies', value: '${st['companies']}/${st['companies_all']}', unit: 'Active', color: Kv.blueLight, foot: '${Fmt.compact(st['subscriptions'])} RWF monthly subscriptions'),
                StatTile(label: 'Verified workers', value: '${st['workers']}', color: Kv.amberLight, foot: '${st['online']} online • ${st['workers_pending']} pending'),
                StatTile(label: 'Clients', value: '${st['clients']}', color: kv.text, foot: '${st['users']} users • ${st['active']} live jobs'),
              ]),
              const SizedBox(height: 14),
              KvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionTitle('Pending Approval Queue',
                      icon: Icons.warning_amber_rounded,
                      color: Kv.amber,
                      trailing: MonoTag('${d.pending.length} companies', color: kv.muted, size: 10)),
                  const SizedBox(height: 12),
                  if (d.pending.isEmpty)
                    const EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'All Clear! No Pending Requests',
                      message: 'All registered companies are active and verified.',
                    ),
                  for (final c in d.pending) _CompanyTile(company: c),
                ]),
              ),
              const SizedBox(height: 14),
              KvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Daily 19:00 Company Payout Engine',
                      icon: Icons.payments_outlined, color: Kv.emerald, trailing: MonoTag('19:00 CAT', size: 10)),
                  const SizedBox(height: 12),
                  _split(kv, '$fee%', 'Platform revenue cut', 'Retained by KoraVuba HQ', Fmt.money(st['fees']), Kv.purpleLight),
                  const SizedBox(height: 8),
                  _split(kv, '${net.round()}%', 'Company net share', 'Bank / MoMo transfer to companies', Fmt.money(st['payout_due']), Kv.emerald),
                  const SizedBox(height: 14),
                  KvButton(label: 'Trigger 19:00 Batch Payout Now', icon: Icons.sync_rounded, loading: _paying, onPressed: _payout),
                ]),
              ),
              const SizedBox(height: 14),
              KvCard(
                onTap: () => push(context, const _DisputesScreen()),
                child: Row(children: [
                  const Icon(Icons.gavel_rounded, color: Kv.amber),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Disputes (${st['disputes']} open)', style: TextStyle(fontWeight: FontWeight.w800, color: kv.text))),
                  Icon(Icons.chevron_right_rounded, color: kv.muted),
                ]),
              ),
              const SizedBox(height: 10),
              KvCard(
                onTap: () => push(
                    context,
                    Scaffold(
                      appBar: AppBar(title: const Text('All bookings')),
                      body: ActivitiesPage(viewer: Viewer.admin, accent: Kv.purple, loader: () => BookingRepo.all()),
                    )),
                child: Row(children: [
                  const Icon(Icons.receipt_long_rounded, color: Kv.purpleLight),
                  const SizedBox(width: 12),
                  Expanded(child: Text('All bookings (${st['bookings']})', style: TextStyle(fontWeight: FontWeight.w800, color: kv.text))),
                  Icon(Icons.chevron_right_rounded, color: kv.muted),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _split(KvColors kv, String pct, String title, String sub, String value, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kv.isDark ? Kv.s950 : Kv.s50, borderRadius: BorderRadius.circular(16), border: Border.all(color: kv.border)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: fade(color, 0.14), borderRadius: BorderRadius.circular(10)),
            child: Text(pct, style: TextStyle(fontFamily: Kv.mono, fontWeight: FontWeight.w900, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: kv.text, fontSize: 13)),
              Text(sub, style: TextStyle(color: kv.muted, fontSize: 11.5)),
            ]),
          ),
          Text(value, style: TextStyle(fontFamily: Kv.mono, fontWeight: FontWeight.w900, color: color, fontSize: 12.5)),
        ]),
      );
}

// ======================================================================= companies
class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company});
  final Company company;

  Future<void> _act(BuildContext context, String action) async {
    final s = context.session;
    final c = company;
    switch (action) {
      case 'approve':
        final code = await AdminRepo.approveCompany(c, s.user!.id);
        if (context.mounted) showSnack(context, '${c.name} approved • Company ID $code');
      case 'reject':
        final r = await promptText(context, 'Reject ${c.name}?', hint: 'Reason (sent to the company)', ok: 'Reject');
        if (r == null) return;
        await AdminRepo.setCompanyStatus(c, 'rejected', reason: r);
      case 'suspend':
        if (!context.mounted || !await confirm(context, 'Suspend ${c.name}?', 'All its workers go offline.', ok: 'Suspend', danger: true)) return;
        await AdminRepo.setCompanyStatus(c, 'suspended');
      case 'reactivate':
        await AdminRepo.setCompanyStatus(c, 'active');
    }
    s.changed();
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final c = company;
    final pending = c.status == 'pending' || c.status == 'draft';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KvCard(
        padding: const EdgeInsets.all(14),
        color: kv.isDark ? Kv.s950 : kv.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: fade(Kv.blue, 0.14), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.apartment_rounded, color: Kv.blueLight, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
                Text(c.code.isEmpty ? 'No Company ID yet' : c.code, style: TextStyle(fontFamily: Kv.mono, fontSize: 11, color: kv.muted)),
              ]),
            ),
            StatusChip(c.status),
          ]),
          const SizedBox(height: 8),
          InfoRow('TIN / RDB', '${c.tin} • ${c.rdb}', mono: true),
          InfoRow('Contact', '${c.phone} • ${c.email}'),
          InfoRow('Workers', '${c.workers}'),
          const SizedBox(height: 8),
          if (pending)
            Row(children: [
              Expanded(child: KvButton(label: 'Reject', color: Kv.red, outlined: true, height: 42, onPressed: () => _act(context, 'reject'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: KvButton(label: 'Verify & approve', icon: Icons.verified_rounded, color: Kv.purple, height: 42, onPressed: () => _act(context, 'approve')),
              ),
            ])
          else if (c.status == 'suspended' || c.status == 'rejected')
            KvButton(label: 'Reactivate', color: Kv.emerald, outlined: true, height: 42, onPressed: () => _act(context, 'reactivate'))
          else
            KvButton(label: 'Suspend company', color: Kv.red, outlined: true, height: 42, onPressed: () => _act(context, 'suspend')),
        ]),
      ),
    );
  }
}

class AdminCompanies extends StatelessWidget {
  const AdminCompanies({super.key});

  @override
  Widget build(BuildContext context) {
    return DataView<List<Company>>(
      load: AdminRepo.companies,
      builder: (context, list, reload) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            SectionTitle('Company Registrations', icon: Icons.apartment_rounded, color: Kv.blue, subtitle: '${list.length} companies on KoraVuba'),
            const SizedBox(height: 12),
            if (list.isEmpty) const EmptyState(icon: Icons.apartment_rounded, title: 'No companies', message: 'Companies register from the login screen.'),
            for (final c in list) _CompanyTile(company: c),
          ],
        ),
      ),
    );
  }
}

// ======================================================================= workers
class AdminWorkers extends StatefulWidget {
  const AdminWorkers({super.key});

  @override
  State<AdminWorkers> createState() => _AdminWorkersState();
}

class _AdminWorkersState extends State<AdminWorkers> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final s = context.session;
    return DataView<List<Worker>>(
      load: AdminRepo.workers,
      builder: (context, all, reload) {
        final q = _q.toLowerCase();
        final list = all
            .where((w) => q.isEmpty || [w.name, w.badgeId, w.companyName, w.serviceName, w.phone].any((f) => f.toLowerCase().contains(q)))
            .toList();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              SectionTitle('Worker Badges', icon: Icons.badge_outlined, color: Kv.amber, subtitle: '${all.length} providers in the database'),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name, badge, company…'),
              ),
              const SizedBox(height: 12),
              for (final w in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KvCard(
                    padding: const EdgeInsets.all(12),
                    radius: 18,
                    child: Row(children: [
                      Avatar(name: w.name, path: w.photo, color: Kv.named(w.categoryColor), online: w.online, size: 42),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(w.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
                          Text('${w.badgeId} • ${w.companyName}',
                              overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: Kv.mono, fontSize: 10.5, color: kv.muted)),
                          Text(w.serviceName, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: kv.faint)),
                        ]),
                      ),
                      StatusChip(w.status),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'call') {
                            await callPhone(context, w.phone);
                            return;
                          }
                          await CompanyRepo.setWorkerSuspended(w, v == 'suspend');
                          s.changed();
                        },
                        itemBuilder: (_) => [
                          if (w.status == 'suspended')
                            const PopupMenuItem(value: 'activate', child: Text('Reactivate badge'))
                          else if (w.status == 'approved')
                            const PopupMenuItem(value: 'suspend', child: Text('Suspend badge')),
                          const PopupMenuItem(value: 'call', child: Text('Call')),
                        ],
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================= ledger
class AdminLedger extends StatelessWidget {
  const AdminLedger({super.key});

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return DataView<List<Txn>>(
      load: AdminRepo.transactions,
      builder: (context, list, reload) {
        double sum(String type) => list.where((t) => t.type == type && t.status == 'completed').fold(0.0, (a, t) => a + t.amount);
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              const SectionTitle('Transactions Ledger', icon: Icons.receipt_long_rounded, color: Kv.purple, subtitle: 'MoMo payments, refunds and payouts'),
              const SizedBox(height: 12),
              StatGrid(children: [
                StatTile(label: 'Collected', value: Fmt.compact(sum('payment')), unit: 'RWF', color: Kv.emerald),
                StatTile(label: 'Paid out', value: Fmt.compact(sum('payout')), unit: 'RWF', color: Kv.blueLight),
                StatTile(label: 'Refunded', value: Fmt.compact(sum('refund')), unit: 'RWF', color: Kv.red),
                StatTile(label: 'Records', value: '${list.length}', color: kv.text),
              ]),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(icon: Icons.receipt_outlined, title: 'No transactions yet', message: 'Client MoMo payments appear here.'),
              for (final t in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KvCard(
                    padding: const EdgeInsets.all(12),
                    radius: 16,
                    child: Row(children: [
                      Icon(
                        t.type == 'refund' ? Icons.undo_rounded : (t.type == 'payout' ? Icons.account_balance_rounded : Icons.phone_iphone_rounded),
                        color: t.type == 'refund' ? Kv.red : (t.type == 'payout' ? Kv.blueLight : Kv.emerald),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${Fmt.title(t.type)} • ${t.clientName.isEmpty ? t.providerName : t.clientName}',
                              overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: kv.text, fontSize: 13)),
                          Text('${t.bookingNumber} • ${t.gatewayRef}',
                              overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: Kv.mono, fontSize: 10.5, color: kv.muted)),
                          Text(Fmt.dateTime(t.createdAt), style: TextStyle(fontSize: 10.5, color: kv.faint)),
                        ]),
                      ),
                      Text(Fmt.money(t.amount), style: TextStyle(fontFamily: Kv.mono, fontWeight: FontWeight.w900, color: kv.text, fontSize: 12.5)),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================= control
class AdminControl extends StatelessWidget {
  const AdminControl({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfilePage(accent: Kv.purple, roleTag: 'PLATFORM ADMIN', extra: const [_SettingsCard()]);
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  Future<void> _edit(BuildContext context, String key, String title, String current) async {
    final v = await promptText(context, title, initial: current, ok: 'Save');
    if (v == null || v.isEmpty) return;
    if (key.endsWith('percent')) {
      final n = double.tryParse(v);
      if (n == null || n < 0 || n > 100) {
        if (context.mounted) showSnack(context, 'Enter a number between 0 and 100', error: true);
        return;
      }
    }
    await AdminRepo.saveSetting(key, v);
    if (context.mounted) context.session.changed();
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DataView<(Map<String, String>, int)>(
        load: () async => (await AdminRepo.settings(), await AdminRepo.pendingSync()),
        builder: (context, d, _) {
          final (st, sync) = d;
          return KvCard(
            borderColor: fade(Kv.purple, 0.45),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: SectionTitle('Platform settings', icon: Icons.tune_rounded, color: Kv.purple),
              ),
              ListTile(
                title: const Text('Platform commission', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Fee kept by KoraVuba on each job'),
                trailing: MonoTag('${st['platform_commission_percent'] ?? '9'}%', color: Kv.purpleLight),
                onTap: () => _edit(context, 'platform_commission_percent', 'Commission %', st['platform_commission_percent'] ?? '9'),
              ),
              ListTile(
                title: const Text('Upfront deposit', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Paid by MoMo when booking'),
                trailing: MonoTag('${st['upfront_deposit_percent'] ?? '50'}%', color: Kv.purpleLight),
                onTap: () => _edit(context, 'upfront_deposit_percent', 'Deposit %', st['upfront_deposit_percent'] ?? '50'),
              ),
              ListTile(
                title: const Text('Service categories', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Create the services workers can offer and their prices'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => push(context, const _CategoriesScreen()),
              ),
              ListTile(
                title: const Text('Users', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Activate / deactivate accounts'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => push(context, const _UsersScreen()),
              ),
              ListTile(
                title: const Text('Database', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${st['db_source'] ?? ''}\n$sync local changes waiting for a future API sync',
                    style: TextStyle(fontSize: 12, color: kv.muted)),
                isThreeLine: true,
              ),
              ListTile(
                leading: const Icon(Icons.restore_rounded, color: Kv.red),
                title: const Text('Reset to the bundled database', style: TextStyle(fontWeight: FontWeight.w700, color: Kv.red)),
                subtitle: const Text('Deletes every change made on this phone'),
                onTap: () async {
                  if (!await confirm(context, 'Reset database?', 'All bookings, accounts and changes made on this phone will be lost.',
                      ok: 'Reset', danger: true)) {
                    return;
                  }
                  if (!context.mounted) return;
                  final s = context.session;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  await AppDb.resetToBundled();
                  await s.signOut();
                },
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _UsersScreen extends StatefulWidget {
  const _UsersScreen();

  @override
  State<_UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<_UsersScreen> {
  String? _type;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final s = context.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: DataView<List<AppUser>>(
        key: ValueKey(_type),
        load: () => AdminRepo.users(type: _type),
        builder: (context, list, reload) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (k, label) in [(null, 'All'), ('client', 'Clients'), ('provider', 'Workers'), ('entity_admin', 'Company admins'), ('admin', 'Admins')])
                ChoiceChip(label: Text(label), selected: _type == k, onSelected: (_) => setState(() => _type = k)),
            ]),
            const SizedBox(height: 12),
            for (final u in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: KvCard(
                  padding: const EdgeInsets.all(12),
                  radius: 16,
                  child: Row(children: [
                    Avatar(name: u.fullName, path: u.profileImage, size: 40, color: u.isActive ? Kv.purple : Kv.s500),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u.fullName, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: kv.text)),
                        Text('${u.email} • ${Fmt.title(u.userType)}',
                            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: kv.muted)),
                      ]),
                    ),
                    Switch(
                      value: u.isActive,
                      onChanged: u.id == s.user!.id
                          ? null
                          : (v) async {
                              await AdminRepo.setUserActive(u.id, v);
                              await reload();
                            },
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DisputesScreen extends StatelessWidget {
  const _DisputesScreen();

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final s = context.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Disputes')),
      body: DataView<List<Dispute>>(
        load: AdminRepo.disputes,
        builder: (context, list, reload) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (list.isEmpty) const EmptyState(icon: Icons.gavel_rounded, title: 'No disputes', message: 'Problems reported on bookings appear here.'),
            for (final d in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KvCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(d.title, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text))),
                      StatusChip(d.status),
                    ]),
                    const SizedBox(height: 4),
                    Text('${Fmt.title(d.type)} • ${d.bookingNumber} • by ${d.raisedBy}', style: TextStyle(fontSize: 11.5, color: kv.muted)),
                    if (d.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(d.description, style: TextStyle(color: kv.text, fontSize: 13)),
                    ],
                    if (d.resolutionNotes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Resolution: ${d.resolutionNotes}', style: const TextStyle(color: Kv.emerald, fontSize: 12.5)),
                    ],
                    if (d.status != 'resolved' && d.status != 'dismissed') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: KvButton(
                            label: 'Dismiss',
                            color: Kv.s400,
                            outlined: true,
                            height: 40,
                            onPressed: () async {
                              final n = await promptText(context, 'Dismiss dispute', hint: 'Notes', ok: 'Dismiss');
                              if (n == null) return;
                              await AdminRepo.resolveDispute(d, s.user!.id, 'dismissed', n);
                              await reload();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: KvButton(
                            label: 'Resolve',
                            color: Kv.purple,
                            height: 40,
                            onPressed: () async {
                              final n = await promptText(context, 'Resolve dispute', hint: 'Resolution notes', ok: 'Resolve');
                              if (n == null) return;
                              await AdminRepo.resolveDispute(d, s.user!.id, 'resolved', n);
                              await reload();
                            },
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================= categories
class _CategoriesScreen extends StatelessWidget {
  const _CategoriesScreen();

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Scaffold(
      appBar: AppBar(title: const Text('Service categories')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Kv.purple,
        foregroundColor: Colors.white,
        onPressed: () => _editCategory(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
      ),
      body: DataView<List<Category>>(
        load: () => CatalogRepo.categories(includeHidden: true),
        builder: (context, list, reload) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (list.isEmpty)
              const EmptyState(
                icon: Icons.category_outlined,
                title: 'No categories yet',
                message: 'Add at least one category. Workers choose a category when they register, and clients filter by it.',
              ),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KvCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => _editCategory(context, c),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(color: fade(Kv.named(c.color), 0.14), borderRadius: BorderRadius.circular(12)),
                      child: Icon(categoryIcon(c.code), color: Kv.named(c.color)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.name, style: TextStyle(fontWeight: FontWeight.w900, color: c.isActive ? kv.text : kv.faint)),
                        if (c.rwName.isNotEmpty) Text(c.rwName, style: TextStyle(fontSize: 12, color: kv.muted, fontStyle: FontStyle.italic)),
                        Text('${Fmt.money(c.basePrice)} ${c.priceUnit}', style: const TextStyle(fontFamily: Kv.mono, fontSize: 11.5, color: Kv.emerald)),
                      ]),
                    ),
                    Switch(
                      value: c.isActive,
                      onChanged: (v) async {
                        await CatalogRepo.setCategoryActive(c, v);
                        if (context.mounted) context.session.changed();
                      },
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _editCategory(BuildContext context, Category? c) async {
  final name = TextEditingController(text: c?.name ?? '');
  final rw = TextEditingController(text: c?.rwName ?? '');
  final desc = TextEditingController(text: c?.description ?? '');
  final price = TextEditingController(text: c == null ? '' : c.basePrice.round().toString());
  final unit = TextEditingController(text: c?.priceUnit ?? 'per job');
  var type = c == null ? 'other' : categoryType(c.code);
  var color = c?.color.isNotEmpty == true ? c!.color : 'emerald';
  const colors = ['emerald', 'amber', 'blue', 'violet', 'pink', 'yellow', 'sky', 'teal', 'red'];
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(c == null ? 'New category' : 'Edit category', icon: Icons.category_rounded, color: Kv.purple),
            const SizedBox(height: 14),
            KvField(label: 'Name', controller: name, hint: 'e.g. Home & Office Cleaners', accent: Kv.purple, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 10),
            KvField(label: 'Kinyarwanda name (optional)', controller: rw, hint: 'e.g. Isuku y’Inzu', accent: Kv.purple),
            const SizedBox(height: 10),
            KvField(label: 'Description', controller: desc, accent: Kv.purple, maxLines: 2),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: KvField(label: 'Base price (RWF)', controller: price, keyboard: TextInputType.number, mono: true, accent: Kv.purple)),
              const SizedBox(width: 10),
              Expanded(child: KvField(label: 'Price unit', controller: unit, hint: 'per km / per hour', accent: Kv.purple)),
            ]),
            const SizedBox(height: 8),
            const Text('Tip: a unit with "km" makes it a distance-priced trip; anything else is priced per unit (hour, job, session…).',
                style: TextStyle(fontSize: 11.5, color: Kv.s500)),
            if (c == null) ...[
              const SizedBox(height: 12),
              const Text('Kind (icon, badge prefix, trip or service):', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (k, label) in categoryTypes)
                  ChoiceChip(
                    avatar: Icon(categoryIcon(k), size: 16),
                    label: Text(label),
                    selected: type == k,
                    onSelected: (_) => set(() => type = k),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final col in colors)
                GestureDetector(
                  onTap: () => set(() => color = col),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Kv.named(col),
                      shape: BoxShape.circle,
                      border: Border.all(color: color == col ? Colors.white : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            KvButton(label: 'Save category', color: Kv.purple, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final p = double.tryParse(price.text.trim());
  if (name.text.trim().isEmpty || p == null || p <= 0) {
    showSnack(context, 'A name and a base price are required', error: true);
    return;
  }
  if (c == null) {
    await CatalogRepo.createCategory(
        name: name.text, rwName: rw.text, type: type, description: desc.text, basePrice: p, priceUnit: unit.text, color: color);
  } else {
    await CatalogRepo.updateCategory(c, name: name.text, rwName: rw.text, description: desc.text, basePrice: p, priceUnit: unit.text, color: color);
  }
  if (context.mounted) {
    context.session.changed();
    showSnack(context, 'Category saved');
  }
}
