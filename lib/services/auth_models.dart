const Object _unset = Object();

String? _stringOrNull(dynamic value) {
  if (value == null) return null;
  final str = value.toString().trim();
  return str.isEmpty ? null : str;
}

int? _intOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.round();
  final str = value.toString().trim();
  if (str.isEmpty) return null;
  return int.tryParse(str);
}

double? _doubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  final str = value.toString().trim();
  if (str.isEmpty) return null;
  return double.tryParse(str);
}

bool? _boolOrNull(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final str = value.toString().trim().toLowerCase();
  if (str.isEmpty) return null;
  if (str == 'true' || str == '1' || str == 'yes' || str == 'y' || str == 'on') {
    return true;
  }
  if (str == 'false' || str == '0' || str == 'no' || str == 'n' || str == 'off') {
    return false;
  }
  return null;
}

DateTime? _dateTimeOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is int) {
    if (value == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      value.abs() < 1000000000000 ? value * 1000 : value,
      isUtc: true,
    ).toLocal();
  }
  if (value is double) {
    final normalized = value.abs() < 1000000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(
      normalized.round(),
      isUtc: true,
    ).toLocal();
  }
  final str = value.toString().trim();
  if (str.isEmpty) return null;
  final numeric = int.tryParse(str);
  if (numeric != null) {
    return DateTime.fromMillisecondsSinceEpoch(
      numeric.abs() < 1000000000000 ? numeric * 1000 : numeric,
      isUtc: true,
    ).toLocal();
  }
  final parsed = DateTime.tryParse(str);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

