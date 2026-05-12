/// A single proof-of-work photo attached to a finished job.
///
/// `url` is the renderable signed image URL (null on older backends).
class DispatchJobPhoto {
  DispatchJobPhoto({
    required this.id,
    required this.filename,
    this.url,
  });

  final int id;
  final String filename;
  final String? url;

  factory DispatchJobPhoto.fromJson(Map<String, dynamic> json) {
    return DispatchJobPhoto(
      id: (json['id'] as num).toInt(),
      filename: json['photo']?.toString() ?? '',
      url: json['url']?.toString(),
    );
  }
}

/// Job entity from `/jobs/today` and `/jobs/{id}`.
///
/// Status semantics:
///   null → assigned, not yet started
///   1    → on-the-way (rider called /start)
///   2    → finished
///   3    → reschedule pending (admin action; read-only for rider)
class DispatchJob {
  DispatchJob({
    required this.id,
    required this.jobName,
    this.status,
    this.jobDate,
    this.address,
    this.lat,
    this.lng,
    this.routeId,
    this.routeOrder,
    this.scheduledArrival,
    this.actualArrival,
    this.finishWhen,
    this.createdAt,
    this.customer,
    this.serviceType,
    this.notes,
    this.photos,
  });

  final int id;
  final String jobName;
  final int? status;
  final String? jobDate;
  final String? address;
  final double? lat;
  final double? lng;
  final int? routeId;
  final int? routeOrder;
  final String? scheduledArrival;
  final String? actualArrival;
  final String? finishWhen;
  final String? createdAt;
  final String? customer;
  final String? serviceType;
  final String? notes;

  /// `null` on the today list, possibly-empty list on the detail/finish view.
  final List<DispatchJobPhoto>? photos;

  bool get isAssigned => status == null;
  bool get isOnTheWay => status == 1;
  bool get isFinished => status == 2;
  bool get isReschedulePending => status == 3;

  factory DispatchJob.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    List<DispatchJobPhoto>? photos;
    if (rawPhotos is List) {
      photos = rawPhotos
          .whereType<Map<String, dynamic>>()
          .map(DispatchJobPhoto.fromJson)
          .toList(growable: false);
    }
    return DispatchJob(
      id: (json['id'] as num).toInt(),
      jobName: json['job_name']?.toString() ?? 'Untitled job',
      status: (json['status'] as num?)?.toInt(),
      jobDate: json['job_date']?.toString(),
      address: json['address']?.toString(),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      routeId: (json['route_id'] as num?)?.toInt(),
      routeOrder: (json['route_order'] as num?)?.toInt(),
      scheduledArrival: json['scheduled_arrival']?.toString(),
      actualArrival: json['actual_arrival']?.toString(),
      finishWhen: json['finish_when']?.toString(),
      createdAt: json['created_at']?.toString(),
      customer: json['customer']?.toString() ?? json['customer_name']?.toString(),
      serviceType: json['service_type']?.toString() ?? json['service']?.toString(),
      notes: json['notes']?.toString(),
      photos: photos,
    );
  }
}
