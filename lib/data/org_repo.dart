import '../core/db.dart';
import '../core/format.dart';
import 'booking_repo.dart';
import 'catalog_repo.dart';
import 'models.dart';
import 'notify.dart';

class Stats {
  Stats(this.values);
  final Map<String, num> values;
  num operator [](String k) => values[k] ?? 0;
}

/// Company (entity) admin features.
class CompanyRepo {
  CompanyRepo._();

  static const _companySql = '''
SELECT e.*, (SELECT COUNT(*) FROM provider_profiles pp WHERE pp.entity_id = e.id AND pp.deleted_at IS NULL
             AND pp.verification_status = 'approved') AS workers
FROM entities e WHERE e.deleted_at IS NULL''';

  static Future<Company?> company(String entityId) async {
    final r = await AppDb.one('$_companySql AND e.id = ?', [entityId]);
    return r == null ? null : Company.fromRow(r);
  }

  static Future<List<Worker>> workers(String entityId) async {
    final rows = await AppDb.query(
        "${CatalogRepo.workerSql()} AND pp.entity_id = ? AND pp.verification_status != 'pending' ORDER BY pp.is_active DESC, u.first_name",
        [entityId]);
    return rows.map(Worker.fromRow).toList();
  }

  static Future<List<Application>> applications(String entityId, {bool pendingOnly = true}) async {
    final rows = await AppDb.query(
        'SELECT a.*, e.business_name AS company_name FROM provider_applications a LEFT JOIN entities e ON e.id = a.entity_id '
        'WHERE a.entity_id = ? AND a.deleted_at IS NULL ${pendingOnly ? "AND a.status = 'pending'" : ''} ORDER BY a.created_at DESC',
        [entityId]);
    return rows.map(Application.new).toList();
  }

  static Future<Stats> stats(String entityId) async {
    final r = await AppDb.one('''
SELECT
  (SELECT COUNT(*) FROM provider_profiles WHERE entity_id = ? AND verification_status = 'approved' AND deleted_at IS NULL) AS workers,
  (SELECT COUNT(*) FROM provider_profiles WHERE entity_id = ? AND verification_status = 'approved' AND is_active = 1) AS online,
  (SELECT COUNT(*) FROM provider_applications WHERE entity_id = ? AND status = 'pending') AS pending,
  (SELECT COUNT(*) FROM bookings b JOIN provider_profiles pp ON pp.id = b.provider_id WHERE pp.entity_id = ?) AS bookings,
  (SELECT COUNT(*) FROM bookings b JOIN provider_profiles pp ON pp.id = b.provider_id WHERE pp.entity_id = ? AND b.status IN ('pending','accepted','in_progress')) AS active,
  (SELECT COUNT(*) FROM bookings b JOIN provider_profiles pp ON pp.id = b.provider_id WHERE pp.entity_id = ? AND b.status = 'completed') AS completed,
  (SELECT COALESCE(SUM(b.total_amount),0) FROM bookings b JOIN provider_profiles pp ON pp.id = b.provider_id WHERE pp.entity_id = ? AND b.status = 'completed') AS gross,
  (SELECT COALESCE(SUM(b.provider_earnings),0) FROM bookings b JOIN provider_profiles pp ON pp.id = b.provider_id WHERE pp.entity_id = ? AND b.status = 'completed') AS net,
  (SELECT COALESCE(SUM(b.provider_earnings),0) FROM bookings b JOIN provider_profiles pp ON pp.id = b.provider_id WHERE pp.entity_id = ? AND b.payout_status = 'completed') AS paid_out,
  (SELECT COALESCE(AVG(average_rating),0) FROM provider_profiles WHERE entity_id = ? AND verification_status = 'approved' AND average_rating > 0) AS rating
''', List.filled(10, entityId));
    return Stats({for (final e in (r ?? const <String, Object?>{}).entries) e.key: (e.value is num ? e.value as num : 0)});
  }