class AuthTokens {
  final String accessToken;
  final DateTime? accessTokenExpiresAt;
  final String refreshToken;
  final DateTime? refreshTokenExpiresAt;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.accessTokenExpiresAt,
    this.refreshTokenExpiresAt,
  });

  bool get hasAccessToken => accessToken.trim().isNotEmpty;
  bool get hasRefreshToken => refreshToken.trim().isNotEmpty;

  bool get isAccessTokenExpired {
    if (accessTokenExpiresAt == null) return false;
    return DateTime.now().isAfter(accessTokenExpiresAt!);
  }

  bool shouldRefresh({Duration threshold = const Duration(minutes: 1)}) {
    final expiresAt = accessTokenExpiresAt;
    if (expiresAt == null) return false;
    return expiresAt.isBefore(DateTime.now().add(threshold));
  }

  AuthTokens copyWith({
    String? accessToken,
    Object? refreshToken = _unset,
    DateTime? accessTokenExpiresAt,
    DateTime? refreshTokenExpiresAt,
  }) {
    return AuthTokens(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken == _unset
          ? this.refreshToken
          : (refreshToken is String ? refreshToken : ''),
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      refreshTokenExpiresAt:
          refreshTokenExpiresAt ?? this.refreshTokenExpiresAt,
    );
  }

  Map<String, dynamic> toJson({bool includeRefreshToken = true}) {
    return {
      'token': accessToken,
      'tokenExpiresAt': accessTokenExpiresAt?.toUtc().toIso8601String(),
      if (includeRefreshToken) 'refreshToken': refreshToken,
      if (includeRefreshToken)
        'refreshTokenExpiresAt':
            refreshTokenExpiresAt?.toUtc().toIso8601String(),
    };
  }

  factory AuthTokens.fromJson(
    Map<String, dynamic> json, {
    String? fallbackRefreshToken,
  }) {
    final access =
        _stringOrNull(json['token']) ?? _stringOrNull(json['accessToken']) ?? '';
    final refresh =
        _stringOrNull(json['refreshToken']) ?? fallbackRefreshToken ?? '';
    final tokenExpires = _dateTimeOrNull(
      json['tokenExpiresAt'] ?? json['accessTokenExpiresAt'],
    );
    final refreshExpires = _dateTimeOrNull(
      json['refreshTokenExpiresAt'],
    );
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      accessTokenExpiresAt: tokenExpires,
      refreshTokenExpiresAt: refreshExpires,
    );
  }
}

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final int walletBalancePaise;
  final String? referralCode;
  final String? referralShareLink;
  final int referralCount;
  final DateTime? referralActivatedAt;
  final String? referredBy;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.walletBalancePaise = 0,
    this.referralCode,
    this.referralShareLink,
    this.referralCount = 0,
    this.referralActivatedAt,
    this.referredBy,
  });

  double get walletBalanceRupees => walletBalancePaise / 100.0;

  AuthUser copyWith({
    String? id,
    String? name,
    String? email,
    Object? phone = _unset,
    int? walletBalancePaise,
    Object? referralCode = _unset,
    Object? referralShareLink = _unset,
    int? referralCount,
    Object? referralActivatedAt = _unset,
    Object? referredBy = _unset,
  }) {
    return AuthUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone == _unset ? this.phone : phone as String?,
      walletBalancePaise: walletBalancePaise ?? this.walletBalancePaise,
      referralCode: referralCode == _unset
          ? this.referralCode
          : referralCode as String?,
      referralShareLink: referralShareLink == _unset
          ? this.referralShareLink
          : referralShareLink as String?,
      referralCount: referralCount ?? this.referralCount,
      referralActivatedAt: referralActivatedAt == _unset
          ? this.referralActivatedAt
          : referralActivatedAt as DateTime?,
      referredBy:
          referredBy == _unset ? this.referredBy : referredBy as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      if (phone != null) 'phone': phone,
      'walletBalance': walletBalancePaise,
      if (referralCode != null) 'referralCode': referralCode,
      if (referralShareLink != null) 'referralShareLink': referralShareLink,
      'referralCount': referralCount,
      if (referralActivatedAt != null)
        'referralActivatedAt': referralActivatedAt!.toUtc().toIso8601String(),
      if (referredBy != null) 'referredBy': referredBy,
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final id = _stringOrNull(json['id']) ?? '';
    final name = _stringOrNull(json['name']) ?? '';
    final email = _stringOrNull(json['email']) ?? '';
    final phone = _stringOrNull(json['phone']);
    final walletBalance = _intOrNull(json['walletBalance']) ?? 0;
    final referralCode = _stringOrNull(json['referralCode']);
    final referralShareLink = _stringOrNull(json['referralShareLink']);
    final referralCount = _intOrNull(json['referralCount']) ?? 0;
    final referralActivatedAt = _dateTimeOrNull(json['referralActivatedAt']);
    final referredBy = _stringOrNull(json['referredBy']);

    return AuthUser(
      id: id,
      name: name,
      email: email,
      phone: phone,
      walletBalancePaise: walletBalance,
      referralCode: referralCode,
      referralShareLink: referralShareLink,
      referralCount: referralCount,
      referralActivatedAt: referralActivatedAt,
      referredBy: referredBy,
    );
  }
}

class AuthSession {
  final AuthTokens tokens;
  final AuthUser user;
  final bool termsAccepted;

  const AuthSession({
    required this.tokens,
    required this.user,
    required this.termsAccepted,
  });

  bool get isValid => tokens.hasAccessToken && user.id.trim().isNotEmpty;

  bool get hasAcceptedTerms => termsAccepted;

  String get accessToken => tokens.accessToken;

  String get refreshToken => tokens.refreshToken;

  AuthSession copyWith({
    AuthTokens? tokens,
    AuthUser? user,
    bool? termsAccepted,
  }) {
    return AuthSession(
      tokens: tokens ?? this.tokens,
      user: user ?? this.user,
      termsAccepted: termsAccepted ?? this.termsAccepted,
    );
  }

  Map<String, dynamic> toJson({bool includeRefreshToken = true}) {
    return {
      'tokens': tokens.toJson(includeRefreshToken: includeRefreshToken),
      'user': user.toJson(),
      'termsAccepted': termsAccepted,
    };
  }

