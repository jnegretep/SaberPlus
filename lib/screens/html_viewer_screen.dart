import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class HtmlViewerScreen extends StatelessWidget {
  final String title;
  final String html;

  const HtmlViewerScreen({
    Key? key,
    required this.title,
    required this.html,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HtmlWidget(html),
      ),
    );
  }
}
