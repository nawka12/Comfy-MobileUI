import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/nodes.dart';

class ComfyUIService {
  String _baseUrl;
  final String _clientId;
  final http.Client _client;
  final NodeRegistry registry;

  ComfyUIService({String baseUrl = 'http://localhost:8188', NodeRegistry? registry})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _clientId = const Uuid().v4(),
        _client = http.Client(),
        registry = registry ?? NodeRegistry();

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get _promptUrl => '$_baseUrl/prompt';
  String get _queueUrl => '$_baseUrl/queue';
  String get _historyUrl => '$_baseUrl/history';
  String get _viewUrl => '$_baseUrl/view';
  String get _objectInfoUrl => '$_baseUrl/object_info';

  Future<void> loadObjectInfo() async {
    final resp = await _client.get(Uri.parse(_objectInfoUrl));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      registry.loadFromApi(data);
    } else {
      throw ComfyUIException('Failed to load object info: ${resp.statusCode}');
    }
  }

  Future<String> queuePrompt(Map<String, dynamic> workflow) async {
    final body = jsonEncode({
      'prompt': workflow,
      'client_id': _clientId,
    });
    final resp = await _client.post(
      Uri.parse(_promptUrl),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['prompt_id'] as String;
    }
    throw ComfyUIException('Failed to queue prompt: ${resp.statusCode} ${resp.body}');
  }

  Future<Map<String, dynamic>?> getHistory(String promptId) async {
    final resp = await _client.get(Uri.parse('$_historyUrl/$promptId'));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data[promptId] as Map<String, dynamic>?;
    }
    if (resp.statusCode == 404) return null;
    throw ComfyUIException('Failed to get history: ${resp.statusCode}');
  }

  Future<Uint8List> getImage(String filename, {String subfolder = '', String type = 'output'}) async {
    final uri = Uri.parse(_viewUrl).replace(queryParameters: {
      'filename': filename,
      'subfolder': subfolder,
      'type': type,
    });
    final resp = await _client.get(uri);
    if (resp.statusCode == 200) {
      return resp.bodyBytes;
    }
    throw ComfyUIException('Failed to get image: ${resp.statusCode}');
  }

  Future<Map<String, dynamic>> getQueue() async {
    final resp = await _client.get(Uri.parse(_queueUrl));
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw ComfyUIException('Failed to get queue: ${resp.statusCode}');
  }

  /// Discover available models for a given loader type
  List<String> getModels(String loaderType) {
    final node = registry[loaderType];
    if (node == null) return [];
    for (final input in node.requiredInputs) {
      if (input.options != null && input.options!.isNotEmpty) {
        return input.options!;
      }
    }
    return [];
  }

  /// Get available sampler names from the registry
  List<String> get samplerNames {
    final sampler = registry['KSampler'];
    if (sampler == null) return defaultSamplers;
    final input = sampler.input('sampler_name');
    return input?.options ?? defaultSamplers;
  }

  /// Get available scheduler names from the registry
  List<String> get schedulerNames {
    final sampler = registry['KSampler'];
    if (sampler == null) return defaultSchedulers;
    final input = sampler.input('scheduler');
    return input?.options ?? defaultSchedulers;
  }

  /// Get available options for a specific node input
  List<String> getNodeInputOptions(String nodeType, String inputName) {
    final node = registry[nodeType];
    if (node == null) return [];
    final input = node.input(inputName);
    return input?.options ?? [];
  }

  Future<bool> testConnection() async {
    try {
      final resp = await _client
          .get(Uri.parse('$_objectInfoUrl/KSampler'))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}

class ComfyUIException implements Exception {
  final String message;
  ComfyUIException(this.message);

  @override
  String toString() => 'ComfyUIException: $message';
}

const defaultSamplers = [
  'euler', 'euler_cfg_pp', 'euler_ancestral', 'euler_ancestral_cfg_pp',
  'heun', 'heunpp2', 'dpm_2', 'dpm_2_ancestral', 'dpm_fast',
  'dpm_adaptive', 'dpmpp_2s_ancestral', 'dpmpp_2s_ancestral_cfg_pp',
  'dpmpp_2m', 'dpmpp_2m_cfg_pp', 'dpmpp_2m_sde', 'dpmpp_3m_sde',
  'lms', 'lcm', 'ddim', 'uni_pc', 'uni_pc_bh2',
];

const defaultSchedulers = [
  'normal', 'karras', 'exponential', 'sgm_uniform', 'simple', 'ddim_uniform',
];
