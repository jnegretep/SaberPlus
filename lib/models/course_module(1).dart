import 'module_content.dart';

class CourseModule {
  final int id;
  final String name;
  final String modName;
  final String? url;
  final int? instanceId;
  final int? timelimit;
  final String? type;
  final List<ModuleContent> contents;

  CourseModule({
    required this.id,
    required this.name,
    required this.modName,
    this.url,
    this.instanceId,
    this.timelimit,
    this.type,
    required this.contents,
  });

  factory CourseModule.fromJson(Map<String, dynamic> json) {
    // ✅ contents puede venir como "", null o []
    List<ModuleContent> parsedContents = [];

    final rawContents = json['contents'];

    if (rawContents is List) {
      parsedContents =
          rawContents.map((c) => ModuleContent.fromJson(c)).toList();
    }

    return CourseModule(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      name: json['name']?.toString() ?? 'Recurso sin nombre',
      modName: json['modname']?.toString() ?? 'unknown',
      url: json['url']?.toString(),
      instanceId: json['instance'] is int
          ? json['instance']
          : int.tryParse('${json['instance']}'),
      timelimit: json['timelimit'] is int
          ? json['timelimit']
          : int.tryParse('${json['timelimit']}'),
      type: json['modtype']?.toString(),
      contents: parsedContents,
    );
  }

  bool get isQuiz => modName == 'quiz';
  bool get isVideo =>
      contents.any((c) => c.filename != null && c.filename!.endsWith('.mp4'));
  bool get isPage => modName == 'page';
  bool get isBook => modName == 'book';
  bool get isLesson => modName == 'lesson';
  bool get isLabel => modName == 'label';

  int? get quizId => instanceId ?? id;

  List<String> get files =>
      contents.where((c) => c.fileurl != null).map((c) => c.fileurl!).toList();

  String get content => contents.isNotEmpty
      ? (contents.first.content ?? '')
      : '';
}
