import 'course_module.dart';

class CourseSection {
  final int id;
  final String name;
  final String? summary;
  final List<String> files;
  final List<CourseModule> modules;

  CourseSection({
    required this.id,
    required this.name,
    this.summary,
    required this.files,
    required this.modules,
  });

  factory CourseSection.fromJson(Map<String, dynamic> json) {
    // ✅ modules puede venir como "", null o []
    List<CourseModule> parsedModules = [];

    if (json['modules'] is List) {
      parsedModules = (json['modules'] as List)
          .map((m) => CourseModule.fromJson(m))
          .toList();
    }

    return CourseSection(
      id: json['sectionid'] is int
          ? json['sectionid']
          : int.tryParse('${json['sectionid']}') ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      summary: json['summary']?.toString(),
      files: (json['files'] as List?)
              ?.map((f) => f.toString())
              .toList() ??
          [],
      modules: parsedModules,
    );
  }
}
