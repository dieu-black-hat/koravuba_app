import '../core/db.dart';
import 'catalog_repo.dart';
import 'models.dart';

class WorkerRepo {
  WorkerRepo._();

  static Future<Worker?> me(String profileId) async {
    final r = await AppDb.one('${CatalogRepo.workerSql()} AND pp.id = ?', [profileId]);
    return r == null ? null : Worker.fromRow(r);
  }

  /// Online = `provider_profiles.is_active` (+ `provider_availability.is_available`), as in the web app.
  static Future<void> setOnline(String profileId, bool online) async {
    await AppDb.update('provider_profiles', profileId, {'is_active': online ? 1 : 0, 'last_active_at': AppDb.now()});
    final av = await AppDb.one('SELECT id FROM provider_availability WHERE provider_id = ?', [profileId]);
    if (av != null) await AppDb.update('provider_availability', av.s('id'), {'is_available': online ? 1 : 0});
  }

  static Future<Map<String, num>> stats(String profileId) async {
    final r = await AppDb.one('''
SELECT
  (SELECT COUNT(*) FROM bookings WHERE provider_id = ? AND status = 'pending') AS pending,
  (SELECT COUNT(*) FROM bookings WHERE provider_id = ? AND status IN ('accepted','in_progress')) AS active,
  (SELECT COUNT(*) FROM bookings WHERE provider_id = ? AND status = 'completed') AS completed,
  (SELECT COALESCE(SUM(provider_earnings),0) FROM bookings WHERE provider_id = ? AND status = 'completed') AS earned,
  (SELECT COALESCE(SUM(provider_earnings),0) FROM bookings WHERE provider_id = ? AND status = 'completed' AND date(completed_at) = date('now')) AS today
''', List.filled(5, profileId));
    return {for (final e in (r ?? const <String, Object?>{}).entries) e.key: (e.value is num ? e.value as num : 0)};
  }

  static Future<void> updateService(String serviceId, {required String description, required double price}) =>
      AppDb.update('provider_services', serviceId, {'description': description, 'price': price});
}
