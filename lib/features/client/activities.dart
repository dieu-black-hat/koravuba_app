import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../shared/booking_detail.dart';

/// "Activity History & Audit Logs" with search, type / status filters and sort.
class ActivitiesPage extends StatefulWidget {
  const ActivitiesPage({super.key, required this.viewer, this.accent = Kv.emerald, this.loader});
  final Viewer viewer;
  final Color accent;
  final Future<List<Booking>> Function()? loader;

  @override
  State<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends State<ActivitiesPage> {
  final _q = TextEditingController();
  String _type = 'all';
  String _status = 'all';
  bool _newest = true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _matchStatus(Booking b) => switch (_status) {
        'open' => b.isOpen,
        'completed' => b.status == 'completed',
        'cancelled' => b.isCancelled,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final s = context.session;
    return DataView<List<Booking>>(
      load: widget.loader ?? () => BookingRepo.forClient(s.user!.id),
      builder: (context, all, reload) {
        final trips = all.where((b) => b.isTransport).toList();
        final value = all.where((b) => b.status == 'completed').fold<double>(0, (a, b) => a + b.total);
        final q = _q.text.trim().toLowerCase();
        final list = all.where((b) {
          if (_type == 'trips' && !b.isTransport) return false;
          if (_type == 'services' && b.isTransport) return false;
          if (!_matchStatus(b)) return false;
          if (q.isEmpty) return true;
          return [b.number, b.providerName, b.clientName, b.serviceName, b.address, b.providerPhone, b.clientPhone]
              .any((f) => f.toLowerCase().contains(q));
        }).toList();
        if (!_newest) {
          list.sort((a, b) => (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000)));
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              KvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionTitle(
                    'Activity History & Audit Logs',
                    icon: Icons.history_rounded,
                    color: widget.accent,
                    subtitle: 'Bookings, trips, timestamps, amounts and provider / client records.',
                  ),
                  const SizedBox(height: 14),
                  StatGrid(children: [
                    StatTile(label: 'Total activities', value: '${all.length}', color: kv.text),
                    StatTile(label: 'Trips & transport', value: '${trips.length}', color: Kv.emerald),
                    StatTile(label: 'Home services', value: '${all.length - trips.length}', color: Kv.blueLight),
                    StatTile(label: 'Total value', value: Fmt.compact(value), unit: 'RWF', color: Kv.amberLight),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              KvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by ID, name, phone, address…'),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final (k, label) in [('all', 'All Types'), ('trips', '🚕 Trips (${trips.length})'), ('services', '🧹 Services (${all.length - trips.length})')])
                      ChoiceChip(label: Text(label), selected: _type == k, onSelected: (_) => setState(() => _type = k)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final (k, label) in [('all', 'All statuses'), ('open', '⚡ Active'), ('completed', '✅ Completed'), ('cancelled', '✖ Cancelled')])
                      ChoiceChip(label: Text(label), selected: _status == k, onSelected: (_) => setState(() => _status = k)),
                    ActionChip(
                      avatar: Icon(_newest ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 16),
                      label: Text(_newest ? 'Newest first' : 'Oldest first'),
                      onPressed: () => setState(() => _newest = !_newest),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Showing ', style: TextStyle(color: kv.muted)),
                    TextSpan(text: '${list.length}', style: TextStyle(color: widget.accent, fontWeight: FontWeight.w900)),
                    TextSpan(text: ' of ', style: TextStyle(color: kv.muted)),
                    TextSpan(text: '${all.length}', style: TextStyle(color: kv.text, fontWeight: FontWeight.w900)),
                    TextSpan(text: ' activity records', style: TextStyle(color: kv.muted)),
                  ]), style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.schedule_rounded,
                  title: 'No Activity Records Found',
                  message: 'There are no bookings, trips or service activity matching your filters.',
                ),
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BookingCard(booking: b, viewer: widget.viewer, accent: widget.accent),
                ),
            ],
          ),
        );
      },
    );
  }
}
