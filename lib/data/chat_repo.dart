import '../core/db.dart';
import 'models.dart';
import 'notify.dart';

/// Chat (`chat_conversations` + `chat_messages`): one conversation per
/// client / provider pair, as on the web app.
class ChatRepo {
  ChatRepo._();

  static Future<String> ensureConversation(String clientId, String providerProfileId) async {
    final r = await AppDb.one(
        'SELECT id FROM chat_conversations WHERE client_id = ? AND provider_id = ? AND deleted_at IS NULL', [clientId, providerProfileId]);
    if (r != null) return r.s('id');
    return AppDb.insert('chat_conversations', {
      'client_id': clientId,
      'provider_id': providerProfileId,
      'is_blocked': 0,
      'last_message': '',
      'last_message_at': AppDb.now(),
    });
  }

  /// Conversations for a client (by user id) or a worker (by profile id).
  static Future<List<Conversation>> list({required String userId, String? providerProfileId}) async {
    final asProvider = providerProfileId != null;
    final rows = await AppDb.query('''
SELECT c.*, cu.first_name AS c_first, cu.last_name AS c_last, cu.profile_image AS c_photo, cu.phone AS c_phone,
       pu.first_name AS p_first, pu.last_name AS p_last, pu.profile_image AS p_photo, pu.phone AS p_phone,
       kb.badge_id, e.business_name AS company_name,
       (SELECT COUNT(*) FROM chat_messages m WHERE m.conversation_id = c.id AND m.sender_id != ? AND m.is_read = 0 AND COALESCE(m.is_deleted, 0) = 0) AS unread
FROM chat_conversations c
JOIN users cu ON cu.id = c.client_id
JOIN provider_profiles pp ON pp.id = c.provider_id
JOIN users pu ON pu.id = pp.user_id
LEFT JOIN kv_badges kb ON kb.provider_id = pp.id
LEFT JOIN entities e ON e.id = pp.entity_id
WHERE c.deleted_at IS NULL AND ${asProvider ? 'c.provider_id = ?' : 'c.client_id = ?'}
ORDER BY c.last_message_at DESC''', [userId, asProvider ? providerProfileId : userId]);
    return rows.map((r) {
      final otherName = asProvider ? '${r.s('c_first')} ${r.s('c_last')}'.trim() : '${r.s('p_first')} ${r.s('p_last')}'.trim();
      return Conversation(
        id: r.s('id'),
        otherName: otherName.isEmpty ? 'KoraVuba user' : otherName,
        otherPhoto: asProvider ? r.s('c_photo') : r.s('p_photo'),
        otherPhone: asProvider ? r.s('c_phone') : r.s('p_phone'),
        subtitle: asProvider ? 'Client' : [r.s('badge_id'), r.s('company_name')].where((e) => e.isNotEmpty).join(' • '),
        lastMessage: r.s('last_message'),
        lastAt: r.dt('last_message_at'),
        unread: r.i('unread'),
        clientId: r.s('client_id'),
        providerId: r.s('provider_id'),
      );
    }).toList();
  }

  static Future<int> unreadTotal({required String userId, String? providerProfileId}) async {
    final asProvider = providerProfileId != null;
    return (await AppDb.number(
      'SELECT COUNT(*) FROM chat_messages m JOIN chat_conversations c ON c.id = m.conversation_id '
      'WHERE ${asProvider ? 'c.provider_id = ?' : 'c.client_id = ?'} AND m.sender_id != ? AND m.is_read = 0 AND COALESCE(m.is_deleted, 0) = 0',
      [asProvider ? providerProfileId : userId, userId],
    ))
        .toInt();
  }

  static Future<List<Message>> messages(String conversationId) async => (await AppDb.query(
          'SELECT * FROM chat_messages WHERE conversation_id = ? AND COALESCE(is_deleted, 0) = 0 ORDER BY created_at', [conversationId]))
      .map(Message.new)
      .toList();

  static Future<void> markRead(String conversationId, String readerId) async {
    await AppDb.db.update('chat_messages', {'is_read': 1, 'read_at': AppDb.now()},
        where: 'conversation_id = ? AND sender_id != ? AND is_read = 0', whereArgs: [conversationId, readerId]);
  }

  static Future<void> send(String conversationId, String senderId, String text, {String type = 'text'}) async {
    final now = AppDb.now();
    await AppDb.insert('chat_messages', {
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': text,
      'message_type': type,
      'media_file': '',
      'media_url': '',
      'media_name': '',
      'is_read': 0,
      'deleted_for_receiver': 0,
      'deleted_for_sender': 0,
      'metadata': '{}',
      'edit_count': 0,
      'edit_history': '[]',
      'is_deleted': 0,
      'is_edited': 0,
      'original_content': '',
    });
    await AppDb.update('chat_conversations', conversationId, {
      'last_message': text.length > 120 ? '${text.substring(0, 120)}…' : text,
      'last_message_at': now,
      'last_message_sender_id': senderId,
    });
    if (type != 'text') return;
    final c = await AppDb.one(
        'SELECT c.client_id, pp.user_id AS provider_user_id, s.first_name, s.last_name FROM chat_conversations c '
        'JOIN provider_profiles pp ON pp.id = c.provider_id JOIN users s ON s.id = ? WHERE c.id = ?',
        [senderId, conversationId]);
    if (c == null) return;
    final to = c.s('client_id') == senderId ? c.s('provider_user_id') : c.s('client_id');
    await Notify.send(to, 'new_message', 'New message from ${c.s('first_name')} ${c.s('last_name')}'.trim(),
        text.length > 90 ? '${text.substring(0, 90)}…' : text,
        relatedId: conversationId, relatedType: 'conversation');
  }

  static Future<void> deleteMessage(String id, String byUserId) =>
      AppDb.update('chat_messages', id, {'is_deleted': 1, 'deleted_by_id': byUserId});
}
