import 'dart:convert';

import 'package:fms/core/constants/variables.dart';

/// Response model for fetching job history.
class GetJobHistoryResponseModel {
  final bool? success;
  final List<Data>? data;

  GetJobHistoryResponseModel({this.success, this.data});

  factory GetJobHistoryResponseModel.fromJson(String str) =>
      GetJobHistoryResponseModel.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory GetJobHistoryResponseModel.fromMap(Map<String, dynamic> json) =>
      GetJobHistoryResponseModel(
        success: json["Success"],
        data: json["Data"] == null
            ? []
            : List<Data>.from(json["Data"]!.map((x) => Data.fromMap(x))),
      );

  Map<String, dynamic> toMap() => {
    "Success": success,
    "Data": data == null ? [] : List<dynamic>.from(data!.map((x) => x.toMap())),
  };
}

/// Data object representing a historical job entry.
class Data {
  final int? jobId;
  final String? jobName;
  final int? userId;
  final int? customerId;
  final int? typeJob;
  final String? createdBy;
  final DateTime? jobDate;
  final DateTime? createdAt;
  final dynamic assignWhen;
  final String? customerName;
  final String? phoneNumber;
  final String? address;
  final double? latitude;
  final double? longitude;
  final List<JobDetail>? details;

  Data({
    this.jobId,
    this.jobName,
    this.userId,
    this.customerId,
    this.typeJob,
    this.createdBy,
    this.jobDate,
    this.createdAt,
    this.assignWhen,
    this.customerName,
    this.phoneNumber,
    this.address,
    this.latitude,
    this.longitude,
    this.details,
  });

  factory Data.fromJson(String str) => Data.fromMap(json.decode(str));

  String toJson() => json.encode(toMap());

  factory Data.fromMap(Map<String, dynamic> json) => Data(
    jobId: json["JobID"],
    jobName: json["JobName"],
    userId: json["UserID"],
    customerId: json["CustomerID"],
    typeJob: json["TypeJob"],
    createdBy: json["CreatedBy"]?.toString(),
    jobDate: json["JobDate"] == null ? null : DateTime.parse(json["JobDate"]),
    createdAt: json["created_at"] == null
        ? null
        : DateTime.parse(json["created_at"]),
    assignWhen: json["AssignWhen"],
    customerName: json["CustomerName"],
    phoneNumber: json["PhoneNumber"],
    address: json["Address"],
    latitude: _parseDouble(json["Latitude"]),
    longitude: _parseDouble(json["Longitude"]),
    details: json["details"] == null && json["Details"] == null
        ? null
        : List<JobDetail>.from(
            (json["details"] ?? json["Details"])!.map((x) => JobDetail.fromMap(x)),
          ),
  );

  Map<String, dynamic> toMap() => {
    "JobID": jobId,
    "JobName": jobName,
    "UserID": userId,
    "CustomerID": customerId,
    "TypeJob": typeJob,
    "CreatedBy": createdBy,
    "JobDate": jobDate == null
        ? null
        : "${jobDate!.year.toString().padLeft(4, '0')}-${jobDate!.month.toString().padLeft(2, '0')}-${jobDate!.day.toString().padLeft(2, '0')}",
    "created_at": createdAt?.toIso8601String(),
    "AssignWhen": assignWhen,
    "CustomerName": customerName,
    "PhoneNumber": phoneNumber,
    "Address": address,
    "Latitude": latitude,
    "Longitude": longitude,
    "details": details == null
        ? null
        : List<dynamic>.from(details!.map((x) => x.toMap())),
  };
}

/// A detail entry for a completed job, may include a photo.
class JobDetail {
  final int? detailId;
  final int? listJobId;
  final String? photo;
  final DateTime? createdAt;

  JobDetail({this.detailId, this.listJobId, this.photo, this.createdAt});

  factory JobDetail.fromMap(Map<String, dynamic> json) => JobDetail(
    detailId: json['ListDetailID'] ?? json['detailId'],
    listJobId: json['ListJobID'] ?? json['listJobId'],
    photo: (json['Photo'] ?? json['photo'])?.toString(),
    createdAt: json['created_at'] == null
        ? null
        : DateTime.tryParse(json['created_at'].toString()),
  );

  Map<String, dynamic> toMap() => {
    'ListDetailID': detailId,
    'ListJobID': listJobId,
    'Photo': photo,
    'created_at': createdAt?.toIso8601String(),
  };

  /// Returns the full photo URL, handling both relative and absolute paths.
  String? get photoUrl {
    if (photo == null || photo!.isEmpty) return null;
    if (photo!.startsWith('http://') || photo!.startsWith('https://')) {
      return photo;
    }
    return '${Variables.baseUrl}/$photo';
  }
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String && value.isNotEmpty) {
    return double.tryParse(value);
  }
  return null;
}
