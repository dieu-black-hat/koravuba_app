import 'dart:convert';
import 'dart:math' as math;

import '../core/db.dart';
import '../core/format.dart';
import 'chat_repo.dart';
import 'models.dart';
import 'notify.dart';

class Pricing {
  Pricing({required this.servicePrice, required this.commissionPercent, required this.depositPercent});
  final double servicePrice;
  final double commissionPercent;
  final double depositPercent;

  double get total => servicePrice;
  double get platformFee => (servicePrice * commissionPercent / 100).roundToDouble();
  double get providerEarnings => total - platformFee;
  double get deposit => (total * depositPercent / 100).roundToDouble();
  double get balance => total - deposit;
}

class MomoPayment {
  MomoPayment({required this.network, required this.phone});
  final String network; // 'MTN MoMo' | 'Airtel Money'
  final String phone;
  String get gateway => network.startsWith('Airtel') ? 'airtel_money' : 'mtn_momo';
}

/// Bookings, payments (`transactions`), status history, reviews, SOS and disputes.
class BookingRepo {
  BookingRepo._();

  static Future<double> commissionPercent() async => double.tryParse(await AppDb.getSetting('platform_commission_percent') ?? '') ?? 9;
  static Future<double> depositPercent() async => double.tryParse(await AppDb.getSetting('upfront_deposit_percent') ?? '') ?? 50;

  static Future<Pricing> pricing(double servicePrice) async => Pricing(
        servicePrice: servicePrice,
        commissionPercent: await commissionPercent(),
        depositPercent: await depositPercent(),
      );

  static const baseSql = '''
SELECT b.*, cu.first_name AS client_first, cu.last_name AS client_last, cu.phone AS client_phone, cu.profile_image AS client_photo,
       pp.user_id AS provider_user_id, pp.business_name, pp.entity_id,
       pu.first_name AS provider_first, pu.last_name AS provider_last, pu.phone AS provider_phone, pu.profile_image AS provider_photo,
       kb.badge_id, e.business_name AS company_name, ps.name AS service_name, sc.name AS category_name, m.code AS category_code,
       (SELECT COALESCE(SUM(t.amount), 0) FROM transactions t WHERE t.booking_id = b.id AND t.transaction_type = 'payment' AND t.status = 'completed') AS paid_amount,
       (SELECT rv.rating FROM reviews rv WHERE rv.booking_id = b.id AND rv.deleted_at IS NULL LIMIT 1) AS review_rating
FROM bookings b
JOIN users cu ON cu.id = b.client_id
JOIN provider_profiles pp ON pp.id = b.provider_id
JOIN users pu ON pu.id = pp.user_id
LEFT JOIN kv_badges kb ON kb.provider_id = pp.id
LEFT JOIN entities e ON e.id = pp.entity_id
LEFT JOIN provider_services ps ON ps.id = b.service_id
LEFT JOIN service_categories sc ON sc.id = ps.category_id
LEFT JOIN kv_category_meta m ON m.category_id = sc.id
WHERE b.deleted_at IS NULL''';

  static Future<List<Booking>> forClient(String userId) async =>
      (await AppDb.query('$baseSql AND b.client_id = ? ORDER BY b.created_at DESC', [userId])).map(Booking.new).toList();

  static Future<List<Booking>> forProvider(String profileId) async =>
      (await AppDb.query('$baseSql AND b.provider_id = ? ORDER BY b.created_at DESC', [profileId])).map(Booking.new).toList();

  static Future<List<Booking>> forEntity(String entityId) async =>
      (await AppDb.query('$baseSql AND pp.entity_id = ? ORDER BY b.created_at DESC', [entityId])).map(Booking.new).toList();

  static Future<List<Booking>> all({int limit = 300}) async =>
      (await AppDb.query('$baseSql ORDER BY b.created_at DESC LIMIT ?', [limit])).map(Booking.new).toList();

  static Future<Booking?> byId(String id) async {
    final r = await AppDb.one('$baseSql AND b.id = ?', [id]);
    return r == null ? null : Booking(r);
  }

  static String _bookingNumber() {
    final now = DateTime.now().toUtc();
    final ts = '${now.year}${Fmt.two(now.month)}${Fmt.two(now.day)}${Fmt.two(now.hour)}${Fmt.two(now.minute)}${Fmt.two(now.second)}';
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = math.Random();
    return 'KV-$ts-${List.generate(6, (_) => chars[r.nextInt(chars.length)]).join()}';
  }

