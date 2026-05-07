import 'dart:convert';

import 'nodes.dart';

/// A single user-editable input on a node in a custom workflow.
class ExposedInput {
  final String nodeId;
  final String classType;
  final String inputName;
  final String label;
  final String group;
  final NodeInputDef? def;
  dynamic value;

  ExposedInput({
    required this.nodeId,
    required this.classType,
    required this.inputName,
    required this.label,
    required this.group,
    required this.def,
    required this.value,
  });

  String get key => '$nodeId.$inputName';
}

class DynamicWorkflow {
  final Map<String, dynamic> source;
  final List<ExposedInput> inputs;

  DynamicWorkflow({required this.source, required this.inputs});

  /// Parse an API-format workflow ({nodeId: {class_type, inputs}}).
  /// Cross-references each non-wired input against [registry] to
  /// derive widget metadata, then groups + labels via heuristics.
  factory DynamicWorkflow.parse(
    Map<String, dynamic> workflow,
    NodeRegistry registry,
  ) {
    final exposed = <ExposedInput>[];
    final positiveSources = <String>{};
    final negativeSources = <String>{};

    for (final entry in workflow.entries) {
      final node = entry.value;
      if (node is! Map) continue;
      final inputs = node['inputs'];
      if (inputs is! Map) continue;
      for (final inEntry in inputs.entries) {
        final v = inEntry.value;
        if (!_isWire(v)) continue;
        final srcId = (v as List)[0].toString();
        if (inEntry.key == 'positive') positiveSources.add(srcId);
        if (inEntry.key == 'negative') negativeSources.add(srcId);
      }
    }

    for (final entry in workflow.entries) {
      final nodeId = entry.key;
      final node = entry.value;
      if (node is! Map) continue;
      final classType = node['class_type'] as String?;
      if (classType == null) continue;
      final rawInputs = node['inputs'];
      if (rawInputs is! Map) continue;

      final nodeType = registry[classType];
      final group = '$classType #$nodeId';

      for (final inEntry in rawInputs.entries) {
        final inputName = inEntry.key as String;
        final value = inEntry.value;
        if (_isWire(value)) continue;

        final def = nodeType?.input(inputName);
        if (def != null && def.isConnection) continue;

        final label = _labelFor(
          classType: classType,
          inputName: inputName,
          nodeId: nodeId,
          positiveSources: positiveSources,
          negativeSources: negativeSources,
        );

        exposed.add(ExposedInput(
          nodeId: nodeId,
          classType: classType,
          inputName: inputName,
          label: label,
          group: group,
          def: def,
          value: value,
        ));
      }
    }

    return DynamicWorkflow(source: workflow, inputs: exposed);
  }

  /// Deep-copy the source workflow and write user values back into each
  /// `[nodeId][inputs][inputName]`. Original wired references are preserved.
  Map<String, dynamic> applyValues() {
    final copy = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
    for (final ex in inputs) {
      final node = copy[ex.nodeId];
      if (node is Map && node['inputs'] is Map) {
        (node['inputs'] as Map)[ex.inputName] = ex.value;
      }
    }
    return copy;
  }

  /// Restore values from a saved map keyed by "nodeId.inputName".
  /// Unknown keys are ignored. Missing keys keep the workflow's literal.
  void applySavedValues(Map<String, dynamic> saved) {
    for (final ex in inputs) {
      if (saved.containsKey(ex.key)) {
        ex.value = saved[ex.key];
      }
    }
  }

  Map<String, dynamic> currentValues() {
    return {for (final ex in inputs) ex.key: ex.value};
  }
}

bool _isWire(dynamic v) {
  if (v is! List || v.length != 2) return false;
  return v[0] is String && v[1] is num;
}

const _labelMap = <String, String>{
  'KSampler.seed': 'Seed',
  'KSampler.steps': 'Steps',
  'KSampler.cfg': 'CFG',
  'KSampler.sampler_name': 'Sampler',
  'KSampler.scheduler': 'Scheduler',
  'KSampler.denoise': 'Denoise',
  'KSamplerAdvanced.noise_seed': 'Seed',
  'KSamplerAdvanced.steps': 'Steps',
  'KSamplerAdvanced.cfg': 'CFG',
  'KSamplerAdvanced.sampler_name': 'Sampler',
  'KSamplerAdvanced.scheduler': 'Scheduler',
  'KSamplerAdvanced.start_at_step': 'Start Step',
  'KSamplerAdvanced.end_at_step': 'End Step',
  'EmptyLatentImage.width': 'Width',
  'EmptyLatentImage.height': 'Height',
  'EmptyLatentImage.batch_size': 'Batch Size',
  'EmptySD3LatentImage.width': 'Width',
  'EmptySD3LatentImage.height': 'Height',
  'EmptySD3LatentImage.batch_size': 'Batch Size',
  'CheckpointLoaderSimple.ckpt_name': 'Model',
  'UNETLoader.unet_name': 'UNET',
  'UNETLoader.weight_dtype': 'Weight dtype',
  'CLIPLoader.clip_name': 'CLIP',
  'CLIPLoader.type': 'CLIP Type',
  'DualCLIPLoader.clip_name1': 'CLIP 1',
  'DualCLIPLoader.clip_name2': 'CLIP 2',
  'DualCLIPLoader.type': 'CLIP Type',
  'VAELoader.vae_name': 'VAE',
  'LoraLoader.lora_name': 'LoRA',
  'LoraLoader.strength_model': 'LoRA Strength (model)',
  'LoraLoader.strength_clip': 'LoRA Strength (CLIP)',
  'FluxGuidance.guidance': 'Flux Guidance',
  'ModelSamplingSD3.shift': 'Shift',
  'SaveImage.filename_prefix': 'Filename Prefix',
};

String _labelFor({
  required String classType,
  required String inputName,
  required String nodeId,
  required Set<String> positiveSources,
  required Set<String> negativeSources,
}) {
  if (_isTextEncodeClass(classType) &&
      (inputName == 'text' ||
          inputName == 'text_g' ||
          inputName == 'text_l' ||
          inputName == 'clip_l' ||
          inputName == 't5xxl')) {
    final isPos = positiveSources.contains(nodeId);
    final isNeg = negativeSources.contains(nodeId);
    final base = isPos
        ? 'Positive Prompt'
        : isNeg
            ? 'Negative Prompt'
            : 'Prompt';
    if (inputName == 'text' || inputName == 'text_g' || inputName == 'clip_l') {
      return base;
    }
    return '$base ($inputName)';
  }
  return _labelMap['$classType.$inputName'] ?? inputName;
}

bool _isTextEncodeClass(String classType) {
  return classType.startsWith('CLIPTextEncode');
}
