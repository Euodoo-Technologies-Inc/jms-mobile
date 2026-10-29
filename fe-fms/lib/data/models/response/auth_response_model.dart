import 'dart:convert';

/// Response model for authentication requests.
class AuthResponseModel {
  final bool? success;
  final Data? data;

  AuthResponseModel({this.success, this.data});

  factory AuthResponseModel.fromJson(String str) =>
      AuthResponseModel.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory AuthResponseModel.fromMap(Map<String, dynamic> json) {
    final data = json["Data"] ?? json["data"];
    return AuthResponseModel(
      success: json["Success"] ?? json["success"],
      data: data == null ? null : Data.fromMap(data),
    );
  }

  Map<String, dynamic> toMap() => {"Success": success, "Data": data?.toMap()};
}

/// Data object containing user and company information.
class Data {
  final int? userId;
  final String? apiKey;
  final String? company;
  final int? companyId;
  final int? companyType;
  final String? companyLabel;
  final bool? hasTraxroot;
  final String? fullname;
  final String? email;

  Data({
    this.userId,
    this.apiKey,
    this.company,
    this.companyId,
    this.companyType,
    this.companyLabel,
    this.hasTraxroot,
    this.fullname,
    this.email,
  });

  factory Data.fromJson(String str) => Data.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory Data.fromMap(Map<String, dynamic> json) => Data(
    userId: json["UserID"] ?? json["userId"] ?? json["user_id"],
    apiKey: json["ApiKey"] ?? json["apiKey"] ?? json["api_key"],
    company: json["Company"] ?? json["company"],
    companyId: json["CompanyID"] ?? json["companyId"] ?? json["company_id"],
    companyType: json["CompanyType"] ?? json["companyType"] ?? json["company_type"],
    companyLabel: json["CompanyLabel"] ?? json["companyLabel"] ?? json["company_label"],
    hasTraxroot: _parseBool(json["HasTraxroot"] ?? json["hasTraxroot"] ?? json["has_traxroot"]),
    fullname: json["Fullname"] ?? json["fullname"] ?? json["FullName"] ?? json["full_name"],
    email: json["Email"] ?? json["email"],
  );

  /// Parses a value to bool, handling bool, int (1/0), and string ("true"/"1").
  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      return lower == 'true' || lower == '1';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    "UserID": userId,
    "ApiKey": apiKey,
    "Company": company,
    "CompanyID": companyId,
    "CompanyType": companyType,
    "CompanyLabel": companyLabel,
    "HasTraxroot": hasTraxroot,
    "Fullname": fullname,
    "Email": email,
  };
}