  static String _momoRef() => 'MOMO-RW-${1000000 + math.Random().nextInt(8999999)}';

  static Future<String> _txn({
    required String bookingId,
    required String clientId,
    required String providerId,
    required String type,
    required double amount,
    required double fee,
    required String gateway,
    String status = 'completed',
    Map<String, Object?> response = const {},
  }) async {
    final ref = gateway == 'bank_transfer' ? 'BANK-${DateTime.now().millisecondsSinceEpoch}' : _momoRef();
    await AppDb.insert('transactions', {
      'transaction_id': 'TXN-${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(9999).toString().padLeft(4, '0')}',
      'transaction_type': type,
      'amount': amount,
      'platform_fee': fee,
      'provider_amount': amount - fee,
      'tax_amount': 0,
      'currency': 'RWF',
      'status': status,
      'gateway': gateway,
      'gateway_transaction_id': ref,
      'gateway_response': jsonEncode(response),
      'receipt_url': '',
      'invoice_url': '',
      'processed_at': AppDb.now(),
      'booking_id': bookingId,
      'client_id': clientId,
      'provider_id': providerId,
    });
    return ref;
  }

  static Future<void> _history(String bookingId, String oldStatus, String newStatus, String byUserId, String notes) async {
    await AppDb.insert('booking_status_history', {
      'booking_id': bookingId,
      'old_status': oldStatus,
      'new_status': newStatus,
      'notes': notes,
      'changed_by_id': byUserId,
    });
  }

  /// Creates the booking after the (simulated) MoMo deposit succeeded.
  static Future<Booking> create({
    required AppUser client,
    required Worker worker,
    required DateTime when,
    required double units,
    required String address,
    required String notes,
    required double lat,
    required double lng,
    required MomoPayment payment,
  }) async {
    final p = await pricing(worker.price * units);
    final number = _bookingNumber();
    final conversationId = await ChatRepo.ensureConversation(client.id, worker.profileId);
    final linked = await AppDb.one('SELECT id FROM bookings WHERE conversation_id = ?', [conversationId]);
    final perHour = !worker.priceUnit.contains('km');
    final id = await AppDb.insert('bookings', {
      'booking_number': number,
      'scheduled_date': '${when.year}-${Fmt.two(when.month)}-${Fmt.two(when.day)}',
      'scheduled_time': '${Fmt.two(when.hour)}:${Fmt.two(when.minute)}:00',
      'duration_minutes': perHour ? math.max(15, (units * 60).round()) : 60,
      'address_line1': address,
      'address_line2': '',
      'city': 'Kigali',
      'state': '',
      'postal_code': '',
      'latitude': lat,
      'longitude': lng,
      'service_price': p.servicePrice,
      'platform_fee': p.platformFee,
      'total_amount': p.total,
      'provider_earnings': p.providerEarnings,
      'status': 'pending',
      'client_notes': notes,
      'provider_notes': '',
      'cancellation_reason': '',
      'client_id': client.id,
      'provider_id': worker.profileId,
      'service_id': worker.serviceId,
      'conversation_id': linked == null ? conversationId : null,
      'payment_status': 'processing',
      'payment_method_id': payment.gateway,
      'payout_status': 'pending',
    });
    final ref = await _txn(
      bookingId: id,
      clientId: client.id,
      providerId: worker.profileId,
      type: 'payment',
      amount: p.deposit,
      fee: (p.deposit * p.commissionPercent / 100).roundToDouble(),
      gateway: payment.gateway,
      response: {'phone': payment.phone, 'network': payment.network, 'kind': 'deposit'},
    );
    await AppDb.update('bookings', id, {'payment_intent_id': ref});
    await _history(id, '', 'pending', client.id, 'Booking created from the mobile app');
    await ChatRepo.send(conversationId, client.id,
        '📋 Booking $number: ${worker.serviceName} on ${Fmt.dateTime(when)} at $address. Deposit ${Fmt.money(p.deposit)} paid.',
        type: 'system');
    await Notify.send(worker.userId, 'new_booking', 'New dispatch request',
        '${client.fullName} booked ${worker.serviceName} for ${Fmt.dateTime(when)} ($address).',
        priority: 'high', relatedId: id, relatedType: 'booking');
    await Notify.send(client.id, 'booking_created', 'Payment confirmed',
        '${payment.network} transaction $ref for ${Fmt.money(p.deposit)} (50% deposit). ${worker.name} has been notified.',
        relatedId: id, relatedType: 'booking');
    await Notify.companyAdmins(worker.entityId, 'new_booking', 'New booking for ${worker.name}',
        '$number • ${worker.serviceName} • ${Fmt.money(p.total)}');
    return (await byId(id))!;
  }

