import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

const MethodChannel _channel = MethodChannel('com.example.floating_teleprompter/overlay');

// ============================================================================
// Models
// ============================================================================

class ScriptEntry {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScriptEntry({
    String? id,
    required this.title,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ScriptEntry.fromJson(Map<String, dynamic> json) => ScriptEntry(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Untitled',
        content: json['content'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );

  ScriptEntry copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ScriptEntry(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class TeleprompterSettings {
  final double speed;
  final double textSize;
  final double lineSpacing;
  final double opacity;
  final bool showControls;
  final int countdownSeconds;

  const TeleprompterSettings({
    this.speed = 120.0,
    this.textSize = 46.0,
    this.lineSpacing = 1.5,
    this.opacity = 0.95,
    this.showControls = true,
    this.countdownSeconds = 3,
  });

  Map<String, dynamic> toJson() => {
        'speed': speed,
        'textSize': textSize,
        'lineSpacing': lineSpacing,
        'opacity': opacity,
        'showControls': showControls,
        'countdownSeconds': countdownSeconds,
      };

  factory TeleprompterSettings.fromJson(Map<String, dynamic> json) =>
      TeleprompterSettings(
        speed: (json['speed'] as num?)?.toDouble() ?? 120.0,
        textSize: (json['textSize'] as num?)?.toDouble() ?? 46.0,
        lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 1.5,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 0.95,
        showControls: json['showControls'] as bool? ?? true,
        countdownSeconds: json['countdownSeconds'] as int? ?? 3,
      );

  TeleprompterSettings copyWith({
    double? speed,
    double? textSize,
    double? lineSpacing,
    double? opacity,
    bool? showControls,
    int? countdownSeconds,
  }) =>
      TeleprompterSettings(
        speed: speed ?? this.speed,
        textSize: textSize ?? this.textSize,
        lineSpacing: lineSpacing ?? this.lineSpacing,
        opacity: opacity ?? this.opacity,
        showControls: showControls ?? this.showControls,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      );
}

// ============================================================================
// Services
// ============================================================================

class StorageService {
  static const String _scriptsKey = 'teleprompter_scripts';
  static const String _settingsKey = 'teleprompter_settings';
  static const String _lastScriptKey = 'teleprompter_last_script';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<List<ScriptEntry>> loadScripts() async {
    final data = _prefs.getStringList(_scriptsKey) ?? [];
    return data
        .map((e) => ScriptEntry.fromJson(jsonDecode(e)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveScript(ScriptEntry script) async {
    final scripts = await loadScripts();
    final index = scripts.indexWhere((s) => s.id == script.id);
    if (index >= 0) {
      scripts[index] = script;
    } else {
      scripts.insert(0, script);
    }
    await _prefs.setStringList(
      _scriptsKey,
      scripts.map((s) => jsonEncode(s.toJson())).toList(),
    );
    await _prefs.setString(_lastScriptKey, script.id);
  }

  Future<void> deleteScript(String id) async {
    final scripts = await loadScripts();
    scripts.removeWhere((s) => s.id == id);
    await _prefs.setStringList(
      _scriptsKey,
      scripts.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  Future<ScriptEntry?> loadLastScript() async {
    final id = _prefs.getString(_lastScriptKey);
    if (id == null) return null;
    final scripts = await loadScripts();
    return scripts.cast<ScriptEntry?>().firstWhere(
          (s) => s?.id == id,
          orElse: () => null,
        );
  }

  Future<TeleprompterSettings> loadSettings() async {
    final data = _prefs.getString(_settingsKey);
    if (data == null) return const TeleprompterSettings();
    return TeleprompterSettings.fromJson(jsonDecode(data));
  }

  Future<void> saveSettings(TeleprompterSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}

class OverlayService {
  static Future<bool> checkPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkOverlayPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
    }
  }

  static Future<void> start({
    required String scriptText,
    required double speed,
    required double textSize,
    required double lineSpacing,
    required double opacity,
    required bool showControls,
  }) async {
    try {
      await _channel.invokeMethod('startOverlay', {
        'scriptText': scriptText,
        'speed': speed,
        'textSize': textSize,
        'lineSpacing': lineSpacing,
        'opacity': opacity,
        'showControls': showControls,
      });
    } catch (e) {
      debugPrint('Error starting overlay: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopOverlay');
    } catch (e) {
      debugPrint('Error stopping overlay: $e');
    }
  }

  static Future<void> pause() async {
    try {
      await _channel.invokeMethod('pauseOverlay');
    } catch (e) {
      debugPrint('Error pausing overlay: $e');
    }
  }

  static Future<void> resume() async {
    try {
      await _channel.invokeMethod('resumeOverlay');
    } catch (e) {
      debugPrint('Error resuming overlay: $e');
    }
  }

  static Future<void> restart() async {
    try {
      await _channel.invokeMethod('restartOverlay');
    } catch (e) {
      debugPrint('Error restarting overlay: $e');
    }
  }

  static Future<void> setSpeed(double speed) async {
    try {
      await _channel.invokeMethod('setSpeed', {'speed': speed});
    } catch (e) {
      debugPrint('Error setting speed: $e');
    }
  }

  static Future<void> setTextSize(double size) async {
    try {
      await _channel.invokeMethod('setTextSize', {'textSize': size});
    } catch (e) {
      debugPrint('Error setting text size: $e');
    }
  }

  static Future<void> setOpacity(double opacity) async {
    try {
      await _channel.invokeMethod('setOpacity', {'opacity': opacity});
    } catch (e) {
      debugPrint('Error setting opacity: $e');
    }
  }
}

// ============================================================================
// Main App
// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  runApp(FloatingTeleprompterApp(storage: storage));
}

class FloatingTeleprompterApp extends StatelessWidget {
  final StorageService storage;

  const FloatingTeleprompterApp({required this.storage, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Floating Teleprompter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: Colors.cyan,
          background: const Color(0xFF0A0E27),
          surface: const Color(0xFF1A1F3A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141B2F),
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
      ),
      home: HomePage(storage: storage),
    );
  }
}

// ============================================================================
// Home Page with Tab Navigation
// ============================================================================

class HomePage extends StatefulWidget {
  final StorageService storage;

  const HomePage({required this.storage, super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _titleController;
  late TextEditingController _scriptController;

  List<ScriptEntry> _scripts = [];
  ScriptEntry? _currentScript;
  TeleprompterSettings _settings = const TeleprompterSettings();
  bool _isLoading = true;
  bool _overlayPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _titleController = TextEditingController();
    _scriptController = TextEditingController();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final [scripts, settings, lastScript, hasPermission] = await Future.wait([
        widget.storage.loadScripts(),
        widget.storage.loadSettings(),
        widget.storage.loadLastScript(),
        OverlayService.checkPermission(),
      ]);

      setState(() {
        _scripts = scripts as List<ScriptEntry>;
        _settings = settings as TeleprompterSettings;
        _currentScript = lastScript as ScriptEntry?;
        _overlayPermissionGranted = hasPermission as bool;
        if (_currentScript != null) {
          _titleController.text = _currentScript!.title;
          _scriptController.text = _currentScript!.content;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing app: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveScript() async {
    final title = _titleController.text.trim();
    final content = _scriptController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      _showSnackBar('Add a title or script content', isError: true);
      return;
    }

    final script = ScriptEntry(
      id: _currentScript?.id,
      title: title.isEmpty ? 'Untitled' : title,
      content: content,
      createdAt: _currentScript?.createdAt,
    );

    await widget.storage.saveScript(script);

    setState(() {
      _currentScript = script;
      final index = _scripts.indexWhere((s) => s.id == script.id);
      if (index >= 0) {
        _scripts[index] = script;
      } else {
        _scripts.insert(0, script);
      }
    });

    _showSnackBar('Script saved successfully ✓');
  }

  Future<void> _deleteScript(ScriptEntry script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Script?'),
        content: Text('Delete "${script.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.storage.deleteScript(script.id);
    setState(() {
      _scripts.removeWhere((s) => s.id == script.id);
      if (_currentScript?.id == script.id) {
        if (_scripts.isNotEmpty) {
          _openScript(_scripts.first);
        } else {
          _currentScript = null;
          _titleController.clear();
          _scriptController.clear();
        }
      }
    });

    _showSnackBar('Script deleted');
  }

  Future<void> _renameScript(ScriptEntry script) async {
    final controller = TextEditingController(text: script.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Script'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Script title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty) return;

    final updated = script.copyWith(title: newTitle);
    await widget.storage.saveScript(updated);

    setState(() {
      final index = _scripts.indexWhere((s) => s.id == script.id);
      if (index >= 0) _scripts[index] = updated;
      if (_currentScript?.id == script.id) _currentScript = updated;
    });

    _titleController.text = updated.title;
  }

  void _openScript(ScriptEntry script) {
    setState(() {
      _currentScript = script;
      _titleController.text = script.title;
      _scriptController.text = script.content;
    });
  }

  Future<void> _requestOverlayPermission() async {
    await OverlayService.requestPermission();
    await Future.delayed(const Duration(milliseconds: 500));
    final granted = await OverlayService.checkPermission();
    setState(() => _overlayPermissionGranted = granted);
    if (granted) {
      _showSnackBar('Overlay permission granted! ✓');
    } else {
      _showSnackBar('Permission denied. Please enable in settings.', isError: true);
    }
  }

  Future<void> _startFloatingMode() async {
    final content = _scriptController.text.trim();
    if (content.isEmpty) {
      _showSnackBar('Add script content before starting', isError: true);
      return;
    }

    if (!_overlayPermissionGranted) {
      final granted = await OverlayService.checkPermission();
      if (!granted) {
        _showSnackBar('Overlay permission required. Tap lock icon to grant.', isError: true);
        return;
      }
      setState(() => _overlayPermissionGranted = true);
    }

    await _saveScript();

    if (mounted) {
      await OverlayService.start(
        scriptText: content,
        speed: _settings.speed,
        textSize: _settings.textSize,
        lineSpacing: _settings.lineSpacing,
        opacity: _settings.opacity,
        showControls: _settings.showControls,
      );
      _showSnackBar('Overlay started! Switch to another app.');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: 16),
              Text(
                'Loading Teleprompter',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEditorTab(),
          _buildScriptsTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.script, size: 26),
          SizedBox(width: 12),
          Text(
            'Floating Teleprompter',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _overlayPermissionGranted ? Icons.lock_open : Icons.lock,
            color: _overlayPermissionGranted ? Colors.green : Colors.orange,
          ),
          tooltip: _overlayPermissionGranted ? 'Permission granted' : 'Grant overlay permission',
          onPressed: _requestOverlayPermission,
        ),
        const SizedBox(width: 8),
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(icon: Icon(Icons.edit), text: 'Editor'),
          Tab(icon: Icon(Icons.library_books), text: 'Scripts'),
          Tab(icon: Icon(Icons.settings), text: 'Settings'),
        ],
        indicatorColor: Colors.cyan,
        labelColor: Colors.cyan,
        unselectedLabelColor: Colors.grey,
      ),
    );
  }

  Widget _buildEditorTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title field
          _buildTextField(
            controller: _titleController,
            label: 'Script Title',
            icon: Icons.title,
            maxLines: 1,
          ),
          const SizedBox(height: 16),

          // Script editor
          Expanded(
            child: _buildTextField(
              controller: _scriptController,
              label: 'Paste or type your script here...',
              icon: null,
              maxLines: null,
              expands: true,
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.save,
                  label: 'Save',
                  onPressed: _saveScript,
                  isPrimary: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.play_circle_fill,
                  label: 'Start Overlay',
                  onPressed: _startFloatingMode,
                  isPrimary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.stop_circle,
                  label: 'Stop',
                  onPressed: () async => await OverlayService.stop(),
                  isPrimary: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScriptsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saved Scripts (${_scripts.length})',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _scripts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.note_outlined,
                          size: 56,
                          color: const Color(0xFF6A7FA0),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No scripts yet',
                          style: TextStyle(
                            color: const Color(0xFF6A7FA0),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create one in the Editor tab',
                          style: TextStyle(
                            color: const Color(0xFF6A7FA0),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _scripts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final script = _scripts[index];
                      final isSelected = _currentScript?.id == script.id;
                      final date = DateFormat('MMM d, yyyy').format(script.updatedAt);

                      return GestureDetector(
                        onTap: () => _openScript(script),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.cyan.shade700.withOpacity(0.2)
                                : const Color(0xFF1A1F3A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.cyan.shade700
                                  : const Color(0xFF2A3F5F),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      script.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          '${script.content.length} chars',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6A7FA0),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          date,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6A7FA0),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton(
                                icon: const Icon(Icons.more_vert),
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    child: const Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 8),
                                        Text('Rename'),
                                      ],
                                    ),
                                    onTap: () => _renameScript(script),
                                  ),
                                  PopupMenuItem(
                                    child: const Row(
                                      children: [
                                        Icon(Icons.delete, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                    onTap: () => _deleteScript(script),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Teleprompter Settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        _buildSettingCard(
          title: 'Reading Speed',
          subtitle: 'Words per minute',
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Speed:'),
                  Text(
                    '${_settings.speed.toStringAsFixed(0)} wpm',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: _settings.speed,
                min: 30,
                max: 260,
                divisions: 46,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings.copyWith(speed: value);
                  });
                  widget.storage.saveSettings(_settings);
                },
                activeColor: Colors.cyan.shade700,
                inactiveColor: const Color(0xFF2A3F5F),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSettingCard(
          title: 'Text Size',
          subtitle: 'Adjust readability',
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Size:'),
                  Text(
                    '${_settings.textSize.toStringAsFixed(0)} sp',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: _settings.textSize,
                min: 20,
                max: 90,
                divisions: 70,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings.copyWith(textSize: value);
                  });
                  widget.storage.saveSettings(_settings);
                },
                activeColor: Colors.cyan.shade700,
                inactiveColor: const Color(0xFF2A3F5F),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSettingCard(
          title: 'Opacity',
          subtitle: 'Background transparency',
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Opacity:'),
                  Text(
                    '${(_settings.opacity * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: _settings.opacity,
                min: 0.2,
                max: 1.0,
                divisions: 16,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings.copyWith(opacity: value);
                  });
                  widget.storage.saveSettings(_settings);
                },
                activeColor: Colors.cyan.shade700,
                inactiveColor: const Color(0xFF2A3F5F),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSettingCard(
          title: 'Line Spacing',
          subtitle: 'Text line height',
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Spacing:'),
                  Text(
                    '${_settings.lineSpacing.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: _settings.lineSpacing,
                min: 1.0,
                max: 3.0,
                divisions: 20,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings.copyWith(lineSpacing: value);
                  });
                  widget.storage.saveSettings(_settings);
                },
                activeColor: Colors.cyan.shade700,
                inactiveColor: const Color(0xFF2A3F5F),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A3F5F),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A7FA0),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    int? maxLines,
    bool expands = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A3F5F),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        maxLines: expands ? null : maxLines,
        expands: expands,
        textAlignVertical: expands ? TextAlignVertical.top : null,
        style: const TextStyle(
          fontSize: 15,
          height: 1.6,
          color: Color(0xFFE8F0FE),
        ),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(
            color: Color(0xFF6A7FA0),
            fontSize: 15,
          ),
          prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF6A7FA0)) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: isPrimary ? Colors.cyan.shade700 : const Color(0xFF2A3F5F),
        foregroundColor: isPrimary ? Colors.white : const Color(0xFFB0C4DE),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: const Color(0xFF2A3F5F),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(icon: Icon(Icons.edit), text: 'Editor'),
          Tab(icon: Icon(Icons.library_books), text: 'Scripts'),
          Tab(icon: Icon(Icons.settings), text: 'Settings'),
        ],
        indicatorColor: Colors.cyan,
        labelColor: Colors.cyan,
        unselectedLabelColor: Colors.grey,
      ),
    );
  }
}
