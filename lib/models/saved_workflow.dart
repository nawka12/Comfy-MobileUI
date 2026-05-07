import 'package:uuid/uuid.dart';

/// Persisted user-imported workflow + their per-input overrides.
class SavedWorkflow {
  final String id;
  final String name;
  final String json;
  final Map<String, dynamic> values;

  SavedWorkflow({
    required this.id,
    required this.name,
    required this.json,
    Map<String, dynamic>? values,
  }) : values = values ?? {};

  factory SavedWorkflow.create({
    required String name,
    required String json,
    Map<String, dynamic>? values,
  }) =>
      SavedWorkflow(
        id: const Uuid().v4(),
        name: name,
        json: json,
        values: values,
      );

  SavedWorkflow copyWith({
    String? name,
    String? json,
    Map<String, dynamic>? values,
  }) =>
      SavedWorkflow(
        id: id,
        name: name ?? this.name,
        json: json ?? this.json,
        values: values ?? this.values,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'json': json,
        'values': values,
      };

  factory SavedWorkflow.fromJson(Map<String, dynamic> j) => SavedWorkflow(
        id: j['id'] as String,
        name: j['name'] as String,
        json: j['json'] as String,
        values: (j['values'] as Map<String, dynamic>?) ?? {},
      );
}
