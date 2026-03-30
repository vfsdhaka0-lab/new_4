import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/github_service.dart';
import '../models/project_model.dart';
import '../services/ultra_update_service.dart';

import '../widgets/code_editor.dart';
import '../widgets/ide_toolbar.dart';
import '../widgets/file_explorer.dart';
import '../widgets/console_panel.dart';

class EditorScreen extends StatefulWidget {
  final ProjectModel project;

  const EditorScreen({super.key, required this.project});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final GitHubService github = GitHubService();

  String _filePath = "lib/main.dart";
  String _content = "";

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isChanged = false;

  /// ⚡ Build
  String _buildStatus = "idle";
  bool _isBuilding = false;

  /// 📂 Explorer
  double _explorerWidth = 250;
  bool _explorerCollapsed = false;

  /// 📜 Console
  final List<String> _consoleLogs = [];
  double _consoleHeight = 150;

  /// 📡 Update System (PRO MAX)
  late final UltraUpdateService _updater;

  /// ⚡ File Cache (Fix delay)
  final Map<String, String> _fileCache = {};

  /// 👤 User Profile
  String? _userName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();

    _updater = UltraUpdateService(
      repoOwner: "vfsdhaka0-lab",
      repoName: "android_mobile_ide",
      log: _appendLog,
    );

    _loadFile();
    _loadProfile();

    // 🚀 PRO MAX AUTO UPDATE
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;

      if (!await _isInternetAvailable()) return;