  factory AuthSession.fromJson(
    Map<String, dynamic> json, {
    String? refreshTokenFallback,
  }) {
    final tokenSection = json['tokens'];
    Map<String, dynamic> tokensMap;
    if (tokenSection is Map) {
      tokensMap = tokenSection.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
    } else {
      tokensMap = json;
    }

    final userSection = json['user'];
    Map<String, dynamic> userMap = {};
    if (userSection is Map) {
      userMap = userSection.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    final tokens = AuthTokens.fromJson(
      tokensMap,
      fallbackRefreshToken: refreshTokenFallback,
    );
    final user = AuthUser.fromJson(userMap);
    final terms = _boolOrNull(json['termsAccepted']) ?? false;

    return AuthSession(
      tokens: tokens,
      user: user,
      termsAccepted: terms,
    );
  }
}

class ReferralListEntry {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? referralCode;
  final String? referralShareLink;
  final DateTime? createdAt;
  final DateTime? referralActivatedAt;
  final int loginCount;

  const ReferralListEntry({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.referralCode,
    this.referralShareLink,
    this.createdAt,
    this.referralActivatedAt,
    this.loginCount = 0,
  });

  factory ReferralListEntry.fromJson(Map<String, dynamic> json) {
    return ReferralListEntry(
      id: _stringOrNull(json['id']) ?? '',
      name: _stringOrNull(json['name']) ?? '',
      email: _stringOrNull(json['email']) ?? '',
      phone: _stringOrNull(json['phone']),
      referralCode: _stringOrNull(json['referralCode']),
      referralShareLink: _stringOrNull(json['referralShareLink']),
      createdAt: _dateTimeOrNull(json['createdAt']),
      referralActivatedAt: _dateTimeOrNull(json['referralActivatedAt']),
      loginCount: _intOrNull(json['loginCount']) ?? 0,
    );
  }
}

class ReferralListResponse {
  final int total;
  final int offset;
  final int limit;
  final List<ReferralListEntry> referrals;

  const ReferralListResponse({
    required this.total,
    required this.offset,
    required this.limit,
    required this.referrals,
  });

  bool get isEmpty => referrals.isEmpty;

  factory ReferralListResponse.fromJson(Map<String, dynamic> json) {
    final list = <ReferralListEntry>[];
    final raw = json['referrals'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          list.add(ReferralListEntry.fromJson(item));
        } else if (item is Map) {
          list.add(
            ReferralListEntry.fromJson(
              item.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      }
    }

    return ReferralListResponse(
      total: _intOrNull(json['total']) ?? list.length,
      offset: _intOrNull(json['offset']) ?? 0,
      limit: _intOrNull(json['limit']) ?? list.length,
      referrals: list,
    );
  }
}

class ReferralTreeUser {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? referralCode;
  final String? referralShareLink;
  final DateTime? createdAt;
  final DateTime? referralActivatedAt;

  const ReferralTreeUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.referralCode,
    this.referralShareLink,
    this.createdAt,
    this.referralActivatedAt,
  });

  factory ReferralTreeUser.fromJson(Map<String, dynamic> json) {
    return ReferralTreeUser(
      id: _stringOrNull(json['id']) ?? '',
      name: _stringOrNull(json['name']) ?? '',
      email: _stringOrNull(json['email']) ?? '',
      phone: _stringOrNull(json['phone']),
      referralCode: _stringOrNull(json['referralCode']),
      referralShareLink: _stringOrNull(json['referralShareLink']),
      createdAt: _dateTimeOrNull(json['createdAt']),
      referralActivatedAt: _dateTimeOrNull(json['referralActivatedAt']),
    );
  }
}

class ReferralTreeLevel {
  final int level;
  final List<ReferralTreeUser> users;

  const ReferralTreeLevel({
    required this.level,
    required this.users,
  });

