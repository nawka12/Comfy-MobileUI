import 'dart:convert';

import 'package:comfy_mobileui/models/dynamic_workflow.dart';
import 'package:comfy_mobileui/models/nodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Minimal API-format SDXL-ish workflow.
  final sample = <String, dynamic>{
    '3': {
      'class_type': 'CheckpointLoaderSimple',
      'inputs': {'ckpt_name': 'sd_xl_base.safetensors'},
    },
    '4': {
      'class_type': 'EmptyLatentImage',
      'inputs': {'width': 1024, 'height': 1024, 'batch_size': 1},
    },
    '5': {
      'class_type': 'CLIPTextEncode',
      'inputs': {
        'text': 'a cat',
        'clip': ['3', 1],
      },
    },
    '6': {
      'class_type': 'CLIPTextEncode',
      'inputs': {
        'text': 'blurry',
        'clip': ['3', 1],
      },
    },
    '7': {
      'class_type': 'KSampler',
      'inputs': {
        'seed': 12345,
        'steps': 20,
        'cfg': 7.0,
        'sampler_name': 'euler',
        'scheduler': 'normal',
        'denoise': 1.0,
        'model': ['3', 0],
        'positive': ['5', 0],
        'negative': ['6', 0],
        'latent_image': ['4', 0],
      },
    },
    '8': {
      'class_type': 'VAEDecode',
      'inputs': {
        'samples': ['7', 0],
        'vae': ['3', 2],
      },
    },
    '9': {
      'class_type': 'SaveImage',
      'inputs': {
        'images': ['8', 0],
        'filename_prefix': 'test',
      },
    },
  };

  group('DynamicWorkflow.parse', () {
    final dw = DynamicWorkflow.parse(sample, NodeRegistry());

    test('skips wired inputs', () {
      // KSampler has 4 wired inputs (model/positive/negative/latent_image)
      // and 6 primitive inputs.
      final ksamplerInputs = dw.inputs.where((e) => e.classType == 'KSampler');
      expect(ksamplerInputs.length, 6);
      final names = ksamplerInputs.map((e) => e.inputName).toSet();
      expect(names, {'seed', 'steps', 'cfg', 'sampler_name', 'scheduler', 'denoise'});
    });

    test('CLIPTextEncode positive vs negative is disambiguated', () {
      final pos = dw.inputs.firstWhere((e) => e.nodeId == '5' && e.inputName == 'text');
      final neg = dw.inputs.firstWhere((e) => e.nodeId == '6' && e.inputName == 'text');
      expect(pos.label, 'Positive Prompt');
      expect(neg.label, 'Negative Prompt');
    });

    test('exposes ckpt_name, dims, batch, filename_prefix', () {
      final keys = dw.inputs.map((e) => e.key).toSet();
      expect(keys.contains('3.ckpt_name'), isTrue);
      expect(keys.contains('4.width'), isTrue);
      expect(keys.contains('4.height'), isTrue);
      expect(keys.contains('4.batch_size'), isTrue);
      expect(keys.contains('9.filename_prefix'), isTrue);
    });

    test('groups by classType and node id', () {
      final ksampler = dw.inputs.firstWhere((e) => e.classType == 'KSampler');
      expect(ksampler.group, 'KSampler #7');
    });
  });

  group('DynamicWorkflow.applyValues', () {
    test('round-trips an unedited workflow', () {
      final dw = DynamicWorkflow.parse(sample, NodeRegistry());
      final out = dw.applyValues();
      expect(jsonEncode(out), jsonEncode(sample));
    });

    test('writes overrides back into deep-copied workflow', () {
      final dw = DynamicWorkflow.parse(sample, NodeRegistry());
      final pos = dw.inputs.firstWhere((e) => e.nodeId == '5' && e.inputName == 'text');
      pos.value = 'a dog';
      final seed = dw.inputs.firstWhere((e) => e.nodeId == '7' && e.inputName == 'seed');
      seed.value = 99;
      final out = dw.applyValues();
      expect((out['5'] as Map)['inputs']['text'], 'a dog');
      expect((out['7'] as Map)['inputs']['seed'], 99);
      // Source is untouched.
      expect((sample['5'] as Map)['inputs']['text'], 'a cat');
      expect((sample['7'] as Map)['inputs']['seed'], 12345);
    });
  });

  group('DynamicWorkflow.applySavedValues', () {
    test('restores values from saved map and ignores unknown keys', () {
      final dw = DynamicWorkflow.parse(sample, NodeRegistry());
      dw.applySavedValues({'7.seed': 42, 'unknown.key': 'x'});
      final seed = dw.inputs.firstWhere((e) => e.key == '7.seed');
      expect(seed.value, 42);
    });
  });
}
