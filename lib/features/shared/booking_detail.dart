import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/chat_repo.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'call.dart';
import 'messages.dart';
import 'momo.dart';

enum Viewer { client, worker, company, admin }

/// Compact booking card used in every list.
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.viewer, this.accent = Kv.emerald});
  final Booking booking;
  final Viewer viewer;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final b = booking;
    final other = viewer == Viewer.worker ? b.clientName : b.providerName;
    return KvCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      onTap: () => push(context, BookingDetailScreen(bookingId: b.id, viewer: viewer, accent: accent)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: fade(accent, 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(categoryIcon(b.categoryCode), color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.serviceName.isEmpty ? b.categoryName : b.serviceName,
                  overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
              Text(b.number, style: TextStyle(fontSize: 11, fontFamily: Kv.mono, color: kv.faint)),
            ]),
          ),
          StatusChip(b.status),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.person_outline_rounded, size: 15, color: kv.muted),
          const SizedBox(width: 5),
          Expanded(child: Text(other, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: kv.muted))),
          Icon(Icons.schedule_rounded, size: 15, color: kv.muted),
          const SizedBox(width: 5),
          Text('${Fmt.dayDate(b.scheduledAt)} ${Fmt.hhmm(b.scheduledTime)}', style: TextStyle(fontSize: 12.5, color: kv.muted)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.place_outlined, size: 15, color: kv.muted),
          const SizedBox(width: 5),
          Expanded(child: Text(b.address, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: kv.muted))),
          Text(Fmt.money(viewer == Viewer.worker ? b.providerEarnings : b.total),
              style: TextStyle(fontFamily: Kv.mono, fontWeight: FontWeight.w900, color: accent)),
        ]),
      ]),
    );
  }
}

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId, required this.viewer, this.accent = Kv.emerald});
  final String bookingId;
  final Viewer viewer;
  final Color accent;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  Booking? _b;
  List<Map<String, Object?>> _history = [];
  List<Txn> _txns = [];
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _b?.status == 'in_progress') setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await BookingRepo.byId(widget.bookingId);
    final h = await BookingRepo.history(widget.bookingId);
    final t = await BookingRepo.transactionsFor(widget.bookingId);
    if (!mounted) return;
    setState(() {
      _b = b;
      _history = h;
      _txns = t;
    });
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      context.session.changed();
      await _load();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _me => context.session.user!.id;

  Future<void> _status(String status, String done, {bool askReason = false}) async {
    final b = _b!;
    var reason = '';
    if (askReason) {
      final r = await promptText(context, 'Reason', hint: 'Tell the other side why (optional)', ok: 'Confirm');
      if (r == null) return;
      reason = r;
    }
    await _run(() => BookingRepo.setStatus(b, status, _me, reason: reason), done);
  }

  Future<void> _payBalance() async {
    final b = _b!;
    final pay = await askMomo(context, amount: b.balance, purpose: 'Balance for ${b.number}');
    if (pay == null) return;
    await _run(() async {
      await BookingRepo.payBalance(b, pay);
    }, 'Balance paid. Thank you!');
  }

  Future<void> _rate() async {
    final b = _b!;
    var stars = 5;
    final comment = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle('Rate ${b.providerName}', icon: Icons.star_rounded, color: Kv.amber, subtitle: b.serviceName),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 38,
                  onPressed: () => set(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: Kv.amberLight),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(hintText: 'How was the service? (optional)')),
            const SizedBox(height: 16),
            KvButton(label: 'Submit review', color: Kv.amber, onPressed: () => Navigator.pop(c, true)),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => BookingRepo.review(b, _me, stars, comment.text.trim()), 'Thanks for rating!');
  }

  Future<void> _sos() async {
    final b = _b!;
    final msg = await promptText(context, '🚨 Send SOS alert', hint: 'What is happening? (KoraVuba HQ + company are alerted)', ok: 'SEND SOS');
    if (msg == null) return;
    await _run(() => BookingRepo.sos(b, _me, msg.isEmpty ? 'Emergency — please call me' : msg, b.lat, b.lng),
        'SOS sent. KoraVuba HQ and the company were alerted.');
    if (mounted && await confirm(context, 'Call emergency services?', 'Rwanda National Police: 112', ok: 'Call 112', danger: true)) {
      if (mounted) await callPhone(context, '112');
    }
  }

  Future<void> _report() async {
    final b = _b!;
    var type = 'service_quality';
    final title = TextEditingController();
    final desc = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionTitle('Report a problem', icon: Icons.gavel_rounded, color: Kv.amber),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in const ['service_quality', 'payment', 'no_show', 'misconduct', 'damage', 'other'])
                ChoiceChip(label: Text(Fmt.title(t)), selected: type == t, onSelected: (_) => set(() => type = t)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: title, decoration: const InputDecoration(hintText: 'Short title')),
            const SizedBox(height: 10),
            TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(hintText: 'Describe what happened')),
            const SizedBox(height: 16),
            KvButton(label: 'Send report', color: Kv.amber, onPressed: () => Navigator.pop(c, true)),
          ]),
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await _run(
        () => BookingRepo.dispute(b, _me, type, title.text.trim(), desc.text.trim(), byClient: widget.viewer == Viewer.client),
        'Report sent to KoraVuba support');
  }

  Future<void> _chat() async {
    final b = _b!;
    final convId = b.conversationId ?? await ChatRepo.ensureConversation(b.clientId, b.providerId);
    if (!mounted) return;
    final asWorker = widget.viewer == Viewer.worker;
    push(
      context,
      ChatScreen(
        accent: widget.accent,
        conversation: Conversation(
          id: convId,
          otherName: asWorker ? b.clientName : b.providerName,
          otherPhoto: asWorker ? b.clientPhoto : b.providerPhoto,
          otherPhone: asWorker ? b.clientPhone : b.providerPhone,
          subtitle: asWorker ? 'Client' : [b.badgeId, b.companyName].where((e) => e.isNotEmpty).join(' • '),
          lastMessage: '',
          lastAt: null,
          unread: 0,
          clientId: b.clientId,
          providerId: b.providerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    final kv = context.kv;
    return Scaffold(
      appBar: AppBar(title: Text(b?.number ?? 'Booking', style: const TextStyle(fontFamily: Kv.mono, fontSize: 15, fontWeight: FontWeight.w800))),
      body: b == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _header(b, kv),
                  const SizedBox(height: 12),
                  _progress(b, kv),
                  const SizedBox(height: 12),
                  _people(b, kv),
                  const SizedBox(height: 12),
                  _payment(b, kv),
                  const SizedBox(height: 14),
                  ..._actions(b),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    KvCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionTitle('Audit trail', icon: Icons.history_rounded, color: Kv.s400),
                        const SizedBox(height: 10),
                        for (final h in _history)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(Fmt.dateTime(AppDb.parse(h['created_at'])),
                                  style: TextStyle(fontFamily: Kv.mono, fontSize: 11, color: kv.faint)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${Fmt.title('${h['new_status'] ?? ''}')}${'${h['notes'] ?? ''}'.isEmpty ? '' : ' — ${h['notes']}'}',
                                  style: TextStyle(fontSize: 12.5, color: kv.text),
                                ),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _header(Booking b, KvColors kv) {
    return KvCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [fade(widget.accent, kv.isDark ? 0.18 : 0.10), kv.card],
      ),
      borderColor: fade(widget.accent, 0.4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(categoryIcon(b.categoryCode), color: widget.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(b.serviceName.isEmpty ? b.categoryName : b.serviceName,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kv.text)),
          ),
          StatusChip(b.status),
        ]),
        const SizedBox(height: 12),
        InfoRow('Scheduled', '${Fmt.dayDate(b.scheduledAt)} • ${Fmt.hhmm(b.scheduledTime)}'),
        InfoRow('Address', b.address.isEmpty ? b.city : b.address),
        if (b.clientNotes.isNotEmpty) InfoRow('Client notes', b.clientNotes),
        if (b.cancellationReason.isNotEmpty) InfoRow('Reason', b.cancellationReason, valueColor: Kv.red),
        if (b.status == 'in_progress' && b.startedAt != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: kv.isDark ? Kv.s950 : Kv.s50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: fade(Kv.purple, 0.5)),
            ),
            child: Column(children: [
              Text('LIVE JOB TIMER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: kv.muted)),
              const SizedBox(height: 4),
              Text(Fmt.duration(DateTime.now().difference(b.startedAt!)),
                  style: const TextStyle(fontFamily: Kv.mono, fontSize: 34, fontWeight: FontWeight.w900, color: Kv.purpleLight)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _progress(Booking b, KvColors kv) {
    if (b.isCancelled) {
      return KvCard(
        borderColor: fade(Kv.red, 0.4),
        child: Row(children: [
          const Icon(Icons.cancel_rounded, color: Kv.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${StatusChip.info(b.status).$1} • ${Fmt.dateTime(b.cancelledAt)}',
                style: TextStyle(color: kv.text, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    final steps = [
      ('Requested', b.createdAt, true),
      (b.isTransport ? 'Driver en route' : 'Accepted • en route', b.acceptedAt, ['accepted', 'in_progress', 'completed'].contains(b.status)),
      ('In progress', b.startedAt, ['in_progress', 'completed'].contains(b.status)),
      ('Completed', b.completedAt, b.status == 'completed'),
    ];
    return KvCard(
      child: Column(children: [
        for (var i = 0; i < steps.length; i++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Icon(steps[i].$3 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 22, color: steps[i].$3 ? widget.accent : kv.faint),
              if (i < steps.length - 1) Container(width: 2, height: 22, color: steps[i + 1].$3 ? widget.accent : kv.border),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(steps[i].$1,
                        style: TextStyle(fontWeight: FontWeight.w800, color: steps[i].$3 ? kv.text : kv.faint)),
                  ),
                  Text(steps[i].$2 == null ? '' : Fmt.time(steps[i].$2),
                      style: TextStyle(fontFamily: Kv.mono, fontSize: 12, color: kv.muted)),
                ]),
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _people(Booking b, KvColors kv) {
    final asWorker = widget.viewer == Viewer.worker;
    final name = asWorker ? b.clientName : b.providerName;
    final phone = asWorker ? b.clientPhone : b.providerPhone;
    return KvCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: name, path: asWorker ? b.clientPhoto : b.providerPhoto, color: widget.accent, size: 50),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asWorker ? 'CLIENT' : 'SERVICE PROVIDER',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: kv.muted)),
              Text(name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kv.text)),
              Text(Fmt.phone(phone), style: TextStyle(fontFamily: Kv.mono, fontSize: 12, color: kv.muted)),
            ]),
          ),
        ]),
        if (!asWorker && (b.badgeId.isNotEmpty || b.companyName.isNotEmpty)) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (b.badgeId.isNotEmpty) MonoTag(b.badgeId, color: Kv.amberLight),
            if (b.companyName.isNotEmpty) MonoTag(b.companyName, color: Kv.blueLight, icon: Icons.verified_rounded),
          ]),
        ],
        if (widget.viewer == Viewer.client || widget.viewer == Viewer.worker) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: KvButton(label: 'Chat', icon: Icons.chat_bubble_outline_rounded, outlined: true, color: widget.accent, height: 44, onPressed: _chat)),
            const SizedBox(width: 10),
            Expanded(
              child: KvButton(
                  label: 'Call', icon: Icons.call_rounded, outlined: true, color: widget.accent, height: 44, onPressed: () => callPhone(context, phone)),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _payment(Booking b, KvColors kv) {
    return KvCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Payment', icon: Icons.account_balance_wallet_outlined, color: widget.accent, trailing: StatusChip(b.paymentStatus)),
        const SizedBox(height: 10),
        InfoRow('Service price', Fmt.money(b.servicePrice), mono: true),
        InfoRow('KoraVuba fee (included)', Fmt.money(b.platformFee), mono: true),
        if (widget.viewer != Viewer.client) InfoRow('Provider / company share', Fmt.money(b.providerEarnings), mono: true),
        InfoRow('Paid so far', Fmt.money(b.paid), mono: true, valueColor: Kv.emerald),
        if (!b.isCancelled) InfoRow('Balance due', Fmt.money(b.balance), mono: true, bold: true, valueColor: b.balance > 0 ? Kv.amber : Kv.emerald),
        if (_txns.isNotEmpty) ...[
          const Divider(height: 22),
          for (final t in _txns)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(
                    t.type == 'refund'
                        ? Icons.undo_rounded
                        : (t.type == 'payout' ? Icons.account_balance_rounded : Icons.phone_iphone_rounded),
                    size: 16,
                    color: kv.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${Fmt.title(t.type)} • ${t.gatewayRef}',
                      overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontFamily: Kv.mono, color: kv.muted)),
                ),
                Text(Fmt.money(t.amount), style: TextStyle(fontSize: 12.5, fontFamily: Kv.mono, fontWeight: FontWeight.w800, color: kv.text)),
              ]),
            ),
        ],
      ]),
    );
  }

  List<Widget> _actions(Booking b) {
    const gap = SizedBox(height: 10);
    final list = <Widget>[];
    void add(Widget w) {
      if (list.isNotEmpty) list.add(gap);
      list.add(w);
    }

    switch (widget.viewer) {
      case Viewer.client:
        if (b.status == 'completed' && b.balance > 0 && b.paymentStatus != 'refunded') {
          add(KvButton(label: 'Pay balance ${Fmt.money(b.balance)} with MoMo', icon: Icons.phone_iphone_rounded, loading: _busy, onPressed: _payBalance));
        }
        if (b.status == 'completed' && b.rating == null) {
          add(KvButton(label: 'Rate this service', icon: Icons.star_rounded, color: Kv.amber, loading: _busy, onPressed: _rate));
        }
        if (b.status == 'pending') {
          add(KvButton(
              label: 'Cancel booking',
              icon: Icons.close_rounded,
              color: Kv.red,
              outlined: true,
              loading: _busy,
              onPressed: () => _status('cancelled_by_client', 'Booking cancelled. Deposit refunded.', askReason: true)));
        }
      case Viewer.worker:
        if (b.status == 'pending') {
          add(KvButton(
              label: 'Accept dispatch', icon: Icons.check_rounded, color: Kv.amber, loading: _busy, onPressed: () => _status('accepted', 'Accepted — the client was notified')));
          add(KvButton(
              label: 'Decline',
              icon: Icons.close_rounded,
              color: Kv.red,
              outlined: true,
              loading: _busy,
              onPressed: () => _status('cancelled_by_provider', 'Dispatch declined', askReason: true)));
        }
        if (b.status == 'accepted') {
          add(KvButton(label: 'Arrived — start job & timer', icon: Icons.play_arrow_rounded, color: Kv.amber, loading: _busy, onPressed: () => _status('in_progress', 'Job started')));
        }
        if (b.status == 'in_progress') {
          add(KvButton(label: 'Finish job', icon: Icons.flag_rounded, color: Kv.emerald, loading: _busy, onPressed: () => _status('completed', 'Job completed 🎉')));
        }
      case Viewer.company:
      case Viewer.admin:
        if (b.isOpen) {
          add(KvButton(
              label: 'Cancel booking (admin)',
              icon: Icons.block_rounded,
              color: Kv.red,
              outlined: true,
              loading: _busy,
              onPressed: () => _status('cancelled_by_admin', 'Booking cancelled', askReason: true)));
        }
    }
    if ((widget.viewer == Viewer.client || widget.viewer == Viewer.worker) && b.isOpen) {
      add(KvButton(label: 'SOS — Emergency', icon: Icons.sos_rounded, color: Kv.red, loading: _busy, onPressed: _sos));
    }
    if (widget.viewer == Viewer.client || widget.viewer == Viewer.worker) {
      add(KvButton(label: 'Report a problem', icon: Icons.flag_outlined, color: Kv.s400, outlined: true, onPressed: _report));
    }
    return list;
  }
}
