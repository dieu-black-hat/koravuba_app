import '../core/db.dart';

enum Role { client, worker, company, admin }

extension RoleX on Role {
  String get label => switch (this) {
        Role.client => 'Client',
        Role.worker => 'Worker',
        Role.company => 'Company',
        Role.admin => 'Platform Admin',
      };
}

class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.lastName,
    required this.userType,
    required this.profileImage,
    required this.city,
    required this.address,
    required this.lat,
    required this.lng,
    required this.isActive,
    required this.createdAt,
    this.bio = '',
  });

  final String id;
  final String email;
  final String phone;
  final String firstName;
  final String lastName;
  final String userType;
  final String profileImage;
  final String city;
  final String address;
  final double? lat;
  final double? lng;
  final bool isActive;
  final DateTime? createdAt;
  final String bio;

  String get fullName => '$firstName $lastName'.trim().isEmpty ? email : '$firstName $lastName'.trim();

  factory AppUser.fromRow(Map<String, Object?> r) => AppUser(
        id: r.s('id'),
        email: r.s('email'),
        phone: r.s('phone'),
        firstName: r.s('first_name'),
        lastName: r.s('last_name'),
        userType: r.s('user_type'),
        profileImage: r.s('profile_image'),
        city: r.s('city'),
        address: r.s('address'),
        lat: r.dn('latitude'),
        lng: r.dn('longitude'),
        isActive: r.b('is_active'),
        createdAt: r.dt('created_at'),
        bio: r.s('bio'),
      );
}

class Category {
  Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.code,
    required this.rwName,
    required this.icon,
    required this.description,
    required this.basePrice,
    required this.priceUnit,
    required this.color,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String slug;
  final bool isActive;
  final String code;
  final String rwName;
  final String icon;
  final String description;
  final double basePrice;
  final String priceUnit;
  final String color;

  factory Category.fromRow(Map<String, Object?> r) => Category(
        id: r.s('id'),
        name: r.s('name'),
        slug: r.s('slug'),
        code: r.s('code'),
        rwName: r.s('kinyarwanda_name'),
        icon: r.s('icon'),
        description: r.s('description'),
        basePrice: r.d('base_price'),
        priceUnit: r.s('price_unit'),
        color: r.s('color'),
        isActive: r.b('is_active'),
      );
}

/// A service provider as shown to clients: profile + user + main service +
/// badge + company, joined from several Django tables.
class Worker {
  Worker({
    required this.profileId,
    required this.userId,
    required this.name,
    required this.phone,
    required this.email,
    required this.photo,
    required this.badgeId,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.entityId,
    required this.companyName,
    required this.companyCode,
    required this.rating,
    required this.reviews,
    required this.jobs,
    required this.lat,
    required this.lng,
    required this.online,
    required this.verified,
    required this.status,
    required this.serviceId,
    required this.serviceName,
    required this.price,
    required this.priceUnit,
    required this.description,
    required this.earnings,
    this.distanceKm,
  });

  final String profileId;
  final String userId;
  final String name;
  final String phone;
  final String email;
  final String photo;
  final String badgeId;
  final String? categoryId;
  final String categoryName;
  final String categoryColor;
  final String? entityId;
  final String companyName;
  final String companyCode;
  final double rating;
  final int reviews;
  final int jobs;
  final double? lat;
  final double? lng;
  final bool online;
  final bool verified;
  final String status;
  final String? serviceId;
  final String serviceName;
  final double price;
  final String priceUnit;
  final String description;
  final double earnings;
  double? distanceKm;

  factory Worker.fromRow(Map<String, Object?> r) {
    final first = r.s('first_name');
    final last = r.s('last_name');
    final full = '$first $last'.trim();
    return Worker(
      profileId: r.s('profile_id'),
      userId: r.s('user_id'),
      name: full.isEmpty ? r.s('business_name') : full,
      phone: r.s('phone').isNotEmpty ? r.s('phone') : r.s('user_phone'),
      email: r.s('email'),
      photo: r.s('profile_image'),
      badgeId: r.s('badge_id'),
      categoryId: r.sn('category_id'),
      categoryName: r.s('category_name').isEmpty ? r.s('service_name') : r.s('category_name'),
      categoryColor: r.s('category_color'),
      entityId: r.sn('entity_id'),
      companyName: r.s('company_name').isEmpty ? 'Independent provider' : r.s('company_name'),
      companyCode: r.s('company_code'),
      rating: r.d('average_rating'),
      reviews: r.i('total_reviews'),
      jobs: r.i('total_jobs_completed'),
      lat: r.dn('latitude'),
      lng: r.dn('longitude'),
      online: r.b('is_active'),
      verified: r.b('is_verified'),
      status: r.s('verification_status'),
      serviceId: r.sn('service_id'),
      serviceName: r.s('service_name'),
      price: r.d('price'),
      priceUnit: r.s('price_unit'),
      description: r.s('service_description').isEmpty ? r.s('business_description') : r.s('service_description'),
      earnings: r.d('total_earnings'),
    );
  }
}