  static Future<void> setStatus(Booking b, String status, String byUserId, {String reason = ''}) async {
    final now = AppDb.now();
    final values = <String, Object?>{'status': status};
    switch (status) {
      case 'accepted':
        values['accepted_at'] = now;
      case 'in_progress':
        values['started_at'] = now;
      case 'completed':
        values['completed_at'] = now;
      default:
        if (status.startsWith('cancelled')) {
          values['cancelled_at'] = now;
          values['cancelled_by_id'] = byUserId;
          values['cancellation_reason'] = reason;
        }
    }
    await AppDb.update('bookings', b.id, values);
    await _history(b.id, b.status, status, byUserId, reason);

    final label = Fmt.title(status);
    switch (status) {
      case 'accepted':
        await Notify.send(b.clientId, 'booking_status', 'Provider en route',
            '${b.providerName} (${b.badgeId}) accepted ${b.number} and is on the way.', relatedId: b.id, relatedType: 'booking');
      case 'in_progress':
        await Notify.send(b.clientId, 'booking_status', 'Job started', '${b.providerName} started ${b.serviceName} (${b.number}).',
            relatedId: b.id, relatedType: 'booking');
      case 'completed':
        await AppDb.db.rawUpdate(
            'UPDATE provider_profiles SET total_jobs_completed = COALESCE(total_jobs_completed, 0) + 1, '
            'total_earnings = COALESCE(total_earnings, 0) + ?, updated_at = ? WHERE id = ?',
            [b.providerEarnings, now, b.providerId]);
        await Notify.send(b.clientId, 'booking_status', 'Job completed',
            '${b.serviceName} is complete. Please pay the balance of ${Fmt.money(b.balance)} and rate ${b.providerName}.',
            relatedId: b.id, relatedType: 'booking');
      default:
        if (status == 'cancelled_by_client') {
          await _refundDeposit(b, byUserId);
          await Notify.send(b.providerUserId, 'booking_cancelled', 'Booking cancelled',
              '${b.clientName} cancelled ${b.number}${reason.isEmpty ? '' : ': $reason'}.',
              relatedId: b.id, relatedType: 'booking');
        } else if (status.startsWith('cancelled')) {
          await _refundDeposit(b, byUserId);
          await Notify.send(b.clientId, 'booking_cancelled', 'Booking declined',
              '${b.providerName} could not take ${b.number}${reason.isEmpty ? '' : ': $reason'}. Your deposit is refunded.',
              relatedId: b.id, relatedType: 'booking');
        } else {
          await Notify.send(b.clientId, 'booking_status', 'Booking $label', '${b.number} is now $label.');
        }
    }
    if (b.conversationId != null) {
      await ChatRepo.send(b.conversationId!, byUserId, 'Status: $label${reason.isEmpty ? '' : ' — $reason'}', type: 'system');
    }
  }

  static Future<void> _refundDeposit(Booking b, String byUserId) async {
    if (b.paid <= 0) return;
    await _txn(
      bookingId: b.id,
      clientId: b.clientId,
      providerId: b.providerId,
      type: 'refund',
      amount: b.paid,
      fee: 0,
      gateway: b.r.s('payment_method_id').isEmpty ? 'mtn_momo' : b.r.s('payment_method_id'),
      response: {'kind': 'refund', 'by': byUserId},
    );
    await AppDb.update('bookings', b.id, {'payment_status': 'refunded', 'refund_amount': b.paid, 'refunded_at': AppDb.now()});
  }

