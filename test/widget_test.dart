import 'package:flutter_test/flutter_test.dart';
import 'package:comfy_mobileui/models/generation_params.dart';
import 'package:comfy_mobileui/models/architecture_profile.dart';

void main() {
  test('GenerationParams creates with defaults', () {
    final params = GenerationParams(
      positivePrompt: 'test prompt',
      negativePrompt: 'bad things',
      seed: 42,
      steps: 20,
      cfg: 7.0,
      denoise: 1.0,
      width: 512,
      height: 512,
      batchSize: 1,
      samplerName: 'euler',
      scheduler: 'normal',
      checkpoint: 'model.safetensors',
      profileId: 'standard',
    );

    expect(params.seed, 42);
    expect(params.steps, 20);
    expect(params.positivePrompt, 'test prompt');
    expect(params.negativePrompt, 'bad things');
    expect(params.profileId, 'standard');
  });

  test('GenerationParams.randomizeSeed changes seed', () {
    final params = GenerationParams(seed: 100);
    final original = params.seed;
    params.randomizeSeed();
    expect(params.seed, isNot(original));
  });

  test('GenerationParams.copy creates independent copy', () {
    final original = GenerationParams(seed: 42, steps: 20);
    final copy = original.copy();
    copy.seed = 99;
    expect(original.seed, 42);
    expect(copy.seed, 99);
  });

  test('GenerationParams extras round-trip through JSON', () {
    final params = GenerationParams(
      profileId: 'sdxl',
      extras: {'sdxlTargetWidth': 1024, 'sdxlTargetHeight': 1024},
    );
    final json = params.toJson();
    final restored = GenerationParams.fromJson(json);
    expect(restored.profileId, 'sdxl');
    expect(restored.extras['sdxlTargetWidth'], 1024);
    expect(restored.extras['sdxlTargetHeight'], 1024);
  });

  test('ArchitectureProfile detects from model name', () {
    expect(ArchitectureProfile.detect('flux-schnell')?.id, 'flux');
    expect(ArchitectureProfile.detect('sdxl_vae')?.id, 'sdxl');
    expect(ArchitectureProfile.detect('sd3.5_medium')?.id, 'sd3');
    expect(ArchitectureProfile.detect('anything_else'), isNull);
  });

  test('ArchitectureProfile byId returns correct profile', () {
    expect(ArchitectureProfile.byId('flux').name, 'Flux');
    expect(ArchitectureProfile.byId('sdxl').name, 'SDXL');
    expect(ArchitectureProfile.byId('sd3').name, 'SD3');
    expect(ArchitectureProfile.byId('unknown').id, 'standard');
  });

  test('ArchitectureProfile round-trips through JSON', () {
    final original = ArchitectureProfile.flux;
    final json = original.toJson();
    final restored = ArchitectureProfile.fromJson(json);
    expect(restored?.id, original.id);
    expect(restored?.name, original.name);
    expect(restored?.modelLoader, original.modelLoader);
    expect(restored?.textEncoder, original.textEncoder);
  });
}