class Company {
  Company({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    required this.type,
    required this.tin,
    required this.rdb,
    required this.email,
    required this.phone,
    required this.address,
    required this.description,
    required this.payout,
    required this.bankName,
    required this.subscription,
    required this.subscriptionEnd,
    required this.createdAt,
    required this.workers,
    required this.rejectionReason,
  });

  final String id;
  final String name;
  final String code;
  final String status;
  final String type;
  final String tin;
  final String rdb;
  final String email;
  final String phone;
  final String address;
  final String description;
  final String payout;
  final String bankName;
  final String subscription;
  final DateTime? subscriptionEnd;
  final DateTime? createdAt;
  final int workers;
  final String rejectionReason;

  bool get isActive => status == 'active' || status == 'verified';

  factory Company.fromRow(Map<String, Object?> r) => Company(
        id: r.s('id'),
        name: r.s('business_name'),
        code: r.s('company_id'),
        status: r.s('status'),
        type: r.s('entity_type'),
        tin: r.s('tin_number'),
        rdb: r.s('registration_number'),
        email: r.s('official_email'),
        phone: r.s('official_phone'),
        address: r.s('physical_address'),
        description: r.s('business_description'),
        payout: r.s('payout_account_number'),
        bankName: r.s('bank_name'),
        subscription: r.s('subscription_type'),
        subscriptionEnd: r.dt('subscription_end'),
        createdAt: r.dt('created_at'),
        workers: r.i('workers'),
        rejectionReason: r.s('rejection_reason'),
      );
}

class Booking {
  Booking(this.r);
  final Map<String, Object?> r;

  String get id => r.s('id');
  String get number => r.s('booking_number');
  String get status => r.s('status');
  String get paymentStatus => r.s('payment_status');
  String get payoutStatus => r.s('payout_status');
  String get clientId => r.s('client_id');
  String get clientName => '${r.s('client_first')} ${r.s('client_last')}'.trim();
  String get clientPhone => r.s('client_phone');
  String get clientPhoto => r.s('client_photo');
  String get providerId => r.s('provider_id');
  String get providerUserId => r.s('provider_user_id');
  String get providerName {
    final n = '${r.s('provider_first')} ${r.s('provider_last')}'.trim();
    return n.isEmpty ? r.s('business_name') : n;
  }

  String get providerPhone => r.s('provider_phone');
  String get providerPhoto => r.s('provider_photo');
  String get badgeId => r.s('badge_id');
  String get companyName => r.s('company_name');
  String? get entityId => r.sn('entity_id');
  String get serviceName => r.s('service_name');
  String get categoryName => r.s('category_name').isEmpty ? r.s('service_name') : r.s('category_name');
  String get categoryCode => r.s('category_code');
  String get scheduledDate => r.s('scheduled_date');
  String get scheduledTime => r.s('scheduled_time');
  int get durationMinutes => r.i('duration_minutes');
  String get address => r.s('address_line1');
  String get city => r.s('city');
  double get servicePrice => r.d('service_price');
  double get platformFee => r.d('platform_fee');
  double get total => r.d('total_amount');
  double get providerEarnings => r.d('provider_earnings');
  double get paid => r.d('paid_amount');
  double get balance => (total - paid).clamp(0, double.infinity).toDouble();
  String get clientNotes => r.s('client_notes');
  String get providerNotes => r.s('provider_notes');
  String get cancellationReason => r.s('cancellation_reason');
  String? get conversationId => r.sn('conversation_id');
  DateTime? get createdAt => r.dt('created_at');
  DateTime? get acceptedAt => r.dt('accepted_at');
  DateTime? get startedAt => r.dt('started_at');
  DateTime? get completedAt => r.dt('completed_at');
  DateTime? get cancelledAt => r.dt('cancelled_at');
  DateTime? get paidAt => r.dt('paid_at');
  double? get rating => r.dn('review_rating');
  double? get lat => r.dn('latitude');
  double? get lng => r.dn('longitude');

