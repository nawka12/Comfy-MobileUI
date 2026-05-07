import 'package:comfy_mobileui/models/saved_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SavedWorkflow round-trips through JSON', () {
    final w = SavedWorkflow.create(
      name: 'My SDXL flow',
      json: '{"3":{"class_type":"KSampler","inputs":{}}}',
      values: {'3.seed': 42, '5.text': 'hello'},
    );
    final j = w.toJson();
    final restored = SavedWorkflow.fromJson(j);
    expect(restored.id, w.id);
    expect(restored.name, w.name);
    expect(restored.json, w.json);
    expect(restored.values, w.values);
  });

  test('copyWith updates only specified fields', () {
    final w = SavedWorkflow.create(name: 'A', json: '{}');
    final renamed = w.copyWith(name: 'B');
    expect(renamed.id, w.id);
    expect(renamed.name, 'B');
    expect(renamed.json, w.json);
  });
}