  factory ReferralTreeLevel.fromJson(Map<String, dynamic> json) {
    final users = <ReferralTreeUser>[];
    final rawUsers = json['users'];
    if (rawUsers is List) {
      for (final user in rawUsers) {
        if (user is Map<String, dynamic>) {
          users.add(ReferralTreeUser.fromJson(user));
        } else if (user is Map) {
          users.add(
            ReferralTreeUser.fromJson(
              user.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      }
    }

    return ReferralTreeLevel(
      level: _intOrNull(json['level']) ?? 0,
      users: users,
    );
  }
}

class ReferralTreeResponse {
  final int depth;
  final List<ReferralTreeLevel> levels;

  const ReferralTreeResponse({
    required this.depth,
    required this.levels,
  });

  bool get isEmpty => levels.isEmpty;

  factory ReferralTreeResponse.fromJson(Map<String, dynamic> json) {
    final levels = <ReferralTreeLevel>[];
    final rawLevels = json['levels'];
    if (rawLevels is List) {
      for (final level in rawLevels) {
        if (level is Map<String, dynamic>) {
          levels.add(ReferralTreeLevel.fromJson(level));
        } else if (level is Map) {
          levels.add(
            ReferralTreeLevel.fromJson(
              level.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      }
    }

    return ReferralTreeResponse(
      depth: _intOrNull(json['depth']) ?? levels.length,
      levels: levels,
    );
  }
}

class ReferralEarningEntry {
  final int amountPaise;
  final String note;
  final DateTime? createdAt;
  final String? externalReference;
  final int? level;
  final String? status;

  const ReferralEarningEntry({
    required this.amountPaise,
    required this.note,
    this.createdAt,
    this.externalReference,
    this.level,
    this.status,
  });

  double get amountRupees => amountPaise / 100.0;

  factory ReferralEarningEntry.fromJson(Map<String, dynamic> json) {
    // Accept both auth.js and legacy shapes
    final amount = _intOrNull(json['amountPaise']) ?? _intOrNull(json['amount']) ?? 0;
    final extRef = _stringOrNull(json['topupExtRef']) ?? _stringOrNull(json['extRef']);
    return ReferralEarningEntry(
      amountPaise: amount,
      note: _stringOrNull(json['note']) ?? '',
      createdAt: _dateTimeOrNull(json['createdAt']),
      externalReference: extRef,
      level: _intOrNull(json['level']),
      status: _stringOrNull(json['status']),
    );
  }
}

class ReferralEarningsResponse {
  final int totalEarnedPaise;
  final int totalPendingPaise;
  final int totalPaidPaise;
  final int totalCancelledPaise;
  final List<ReferralEarningEntry> entries;

  const ReferralEarningsResponse({
    required this.totalEarnedPaise,
    required this.totalPendingPaise,
    required this.totalPaidPaise,
    required this.totalCancelledPaise,
    required this.entries,
  });

  double get totalEarnedRupees => totalEarnedPaise / 100.0;
  double get totalPendingRupees => totalPendingPaise / 100.0;
  double get totalPaidRupees => totalPaidPaise / 100.0;
  double get totalCancelledRupees => totalCancelledPaise / 100.0;

  bool get isEmpty => entries.isEmpty;

  factory ReferralEarningsResponse.fromJson(Map<String, dynamic> json) {
    final entries = <ReferralEarningEntry>[];
    final raw = json['entries'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          entries.add(ReferralEarningEntry.fromJson(item));
        } else if (item is Map) {
          entries.add(
            ReferralEarningEntry.fromJson(
              item.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          );
        }
      }
    }

    final totalEarned = _intOrNull(json['totalEarnedPaise']) ?? 0;
    final totalPending = _intOrNull(json['totalPendingPaise']) ?? 0;
    final totalPaid = _intOrNull(json['totalPaidPaise']) ?? 0;
    final totalCancelled = _intOrNull(json['totalCancelledPaise']) ?? 0;

    return ReferralEarningsResponse(
      totalEarnedPaise: totalEarned,
      totalPendingPaise: totalPending,
      totalPaidPaise: totalPaid,
      totalCancelledPaise: totalCancelled,
      entries: entries,
    );
  }
}

class ReferralWithdrawalRequestModel {
  final String id;
  final int amountPaise;
  final String status;
  final String? note;
  final String? adminNote;
  final int ledgerCount;
  final DateTime? processedAt;
  final String? processedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ReferralWithdrawalRequestModel({
    required this.id,
    required this.amountPaise,
    required this.status,
    this.note,
    this.adminNote,
    required this.ledgerCount,
    this.processedAt,
    this.processedBy,
    this.createdAt,
    this.updatedAt,
  });

  double get amountRupees => amountPaise / 100.0;

  factory ReferralWithdrawalRequestModel.fromJson(Map<String, dynamic> json) {
    return ReferralWithdrawalRequestModel(
      id: _stringOrNull(json['id']) ?? '',
      amountPaise: _intOrNull(json['amountPaise']) ?? 0,
      status: _stringOrNull(json['status']) ?? 'pending',
      note: _stringOrNull(json['note']),
      adminNote: _stringOrNull(json['adminNote']),
      ledgerCount: _intOrNull(json['ledgerCount']) ?? 0,
      processedAt: _dateTimeOrNull(json['processedAt']),
      processedBy: _stringOrNull(json['processedBy']),
      createdAt: _dateTimeOrNull(json['createdAt']),
      updatedAt: _dateTimeOrNull(json['updatedAt']),
    );
  }
}

class ReferralConfig {
  final Map<int, double> levelPercentages;
  final int? minimumActivationAmount;
  final int? minimumTopUpAmount;
  final double? gstRate;
  final String? shareUrlTemplate;

  const ReferralConfig({
    required this.levelPercentages,
    this.minimumActivationAmount,
    this.minimumTopUpAmount,
    this.gstRate,
    this.shareUrlTemplate,
  });

  factory ReferralConfig.fromJson(Map<String, dynamic> json) {
    final levels = <int, double>{};
    final levelsRaw = json['levels'] ?? json['percentages'] ?? json['levelPercentages'];
    if (levelsRaw is List) {
      int idx = 1;
      for (final item in levelsRaw) {
        if (item is num) {
          // Server may return decimals for percentages (e.g., 0.1 for 10%)
          final value = item.toDouble();
          levels[idx] = value;
          idx += 1;
        } else if (item is Map) {
          final map = item.map<String, dynamic>(
            (key, value) => MapEntry(key.toString(), value),
          );
          final level = _intOrNull(map['level']) ?? _intOrNull(map['depth']) ?? idx;
          final pct = _doubleOrNull(map['percentage'] ?? map['value']);
          if (pct != null) {
            levels[level] = pct;
            idx = level + 1;
          }
        }
      }
    } else if (levelsRaw is Map) {
      levelsRaw.forEach((key, value) {
        final level = _intOrNull(key) ?? _intOrNull(value?['level']);
        final pct = _doubleOrNull(value);
        if (level != null && pct != null) {
          levels[level] = pct;
        }
      });
    }

    final minActivation = _intOrNull(
      json['minimumActivationRupees'] ??
          json['minimumActivationAmount'] ??
          json['minimumActivation'],
    );
    final minTopUp = _intOrNull(
      json['minimumTopupRupees'] ??
          json['minimumTopUpRupees'] ??
          json['minimumTopupAmount'],
    );
    final gst = _doubleOrNull(json['gstRate']);
    final template = _stringOrNull(json['shareUrlTemplate'] ?? json['shareTemplate'] ?? json['shareBaseUrl']);

    return ReferralConfig(
      levelPercentages: levels,
      minimumActivationAmount: minActivation,
      minimumTopUpAmount: minTopUp,
      gstRate: gst,
      shareUrlTemplate: template,
    );
  }
}