  static Future<void> approve(Application a, String reviewerId) async {
    final now = AppDb.now();
    await AppDb.update('provider_applications', a.id, {'status': 'approved', 'reviewed_at': now, 'reviewed_by_id': reviewerId});
    if (a.userId == null) return;
    final p = await AppDb.one('SELECT id FROM provider_profiles WHERE user_id = ?', [a.userId]);
    if (p != null) {
      await AppDb.update('provider_profiles', p.s('id'), {
        'is_verified': 1,
        'verification_status': 'approved',
        'verified_at': now,
        'verified_by_entity': 1,
        'entity_verified_at': now,
      });
    }
    await AppDb.update('users', a.userId!, {'is_active': 1});
    final badge = p == null ? null : await AppDb.scalar('SELECT badge_id FROM kv_badges WHERE provider_id = ?', [p.s('id')]);
    await Notify.send(a.userId!, 'application_approved', 'Badge approved 🎉',
        '${a.companyName} approved your application. Sign in with badge ${badge ?? ''} and go online to receive dispatches.',
        priority: 'high');
  }

  static Future<void> reject(Application a, String reviewerId, String reason) async {
    await AppDb.update('provider_applications', a.id,
        {'status': 'rejected', 'rejection_reason': reason, 'reviewed_at': AppDb.now(), 'reviewed_by_id': reviewerId});
    if (a.userId == null) return;
    final p = await AppDb.one('SELECT id FROM provider_profiles WHERE user_id = ?', [a.userId]);
    if (p != null) await AppDb.update('provider_profiles', p.s('id'), {'verification_status': 'rejected', 'is_verified': 0, 'is_active': 0});
    await Notify.send(a.userId!, 'application_rejected', 'Application not approved', reason.isEmpty ? 'Contact ${a.companyName}.' : reason);
  }

  /// Suspend ("mute") or reactivate a worker.
  static Future<void> setWorkerSuspended(Worker w, bool suspended) async {
    await AppDb.update('provider_profiles', w.profileId, {
      'verification_status': suspended ? 'suspended' : 'approved',
      'is_verified': suspended ? 0 : 1,
      if (suspended) 'is_active': 0,
    });
    await Notify.send(
        w.userId,
        'system',
        suspended ? 'Badge suspended' : 'Badge reactivated',
        suspended
            ? 'Your company suspended badge ${w.badgeId}. You will not receive dispatches.'
            : 'Badge ${w.badgeId} is active again. Go online to receive dispatches.',
        priority: 'high');
  }

  static Future<void> updateCompany(String entityId,
      {required String phone, required String email, required String address, required String payout, required String description}) async {
    await AppDb.update('entities', entityId, {
      'official_phone': phone.trim(),
      'official_email': email.trim(),
      'physical_address': address.trim(),
      'payout_account_number': payout.trim(),
      'bank_name': payout.split('•').first.trim(),
      'business_description': description.trim(),
    });
  }

  static Future<void> setServicePrice(String serviceId, double price) =>
      AppDb.update('provider_services', serviceId, {'price': price});
}

/// KoraVuba HQ (platform admin) features.
class AdminRepo {
  AdminRepo._();

  static Future<Stats> stats() async {
    final r = await AppDb.one('''
SELECT
  (SELECT COALESCE(SUM(total_amount),0) FROM bookings WHERE status = 'completed') AS gmv,
  (SELECT COALESCE(SUM(platform_fee),0) FROM bookings WHERE status = 'completed') AS fees,
  (SELECT COALESCE(SUM(provider_earnings),0) FROM bookings WHERE status = 'completed') AS net,
  (SELECT COALESCE(SUM(provider_earnings),0) FROM bookings WHERE status = 'completed' AND payout_status != 'completed') AS payout_due,
  (SELECT COUNT(*) FROM bookings) AS bookings,
  (SELECT COUNT(*) FROM bookings WHERE status IN ('pending','accepted','in_progress')) AS active,
  (SELECT COUNT(*) FROM bookings WHERE status = 'completed') AS completed,
  (SELECT COUNT(*) FROM entities WHERE status IN ('active','verified') AND deleted_at IS NULL) AS companies,
  (SELECT COUNT(*) FROM entities WHERE deleted_at IS NULL) AS companies_all,
  (SELECT COUNT(*) FROM entities WHERE status IN ('pending','draft') AND deleted_at IS NULL) AS companies_pending,
  (SELECT COUNT(*) FROM provider_profiles WHERE verification_status = 'approved' AND deleted_at IS NULL) AS workers,
  (SELECT COUNT(*) FROM provider_profiles WHERE verification_status = 'pending' AND deleted_at IS NULL) AS workers_pending,
  (SELECT COUNT(*) FROM provider_profiles WHERE verification_status = 'approved' AND is_active = 1) AS online,
  (SELECT COUNT(*) FROM users WHERE user_type = 'client') AS clients,
  (SELECT COUNT(*) FROM users) AS users,
  (SELECT COUNT(*) FROM kv_sos_alerts WHERE status = 'open') AS sos,
  (SELECT COUNT(*) FROM disputes WHERE status IN ('pending','investigating','escalated')) AS disputes,
  (SELECT COALESCE(SUM(subscription_fee),0) FROM entities WHERE status = 'active') AS subscriptions
''');
    return Stats({for (final e in (r ?? const <String, Object?>{}).entries) e.key: (e.value is num ? e.value as num : 0)});
  }

