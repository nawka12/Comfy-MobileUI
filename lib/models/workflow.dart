import 'dart:convert';
import 'generation_params.dart';

class AppConfig {
  final String serverUrl;
  final GenerationParams params;

  AppConfig({
    this.serverUrl = 'http://localhost:8188',
    GenerationParams? params,
  }) : params = params ?? GenerationParams();

  Map<String, dynamic> toJson() => {
        'version': 2,
        'serverUrl': serverUrl,
        'params': params.toJson(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        serverUrl: json['serverUrl'] as String? ?? 'http://localhost:8188',
        params: json['params'] != null
            ? GenerationParams.fromJson(
                json['params'] as Map<String, dynamic>)
            : GenerationParams(),
      );

  String exportJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  static AppConfig? importJson(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      if (data['version'] == 1) {
        return _migrateV1(data);
      }
      return AppConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static AppConfig? _migrateV1(Map<String, dynamic> v1) {
    try {
      final settings = v1['settings'] as Map<String, dynamic>? ?? {};
      final profileMap = <String, String>{
        'standard': 'standard',
        'sdxl': 'sdxl',
        'anima': 'flux',
      };
      final arch = settings['architecture'] as String? ?? 'sdxl';
      final params = GenerationParams(
        positivePrompt: settings['positivePrompt'] as String? ?? '',
        negativePrompt: settings['negativePrompt'] as String? ?? '',
        seed: settings['seed'] as int?,
        steps: settings['steps'] as int? ?? 20,
        cfg: (settings['cfg'] as num?)?.toDouble() ?? 7.0,
        denoise: (settings['denoise'] as num?)?.toDouble() ?? 1.0,
        width: settings['width'] as int? ?? 1024,
        height: settings['height'] as int? ?? 1024,
        batchSize: settings['batchSize'] as int? ?? 1,
        samplerName: settings['samplerName'] as String? ?? 'euler',
        scheduler: settings['scheduler'] as String? ?? 'normal',
        profileId: profileMap[arch] ?? 'standard',
        checkpoint: settings['checkpoint'] as String? ?? '',
        clipModel: settings['clipModel'] as String? ?? '',
        vaeModel: settings['vaeModel'] as String? ?? '',
        extras: {
          if (settings['sdxlTargetWidth'] != null)
            'sdxlTargetWidth': settings['sdxlTargetWidth'],
          if (settings['sdxlTargetHeight'] != null)
            'sdxlTargetHeight': settings['sdxlTargetHeight'],
          if (settings['sdxlCropW'] != null) 'sdxlCropW': settings['sdxlCropW'],
          if (settings['sdxlCropH'] != null) 'sdxlCropH': settings['sdxlCropH'],
        },
      );
      return AppConfig(
        serverUrl: v1['serverUrl'] as String? ?? 'http://localhost:8188',
        params: params,
      );
    } catch (_) {
      return null;
    }
  }
}
