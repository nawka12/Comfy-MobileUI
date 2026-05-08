import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/backend_mode.dart';
import '../models/generation_params.dart';
import '../models/config_preset.dart';
import '../models/saved_workflow.dart';
import '../models/workflow.dart';

class ConfigService {
  static const _serverUrlKey = 'server_url';
  static const _paramsKey = 'generation_params';
  static const _autoSaveKey = 'auto_save_on_generate';
  static const _presetsKey = 'config_presets';
  static const _workflowsKey = 'saved_workflows';
  static const _activeWorkflowIdKey = 'active_workflow_id';
  static const _secureWindowKey = 'secure_window_enabled';
  static const _hiddenPwdHashKey = 'hidden_library_pwd_hash';
  static const _hiddenPwdSaltKey = 'hidden_library_pwd_salt';
  static const _backendModeKey = 'backend_mode';
  static const _tamsApiTokenKey = 'tams_api_token';
  static const _tamsBaseUrlKey = 'tams_base_url';
  // Legacy single-workflow keys, migrated on first load.
  static const _legacyWorkflowKey = 'custom_workflow_json';
  static const _legacyWorkflowValuesKey = 'custom_workflow_values';

  // --- Current session ---

  Future<String> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? 'http://localhost:8188';
  }

  Future<void> saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  Future<bool> loadAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSaveKey) ?? true;
  }

  Future<void> saveAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSaveKey, value);
  }

  Future<GenerationParams> loadParams() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_paramsKey);
    if (json == null) return GenerationParams();
    try {
      final config = AppConfig.importJson(json);
      return config?.params ?? GenerationParams();
    } catch (_) {
      return GenerationParams();
    }
  }

  Future<void> saveParams(GenerationParams params) async {
    final prefs = await SharedPreferences.getInstance();
    final config = AppConfig(params: params);
    await prefs.setString(_paramsKey, config.exportJson());
  }

  Future<AppConfig> loadFullConfig() async {
    final url = await loadServerUrl();
    final params = await loadParams();
    return AppConfig(serverUrl: url, params: params);
  }

  Future<List<SavedWorkflow>> loadWorkflows() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_workflowsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => SavedWorkflow.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }
    return _migrateLegacyWorkflow(prefs);
  }

  Future<void> saveWorkflows(List<SavedWorkflow> workflows) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(workflows.map((w) => w.toJson()).toList());
    await prefs.setString(_workflowsKey, encoded);
  }

  Future<String?> loadActiveWorkflowId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeWorkflowIdKey);
  }

  Future<void> saveActiveWorkflowId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_activeWorkflowIdKey);
    } else {
      await prefs.setString(_activeWorkflowIdKey, id);
    }
  }

  Future<List<SavedWorkflow>> _migrateLegacyWorkflow(
      SharedPreferences prefs) async {
    final json = prefs.getString(_legacyWorkflowKey);
    if (json == null || json.isEmpty) return [];
    Map<String, dynamic> values = {};
    final rawValues = prefs.getString(_legacyWorkflowValuesKey);
    if (rawValues != null && rawValues.isNotEmpty) {
      try {
        values = jsonDecode(rawValues) as Map<String, dynamic>;
      } catch (_) {}
    }
    final migrated = SavedWorkflow.create(
      name: 'Imported workflow',
      json: json,
      values: values,
    );
    final list = [migrated];
    await prefs.setString(
      _workflowsKey,
      jsonEncode(list.map((w) => w.toJson()).toList()),
    );
    await prefs.setString(_activeWorkflowIdKey, migrated.id);
    await prefs.remove(_legacyWorkflowKey);
    await prefs.remove(_legacyWorkflowValuesKey);
    return list;
  }

  // --- Presets ---

  Future<List<ConfigPreset>> loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_presetsKey);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => ConfigPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePresets(List<ConfigPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(presets.map((p) => p.toJson()).toList());
    await prefs.setString(_presetsKey, json);
  }

  Future<ConfigPreset> savePreset(
      String name, GenerationParams params, String serverUrl) async {
    final presets = await loadPresets();
    final preset = ConfigPreset(name: name, params: params, serverUrl: serverUrl);
    presets.insert(0, preset);
    await _savePresets(presets);
    return preset;
  }

  Future<void> deletePreset(String id) async {
    final presets = await loadPresets();
    presets.removeWhere((p) => p.id == id);
    await _savePresets(presets);
  }

  Future<void> renamePreset(String id, String name) async {
    final presets = await loadPresets();
    final idx = presets.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    presets[idx] = presets[idx].copyWith(name: name);
    await _savePresets(presets);
  }

  Future<ConfigPreset?> importPresetJson(String jsonString) async {
    try {
      final data = jsonDecode(jsonString);
      if (data is Map<String, dynamic>) {
        return ConfigPreset.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  Future<String> exportPresetJson(ConfigPreset preset) {
    const encoder = JsonEncoder.withIndent('  ');
    return Future.value(encoder.convert(preset.toJson()));
  }

  // --- Backend mode & TAMS ---

  Future<BackendMode> loadBackendMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backendModeKey);
    if (raw == 'tams') return BackendMode.tams;
    return BackendMode.local;
  }

  Future<void> saveBackendMode(BackendMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendModeKey, mode == BackendMode.local ? 'local' : 'tams');
  }

  Future<String?> loadTamsApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tamsApiTokenKey);
  }

  Future<void> saveTamsApiToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_tamsApiTokenKey);
    } else {
      await prefs.setString(_tamsApiTokenKey, token);
    }
  }

  Future<String> loadTamsBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tamsBaseUrlKey) ?? 'https://ap-east-1.tensorart.cloud/v1';
  }

  Future<void> saveTamsBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tamsBaseUrlKey, url);
  }

  // --- Privacy ---

  Future<bool> loadSecureWindow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_secureWindowKey) ?? false;
  }

  Future<void> saveSecureWindow(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_secureWindowKey, value);
  }

  // --- Hidden library password ---

  Future<bool> hasHiddenPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hiddenPwdHashKey) != null;
  }

  Future<void> setHiddenPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    await prefs.setString(_hiddenPwdSaltKey, salt);
    await prefs.setString(_hiddenPwdHashKey, _hashPassword(password, salt));
  }

  Future<bool> verifyHiddenPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_hiddenPwdSaltKey);
    final stored = prefs.getString(_hiddenPwdHashKey);
    if (salt == null || stored == null) return false;
    return _hashPassword(password, salt) == stored;
  }

  Future<void> clearHiddenPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hiddenPwdHashKey);
    await prefs.remove(_hiddenPwdSaltKey);
  }

  String _generateSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Encode(bytes);
  }

  String _hashPassword(String password, String salt) {
    return sha256.convert(utf8.encode('$salt|$password')).toString();
  }
}
