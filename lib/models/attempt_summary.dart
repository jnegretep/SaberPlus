class AttemptSummary {
  final int id;
  final String state;
  final double? sumgrades;
  final int timestart;
  final int? timefinish;

  AttemptSummary({
    required this.id,
    required this.state,
    this.sumgrades,
    required this.timestart,
    this.timefinish,
  });

  factory AttemptSummary.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return AttemptSummary(
      id: _toInt(json['id']),
      state: json['state']?.toString() ?? '',
      sumgrades: _toDouble(json['sumgrades']),
      timestart: _toInt(json['timestart']),
      timefinish: json['timefinish'] != null ? _toInt(json['timefinish']) : null,
    );
  }
}