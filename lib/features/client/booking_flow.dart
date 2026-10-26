import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../shared/booking_detail.dart';
import '../shared/momo.dart';

/// Book a worker: when, how much, where → price summary → MoMo deposit → receipt.
class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({super.key, required this.worker});
  final Worker worker;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  bool _now = true;
  DateTime _when = DateTime.now().add(const Duration(hours: 2));
  double _units = 1;
  late Sector _sector;
  final _street = TextEditingController();
  final _notes = TextEditingController();
  Pricing? _pricing;
  bool _busy = false;

  bool get _perKm => widget.worker.priceUnit.contains('km');
  String get _unitName {
    final u = widget.worker.priceUnit.toLowerCase();
    if (_perKm) return 'km';
    if (u.contains('day')) return 'day';
    if (u.contains('session')) return 'session';
    if (u.contains('person')) return 'person';
    if (u.contains('event')) return 'event';
    if (u.contains('trip') || u.contains('night')) return 'trip';
    if (u.contains('job')) return 'job';
    return 'hour';
  }

  @override
  void initState() {
    super.initState();
    _sector = context.session.sector;
    _units = _perKm ? 5 : 1;
    _price();
  }

  @override
  void dispose() {
    _street.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _price() async {
    final p = await BookingRepo.pricing(widget.worker.price * _units);
    if (mounted) setState(() => _pricing = p);
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t == null) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _pay() async {
    final p = _pricing;
    if (p == null) return;
    if (_street.text.trim().isEmpty) {
      showSnack(context, 'Add a street / house description so the provider can find you', error: true);
      return;
    }
    final pay = await askMomo(context, amount: p.deposit, purpose: '${p.depositPercent.round()}% deposit for ${widget.worker.serviceName}');
    if (pay == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final s = context.session;
      final b = await BookingRepo.create(
        client: s.user!,
        worker: widget.worker,
        when: _now ? DateTime.now() : _when,
        units: _units,
        address: '${_street.text.trim()}, ${_sector.name}, Kigali',
        notes: _notes.text.trim(),
        lat: _sector.lat,
        lng: _sector.lng,
        payment: pay,
      );
      s.changed();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _Receipt(booking: b, network: pay.network)));
    } catch (e) {
      if (mounted) showSnack(context, 'Booking failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final w = widget.worker;
    final p = _pricing;
    return Scaffold(
      appBar: AppBar(title: const Text('Book a service')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          KvCard(
            child: Row(children: [
              Avatar(name: w.name, path: w.photo, color: Kv.named(w.categoryColor), online: w.online),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.name, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text, fontSize: 16)),
                  Text(w.serviceName, style: TextStyle(color: kv.muted, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text('${Fmt.money(w.price)} ${w.priceUnit}', style: const TextStyle(fontFamily: Kv.mono, fontSize: 12, color: Kv.emerald)),
                ]),
              ),
              RatingStars(w.rating),
            ]),
          ),
          const SizedBox(height: 14),
          KvCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('When?', icon: Icons.schedule_rounded),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: ChoiceChip(
                        label: const Center(child: Text('Right now ⚡')), selected: _now, onSelected: (_) => setState(() => _now = true))),
                const SizedBox(width: 8),
                Expanded(
                    child: ChoiceChip(
                        label: const Center(child: Text('Schedule 📅')), selected: !_now, onSelected: (_) => setState(() => _now = false))),
              ]),
              if (!_now) ...[
                const SizedBox(height: 10),
                KvButton(label: Fmt.dateTime(_when), icon: Icons.edit_calendar_rounded, outlined: true, height: 46, onPressed: _pickWhen),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          KvCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle(_perKm ? 'Estimated trip distance' : 'How many ${_unitName}s?', icon: Icons.straighten_rounded),
              const SizedBox(height: 10),
              Row(children: [
                IconButton.filledTonal(
                  onPressed: _units <= 1
                      ? null
                      : () {
                          setState(() => _units -= 1);
                          _price();
                        },
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Text('${_units.round()} $_unitName${_units == 1 ? '' : 's'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: Kv.mono, fontSize: 22, fontWeight: FontWeight.w900, color: Kv.emerald)),
                ),
                IconButton.filledTonal(
                  onPressed: _units >= 60
                      ? null
                      : () {
                          setState(() => _units += 1);
                          _price();
                        },
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          KvCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle(_perKm ? 'Pick-up location' : 'Service address', icon: Icons.place_outlined),
              const SizedBox(height: 12),
              DropdownButtonFormField<Sector>(
                initialValue: _sector,
                isExpanded: true,
                dropdownColor: kv.card,
                items: [for (final s in kigaliSectors) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (s) => setState(() => _sector = s ?? _sector),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _street,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Street, house no. or landmark (e.g. KG 11 Ave, blue gate)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: _perKm ? 'Destination / notes for the driver' : 'Notes for the provider (optional)'),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (p != null)
            KvCard(
              borderColor: fade(Kv.emerald, 0.4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Price summary', icon: Icons.receipt_long_rounded),
                const SizedBox(height: 8),
                InfoRow('${_units.round()} × ${Fmt.money(w.price)}', Fmt.money(p.servicePrice), mono: true),
                InfoRow('KoraVuba fee (${p.commissionPercent.round()}%, included)', Fmt.money(p.platformFee), mono: true),
                const Divider(height: 18),
                InfoRow('Total', Fmt.money(p.total), mono: true, bold: true),
                InfoRow('Pay now (${p.depositPercent.round()}% deposit)', Fmt.money(p.deposit), mono: true, bold: true, valueColor: Kv.emerald),
                InfoRow('Balance after the job', Fmt.money(p.balance), mono: true),
              ]),
            ),
          const SizedBox(height: 18),
          KvButton(
            label: p == null ? 'Calculating…' : 'Pay deposit ${Fmt.money(p.deposit)} with MoMo',
            icon: Icons.phone_iphone_rounded,
            loading: _busy,
            onPressed: p == null ? null : _pay,
          ),
          const SizedBox(height: 10),
          Text('Your deposit is refunded automatically if the provider declines or you cancel before they accept.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: kv.faint)),
        ],
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.booking, required this.network});
  final Booking booking;
  final String network;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final b = booking;
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SizedBox(height: 10),
          const Center(child: Icon(Icons.check_circle_rounded, color: Kv.emerald, size: 80)),
          const SizedBox(height: 12),
          Text('Dispatch confirmed!',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kv.text)),
          const SizedBox(height: 6),
          Text('${b.providerName} has been notified and will accept shortly.',
              textAlign: TextAlign.center, style: TextStyle(color: kv.muted)),
          const SizedBox(height: 20),
          KvCard(
            child: Column(children: [
              InfoRow('Booking', b.number, mono: true),
              InfoRow('Service', b.serviceName),
              InfoRow('Provider', '${b.providerName}${b.badgeId.isEmpty ? '' : ' • ${b.badgeId}'}'),
              if (b.companyName.isNotEmpty) InfoRow('Company', b.companyName),
              InfoRow('When', '${Fmt.dayDate(b.scheduledAt)} • ${Fmt.hhmm(b.scheduledTime)}'),
              InfoRow('Address', b.address),
              const Divider(height: 20),
              InfoRow('Total', Fmt.money(b.total), mono: true, bold: true),
              InfoRow('Paid via $network', Fmt.money(b.paid), mono: true, valueColor: Kv.emerald),
              InfoRow('MoMo reference', b.r.s('payment_intent_id'), mono: true),
              InfoRow('Balance after job', Fmt.money(b.balance), mono: true),
            ]),
          ),
          const SizedBox(height: 18),
          KvButton(
            label: 'Track this job',
            icon: Icons.radar_rounded,
            onPressed: () => Navigator.of(context)
                .pushReplacement(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: b.id, viewer: Viewer.client))),
          ),
        ],
      ),
    );
  }
}
