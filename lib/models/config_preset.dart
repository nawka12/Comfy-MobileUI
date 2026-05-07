import 'package:uuid/uuid.dart';
import 'generation_params.dart';

class ConfigPreset {
  final String id;
  String name;
  final GenerationParams params;
  final String serverUrl;

  ConfigPreset({
    String? id,
    required this.name,
    required this.params,
    this.serverUrl = '',
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'params': params.toJson(),
    'serverUrl': serverUrl,
  };

  factory ConfigPreset.fromJson(Map<String, dynamic> json) => ConfigPreset(
    id: json['id'] as String?,
    name: json['name'] as String? ?? 'Unnamed',
    params: GenerationParams.fromJson(
        json['params'] as Map<String, dynamic>? ?? {}),
    serverUrl: json['serverUrl'] as String? ?? '',
  );

  ConfigPreset copyWith({
    String? name,
    GenerationParams? params,
    String? serverUrl,
  }) => ConfigPreset(
    id: id,
    name: name ?? this.name,
    params: params ?? this.params.copy(),
    serverUrl: serverUrl ?? this.serverUrl,
  );
}
