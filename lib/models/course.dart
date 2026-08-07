class Course {
  final int id;
  final String fullname;
  final String shortname;
  final int startdate;
  final int enddate;
  final bool visible;
  final double? progress; 
  bool attempted;         
  final bool locked;      // 👈 NUEVO: control de paywall

  Course({
    required this.id,
    required this.fullname,
    required this.shortname,
    required this.startdate,
    required this.enddate,
    required this.visible,
    this.progress,
    this.attempted = false,
    this.locked = false, // por defecto no bloqueado
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] is int
          ? json['id'] as int
          : int.parse(json['id'].toString()),
      fullname: json['fullname'] as String,
      shortname: json['shortname'] as String,
      startdate: json['startdate'] is int
          ? json['startdate'] as int
          : int.parse(json['startdate'].toString()),
      enddate: json['enddate'] is int
          ? json['enddate'] as int
          : int.parse(json['enddate'].toString()),
      visible: json['visible'] is bool
          ? json['visible'] as bool
          : json['visible'].toString() == '1',
      progress: json['progress'] != null
          ? (json['progress'] is num
              ? (json['progress'] as num).toDouble()
              : double.tryParse(json['progress'].toString()))
          : null,
      attempted: (json['attempted'] is bool)
          ? json['attempted'] as bool
          : (json['attempted']?.toString() == '1') || false,
      locked: (json['locked'] is bool)
          ? json['locked'] as bool
          : (json['locked']?.toString() == '1') || false, // 👈 PAYWALL
    );
  }

  /// Para simplificar UI
  String get name => fullname;

  /// copyWith para marcar intentos
  Course copyWith({
    bool? attempted,
    double? progress,
    bool? locked,
  }) {
    return Course(
      id: id,
      fullname: fullname,
      shortname: shortname,
      startdate: startdate,
      enddate: enddate,
      visible: visible,
      progress: progress ?? this.progress,
      attempted: attempted ?? this.attempted,
      locked: locked ?? this.locked,
    );
  }
}
