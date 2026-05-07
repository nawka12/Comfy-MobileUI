import 'package:comfy_mobileui/models/architecture_profile.dart';
import 'package:comfy_mobileui/models/generation_params.dart';
import 'package:comfy_mobileui/models/lora_config.dart';
import 'package:comfy_mobileui/models/nodes.dart';
import 'package:comfy_mobileui/services/workflow_builder.dart';
import 'package:flutter_test/flutter_test.dart';

NodeRegistry _fakeRegistry() {
  final r = NodeRegistry();
  r.loadFromApi({
    'CheckpointLoaderSimple': {
      'input': {
        'required': {
          'ckpt_name': [
            ['sd15.safetensors'],
          ],
        },
      },
    },
    'CLIPTextEncode': {
      'input': {
        'required': {
          'text': [
            'STRING',
            {'multiline': true},
          ],
          'clip': ['CLIP'],
        },
      },
    },
  });
  return r;
}

void main() {
  test('LoraConfig round-trips through JSON', () {
    final l = LoraConfig(name: 'foo.safetensors', strength: 0.7, enabled: false);
    final r = LoraConfig.fromJson(l.toJson());
    expect(r.name, 'foo.safetensors');
    expect(r.strength, 0.7);
    expect(r.enabled, false);
  });

  test('GenerationParams.copy deep-copies loras', () {
    final p = GenerationParams(
      loras: [LoraConfig(name: 'a', strength: 0.5)],
    );
    final c = p.copy();
    c.loras[0].strength = 0.1;
    expect(p.loras[0].strength, 0.5);
  });

  test('GenerationParams round-trips loras through JSON', () {
    final p = GenerationParams(
      loras: [
        LoraConfig(name: 'a.safetensors', strength: 0.8),
        LoraConfig(name: 'b.safetensors', strength: 0.3, enabled: false),
      ],
    );
    final r = GenerationParams.fromJson(p.toJson());
    expect(r.loras.length, 2);
    expect(r.loras[0].name, 'a.safetensors');
    expect(r.loras[1].enabled, false);
  });

  test('WorkflowBuilder chains 2 LoRAs between loader and sampler', () {
    final builder = WorkflowBuilder(_fakeRegistry());
    final params = GenerationParams(
      profileId: 'standard',
      checkpoint: 'sd15.safetensors',
      loras: [
        LoraConfig(name: 'style.safetensors', strength: 0.8),
        LoraConfig(name: 'detail.safetensors', strength: 0.5),
      ],
    );
    final wf = builder.build(ArchitectureProfile.standard, params);

    // Allocator starts at 3: loader=3, latent=4, encoder_pos=5,
    // encoder_neg=6, sampler=7, decoder=8, output=9, then lora_0=10, lora_1=11.
    final l0 = wf['10'] as Map<String, dynamic>;
    final l1 = wf['11'] as Map<String, dynamic>;
    expect(l0['class_type'], 'LoraLoader');
    expect(l1['class_type'], 'LoraLoader');

    // First LoRA: model from loader[0], clip from loader[1].
    expect(l0['inputs']['model'], ['3', 0]);
    expect(l0['inputs']['clip'], ['3', 1]);
    expect(l0['inputs']['lora_name'], 'style.safetensors');
    expect(l0['inputs']['strength_model'], 0.8);
    expect(l0['inputs']['strength_clip'], 0.8);

    // Second LoRA: model/clip from first LoRA.
    expect(l1['inputs']['model'], ['10', 0]);
    expect(l1['inputs']['clip'], ['10', 1]);

    // Sampler.model points at the last LoRA.
    final sampler = wf['7'] as Map<String, dynamic>;
    expect(sampler['inputs']['model'], ['11', 0]);

    // Encoders draw CLIP from the last LoRA.
    final encPos = wf['5'] as Map<String, dynamic>;
    expect(encPos['inputs']['clip'], ['11', 1]);
  });

  test('WorkflowBuilder skips disabled LoRAs and ones without a name', () {
    final builder = WorkflowBuilder(_fakeRegistry());
    final params = GenerationParams(
      profileId: 'standard',
      checkpoint: 'sd15.safetensors',
      loras: [
        LoraConfig(name: 'a.safetensors', strength: 0.5),
        LoraConfig(name: 'b.safetensors', strength: 0.5, enabled: false),
        LoraConfig(name: '', strength: 0.5),
      ],
    );
    final wf = builder.build(ArchitectureProfile.standard, params);
    // Only one LoRA should exist.
    final loras = wf.entries.where(
        (e) => (e.value as Map)['class_type'] == 'LoraLoader');
    expect(loras.length, 1);
  });

  test('No LoRAs means sampler.model still points at loader (legacy path)', () {
    final builder = WorkflowBuilder(_fakeRegistry());
    final params = GenerationParams(
      profileId: 'standard',
      checkpoint: 'sd15.safetensors',
    );
    final wf = builder.build(ArchitectureProfile.standard, params);
    final sampler = wf['7'] as Map<String, dynamic>;
    expect(sampler['inputs']['model'], ['3', 0]);
  });
}
