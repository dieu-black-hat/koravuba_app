import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/db.dart';
import 'models.dart';

/// Notifications (`notifications` table) — written for every action, the
/// same way the Django web app does.
class Notify {
  Notify._();

  static Future<void> send(
    String userId,
    String type,
    String title,
    String message, {
    String priority = 'medium',
    String? relatedId,
    String? relatedType,
    DatabaseExecutor? tx,
  }) async {
    await AppDb.insert(
      'notifications',
      {
        'user_id': userId,
        'notification_type': type,
        'title': title,
        'message': message,
        'data': jsonEncode({'source': 'mobile'}),
        'is_read': 0,
        'is_email_sent': 0,
        'is_push_sent': 0,
        'is_sms_sent': 0,
        'action_url': '',
        'is_broadcast': 0,
        'priority': priority,
        'related_object_id': relatedId ?? '',
        'related_object_type': relatedType ?? '',
        'target_user_type': '',
      },
      tx: tx,
    );
  }

  static Future<void> admins(String type, String title, String message, {String priority = 'medium', DatabaseExecutor? tx}) async {
    final ex = tx ?? AppDb.db;
    final rows = await ex.rawQuery("SELECT id FROM users WHERE (user_type = 'admin' OR is_superuser = 1) AND is_active = 1");
    for (final r in rows) {
      await send(r.s('id'), type, title, message, priority: priority, tx: tx);
    }
  }

  static Future<void> companyAdmins(String? entityId, String type, String title, String message,
      {String priority = 'medium', DatabaseExecutor? tx}) async {
    if (entityId == null || entityId.isEmpty) return;
    final ex = tx ?? AppDb.db;
    final rows = await ex.rawQuery('SELECT user_id FROM entity_admins WHERE entity_id = ?', [entityId]);
    for (final r in rows) {
      await send(r.s('user_id'), type, title, message, priority: priority, tx: tx);
    }
  }

  static Future<List<Notice>> list(String userId) async {
    final rows = await AppDb.query(
        'SELECT * FROM notifications WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 200', [userId]);
    return rows.map(Notice.new).toList();
  }

  static Future<int> unread(String userId) async =>
      (await AppDb.number('SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = 0 AND deleted_at IS NULL', [userId]))
          .toInt();

  static Future<void> markRead(String id) =>
      AppDb.update('notifications', id, {'is_read': 1, 'read_at': AppDb.now()});

  static Future<void> markAllRead(String userId) async {
    await AppDb.db.update('notifications', {'is_read': 1, 'read_at': AppDb.now()},
        where: 'user_id = ? AND is_read = 0', whereArgs: [userId]);
  }

  static Future<void> clearAll(String userId) async {
    await AppDb.db.update('notifications', {'deleted_at': AppDb.now()}, where: 'user_id = ? AND deleted_at IS NULL', whereArgs: [userId]);
  }
}