  static Future<String> payBalance(Booking b, MomoPayment payment) async {
    final amount = b.balance;
    final rate = await commissionPercent();
    final ref = await _txn(
      bookingId: b.id,
      clientId: b.clientId,
      providerId: b.providerId,
      type: 'payment',
      amount: amount,
      fee: (amount * rate / 100).roundToDouble(),
      gateway: payment.gateway,
      response: {'phone': payment.phone, 'network': payment.network, 'kind': 'balance'},
    );
    await AppDb.update('bookings', b.id, {'payment_status': 'paid', 'paid_at': AppDb.now()});
    await Notify.send(b.clientId, 'system', 'Payment confirmed', '${payment.network} transaction $ref for ${Fmt.money(amount)} — ${b.number} fully paid.');
    await Notify.send(b.providerUserId, 'system', 'Client paid in full', '${b.clientName} paid the balance for ${b.number}.');
    return ref;
  }

  static Future<void> review(Booking b, String reviewerId, int rating, String comment) async {
    await AppDb.insert('reviews', {
      'rating': rating,
      'title': '${b.serviceName} review',
      'comment': comment,
      'communication_rating': rating,
      'professionalism_rating': rating,
      'quality_rating': rating,
      'value_rating': rating,
      'punctuality_rating': rating,
      'provider_response': '',
      'is_public': 1,
      'is_flagged': 0,
      'booking_id': b.id,
      'reviewee_id': b.providerId,
      'reviewer_id': reviewerId,
      'admin_notes': '',
      'flag_reason': '',
      'helpful_count': 0,
      'unhelpful_count': 0,
      'images': '[]',
      'is_approved': 1,
      'is_featured': 0,
      'review_id': 'REV-${DateTime.now().millisecondsSinceEpoch}',
      'verified_booking': 1,
    });
    final agg = await AppDb.one(
        'SELECT AVG(rating) AS avg, COUNT(*) AS n FROM reviews WHERE reviewee_id = ? AND deleted_at IS NULL', [b.providerId]);
    await AppDb.update('provider_profiles', b.providerId, {
      'average_rating': double.parse((agg?.d('avg') ?? rating).toStringAsFixed(2)),
      'total_reviews': agg?.i('n') ?? 1,
    });
    await Notify.send(b.providerUserId, 'new_review', 'New $rating★ review', '${b.clientName}: ${comment.isEmpty ? 'No comment' : comment}');
  }

  static Future<void> sos(Booking b, String userId, String message, double? lat, double? lng) async {
    await AppDb.db.insert('kv_sos_alerts', {
      'id': AppDb.newId(),
      'booking_id': b.id,
      'raised_by_id': userId,
      'message': message,
      'latitude': lat,
      'longitude': lng,
      'status': 'open',
      'created_at': AppDb.now(),
    });
    await Notify.admins('system', '🚨 SOS alert', 'SOS on ${b.number} (${b.serviceName}) — $message', priority: 'urgent');
    await Notify.companyAdmins(b.entityId, 'system', '🚨 SOS alert', 'SOS raised on ${b.number} with ${b.providerName}: $message',
        priority: 'urgent');
  }

  static Future<void> dispute(Booking b, String userId, String type, String title, String description, {required bool byClient}) async {
    final id = await AppDb.insert('disputes', {
      'dispute_type': type,
      'title': title,
      'description': description,
      'evidence_images': '[]',
      'status': 'pending',
      'resolution_notes': '',
      'escalation_reason': '',
      'admin_notes': '',
      'outcome': '',
      'resolution_outcome': '',
      'booking_id': b.id,
      'raised_by_id': userId,
      'against_id': byClient ? b.providerUserId : b.clientId,
      'against_type': byClient ? 'provider' : 'client',
    });
    await Notify.admins('dispute_created', 'New dispute', '${b.number}: $title', priority: 'high');
    await Notify.send(userId, 'dispute_created', 'Problem reported', 'We received your report "$title". KoraVuba support will contact you.',
        relatedId: id, relatedType: 'dispute');
  }

  static Future<List<Map<String, Object?>>> history(String bookingId) => AppDb.query(
      'SELECT h.*, u.first_name, u.last_name FROM booking_status_history h LEFT JOIN users u ON u.id = h.changed_by_id '
      'WHERE h.booking_id = ? ORDER BY h.created_at',
      [bookingId]);

  static Future<List<Txn>> transactionsFor(String bookingId) async =>
      (await AppDb.query('SELECT t.*, b.booking_number FROM transactions t LEFT JOIN bookings b ON b.id = t.booking_id '
              'WHERE t.booking_id = ? ORDER BY t.created_at',
              [bookingId]))
          .map(Txn.new)
          .toList();
}
