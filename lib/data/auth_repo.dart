import 'dart:math' as math;

import '../core/db.dart';
import '../core/django_password.dart';
import '../core/format.dart';
import '../core/geo.dart';
import 'models.dart';
import 'notify.dart';

class AuthError implements Exception {
  AuthError(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthResult {
  AuthResult(this.user, this.role, {this.profileId, this.entityId});
  final AppUser user;
  final Role role;
  final String? profileId;
  final String? entityId;
}

/// Sign-in / sign-up against the `users` table (Django-compatible hashes).
class AuthRepo {
  AuthRepo._();

  static const _userSql = 'SELECT u.*, up.bio FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id';

  static Future<AppUser?> userById(String id) async {
    final r = await AppDb.one('$_userSql WHERE u.id = ?', [id]);
    return r == null ? null : AppUser.fromRow(r);
  }

  /// Finds users by e-mail or phone (phones compared on their last 9 digits).
  static Future<List<Map<String, Object?>>> _byIdentifier(String identifier) async {
    final id = identifier.trim();
    if (id.contains('@')) {
      return AppDb.query('$_userSql WHERE lower(u.email) = lower(?) AND u.deleted_at IS NULL', [id]);
    }
    final key = Fmt.phoneKey(id);
    if (key.length < 9) return [];
    final rows = await AppDb.query('$_userSql WHERE u.deleted_at IS NULL AND u.phone IS NOT NULL AND u.phone != ?', ['']);
    return rows.where((r) => Fmt.phoneKey(r.s('phone')) == key).toList();
  }

  static Future<Map<String, Object?>> _check(List<Map<String, Object?>> rows, String password, bool Function(Map<String, Object?>) accept,
      String wrongRole) async {
    if (rows.isEmpty) throw AuthError('No account found with these details.');
    final matching = rows.where(accept).toList();
    if (matching.isEmpty) throw AuthError(wrongRole);
    for (final r in matching) {
      if (await DjangoPassword.verify(password, r.s('password'))) {
        if (!r.b('is_active')) throw AuthError('This account has been deactivated. Contact KoraVuba support.');
        await AppDb.update('users', r.s('id'), {'last_login': AppDb.now(), 'last_active': AppDb.now()});
        return r;
      }
    }
    throw AuthError('Incorrect password / PIN.');
  }

  static Future<AuthResult> loginClient(String identifier, String password) async {
    final r = await _check(await _byIdentifier(identifier), password, (r) => r.s('user_type') == 'client',
        'This account is not a client account. Use the Worker or Company tab.');
    return AuthResult(AppUser.fromRow(r), Role.client);
  }

  static Future<AuthResult> loginWorker(String badgeOrPhone, String password) async {
    final input = badgeOrPhone.trim();
    List<Map<String, Object?>> rows;
    if (input.toUpperCase().startsWith('KV-')) {
      rows = await AppDb.query(
          '$_userSql JOIN provider_profiles pp ON pp.user_id = u.id JOIN kv_badges b ON b.provider_id = pp.id '
          'WHERE upper(b.badge_id) = upper(?)',
          [input]);
      if (rows.isEmpty) throw AuthError('Badge ID not found. Check the ID printed on your KoraVuba badge.');
    } else {
      rows = await _byIdentifier(input);
    }
    final r = await _check(rows, password, (r) => r.s('user_type') == 'provider',
        'This account is not a worker account. Use the Client or Company tab.');
    final profile = await AppDb.one(
        'SELECT pp.*, e.business_name AS company_name FROM provider_profiles pp LEFT JOIN entities e ON e.id = pp.entity_id '
        'WHERE pp.user_id = ? AND pp.deleted_at IS NULL',
        [r.s('id')]);
    if (profile == null) throw AuthError('No provider profile is linked to this account yet.');
    final status = profile.s('verification_status');
    if (status == 'pending') {
      final c = profile.s('company_name');
      throw AuthError('Your badge is waiting for approval${c.isEmpty ? '' : ' by $c'}. You can sign in once it is approved.');
    }
    if (status == 'rejected') throw AuthError('Your application was not approved. Contact your company.');
    if (status == 'suspended') throw AuthError('Your badge is suspended by your company. Contact your supervisor.');
    return AuthResult(AppUser.fromRow(r), Role.worker, profileId: profile.s('id'), entityId: profile.sn('entity_id'));
  }

  static Future<AuthResult> loginCompany(String identifier, String password) async {
    final r = await _check(await _byIdentifier(identifier), password, (r) => r.s('user_type') == 'entity_admin',
        'This account is not a company admin account.');
    final e = await AppDb.one(
        'SELECT e.* FROM entity_admins ea JOIN entities e ON e.id = ea.entity_id WHERE ea.user_id = ? ORDER BY ea.is_primary_admin DESC LIMIT 1',
        [r.s('id')]);
    if (e == null) throw AuthError('No company is linked to this account.');
    final status = e.s('status');
    if (status == 'pending' || status == 'draft') {
      throw AuthError('${e.s('business_name')} is waiting for KoraVuba HQ verification. You will be notified once approved.');
    }
    if (status == 'rejected') {
      throw AuthError('Registration rejected${e.s('rejection_reason').isEmpty ? '' : ': ${e.s('rejection_reason')}'}.');
    }
    if (status == 'suspended') throw AuthError('This company account is suspended. Contact KoraVuba HQ.');
    return AuthResult(AppUser.fromRow(r), Role.company, entityId: e.s('id'));
  }

  static Future<AuthResult> loginAdmin(String identifier, String password) async {
    final r = await _check(await _byIdentifier(identifier), password,
        (r) => r.s('user_type') == 'admin' || r.b('is_superuser') || r.b('is_staff'), 'This account has no platform admin rights.');
    return AuthResult(AppUser.fromRow(r), Role.admin);
  }

  static Future<AuthResult?> restore(String userId, Role role) async {
    final u = await userById(userId);
    if (u == null || !u.isActive) return null;
    switch (role) {
      case Role.worker:
        final p = await AppDb.one('SELECT id, entity_id, verification_status FROM provider_profiles WHERE user_id = ?', [userId]);
        if (p == null || p.s('verification_status') != 'approved') return null;
        return AuthResult(u, role, profileId: p.s('id'), entityId: p.sn('entity_id'));
      case Role.company:
        final e = await AppDb.one(
            'SELECT e.id, e.status FROM entity_admins ea JOIN entities e ON e.id = ea.entity_id WHERE ea.user_id = ? LIMIT 1', [userId]);
        if (e == null || (e.s('status') != 'active' && e.s('status') != 'verified')) return null;
        return AuthResult(u, role, entityId: e.s('id'));
      case Role.client:
      case Role.admin:
        return AuthResult(u, role);
    }
  }

  // ------------------------------------------------------------- sign up
  static Future<void> _ensureUnique(String email, String phone) async {
    if (email.isNotEmpty && await AppDb.one('SELECT id FROM users WHERE lower(email) = lower(?)', [email]) != null) {
      throw AuthError('An account with this e-mail already exists.');
    }
    final key = Fmt.phoneKey(phone);
    final phones = await AppDb.query('SELECT phone FROM users');
    if (phones.any((r) => Fmt.phoneKey(r.s('phone')) == key)) throw AuthError('An account with this phone number already exists.');
  }

  static String _normPhone(String phone) {
    final key = Fmt.phoneKey(phone);
    return key.length == 9 ? '+250$key' : phone.trim();
  }

  static Future<String> _createUser({
    required String first,
    required String last,
    required String email,
    required String phone,
    required String type,
    required String password,
    Sector? sector,
  }) async {
    final hash = await DjangoPassword.make(password);
    final s = sector ?? kigaliSectors.first;
    final id = await AppDb.insert('users', {
      'password': hash,
      'is_superuser': 0,
      'email': email.isEmpty ? '${Fmt.phoneKey(phone)}@phone.koravuba.rw' : email.trim().toLowerCase(),
      'phone': _normPhone(phone),
      'first_name': first.trim(),
      'last_name': last.trim(),
      'user_type': type,
      'email_verified': 0,
      'phone_verified': 1,
      'is_active': 1,
      'is_staff': 0,
      'profile_image': '',
      'address': s.label,
      'city': 'Kigali',
      'country': 'Rwanda',
      'state': s.district,
      'postal_code': '',
      'latitude': s.lat,
      'longitude': s.lng,
    });
    await AppDb.insert('user_profiles', {
      'user_id': id,
      'bio': '',
      'address_line1': s.label,
      'address_line2': '',
      'city': 'Kigali',
      'state': s.district,
      'postal_code': '',
      'country': 'Rwanda',
      'latitude': s.lat,
      'longitude': s.lng,
      'language': 'en',
      'notification_enabled': 1,
      'facebook_url': '',
      'twitter_url': '',
      'instagram_url': '',
      'linkedin_url': '',
    });
    await AppDb.db.insert('kv_user_settings', {'user_id': id, 'momo_number': _normPhone(phone), 'momo_network': 'MTN MoMo', 'sector': s.name});
    return id;
  }

  static Future<AuthResult> registerClient({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    required Sector sector,
  }) async {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    await _ensureUnique(email, phone);
    final id = await _createUser(
      first: parts.first,
      last: parts.length > 1 ? parts.sublist(1).join(' ') : '',
      email: email,
      phone: phone,
      type: 'client',
      password: password,
      sector: sector,
    );
    await Notify.send(id, 'system', 'Welcome to KoraVuba 👋', 'Book company-verified cleaners, drivers, plumbers and more across Kigali.');
    return AuthResult((await userById(id))!, Role.client);
  }

  /// Worker sign-up: creates the user, a pending provider profile, the
  /// service, a badge and a `provider_applications` row for the company to approve.
  static Future<String> registerWorker({
    required String companyCode,
    required String fullName,
    required String phone,
    required String nationalId,
    required Category category,
    required String password,
    required Sector sector,
  }) async {
    final e = await AppDb.one('SELECT * FROM entities WHERE upper(company_id) = upper(?) AND deleted_at IS NULL', [companyCode.trim()]);
    if (e == null) throw AuthError('Company ID not found. Ask your company for its KoraVuba Company ID (e.g. KV-COMP-101).');
    if (e.s('status') != 'active' && e.s('status') != 'verified') throw AuthError('${e.s('business_name')} is not active on KoraVuba yet.');
    await _ensureUnique('', phone);
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final email = '${Fmt.phoneKey(phone)}@workers.koravuba.rw';
    final userId = await _createUser(first: first, last: last, email: email, phone: phone, type: 'provider', password: password, sector: sector);
    final profileId = await AppDb.insert('provider_profiles', {
      'user_id': userId,
      'business_name': fullName.trim(),
      'business_description': '${category.name} • ${category.description}',
      'is_verified': 0,
      'verification_status': 'pending',
      'average_rating': 0,
      'total_reviews': 0,
      'max_travel_distance': 10,
      'total_jobs_completed': 0,
      'total_earnings': 0,
      'address': sector.label,
      'can_travel': 1,
      'city': 'Kigali',
      'country': 'Rwanda',
      'phone': _normPhone(phone),
      'postal_code': '',
      'state': sector.district,
      'latitude': sector.lat,
      'longitude': sector.lng,
      'location_updated_at': AppDb.now(),
      'location_verified': 0,
      'company_id': e.s('company_id'),
      'is_active': 0,
      'verified_by_entity': 0,
      'entity_id': e.s('id'),
    });
    await AppDb.insert('provider_services', {
      'provider_id': profileId,
      'category_id': category.id,
      'name': category.name,
      'description': category.description,
      'price_type': category.priceUnit.contains('km') ? 'fixed' : 'hourly',
      'price': category.basePrice,
      'price_unit': category.priceUnit,
      'estimated_duration': 60,
      'image': '',
    });
    await AppDb.insert('provider_availability', {
      'provider_id': profileId,
      'is_available': 0,
      'monday': 1,
      'tuesday': 1,
      'wednesday': 1,
      'thursday': 1,
      'friday': 1,
      'saturday': 1,
      'sunday': 0,
      'available_from': '07:00:00',
      'available_to': '20:00:00',
    });
    final badge = await _newBadge(category.code);
    await AppDb.db.insert('kv_badges', {
      'provider_id': profileId,
      'badge_id': badge,
      'category': category.code,
      'national_id': nationalId.trim(),
      'issued_at': AppDb.now(),
    });
    await AppDb.insert('provider_applications', {
      'first_name': first,
      'last_name': last,
      'email': email,
      'phone': _normPhone(phone),
      'services': category.name,
      'service_description': category.description,
      'price_type': 'fixed',
      'price_amount': category.basePrice,
      'id_document': '',
      'license_document': '',
      'document_type': 'national_id',
      'document_number': nationalId.trim(),
      'additional_document': '',
      'address': sector.label,
      'city': 'Kigali',
      'state': sector.district,
      'country': 'Rwanda',
      'postal_code': '',
      'can_travel': 1,
      'travel_distance': 10,
      'agree_terms': 1,
      'agree_background_check': 1,
      'status': 'pending',
      'admin_notes': '',
      'rejection_reason': '',
      'submitted_at': AppDb.now(),
      'user_id': userId,
      'payment_proof': '',
      'payment_verified': 0,
      'company_id': e.s('company_id'),
      'entity_id': e.s('id'),
    });
    await Notify.companyAdmins(e.s('id'), 'application', 'New worker application',
        '$fullName applied to join ${e.s('business_name')} as ${category.name}. Badge $badge is waiting for your approval.',
        priority: 'high');
    await Notify.send(userId, 'application', 'Application received',
        'Your badge $badge was created. ${e.s('business_name')} will review your application.');
    return badge;
  }

  static Future<String> _newBadge(String categoryCode) async {
    final prefix = switch (categoryCode.replaceFirst(RegExp(r'_\d+$'), '')) {
      'car_taxi' => 'TAXI',
      'moto_taxi' => 'MOTO',
      'cleaner' => 'CLEAN',
      'driver' => 'DRIV',
      'plumber' => 'PLUMB',
      'electrician' => 'ELEC',
      'nanny' => 'NANY',
      'chef' => 'CHEF',
      'tutor' => 'TUTO',
      'barber' => 'BARB',
      _ => 'PRO',
    };
    final r = math.Random();
    while (true) {
      final badge = 'KV-$prefix-${(10000 + r.nextInt(89999)).toString()}';
      if (await AppDb.one('SELECT badge_id FROM kv_badges WHERE badge_id = ?', [badge]) == null) return badge;
    }
  }

  /// Company sign-up: `entities` row (status pending) + its admin user.
  static Future<void> registerCompany({
    required String businessName,
    required String tin,
    required String rdb,
    required String email,
    required String phone,
    required Sector sector,
    required String payoutAccount,
    required String adminName,
    required String password,
  }) async {
    await _ensureUnique(email, phone);
    final parts = adminName.trim().split(RegExp(r'\s+'));
    final userId = await _createUser(
      first: parts.first,
      last: parts.length > 1 ? parts.sublist(1).join(' ') : 'Admin',
      email: email,
      phone: phone,
      type: 'entity_admin',
      password: password,
      sector: sector,
    );
    final entityId = await AppDb.insert('entities', {
      'entity_type': 'company',
      'business_name': businessName.trim(),
      'business_description': '${businessName.trim()} — company-verified service providers in ${sector.name}, Kigali.',
      'logo': '',
      'registration_number': rdb.trim(),
      'registration_certificate': '',
      'tin_number': tin.trim(),
      'tin_certificate': '',
      'official_email': email.trim().toLowerCase(),
      'official_phone': _normPhone(phone),
      'physical_address': '${sector.name}, Kigali',
      'website': '',
      'subscription_type': 'monthly',
      'provider_count': 0,
      'max_providers': 50,
      'subscription_fee': 10000,
      'payment_method': 'mobile_money',
      'payment_reference': '',
      'payment_confirmed': 0,
      'company_id': '',
      'payout_account_type': payoutAccount.toLowerCase().contains('momo') ? 'mobile_money' : 'bank',
      'payout_account_number': payoutAccount.trim(),
      'bank_name': payoutAccount.split('•').first.trim(),
      'account_holder_name': businessName.trim(),
      'status': 'pending',
      'admin_notes': '',
      'rejection_reason': '',
    });
    await AppDb.db.insert('entity_admins', {
      'is_primary_admin': 1,
      'position': 'Company Admin',
      'permissions': '{}',
      'created_at': AppDb.now(),
      'entity_id': entityId,
      'user_id': userId,
    });
    await Notify.admins('application', 'New company registration', '$businessName (TIN $tin) is waiting for verification.',
        priority: 'high');
  }

  // ------------------------------------------------------------- account
  static Future<void> changePassword(String userId, String oldPassword, String newPassword) async {
    final r = await AppDb.one('SELECT password FROM users WHERE id = ?', [userId]);
    if (r == null) throw AuthError('Account not found');
    if (!await DjangoPassword.verify(oldPassword, r.s('password'))) throw AuthError('Your current password is incorrect.');
    await AppDb.update('users', userId, {'password': await DjangoPassword.make(newPassword)});
  }

  static Future<void> updateProfile(String userId,
      {required String first, required String last, required String email, required String phone, String? bio, Sector? sector}) async {
    final other = await AppDb.one('SELECT id FROM users WHERE lower(email) = lower(?) AND id != ?', [email.trim(), userId]);
    if (other != null) throw AuthError('This e-mail is used by another account.');
    final key = Fmt.phoneKey(phone);
    final phones = await AppDb.query('SELECT phone FROM users WHERE id != ?', [userId]);
    if (phones.any((r) => Fmt.phoneKey(r.s('phone')) == key)) throw AuthError('This phone number is used by another account.');
    final values = <String, Object?>{
      'first_name': first.trim(),
      'last_name': last.trim(),
      'email': email.trim().toLowerCase(),
      'phone': _normPhone(phone),
    };
    if (sector != null) {
      values.addAll({'address': sector.label, 'state': sector.district, 'latitude': sector.lat, 'longitude': sector.lng});
    }
    await AppDb.update('users', userId, values);
    final p = await AppDb.one('SELECT id FROM user_profiles WHERE user_id = ?', [userId]);
    final pv = <String, Object?>{if (bio != null) 'bio': bio};
    if (sector != null) pv.addAll({'address_line1': sector.label, 'latitude': sector.lat, 'longitude': sector.lng});
    if (p != null && pv.isNotEmpty) await AppDb.update('user_profiles', p.s('id'), pv);
  }

  static Future<void> setPhoto(String userId, String path) => AppDb.update('users', userId, {'profile_image': path});

  static Future<Map<String, Object?>> settings(String userId) async =>
      await AppDb.one('SELECT * FROM kv_user_settings WHERE user_id = ?', [userId]) ?? <String, Object?>{};

  static Future<void> saveSettings(String userId, {String? momo, String? network, String? sector}) async {
    final cur = await settings(userId);
    await AppDb.db.rawInsert(
      'INSERT OR REPLACE INTO kv_user_settings (user_id, momo_number, momo_network, sector) VALUES (?, ?, ?, ?)',
      [userId, momo ?? cur['momo_number'], network ?? cur['momo_network'], sector ?? cur['sector']],
    );
  }
}
