/// Rider profile returned by `/auth/login`, `/auth/activate`, and `/me`.
class DispatchRider {
  DispatchRider({
    required this.userId,
    required this.phone,
    required this.fullname,
    this.companyId,
    this.category,
    this.license,
    this.riderId,
    this.vehicleName,
    this.externalSource,
  });

  final int userId;
  final String phone;
  final String fullname;
  final int? companyId;
  final String? category;
  final String? license;

  /// From `/me` only (older backends and login omit them).
  final int? riderId;
  final String? vehicleName;

  /// `ormeco_mcs` for an ORMECO crew, null for our own riders.
  final String? externalSource;

  factory DispatchRider.fromJson(Map<String, dynamic> json) {
    return DispatchRider(
      userId: (json['user_id'] as num).toInt(),
      phone: json['phone']?.toString() ?? '',
      fullname: json['fullname']?.toString() ?? '',
      companyId: (json['company_id'] as num?)?.toInt(),
      category: json['category']?.toString(),
      license: json['license']?.toString(),
      riderId: (json['rider_id'] as num?)?.toInt(),
      vehicleName: json['vehicle_name']?.toString() ??
          (json['vehicle'] is Map ? json['vehicle']['vehicle_name']?.toString() : null),
      externalSource: json['external_source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'phone': phone,
        'fullname': fullname,
        if (companyId != null) 'company_id': companyId,
        if (category != null) 'category': category,
        if (license != null) 'license': license,
        if (riderId != null) 'rider_id': riderId,
        if (vehicleName != null) 'vehicle_name': vehicleName,
        if (externalSource != null) 'external_source': externalSource,
      };
}

/// Company info returned by `/me`. Nullable on the response (edge case).
class DispatchCompany {
  DispatchCompany({required this.id, required this.name, this.tier});

  final int id;
  final String name;
  final String? tier;

  factory DispatchCompany.fromJson(Map<String, dynamic> json) {
    return DispatchCompany(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      tier: json['tier']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (tier != null) 'tier': tier,
      };
}