      await _updater.autoUpdate(context);
    });

    // 🔁 Periodic update check (every 10 min)
    Future.doWhile(() async {
      await Future.delayed(const Duration(minutes: 10));

      if (!mounted) return false;

      if (await _isInternetAvailable()) {
        await _updater.autoUpdate(context);
      }

      return true;
    });
  }

  // =========================
  // 👤 LOAD PROFILE
  // =========================
  Future<void> _loadProfile() async {
    try {
      final res = await http.get(
        Uri.parse("https://api.github.com/user"),
        headers: {
          "Authorization": "token ${github.token}",
          "Accept": "application/vnd.github+json",
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        if (!mounted) return;
        setState(() {
          _userName = data["login"];
          _avatarUrl = data["avatar_url"];
        });

        _appendLog("👤 User loaded: $_userName");
      }
    } catch (e) {
      _appendLog("❌ Profile load failed: $e");
    }
  }

  // =========================
  // 🌐 INTERNET CHECK
  // =========================
  Future<bool> _isInternetAvailable() async {
    try {
      final res = await http
          .get(Uri.parse("https://api.github.com"))
          .timeout(const Duration(seconds: 5));

      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // =========================
  // 📥 LOAD FILE
  // =========================
  Future<void> _loadFile() async {
    if (!await _isInternetAvailable()) {
      _show("No internet ❌", true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final data =
          await github.getFileContent(widget.project.repo, _filePath);

      _fileCache[_filePath] = data;

      if (!mounted) return;
      setState(() {
        _content = data;
        _isChanged = false;
      });

      _appendLog("📄 Loaded $_filePath");
    } catch (e) {
      _appendLog("❌ Load failed: $e");
      _show("Load failed", true);
    }

    setState(() => _isLoading = false);
  }

  // =========================
  // 📂 OPEN FILE (CACHE BOOST)
  // =========================
  Future<void> _openFile(String path, [String? _]) async {
    FocusScope.of(context).unfocus();

    // ⚡ Instant cache load
    if (_fileCache.containsKey(path)) {
      setState(() {
        _filePath = path;
        _content = _fileCache[path]!;
        _isChanged = false;
      });

      _appendLog("⚡ Opened from cache: $path");
      return;
    }

    if (!await _isInternetAvailable()) {
      _show("No internet ❌", true);
      return;
    }

    setState(() {
      _isLoading = true;
      _filePath = path;
    });

    try {
      final data =
          await github.getFileContent(widget.project.repo, path);

      _fileCache[path] = data;

      setState(() {
        _content = data;
        _isChanged = false;
      });

      _appendLog("📂 Opened $path");
    } catch (e) {
      _appendLog("❌ Open failed: $e");
      _show("Open failed", true);
    }

    setState(() => _isLoading = false);
  }

  // =========================
  // 💾 SAVE FILE
  // =========================
  Future<void> _saveFile() async {
    if (!await _isInternetAvailable()) return;

    setState(() => _isSaving = true);

    try {
      await github.saveFile(
        repo: widget.project.repo,
        path: _filePath,
        content: _content,
        message: "Update $_filePath",
      );

      _fileCache[_filePath] = _content;

      setState(() => _isChanged = false);

      _appendLog("💾 Saved successfully");
      _show("Saved", false);
    } catch (e) {
      _appendLog("❌ Save failed: $e");
      _show("Save failed", true);
    }

    setState(() => _isSaving = false);
  }

  // =========================
  // 🚀 BUILD
  // =========================
  Future<void> _runBuild() async {
    if (_isBuilding) return;

    if (!await _isInternetAvailable()) {
      _show("No internet ❌", true);
      return;
    }

    setState(() {
      _isBuilding = true;
      _buildStatus = "building";
    });

    _appendLog("🚀 Starting build...");

    try {
      await github.triggerBuild(widget.project.repo);

      final result =
          await github.waitForWorkflowCompletion(widget.project.repo);

      setState(() {
        _buildStatus = result ? "success" : "failed";
        _isBuilding = false;
      });

      _appendLog("🏁 Build ${_buildStatus.toUpperCase()}");
    } catch (e) {
      _appendLog("❌ Build failed: $e");

      setState(() {
        _buildStatus = "failed";
        _isBuilding = false;
      });
    }
  }

  // =========================
  // 🔄 REFRESH
  // =========================
  Future<void> _refresh() async {
    _fileCache.clear();
    await _loadFile();
    _appendLog("🔄 Refreshed");
  }

  // =========================
  // 🧠 HELPERS
  // =========================
  void _appendLog(String msg) {
    if (!mounted) return;
    setState(() => _consoleLogs.add(msg));
  }

  void _show(String msg, bool error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (!_isChanged) return true;

    return await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Unsaved Changes"),
            content: const Text("Discard changes?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel")),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Discard")),
            ],
          ),
        ) ??
        false;
  }

  String _detectLanguage(String path) {
    final ext = path.split('.').last;

    switch (ext) {
      case 'dart':
        return 'dart';
      case 'js':
        return 'javascript';
      case 'py':
        return 'python';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'md':
        return 'markdown';
      default:
        return 'text';
    }
  }

  void _toggleExplorer() {
    setState(() {
      _explorerCollapsed = !_explorerCollapsed;
      _explorerWidth = _explorerCollapsed ? 0 : 250;
    });
  }

  // =========================
  // 🖥 UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              if (_avatarUrl != null)
                CircleAvatar(
                  radius: 14,
                  backgroundImage: NetworkImage(_avatarUrl!),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _filePath,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            if (_userName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(
                    _userName!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            IconButton(
              icon: Icon(
                  _explorerCollapsed ? Icons.arrow_right : Icons.arrow_left),
              onPressed: _toggleExplorer,
            ),
          ],
        ),
        body: Row(
          children: [
            AnimatedContainer(
              width: _explorerWidth,
              duration: const Duration(milliseconds: 200),
              child: _explorerCollapsed
                  ? const SizedBox.shrink()
                  : FileExplorer(
                      repo: widget.project.repo,
                      currentFile: _filePath,
                      onFileOpen: _openFile,
                    ),
            ),
            Expanded(
              child: Column(
                children: [
                  IDEToolbar(
                    projectName: widget.project.name,
                    buildStatus: _buildStatus,
                    isSavingAll: _isSaving,
                    isBuilding: _isBuilding,
                    onSaveAll: _saveFile,
                    onRun: _runBuild,
                    onRefresh: _refresh,
                  ),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : CodeEditor(
                            key: ValueKey(_filePath),
                            initialCode: _content,
                            language: _detectLanguage(_filePath),
                            fileName: _filePath,
                            onChanged: (val) {
                              _content = val;
                              _isChanged = true;
                            },
                          ),
                  ),
                  Container(
                    height: _consoleHeight,
                    color: Colors.black,
                    child: ConsolePanel(
                      logs: _consoleLogs,
                      repo: widget.project.repo,
                      enablePolling: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}