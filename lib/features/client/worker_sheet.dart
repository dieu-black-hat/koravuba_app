import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/catalog_repo.dart';
import '../../data/chat_repo.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../shared/call.dart';
import '../shared/messages.dart';
import 'booking_flow.dart';

Future<void> showWorker(BuildContext context, Worker w) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => _WorkerSheet(worker: w, scroll: scroll),
    ),
  );
}

class _WorkerSheet extends StatelessWidget {
  const _WorkerSheet({required this.worker, required this.scroll});
  final Worker worker;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final w = worker;
    final color = Kv.named(w.categoryColor);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Row(children: [
          Avatar(name: w.name, path: w.photo, size: 64, color: color, online: w.online),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kv.text)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (w.badgeId.isNotEmpty) MonoTag(w.badgeId, color: Kv.amberLight),
                Pill(w.online ? 'Online now' : 'Offline', color: w.online ? Kv.emerald : Kv.s400, icon: Icons.circle),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        KvCard(
          padding: const EdgeInsets.all(14),
          radius: 18,
          color: kv.isDark ? Kv.s950 : Kv.s50,
          child: Row(children: [
            const Icon(Icons.verified_rounded, color: Kv.blueLight),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.companyName, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
                Text(w.companyCode.isEmpty ? 'Verified by KoraVuba' : 'Company guarantee • ${w.companyCode}',
                    style: TextStyle(fontSize: 12, color: kv.muted, fontFamily: Kv.mono)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        StatGrid(children: [
          StatTile(label: 'Rating', value: w.rating <= 0 ? 'New' : w.rating.toStringAsFixed(2), unit: '★', color: Kv.amberLight, foot: '${w.reviews} reviews'),
          StatTile(label: 'Jobs done', value: '${w.jobs}', color: Kv.emerald),
          StatTile(
              label: 'Distance', value: w.distanceKm == null ? '—' : Fmt.km(w.distanceKm!), color: Kv.blueLight, foot: 'From your location'),
          StatTile(label: 'Rate', value: Fmt.compact(w.price), unit: 'RWF', color: color, foot: w.priceUnit),
        ]),
        const SizedBox(height: 14),
        KvCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(categoryIcon(_code(w)), color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(w.serviceName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kv.text))),
            ]),
            if (w.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(w.description, style: TextStyle(color: kv.muted, height: 1.4, fontSize: 13)),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        FutureBuilder<List<Review>>(
          future: CatalogRepo.reviews(w.profileId),
          builder: (context, snap) {
            final list = snap.data ?? const <Review>[];
            if (list.isEmpty) return const SizedBox.shrink();
            return KvCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionTitle('Client reviews', icon: Icons.reviews_outlined, color: Kv.amber),
                const SizedBox(height: 8),
                for (final r in list.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        RatingStars(r.rating, size: 12),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r.reviewer, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: kv.text))),
                        Text(Fmt.date(r.createdAt), style: TextStyle(fontSize: 11, color: kv.faint)),
                      ]),
                      if (r.comment.isNotEmpty) Text(r.comment, style: TextStyle(fontSize: 12.5, color: kv.muted)),
                    ]),
                  ),
              ]),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: KvButton(
              label: 'Chat',
              icon: Icons.chat_bubble_outline_rounded,
              outlined: true,
              height: 48,
              onPressed: () async {
                final me = context.session.user!;
                final id = await ChatRepo.ensureConversation(me.id, w.profileId);
                if (!context.mounted) return;
                Navigator.pop(context);
                push(
                  context,
                  ChatScreen(
                    accent: Kv.emerald,
                    conversation: Conversation(
                      id: id,
                      otherName: w.name,
                      otherPhoto: w.photo,
                      otherPhone: w.phone,
                      subtitle: [w.badgeId, w.companyName].where((e) => e.isNotEmpty).join(' • '),
                      lastMessage: '',
                      lastAt: null,
                      unread: 0,
                      clientId: me.id,
                      providerId: w.profileId,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: KvButton(label: 'Call', icon: Icons.call_rounded, outlined: true, height: 48, onPressed: () => callPhone(context, w.phone)),
          ),
        ]),
        const SizedBox(height: 10),
        KvButton(
          label: w.online ? 'Book ${w.name.split(' ').first} now' : 'Offline — schedule a booking',
          icon: Icons.bolt_rounded,
          onPressed: () {
            Navigator.pop(context);
            push(context, BookingFlowScreen(worker: w));
          },
        ),
      ],
    );
  }

  static String _code(Worker w) {
    final n = w.categoryName.toLowerCase();
    if (n.contains('moto')) return 'moto_taxi';
    if (n.contains('taxi')) return 'car_taxi';
    if (n.contains('clean')) return 'cleaner';
    if (n.contains('driver')) return 'driver';
    if (n.contains('plumb')) return 'plumber';
    if (n.contains('electric')) return 'electrician';
    if (n.contains('nann')) return 'nanny';
    if (n.contains('chef')) return 'chef';
    if (n.contains('tutor')) return 'tutor';
    if (n.contains('barber')) return 'barber';
    return '';
  }
}

String workerCategoryCode(Worker w) => _WorkerSheet._code(w);