  static Future<List<Company>> companies() async {
    final rows = await AppDb.query('${CompanyRepo._companySql} ORDER BY CASE e.status WHEN \'pending\' THEN 0 ELSE 1 END, e.created_at DESC');
    return rows.map(Company.fromRow).toList();
  }

  static Future<String> _nextCompanyCode() async {
    final rows = await AppDb.query("SELECT company_id FROM entities WHERE company_id LIKE 'KV-COMP-%'");
    var max = 100;
    for (final r in rows) {
      final n = int.tryParse(r.s('company_id').replaceFirst('KV-COMP-', ''));
      if (n != null && n > max) max = n;
    }
    return 'KV-COMP-${max + 1}';
  }

  static Future<String> approveCompany(Company c, String adminId) async {
    final code = c.code.isEmpty ? await _nextCompanyCode() : c.code;
    final now = DateTime.now();
    await AppDb.update('entities', c.id, {
      'status': 'active',
      'company_id': code,
      'verified_at': AppDb.now(),
      'verified_by_id': adminId,
      'payment_confirmed': 1,
      'payment_confirmed_at': AppDb.now(),
      'subscription_start': AppDb.now(),
      'subscription_end': AppDb.now(now.add(const Duration(days: 30))),
    });
    final admins = await AppDb.query('SELECT user_id FROM entity_admins WHERE entity_id = ?', [c.id]);
    for (final a in admins) {
      await Notify.send(a.s('user_id'), 'application_approved', 'Company verified ✅',
          '${c.name} is live on KoraVuba. Your Company ID is $code — share it with your workers so they can register.',
          priority: 'high');
    }
    return code;
  }

  static Future<void> setCompanyStatus(Company c, String status, {String reason = ''}) async {
    await AppDb.update('entities', c.id, {'status': status, if (reason.isNotEmpty) 'rejection_reason': reason});
    if (status == 'suspended' || status == 'rejected') {
      await AppDb.db.rawUpdate("UPDATE provider_profiles SET is_active = 0 WHERE entity_id = ?", [c.id]);
    }
    final admins = await AppDb.query('SELECT user_id FROM entity_admins WHERE entity_id = ?', [c.id]);
    for (final a in admins) {
      await Notify.send(a.s('user_id'), 'system', 'Company ${Fmt.title(status)}',
          reason.isEmpty ? '${c.name} is now ${Fmt.title(status).toLowerCase()}.' : reason,
          priority: 'high');
    }
  }

  static Future<List<Worker>> workers() async {
    final rows = await AppDb.query('${CatalogRepo.workerSql()} ORDER BY pp.verification_status, pp.average_rating DESC');
    return rows.map(Worker.fromRow).toList();
  }

  static Future<List<AppUser>> users({String? type}) async {
    final rows = await AppDb.query(
        'SELECT u.*, up.bio FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id WHERE u.deleted_at IS NULL '
        '${type == null ? '' : 'AND u.user_type = ?'} ORDER BY u.created_at DESC',
        [if (type != null) type]);
    return rows.map(AppUser.fromRow).toList();
  }

  static Future<void> setUserActive(String userId, bool active) => AppDb.update('users', userId, {'is_active': active ? 1 : 0});

