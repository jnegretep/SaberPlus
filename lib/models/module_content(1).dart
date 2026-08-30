class ModuleContent {
  final String? filename;
  final String? fileurl;
  final String? mimetype;
  final String? type;
  final String? content;

  ModuleContent({
    this.filename,
    this.fileurl,
    this.mimetype,
    this.type,
    this.content,
  });

  factory ModuleContent.fromJson(Map<String, dynamic> json) {
    return ModuleContent(
      filename: json['filename']?.toString(),
      fileurl: json['fileurl']?.toString(),
      mimetype: json['mimetype']?.toString(),
      type: json['type']?.toString(),
      content: json['content']?.toString(),
    );
  }

  static ModuleContent empty() => ModuleContent(content: '');
}
