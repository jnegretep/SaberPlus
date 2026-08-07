import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class FileViewerScreen extends StatefulWidget {
  final String url;
  final String filename;

  const FileViewerScreen({
    Key? key,
    required this.url,
    required this.filename,
  }) : super(key: key);

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  bool downloading = false;
  double progress = 0;

  Future<void> downloadFile() async {
    var status = await Permission.storage.request();
    if (!status.isGranted) return;

    final dir = await getApplicationDocumentsDirectory();
    final filePath = "${dir.path}/${widget.filename}";

    setState(() {
      downloading = true;
      progress = 0;
    });

    await Dio().download(
      widget.url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          setState(() => progress = received / total);
        }
      },
    );

    setState(() => downloading = false);

    await OpenFilex.open(filePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.filename)),
      body: Center(
        child: downloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text("${(progress * 100).toStringAsFixed(0)}%"),
                ],
              )
            : ElevatedButton.icon(
                icon: Icon(Icons.download),
                label: const Text("Descargar y abrir"),
                onPressed: downloadFile,
              ),
      ),
    );
  }
}