  static Future<List<Txn>> transactions({int limit = 300}) async => (await AppDb.query('''
SELECT t.*, b.booking_number, cu.first_name AS client_first, cu.last_name AS client_last, pp.business_name AS provider_name
FROM transactions t
LEFT JOIN bookings b ON b.id = t.booking_id
LEFT JOIN users cu ON cu.id = t.client_id
LEFT JOIN provider_profiles pp ON pp.id = t.provider_id
WHERE t.deleted_at IS NULL ORDER BY t.created_at DESC LIMIT ?''', [limit])).map(Txn.new).toList();

  /// The "19:00 batch payout": pays the company/provider share of every
  /// completed, fully-paid booking that has not been paid out yet.
  static Future<(int, double)> runPayout(String adminId) async {
    final rows = await AppDb.query(
        "SELECT * FROM bookings WHERE status = 'completed' AND payment_status = 'paid' AND COALESCE(payout_status, 'pending') != 'completed'");
    var total = 0.0;
    for (final b in rows) {
      final amount = b.d('provider_earnings');
      total += amount;
      await AppDb.insert('transactions', {
        'transaction_id': 'PAYOUT-${DateTime.now().millisecondsSinceEpoch}-${b.s('booking_number').hashCode.abs() % 10000}',
        'transaction_type': 'payout',
        'amount': amount,
        'platform_fee': 0,
        'provider_amount': amount,
        'tax_amount': 0,
        'currency': 'RWF',
        'status': 'completed',
        'gateway': 'bank_transfer',
        'gateway_transaction_id': 'BATCH-${DateTime.now().millisecondsSinceEpoch}',
        'gateway_response': '{"batch":"19:00"}',
        'receipt_url': '',
        'invoice_url': '',
        'processed_at': AppDb.now(),
        'booking_id': b.s('id'),
        'client_id': b.s('client_id'),
        'provider_id': b.s('provider_id'),
      });
      await AppDb.update('bookings', b.s('id'), {'payout_status': 'completed', 'paid_out_at': AppDb.now()});
    }
    return (rows.length, total);
  }

  static Future<List<SosAlert>> sosAlerts() async => (await AppDb.query('''
SELECT s.*, b.booking_number, u.first_name, u.last_name, u.phone FROM kv_sos_alerts s
LEFT JOIN bookings b ON b.id = s.booking_id LEFT JOIN users u ON u.id = s.raised_by_id
ORDER BY CASE s.status WHEN 'open' THEN 0 ELSE 1 END, s.created_at DESC''')).map(SosAlert.new).toList();

  static Future<void> resolveSos(String id) async {
    await AppDb.db.update('kv_sos_alerts', {'status': 'resolved', 'resolved_at': AppDb.now()}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Dispute>> disputes() async => (await AppDb.query('''
SELECT d.*, b.booking_number, u.first_name, u.last_name FROM disputes d
LEFT JOIN bookings b ON b.id = d.booking_id LEFT JOIN users u ON u.id = d.raised_by_id
WHERE d.deleted_at IS NULL ORDER BY d.created_at DESC''')).map(Dispute.new).toList();

  static Future<void> resolveDispute(Dispute d, String adminId, String status, String notes) async {
    await AppDb.update('disputes', d.id, {
      'status': status,
      'resolution_notes': notes,
      'resolved_at': AppDb.now(),
      'resolved_by_id': adminId,
    });
    final raisedBy = await AppDb.scalar('SELECT raised_by_id FROM disputes WHERE id = ?', [d.id]);
    if (raisedBy != null) {
      await Notify.send('$raisedBy', 'dispute_resolved', 'Dispute ${Fmt.title(status).toLowerCase()}',
          '"${d.title}" — ${notes.isEmpty ? 'closed by KoraVuba support' : notes}');
    }
  }

  static Future<Map<String, String>> settings() async {
    final rows = await AppDb.query('SELECT key, value FROM kv_settings');
    return {for (final r in rows) r.s('key'): r.s('value')};
  }

  static Future<void> saveSetting(String key, String value) => AppDb.setting(key, value);

  static Future<int> pendingSync() async => (await AppDb.number('SELECT COUNT(*) FROM kv_sync_log')).toInt();

  static Future<double> commission() => BookingRepo.commissionPercent();
}
