import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'db_helper.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:pasteboard/pasteboard.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'roadway'),
      debugShowCheckedModeBanner: false, // Add this line
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _dragging = false;
  bool _clipboardHasContent = false;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    final clipboardContent = await Pasteboard.text;
    setState(() {
      _clipboardHasContent =
          clipboardContent != null && clipboardContent.isNotEmpty;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  String _generateId(String filePath) {
    final bytes = utf8.encode(filePath);
    return sha256.convert(bytes).toString();
  }

  Future<void> _handleFileDrop(List<String> filePaths) async {
    List<String> newFiles = [];
    List<String> existingFiles = [];

    for (String filePath in filePaths) {
      final id = _generateId(filePath);
      final exists = await DatabaseHelper.instance.itemExists(id);

      if (exists) {
        existingFiles.add(filePath);
      } else {
        newFiles.add(filePath);
      }
    }

    if (newFiles.isNotEmpty || existingFiles.isNotEmpty) {
      _showDroppedFilesDialog(newFiles, existingFiles);
    }
  }

  void _showDroppedFilesDialog(
      List<String> newFiles, List<String> existingFiles) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(newFiles.isEmpty
              ? 'Files Already Exist'
              : 'Confirm File Addition'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                if (newFiles.isNotEmpty) ...[
                  Text('New files to be added:'),
                  ...newFiles.map((file) => Text('- ${path.basename(file)}')),
                  SizedBox(height: 10),
                ],
                if (existingFiles.isNotEmpty) ...[
                  Text(
                      'Files already in database ${newFiles.isEmpty ? '(no action needed)' : '(will be skipped)'}:'),
                  ...existingFiles
                      .map((file) => Text('- ${path.basename(file)}')),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            if (newFiles.isNotEmpty) ...[
              TextButton(
                child: Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _showSnackBar('Operation cancelled. No files were added.');
                },
              ),
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _commitNewFiles(newFiles);
                },
              ),
            ] else
              TextButton(
                child: Text('Close'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _showSnackBar(
                      'All files already exist in the database. No changes made.');
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _commitNewFiles(List<String> newFiles) async {
    for (String filePath in newFiles) {
      final id = _generateId(filePath);
      await DatabaseHelper.instance.insertItemIfNotExists(
        id,
        'file',
        filePath,
        parent: path.dirname(filePath),
      );
    }
    _showSnackBar(
        '${newFiles.length} new file(s) added to database successfully.');
  }

  void _checkDatabase() async {
    await DatabaseHelper.instance.printAllItems();
  }

  Future<void> _handleClipboardContent() async {
    final clipboardContent = await Pasteboard.text;
    if (clipboardContent == null || clipboardContent.isEmpty) return;

    final List<String> urls = [];
    final List<String> filePaths = [];

    final lines = clipboardContent.split('\n');
    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      if (line.startsWith('http://') || line.startsWith('https://')) {
        urls.add(line.trim());
      } else {
        final mdMatch =
            RegExp(r'(?:[*-]\s)?\[(?<title>.*)\]\((?<url>https?:\/\/[^\s]+)\)')
                .firstMatch(line);
        if (mdMatch != null) {
          urls.add(mdMatch.namedGroup('url')!);
        } else if (await File(line.trim()).exists()) {
          filePaths.add(line.trim());
        }
      }
    }

    if (urls.isEmpty && filePaths.isEmpty) {
      _showSnackBar('No valid URLs or file paths found in clipboard.');
      return;
    }

    _showClipboardContentDialog(urls, filePaths);
  }

  void _showClipboardContentDialog(List<String> urls, List<String> filePaths) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Content Addition'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                if (urls.isNotEmpty) ...[
                  Text('URLs to be added:'),
                  ...urls.map((url) => Text('- $url')),
                  SizedBox(height: 10),
                ],
                if (filePaths.isNotEmpty) ...[
                  Text('File paths to be added:'),
                  ...filePaths.map((file) => Text('- ${path.basename(file)}')),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                _showSnackBar('Operation cancelled. No content was added.');
              },
            ),
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                _commitClipboardContent(urls, filePaths);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _commitClipboardContent(
      List<String> urls, List<String> filePaths) async {
    int addedCount = 0;

    for (String url in urls) {
      final id = _generateId(url);
      final exists = await DatabaseHelper.instance.itemExists(id);
      if (!exists) {
        await DatabaseHelper.instance.insertItemIfNotExists(id, 'url', url);
        addedCount++;
      }
    }

    for (String filePath in filePaths) {
      final id = _generateId(filePath);
      final exists = await DatabaseHelper.instance.itemExists(id);
      if (!exists) {
        await DatabaseHelper.instance.insertItemIfNotExists(
          id,
          'file',
          filePath,
          parent: path.dirname(filePath),
        );
        addedCount++;
      }
    }

    String snackMessage = addedCount > 0 ?
      '$addedCount new item(s) added to database successfully.' 
      : 'URL(s) or file(s) already in DB, no new items added.';
    _showSnackBar(snackMessage);
    _checkClipboard();
  }

  void _showDraggingSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Drop file(s) to ingest'),
        duration: Duration(days: 1), // Long duration, we'll dismiss it manually
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          Tooltip(
            message: 'Ingest from clipboard',
            child: IconButton(
              icon: Icon(Icons.content_paste),
              onPressed: _clipboardHasContent ? _handleClipboardContent : null,
            ),
          ),
        ],
      ),
      body: DropTarget(
        onDragDone: (detail) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          _handleFileDrop(detail.files.map((xFile) => xFile.path).toList());
        },
        onDragEntered: (detail) {
          setState(() {
            _dragging = true;
          });
          _showDraggingSnackBar();
        },
        onDragExited: (detail) {
          setState(() {
            _dragging = false;
          });
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        },
        child: Container(
          color: _dragging ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          child: Center(
            child: Text(
              'Your main content goes here',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _checkDatabase,
        tooltip: 'DB console dump',
        child: Icon(Icons.list),
      ),
    );
  }
}
