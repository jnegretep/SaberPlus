class AdModel {
  final int id;
  final String title;
  final String type; // image | video
  final String mediaUrl;
  final String? targetUrl;
  final String position;
  final int minViewSeconds;
  final bool showCloseImmediately;

  AdModel({
    required this.id,
    required this.title,
    required this.type,
    required this.mediaUrl,
    required this.position,
    required this.minViewSeconds,
    required this.showCloseImmediately,
    this.targetUrl,
  });

  factory AdModel.fromJson(Map<String, dynamic> json) {
    return AdModel(
      id: json['id'],
      title: json['title'],
      type: json['type'],
      mediaUrl: json['media_url'],
      targetUrl: json['target_url'],
      position: json['position'],
      minViewSeconds: json['min_view_seconds'],
      showCloseImmediately: json['show_close_immediately'],
    );
  }
}