  DateTime? get scheduledAt {
    final d = DateTime.tryParse(scheduledDate);
    if (d == null) return null;
    final t = scheduledTime.split(':');
    return DateTime(d.year, d.month, d.day, t.isNotEmpty ? int.tryParse(t[0]) ?? 0 : 0, t.length > 1 ? int.tryParse(t[1]) ?? 0 : 0);
  }

  bool get isCancelled => status.startsWith('cancelled') || status == 'no_show';
  bool get isOpen => status == 'pending' || status == 'accepted' || status == 'in_progress';
  bool get isTransport => RegExp(r'^(car_taxi|moto_taxi|driver)(_\d+)?$').hasMatch(categoryCode);
}

class Conversation {
  Conversation({
    required this.id,
    required this.otherName,
    required this.otherPhoto,
    required this.otherPhone,
    required this.subtitle,
    required this.lastMessage,
    required this.lastAt,
    required this.unread,
    required this.clientId,
    required this.providerId,
  });

  final String id;
  final String otherName;
  final String otherPhoto;
  final String otherPhone;
  final String subtitle;
  final String lastMessage;
  final DateTime? lastAt;
  final int unread;
  final String clientId;
  final String providerId;
}

class Message {
  Message(this.r);
  final Map<String, Object?> r;
  String get id => r.s('id');
  String get senderId => r.s('sender_id');
  String get content => r.s('content');
  String get type => r.s('message_type');
  bool get isRead => r.b('is_read');
  bool get isEdited => r.b('is_edited');
  DateTime? get createdAt => r.dt('created_at');
}

class Notice {
  Notice(this.r);
  final Map<String, Object?> r;
  String get id => r.s('id');
  String get title => r.s('title');
  String get message => r.s('message');
  String get type => r.s('notification_type');
  bool get isRead => r.b('is_read');
  DateTime? get createdAt => r.dt('created_at');
}

class Txn {
  Txn(this.r);
  final Map<String, Object?> r;
  String get id => r.s('id');
  String get code => r.s('transaction_id');
  String get type => r.s('transaction_type');
  double get amount => r.d('amount');
  double get fee => r.d('platform_fee');
  double get providerAmount => r.d('provider_amount');
  String get status => r.s('status');
  String get gateway => r.s('gateway');
  String get gatewayRef => r.s('gateway_transaction_id');
  String get currency => r.s('currency');
  DateTime? get createdAt => r.dt('created_at');
  String get bookingNumber => r.s('booking_number');
  String get clientName => '${r.s('client_first')} ${r.s('client_last')}'.trim();
  String get providerName => r.s('provider_name');
}

class Review {
  Review(this.r);
  final Map<String, Object?> r;
  double get rating => r.d('rating');
  String get comment => r.s('comment');
  String get title => r.s('title');
  String get reviewer => '${r.s('first_name')} ${r.s('last_name')}'.trim();
  String get response => r.s('provider_response');
  DateTime? get createdAt => r.dt('created_at');
}

class Dispute {
  Dispute(this.r);
  final Map<String, Object?> r;
  String get id => r.s('id');
  String get title => r.s('title');
  String get description => r.s('description');
  String get type => r.s('dispute_type');
  String get status => r.s('status');
  String get bookingNumber => r.s('booking_number');
  String get raisedBy => '${r.s('first_name')} ${r.s('last_name')}'.trim();
  String get resolutionNotes => r.s('resolution_notes');
  DateTime? get createdAt => r.dt('created_at');
}

class Application {
  Application(this.r);
  final Map<String, Object?> r;
  String get id => r.s('id');
  String get name => '${r.s('first_name')} ${r.s('last_name')}'.trim();
  String get email => r.s('email');
  String get phone => r.s('phone');
  String get services => r.s('services');
  String get description => r.s('service_description');
  String get status => r.s('status');
  String get documentNumber => r.s('document_number');
  String? get userId => r.sn('user_id');
  String? get entityId => r.sn('entity_id');
  String get companyName => r.s('company_name');
  double get price => r.d('price_amount');
  DateTime? get submittedAt => r.dt('submitted_at') ?? r.dt('created_at');
}

class SosAlert {
  SosAlert(this.r);
  final Map<String, Object?> r;
  String get id => r.s('id');
  String get message => r.s('message');
  String get status => r.s('status');
  String get bookingNumber => r.s('booking_number');
  String get raisedBy => '${r.s('first_name')} ${r.s('last_name')}'.trim();
  String get phone => r.s('phone');
  DateTime? get createdAt => r.dt('created_at');
}
