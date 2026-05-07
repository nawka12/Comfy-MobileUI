import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/comfyui_service.dart';
import '../services/config_service.dart';
import '../services/gallery_service.dart';
import '../services/secure_window_service.dart';
import '../services/workflow_builder.dart';
import '../models/architecture_profile.dart';
import '../models/config_preset.dart';
import '../models/dynamic_workflow.dart';
import '../models/generation_params.dart';
import '../models/saved_workflow.dart';
import 'generate_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';
import 'workflows_screen.dart';

class HomeScreen extends StatefulWidget {
  final ComfyUIService service;

  const HomeScreen({super.key, required this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(widget.service),
      child: _AppStateInitializer(
        child: Consumer<AppState>(
          builder: (context, state, _) {
            final screens = [
              GenerateScreen(service: widget.service),
              const WorkflowsScreen(),
              GalleryScreen(galleryService: state.galleryService),
              const SettingsScreen(),
            ];
            return Scaffold(
              body: PageView(
                controller: _pageCtrl,
                physics: const PageScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentIndex = i),
                children: screens,
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (i) {
                  _pageCtrl.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  );
                  setState(() => _currentIndex = i);
                },
                height: 72,
                labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome),
                    label: 'Generate',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_tree_outlined),
                    selectedIcon: Icon(Icons.account_tree),
                    label: 'Workflows',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.photo_library_outlined),
                    selectedIcon: Icon(Icons.photo_library),
                    label: 'Gallery',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppStateInitializer extends StatefulWidget {
  final Widget child;
  const _AppStateInitializer({required this.child});

  @override
  State<_AppStateInitializer> createState() => _AppStateInitializerState();
}

class _AppStateInitializerState extends State<_AppStateInitializer> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().init().then((_) {
        if (mounted) setState(() => _ready = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Comfy Mobile',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Connecting to server...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }
}

class AppState extends ChangeNotifier {
  final ComfyUIService comfyService;
  final ConfigService configService;
  final GalleryService galleryService;
  final WorkflowBuilder workflowBuilder;

  GenerationParams params;
  bool connected = false;
  bool autoSave = true;
  bool secureWindow = false;
  bool hiddenLibraryUnlocked = false;
  List<String> availableModels = [];
  List<String> availableClipModels = [];
  List<String> availableVaeModels = [];
  List<String> availableLoras = [];
  String status = 'Disconnected';

  List<SavedWorkflow> workflows = [];
  String? activeWorkflowId;
  DynamicWorkflow? _activeWorkflow;
  bool customMode = false;

  AppState(this.comfyService)
      : configService = ConfigService(),
        galleryService = GalleryService(),
        workflowBuilder = WorkflowBuilder(comfyService.registry),
        params = GenerationParams();

  SavedWorkflow? get activeSavedWorkflow {
    if (activeWorkflowId == null) return null;
    for (final w in workflows) {
      if (w.id == activeWorkflowId) return w;
    }
    return null;
  }

  DynamicWorkflow? get activeWorkflow => _activeWorkflow;

  Future<void> init() async {
    await galleryService.init();
    final savedParams = await configService.loadParams();
    final savedUrl = await configService.loadServerUrl();
    autoSave = await configService.loadAutoSave();
    secureWindow = await configService.loadSecureWindow();
    await SecureWindowService.setSecure(secureWindow);
    workflows = await configService.loadWorkflows();
    activeWorkflowId = await configService.loadActiveWorkflowId();
    if (activeWorkflowId != null &&
        !workflows.any((w) => w.id == activeWorkflowId)) {
      activeWorkflowId = null;
    }
    if (activeWorkflowId == null && workflows.isNotEmpty) {
      activeWorkflowId = workflows.first.id;
      await configService.saveActiveWorkflowId(activeWorkflowId);
    }
    params = savedParams;
    comfyService.updateBaseUrl(savedUrl);
    _rebuildActiveWorkflow();
    if (_activeWorkflow != null) customMode = true;
    notifyListeners();
    await checkConnection();
  }

  void _rebuildActiveWorkflow() {
    final saved = activeSavedWorkflow;
    if (saved == null) {
      _activeWorkflow = null;
      return;
    }
    try {
      final raw = jsonDecode(saved.json) as Map<String, dynamic>;
      final dw = DynamicWorkflow.parse(raw, comfyService.registry);
      if (saved.values.isNotEmpty) dw.applySavedValues(saved.values);
      _activeWorkflow = dw;
    } catch (_) {
      _activeWorkflow = null;
    }
  }

  /// Validate that [contents] is API-format ComfyUI JSON
  /// (`{nodeId: {class_type, inputs}}`) and return the parsed map, or null
  /// if it's the editor format or otherwise invalid.
  Map<String, dynamic>? validateApiWorkflow(String contents) {
    try {
      final raw = jsonDecode(contents);
      if (raw is! Map<String, dynamic>) return null;
      if (raw.containsKey('nodes') && raw.containsKey('links')) return null;
      bool sawNode = false;
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is! Map) continue;
        if (v['class_type'] is String) {
          sawNode = true;
          break;
        }
      }
      if (!sawNode) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<SavedWorkflow?> addWorkflow({
    required String name,
    required String contents,
  }) async {
    if (validateApiWorkflow(contents) == null) return null;
    final w = SavedWorkflow.create(name: name, json: contents);
    workflows = [...workflows, w];
    activeWorkflowId = w.id;
    customMode = true;
    await configService.saveWorkflows(workflows);
    await configService.saveActiveWorkflowId(activeWorkflowId);
    _rebuildActiveWorkflow();
    notifyListeners();
    return w;
  }

  Future<void> setActiveWorkflow(String id) async {
    if (activeWorkflowId == id) return;
    activeWorkflowId = id;
    await configService.saveActiveWorkflowId(id);
    _rebuildActiveWorkflow();
    notifyListeners();
  }

  Future<void> renameWorkflow(String id, String name) async {
    final idx = workflows.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    workflows[idx] = workflows[idx].copyWith(name: name);
    await configService.saveWorkflows(workflows);
    notifyListeners();
  }

  Future<void> deleteWorkflow(String id) async {
    workflows = workflows.where((w) => w.id != id).toList();
    if (activeWorkflowId == id) {
      activeWorkflowId = workflows.isEmpty ? null : workflows.first.id;
      if (activeWorkflowId == null) customMode = false;
      await configService.saveActiveWorkflowId(activeWorkflowId);
    }
    await configService.saveWorkflows(workflows);
    _rebuildActiveWorkflow();
    notifyListeners();
  }

  Future<void> persistActiveWorkflowValues() async {
    final dw = _activeWorkflow;
    final id = activeWorkflowId;
    if (dw == null || id == null) return;
    final idx = workflows.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    workflows[idx] = workflows[idx].copyWith(values: dw.currentValues());
    await configService.saveWorkflows(workflows);
  }

  void setCustomMode(bool value) {
    if (customMode == value) return;
    customMode = value;
    notifyListeners();
  }

  void notifyActiveWorkflowChanged() => notifyListeners();

  Future<void> checkConnection() async {
    status = 'Connecting...';
    notifyListeners();
    connected = await comfyService.testConnection();
    status = connected ? 'Connected' : 'Disconnected';
    notifyListeners();
    if (connected) {
      await _loadNodeInfo();
    }
  }

  Future<void> _loadNodeInfo() async {
    try {
      await comfyService.loadObjectInfo();
    } catch (_) {
      notifyListeners();
      return;
    }

    _syncModelListForProfile();

    if (params.checkpoint.isEmpty && availableModels.isNotEmpty) {
      params.checkpoint = availableModels.first;
    }

    _autoDetectProfile();
    _rebuildActiveWorkflow();
    notifyListeners();
  }

  void _autoDetectProfile() {
    if (params.checkpoint.isEmpty) return;
    final detected = ArchitectureProfile.detect(params.checkpoint);
    if (detected != null && detected.id != params.profileId) {
      params.profileId = detected.id;
    }
  }

  Future<void> refreshModelLists() async {
    final profile = ArchitectureProfile.byId(params.profileId);
    availableModels = comfyService.getModels(profile.modelLoader);

    if (profile.clipLoader != null) {
      availableClipModels = comfyService.getModels(profile.clipLoader!);
    }
    if (profile.vaeLoader != null) {
      availableVaeModels = comfyService.getModels(profile.vaeLoader!);
    }
    notifyListeners();
  }

  Future<void> saveConfig() async {
    await configService.saveParams(params);
  }

  Future<void> setAutoSave(bool value) async {
    autoSave = value;
    await configService.saveAutoSave(value);
    notifyListeners();
  }

  Future<void> setSecureWindow(bool value) async {
    secureWindow = value;
    await configService.saveSecureWindow(value);
    await SecureWindowService.setSecure(value);
    notifyListeners();
  }

  void setHiddenLibraryUnlocked(bool value) {
    if (hiddenLibraryUnlocked == value) return;
    hiddenLibraryUnlocked = value;
    notifyListeners();
  }

  void updateParams(GenerationParams updated) {
    final profileChanged = updated.profileId != params.profileId;
    params = updated;
    if (profileChanged) {
      _initExtrasForProfile();
      _syncModelListForProfile();
    }
    notifyListeners();
  }

  void updateCheckpoint(String ckpt) {
    params.checkpoint = ckpt;
    final detected = ArchitectureProfile.detect(ckpt);
    if (detected != null) {
      params.profileId = detected.id;
      _initExtrasForProfile();
      _syncModelListForProfile();
    }
    notifyListeners();
  }

  // --- Presets ---

  Future<List<ConfigPreset>> loadPresets() => configService.loadPresets();

  Future<ConfigPreset> savePreset(String name) =>
      configService.savePreset(name, params, comfyService.baseUrl);

  Future<void> deletePreset(String id) => configService.deletePreset(id);

  Future<void> renamePreset(String id, String name) =>
      configService.renamePreset(id, name);

  Future<void> applyPreset(ConfigPreset preset) {
    params = preset.params.copy();
    if (preset.serverUrl.isNotEmpty) {
      comfyService.updateBaseUrl(preset.serverUrl);
    }
    _initExtrasForProfile();
    notifyListeners();
    return configService.saveServerUrl(preset.serverUrl);
  }

  void _initExtrasForProfile() {
    final profile = ArchitectureProfile.byId(params.profileId);
    for (final extra in profile.extraParams) {
      params.extras.putIfAbsent(extra.key, () => extra.defaultValue);
    }
  }

  void _syncModelListForProfile() {
    final profile = ArchitectureProfile.byId(params.profileId);
    availableModels = comfyService.getModels(profile.modelLoader);
    availableLoras = comfyService.getModels('LoraLoader');
    if (availableModels.isNotEmpty && !availableModels.contains(params.checkpoint)) {
      params.checkpoint = availableModels.first;
    }
    if (profile.clipLoader != null) {
      availableClipModels = comfyService.getModels(profile.clipLoader!);
      if (availableClipModels.isNotEmpty && !availableClipModels.contains(params.clipModel)) {
        params.clipModel = availableClipModels.first;
      }
    }
    if (profile.vaeLoader != null) {
      availableVaeModels = comfyService.getModels(profile.vaeLoader!);
      if (availableVaeModels.isNotEmpty && !availableVaeModels.contains(params.vaeModel)) {
        params.vaeModel = availableVaeModels.first;
      }
    }
  }

  List<String> get samplerNames => comfyService.samplerNames;
  List<String> get schedulerNames => comfyService.schedulerNames;

  @override
  void dispose() {
    comfyService.dispose();
    super.dispose();
  }
}
