import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String title;

  const PdfViewerScreen({Key? key, required this.url, required this.title})
      : super(key: key);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? localPath;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _downloadPdf();
  }

  Future<void> _downloadPdf() async {
    try {
      final response = await http.get(Uri.parse(widget.url));

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File("${dir.path}/${DateTime.now().millisecondsSinceEpoch}.pdf");
        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          localPath = file.path;
          loading = false;
        });
      } else {
        throw Exception("No se pudo descargar el PDF");
      }
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error cargando PDF: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : localPath == null
              ? const Center(child: Text("No se pudo cargar el PDF"))
              : PDFView(
                  filePath: localPath!,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                ),
    );
  }
}
