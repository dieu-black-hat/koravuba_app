import '../core/db.dart';
import '../core/geo.dart';
import 'models.dart';

/// Categories, workers (providers) and reviews.
class CatalogRepo {
  CatalogRepo._();

  static Future<List<Category>> categories({bool includeHidden = false}) async {
    final rows = await AppDb.query(
        'SELECT sc.*, m.code, m.kinyarwanda_name, m.base_price, m.price_unit, m.color FROM service_categories sc '
        'LEFT JOIN kv_category_meta m ON m.category_id = sc.id WHERE sc.deleted_at IS NULL '
        '${includeHidden ? '' : 'AND sc.is_active = 1 '}ORDER BY sc.sort_order, sc.name');
    return rows.map(Category.fromRow).toList();
  }

  /// HQ: create a service category (`service_categories` + `kv_category_meta`).
  static Future<void> createCategory({
    required String name,
    required String rwName,
    required String type,
    required String description,
    required double basePrice,
    required String priceUnit,
    required String color,
  }) async {
    var code = type;
    var n = 2;
    while (await AppDb.one('SELECT code FROM kv_category_meta WHERE code = ?', [code]) != null) {
      code = '${type}_${n++}';
    }
    var slug = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    if (slug.isEmpty) slug = code;
    if (await AppDb.one('SELECT id FROM service_categories WHERE slug = ?', [slug]) != null) slug = '$slug-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final order = (await AppDb.number('SELECT COALESCE(MAX(sort_order), -1) + 1 FROM service_categories')).toInt();
    final id = await AppDb.insert('service_categories', {
      'name': name.trim(),
      'slug': slug,
      'icon': type,
      'image': '',
      'description': description.trim(),
      'sort_order': order,
      'is_active': 1,
      'parent_id': null,
    });
    await AppDb.db.insert('kv_category_meta', {
      'category_id': id,
      'code': code,
      'kinyarwanda_name': rwName.trim(),
      'base_price': basePrice,
      'price_unit': priceUnit.trim(),
      'color': color,
    });
  }

  static Future<void> updateCategory(Category c,
      {required String name, required String rwName, required String description, required double basePrice, required String priceUnit, required String color}) async {
    await AppDb.update('service_categories', c.id, {'name': name.trim(), 'description': description.trim()});
    await AppDb.db.update('kv_category_meta',
        {'kinyarwanda_name': rwName.trim(), 'base_price': basePrice, 'price_unit': priceUnit.trim(), 'color': color},
        where: 'category_id = ?', whereArgs: [c.id]);
  }

  static Future<void> setCategoryActive(Category c, bool active) => AppDb.update('service_categories', c.id, {'is_active': active ? 1 : 0});

  static String workerSql({String? categoryId}) => '''
SELECT pp.id AS profile_id, pp.user_id, pp.business_name, pp.business_description, pp.phone, pp.average_rating,
       pp.total_reviews, pp.total_jobs_completed, pp.latitude, pp.longitude, pp.is_active, pp.is_verified,
       pp.verification_status, pp.entity_id, pp.total_earnings,
       u.first_name, u.last_name, u.email, u.phone AS user_phone, u.profile_image,
       b.badge_id, e.business_name AS company_name, e.company_id AS company_code,
       ps.id AS service_id, ps.name AS service_name, ps.price, ps.price_unit, ps.description AS service_description,
       ps.category_id, sc.name AS category_name, m.color AS category_color
FROM provider_profiles pp
JOIN users u ON u.id = pp.user_id
LEFT JOIN kv_badges b ON b.provider_id = pp.id
LEFT JOIN entities e ON e.id = pp.entity_id
LEFT JOIN provider_services ps ON ps.id = (
    SELECT x.id FROM provider_services x WHERE x.provider_id = pp.id AND x.deleted_at IS NULL
    ${categoryId == null ? '' : "AND x.category_id = '${categoryId.replaceAll("'", "")}'"}
    ORDER BY x.is_active DESC, x.created_at LIMIT 1)
LEFT JOIN service_categories sc ON sc.id = ps.category_id
LEFT JOIN kv_category_meta m ON m.category_id = sc.id
WHERE pp.deleted_at IS NULL''';

  /// Workers clients can book: approved, active user, has a service.
  static Future<List<Worker>> bookable({String? categoryId, LatLng? from}) async {
    final rows = await AppDb.query(
      '${workerSql(categoryId: categoryId)} AND pp.is_verified = 1 AND pp.verification_status = ? AND u.is_active = 1 AND ps.id IS NOT NULL '
      '${categoryId == null ? '' : 'AND ps.category_id = ?'} ORDER BY pp.is_active DESC, pp.average_rating DESC',
      ['approved', if (categoryId != null) categoryId],
    );
    return _withDistance(rows.map(Worker.fromRow).toList(), from);
  }

  static List<Worker> _withDistance(List<Worker> list, LatLng? from) {
    if (from != null) {
      for (final w in list) {
        if (w.lat != null && w.lng != null) w.distanceKm = distanceKm(from.lat, from.lng, w.lat!, w.lng!);
      }
    }
    return list;
  }

  static Future<Worker?> worker(String profileId, {LatLng? from}) async {
    final r = await AppDb.one('${workerSql()} AND pp.id = ?', [profileId]);
    if (r == null) return null;
    return _withDistance([Worker.fromRow(r)], from).first;
  }

  static Future<List<Worker>> topRated({int limit = 6, LatLng? from}) async {
    final rows = await AppDb.query(
      '${workerSql()} AND pp.is_verified = 1 AND pp.verification_status = ? AND u.is_active = 1 AND ps.id IS NOT NULL '
      'ORDER BY pp.average_rating DESC, pp.total_jobs_completed DESC LIMIT ?',
      ['approved', limit],
    );
    return _withDistance(rows.map(Worker.fromRow).toList(), from);
  }

  static Future<List<Review>> reviews(String profileId) async {
    final rows = await AppDb.query(
        'SELECT r.*, u.first_name, u.last_name FROM reviews r LEFT JOIN users u ON u.id = r.reviewer_id '
        'WHERE r.reviewee_id = ? AND r.deleted_at IS NULL ORDER BY r.created_at DESC LIMIT 50',
        [profileId]);
    return rows.map(Review.new).toList();
  }
}
