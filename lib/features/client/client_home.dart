import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/booking_repo.dart';
import '../../data/catalog_repo.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../shared/booking_detail.dart';
import 'radar.dart';
import 'worker_sheet.dart';

class _HomeData {
  _HomeData(this.categories, this.workers, this.top, this.active);
  final List<Category> categories;
  final List<Worker> workers;
  final List<Worker> top;
  final List<Booking> active;
}

/// Client home: radius, category, orbital radar / GPS map, nearby + top providers.
class ClientHome extends StatefulWidget {
  const ClientHome({super.key});

  @override
  State<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<ClientHome> {
  static const _radii = [1.0, 3.0, 5.0, 10.0, 25.0];
  String? _categoryId;
  bool _map = false;
  Key _dataKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final kv = context.kv;
    final radius = s.radiusKm;
    final loc = s.location;
    return DataView<_HomeData>(
      key: _dataKey,
      load: () async {
        final cats = await CatalogRepo.categories();
        final workers = await CatalogRepo.bookable(categoryId: _categoryId, from: loc);
        final top = await CatalogRepo.topRated(from: loc);
        final active = (await BookingRepo.forClient(s.user!.id)).where((b) => b.isOpen).toList();
        return _HomeData(cats, workers, top, active);
      },
      builder: (context, d, reload) {
        final inRange = d.workers.where((w) => w.distanceKm != null && w.distanceKm! <= radius).toList()
          ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
        final online = inRange.where((w) => w.online).toList();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text('Muraho, ${s.user!.firstName} 👋', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kv.text)),
              const SizedBox(height: 2),
              Text('What do you need today in ${s.sector.name}?', style: TextStyle(color: kv.muted)),
              const SizedBox(height: 14),
              for (final b in d.active.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KvCard(
                    borderColor: fade(Kv.purple, 0.5),
                    padding: const EdgeInsets.all(14),
                    onTap: () => push(context, BookingDetailScreen(bookingId: b.id, viewer: Viewer.client)),
                    child: Row(children: [
                      const Icon(Icons.radar_rounded, color: Kv.purpleLight),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Live job • ${b.serviceName}', style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
                          Text('${b.providerName} • ${StatusChip.info(b.status).$1}', style: TextStyle(fontSize: 12.5, color: kv.muted)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: kv.muted),
                    ]),
                  ),
                ),
              KvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    decoration: BoxDecoration(
                      color: kv.isDark ? Kv.s950 : Kv.s50,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kv.border),
                    ),
                    child: Column(children: [
                      Row(children: [
                        Icon(Icons.tune_rounded, size: 16, color: kv.muted),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Radius Settings:', style: TextStyle(fontWeight: FontWeight.w800, color: kv.text))),
                        MonoTag('${radius.round()} km', size: 12.5),
                      ]),
                      Slider(
                        value: _radii.indexOf(radius).clamp(0, 4).toDouble(),
                        min: 0,
                        max: 4,
                        divisions: 4,
                        onChanged: (v) => s.setRadius(_radii[v.round()]),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        for (final r in _radii)
                          r == radius ? MonoTag('${r.round()}k', size: 10) : MonoTag('${r.round()}k', color: kv.faint, size: 10),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Text('FILTER SERVICE CATEGORY:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: kv.muted)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        color: kv.isDark ? Kv.s950 : Kv.s50, borderRadius: BorderRadius.circular(16), border: Border.all(color: kv.border)),
                    child: Row(children: [
                      _ModeBtn(label: 'Orbital Radar 🪐', selected: !_map, gradient: true, onTap: () => setState(() => _map = false)),
                      _ModeBtn(label: 'GPS Map 🗺️', selected: _map, onTap: () => setState(() => _map = true)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      _CatChip(
                        label: 'All services',
                        icon: Icons.apps_rounded,
                        selected: _categoryId == null,
                        onTap: () => setState(() {
                          _categoryId = null;
                          _dataKey = UniqueKey();
                        }),
                      ),
                      for (final c in d.categories)
                        _CatChip(
                          label: c.name,
                          icon: categoryIcon(c.code),
                          color: Kv.named(c.color),
                          selected: _categoryId == c.id,
                          onTap: () => setState(() {
                            _categoryId = c.id;
                            _dataKey = UniqueKey();
                          }),
                        ),
                    ]),
                  ),
                  if (_categoryId != null) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (_) {
                      final c = d.categories.where((c) => c.id == _categoryId).firstOrNull;
                      if (c == null) return const SizedBox.shrink();
                      return Text('${c.rwName} • from ${Fmt.money(c.basePrice)} ${c.priceUnit}',
                          style: TextStyle(fontSize: 12, color: kv.muted, fontStyle: FontStyle.italic));
                    }),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              KvCard(
                padding: const EdgeInsets.all(12),
                color: kv.isDark ? const Color(0xFF070D1C) : kv.card,
                child: Column(children: [
                  _map
                      ? StreetMap(
                          center: loc,
                          radiusKm: radius,
                          workers: inRange,
                          label: s.sector.label,
                          onTap: (w) => showWorker(context, w),
                        )
                      : OrbitalRadar(
                          center: loc,
                          radiusKm: radius,
                          workers: inRange,
                          label: s.sector.label,
                          onTap: (w) => showWorker(context, w),
                        ),
                  const SizedBox(height: 8),
                  Row(children: [
                    MonoTag('${online.length} online', icon: Icons.circle, size: 10.5),
                    const SizedBox(width: 6),
                    MonoTag('${inRange.length} within ${radius.round()} km', color: Kv.blueLight, size: 10.5),
                    const Spacer(),
                    Text('Tap a dot', style: TextStyle(fontSize: 11, color: kv.faint)),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              if (inRange.isEmpty)
                EmptyState(
                  icon: Icons.travel_explore_rounded,
                  title: 'No providers in ${radius.round()} km',
                  message: 'Increase the radius or choose another category.',
                  action: radius < 25 ? KvButton(label: 'Search 25 km', expand: false, onPressed: () => s.setRadius(25)) : null,
                )
              else ...[
                SectionTitle('Nearby providers', icon: Icons.near_me_rounded, subtitle: 'Sorted by distance from ${s.sector.name}'),
                const SizedBox(height: 10),
                for (final w in inRange) _WorkerTile(worker: w),
              ],
              const SizedBox(height: 14),
              KvCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Top Performing Service Providers',
                      icon: Icons.star_rounded,
                      color: Kv.amber,
                      subtitle: 'Highest-rated Kigali service staff backed by company guarantees & KV-ID badges'),
                  const SizedBox(height: 10),
                  const MonoTag('Top Verified Staff', size: 12),
                  const SizedBox(height: 8),
                  for (final w in d.top) _WorkerTile(worker: w, compact: true),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeBtn extends StatelessWidget {
  const _ModeBtn({required this.label, required this.selected, required this.onTap, this.gradient = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: gradient ? const [Kv.pink, Kv.purple] : const [Kv.blue, Kv.sky])
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: selected ? Colors.white : kv.muted)),
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({required this.label, required this.icon, required this.selected, required this.onTap, this.color = Kv.emerald});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? fade(color, 0.16) : (kv.isDark ? Kv.s950 : Kv.s50),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? color : kv.border),
          ),
          child: Row(children: [
            Icon(icon, size: 17, color: selected ? color : kv.muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: selected ? kv.text : kv.muted)),
          ]),
        ),
      ),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({required this.worker, this.compact = false});
  final Worker worker;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final kv = context.kv;
    final w = worker;
    final color = Kv.named(w.categoryColor);
    final row = Row(children: [
      Avatar(name: w.name, path: w.photo, color: color, online: w.online),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(w.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: kv.text)),
          Text(w.serviceName, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: kv.muted)),
          const SizedBox(height: 4),
          Row(children: [
            RatingStars(w.rating, size: 11.5),
            const SizedBox(width: 8),
            if (w.badgeId.isNotEmpty)
              Flexible(child: Text(w.badgeId, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: Kv.mono, fontSize: 10.5, color: Kv.amberLight))),
          ]),
        ]),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(Fmt.compact(w.price), style: TextStyle(fontFamily: Kv.mono, fontWeight: FontWeight.w900, color: color)),
        Text(w.distanceKm == null ? '' : Fmt.km(w.distanceKm!), style: TextStyle(fontSize: 11, color: kv.faint)),
      ]),
    ]);
    if (compact) {
      return InkWell(
        onTap: () => showWorker(context, w),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: row),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KvCard(padding: const EdgeInsets.all(12), radius: 18, onTap: () => showWorker(context, w), child: row),
    );
  }
}
