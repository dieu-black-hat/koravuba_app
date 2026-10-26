import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The app's own database: a SQLite copy of `globalconnect_db` (same table
/// and column names as the Django/MySQL schema) shipped in
/// `assets/db/koravuba.db` and copied to the phone on first launch.
///
/// Every write goes through [insert] / [update] which also records the change
/// in `kv_sync_log`, so a future API sync knows exactly what to upload.
class AppDb {
  AppDb._();

  static const assetPath = 'assets/db/koravuba.db';
  static const fileName = 'koravuba.db';
  static Database? _db;

  static Database get db {
    final d = _db;
    if (d == null) throw StateError('Database not opened yet');
    return d;
  }

  static Future<String> path() async => p.join(await getDatabasesPath(), fileName);

  static Future<void> open() async {
    if (_db != null) return;
    final file = File(await path());
    if (!await file.exists()) {
      await _copyAsset(file);
    }
    final d = await openDatabase(file.path);
    // app-only tables added after the first release of the bundled database
    await d.execute('CREATE TABLE IF NOT EXISTS kv_user_settings '
        '(user_id TEXT PRIMARY KEY, momo_number TEXT, momo_network TEXT, sector TEXT)');
    _db = d;
  }

  static Future<void> _copyAsset(File file) async {
    await file.parent.create(recursive: true);
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  }

  /// Throws away every change made on this phone and restores the bundled copy.
  static Future<void> resetToBundled() async {
    await _db?.close();
    _db = null;
    final file = File(await path());
    if (await file.exists()) await file.delete();
    await open();
  }

  // ------------------------------------------------------------- helpers
  static String newId() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // uuid4 like Django's uuid.uuid4().hex
    b[8] = (b[8] & 0x3f) | 0x80;
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Timestamp in Django's MySQL format (UTC, microseconds).
  static String now([DateTime? t]) => stamp((t ?? DateTime.now()).toUtc());

  static String stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final u = t.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)} '
        '${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${(u.microsecond + u.millisecond * 1000).toString().padLeft(6, '0')}';
  }

  static DateTime? parse(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final iso = s.contains('T') ? s : s.replaceFirst(' ', 'T');
    final hasZone = iso.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(iso);
    final d = DateTime.tryParse(hasZone || iso.length <= 10 ? iso : '${iso}Z');
    return d?.toLocal();
  }

  static Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]) =>
      db.rawQuery(sql, args);

  static Future<Map<String, Object?>?> one(String sql, [List<Object?> args = const []]) async {
    final rows = await db.rawQuery(sql, args);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Object?> scalar(String sql, [List<Object?> args = const []]) async {
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty || rows.first.isEmpty) return null;
    return rows.first.values.first;
  }

  static Future<num> number(String sql, [List<Object?> args = const []]) async {
    final v = await scalar(sql, args);
    if (v is num) return v;
    return num.tryParse('$v') ?? 0;
  }

  /// Inserts a row; fills `id`, `created_at`, `updated_at` when the table has them.
  static Future<String> insert(String table, Map<String, Object?> values, {DatabaseExecutor? tx}) async {
    final ex = tx ?? db;
    final cols = await columns(table, ex);
    final row = <String, Object?>{};
    final ts = now();
    if (cols.contains('id') && !values.containsKey('id') && table != 'entity_admins') row['id'] = newId();
    if (cols.contains('created_at')) row['created_at'] = ts;
    if (cols.contains('updated_at')) row['updated_at'] = ts;
    if (cols.contains('is_active')) row['is_active'] = 1;
    row.addAll(values);
    row.removeWhere((k, _) => !cols.contains(k));
    await ex.insert(table, row);
    final id = '${row['id'] ?? ''}';
    await _log(ex, table, id, 'insert');
    return id;
  }

  static Future<void> update(String table, String id, Map<String, Object?> values, {DatabaseExecutor? tx}) async {
    final ex = tx ?? db;
    final cols = await columns(table, ex);
    final row = Map<String, Object?>.from(values);
    if (cols.contains('updated_at')) row['updated_at'] = now();
    row.removeWhere((k, _) => !cols.contains(k));
    await ex.update(table, row, where: 'id = ?', whereArgs: [id]);
    await _log(ex, table, id, 'update');
  }

  static Future<void> delete(String table, String id, {DatabaseExecutor? tx}) async {
    final ex = tx ?? db;
    await ex.delete(table, where: 'id = ?', whereArgs: [id]);
    await _log(ex, table, id, 'delete');
  }

  static Future<void> setting(String key, String value) async {
    await db.insert('kv_settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> getSetting(String key) async {
    final v = await scalar('SELECT value FROM kv_settings WHERE key = ?', [key]);
    return v?.toString();
  }

  static final Map<String, Set<String>> _cols = {};

  static Future<Set<String>> columns(String table, [DatabaseExecutor? ex]) async {
    final c = _cols[table];
    if (c != null) return c;
    final rows = await (ex ?? db).rawQuery('PRAGMA table_info("$table")');
    final set = rows.map((r) => '${r['name']}').toSet();
    _cols[table] = set;
    return set;
  }

  static Future<void> _log(DatabaseExecutor ex, String table, String id, String action) async {
    await ex.insert('kv_sync_log', {'table_name': table, 'row_id': id, 'action': action, 'created_at': now()});
  }
}

/// Small typed readers for `Map<String, Object?>` rows.
extension RowX on Map<String, Object?> {
  String s(String k) => this[k]?.toString() ?? '';
  String? sn(String k) {
    final v = this[k];
    if (v == null) return null;
    final t = v.toString();
    return t.isEmpty ? null : t;
  }

  double d(String k) {
    final v = this[k];
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  double? dn(String k) {
    final v = this[k];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  int i(String k) {
    final v = this[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  bool b(String k) {
    final v = this[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = '${v ?? ''}'.toLowerCase();
    return t == '1' || t == 'true';
  }

  DateTime? dt(String k) => AppDb.parse(this[k]);
}
