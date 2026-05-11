/// Rider profile returned by `/auth/login`, `/auth/activate`, and `/me`.
class DispatchRider {
  DispatchRider({
    required this.userId,
    required this.phone,
    required this.fullname,
    this.companyId,
    this.category,
    this.license,
  });

  final int userId;
  final String phone;
  final String fullname;
  final int? companyId;
  final String? category;
  final String? license;

  factory DispatchRider.fromJson(Map<String, dynamic> json) {
    return DispatchRider(
      userId: (json['user_id'] as num).toInt(),
      phone: json['phone']?.toString() ?? '',
      fullname: json['fullname']?.toString() ?? '',
      companyId: (json['company_id'] as num?)?.toInt(),
      category: json['category']?.toString(),
      license: json['license']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'phone': phone,
        'fullname': fullname,
        if (companyId != null) 'company_id': companyId,
        if (category != null) 'category': category,
        if (license != null) 'license': license,
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
