class Attempt {
  final int id;
  final int uniqueId;
  final int timelimit;
  final int timestart;
  final int timefinish;
  final int? timeleft;

  Attempt({
    required this.id,
    required this.uniqueId,
    required this.timelimit,
    required this.timestart,
    required this.timefinish,
    this.timeleft,
  });

  factory Attempt.fromJson(Map<String, dynamic> json) {
    return Attempt(
      id: json['attemptid'] ?? json['id'] ?? 0,
      uniqueId: json['uniqueid'] ?? 0,
      timelimit: json['timelimit'] ?? 0,
      timestart: json['timestart'] ?? 0,
      timefinish: json['timefinish'] ?? 0,
      timeleft: json['timeleft'],
    );
  }

  /// ✅ Constructor auxiliar si necesitas crear un intento desde el cliente (por ejemplo en startAttempt)
  factory Attempt.manual({
    required int id,
    required int timelimit,
    required int timestart,
    required int timefinish,
    int? timeleft,
  }) {
    return Attempt(
      id: id,
      uniqueId: id,
      timelimit: timelimit,
      timestart: timestart,
      timefinish: timefinish,
      timeleft: timeleft,
    );
  }
}
