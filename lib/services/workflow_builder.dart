import '../models/architecture_profile.dart';
import '../models/generation_params.dart';
import '../models/nodes.dart';

class WorkflowBuilder {
  final NodeRegistry registry;

  WorkflowBuilder(this.registry);

  Map<String, dynamic> build(ArchitectureProfile profile, GenerationParams params) {
    final nodeIds = <String, int>{};
    int nextId = 3;

    String alloc(String key) {
      nodeIds[key] = nextId++;
      return nodeIds[key]!.toString();
    }

    final id = <String, String>{};
    id['loader'] = alloc('loader');
    id['latent'] = alloc('latent');
    id['encoder_pos'] = alloc('encoder_pos');
    id['encoder_neg'] = alloc('encoder_neg');
    id['sampler'] = alloc('sampler');
    id['decoder'] = alloc('decoder');
    id['output'] = alloc('output');

    if (profile.clipLoader != null) {
      id['clip_loader'] = alloc('clip_loader');
    }
    if (profile.vaeLoader != null) {
      id['vae_loader'] = alloc('vae_loader');
    }

    for (final extra in profile.extraNodes) {
      id[extra.key] = alloc(extra.key);
    }

    final workflow = <String, dynamic>{};

    void addNode(String nodeKey, String classType, Map<String, dynamic> inputs) {
      workflow[id[nodeKey]!] = {
        'class_type': classType,
        'inputs': inputs,
      };
    }

    // -- Loader --
    final loaderInputs = <String, dynamic>{};
    final loaderNode = registry[profile.modelLoader];
    bool modelInputSet = false;
    if (loaderNode != null) {
      for (final req in loaderNode.requiredInputs) {
        if (req.isConnection) continue;
        if (!modelInputSet && req.options != null && req.options!.isNotEmpty) {
          loaderInputs[req.name] = params.checkpoint;
          modelInputSet = true;
        } else if (params.extras.containsKey(_extraKeyForInput(profile, 'loader', req.name))) {
          loaderInputs[req.name] = params.extras[_extraKeyForInput(profile, 'loader', req.name)];
        } else if (req.defaultValue != null) {
          loaderInputs[req.name] = req.defaultValue;
        } else if (req.options != null && req.options!.isNotEmpty) {
          loaderInputs[req.name] = req.options!.first;
        }
      }
    }
    addNode('loader', profile.modelLoader, loaderInputs);

    // -- CLIP Loader --
    if (profile.clipLoader != null) {
      final clipInputs = <String, dynamic>{};
      final clipNode = registry[profile.clipLoader!];
      clipInputs['clip_name'] = params.clipModel.isNotEmpty ? params.clipModel : params.checkpoint;
      if (clipNode != null) {
        for (final req in clipNode.requiredInputs) {
          if (req.isConnection) continue;
          if (req.name == 'clip_name') continue;
          if (params.extras.containsKey(_extraKeyForInput(profile, 'clip_loader', req.name))) {
            clipInputs[req.name] = params.extras[_extraKeyForInput(profile, 'clip_loader', req.name)];
          } else if (req.defaultValue != null) {
            clipInputs[req.name] = req.defaultValue;
          } else if (req.options != null && req.options!.isNotEmpty) {
            clipInputs[req.name] = req.options!.first;
          }
        }
      }
      addNode('clip_loader', profile.clipLoader!, clipInputs);
    }

    // -- VAE Loader --
    if (profile.vaeLoader != null) {
      final vaeInputs = <String, dynamic>{};
      final vaeNode = registry[profile.vaeLoader!];
      String vaeName = params.vaeModel.isNotEmpty ? params.vaeModel : params.checkpoint;
      if (vaeNode != null) {
        for (final req in vaeNode.requiredInputs) {
          if (req.isConnection) continue;
          if (req.options != null && req.options!.isNotEmpty) {
            if (req.options!.contains(vaeName)) {
              vaeInputs[req.name] = vaeName;
            } else if (req.options!.isNotEmpty) {
              vaeInputs[req.name] = vaeName;
            }
          } else if (req.defaultValue != null) {
            vaeInputs[req.name] = req.defaultValue;
          }
        }
      }
      if (vaeInputs.isEmpty) {
        vaeInputs['vae_name'] = vaeName;
      }
      addNode('vae_loader', profile.vaeLoader!, vaeInputs);
    }

    // -- LoRA chain (chained between loader/clip_loader and encoders) --
    final activeLoras =
        params.loras.where((l) => l.enabled && l.name.isNotEmpty).toList();
    String? lastLoraKey;
    for (int i = 0; i < activeLoras.length; i++) {
      final loraKey = 'lora_$i';
      id[loraKey] = alloc(loraKey);
      final lora = activeLoras[i];
      final inputs = <String, dynamic>{
        'lora_name': lora.name,
        'strength_model': lora.strength,
        'strength_clip': lora.strength,
      };
      if (lastLoraKey == null) {
        inputs['model'] = _ref(id, 'loader', 0);
        inputs['clip'] = _initialClipRef(profile, id);
      } else {
        inputs['model'] = _ref(id, lastLoraKey, 0);
        inputs['clip'] = _ref(id, lastLoraKey, 1);
      }
      addNode(loraKey, 'LoraLoader', inputs);
      lastLoraKey = loraKey;
    }

    // -- Latent --
    addNode('latent', profile.latentSource, {
      'width': params.width,
      'height': params.height,
      'batch_size': params.batchSize,
    });

    // -- Positive Encoder --
    final encoderInputs =
        _buildEncoderInputs(profile, params, params.positivePrompt, true, id, lastLoraKey);
    addNode('encoder_pos', profile.textEncoder, encoderInputs);

    // -- Negative Encoder --
    final negEncoderInputs =
        _buildEncoderInputs(profile, params, params.negativePrompt, false, id, lastLoraKey);
    addNode('encoder_neg', profile.textEncoder, negEncoderInputs);

    // -- Extra nodes that modify model or conditioning --
    for (final extra in profile.extraNodes) {
      final inputs = Map<String, dynamic>.from(extra.fixedInputs);

      final extraType = registry[extra.nodeType];
      for (final req in extraType?.requiredInputs ?? <NodeInputDef>[]) {
        if (!inputs.containsKey(req.name)) {
          final paramDef = profile.extraParams.where((p) => p.inputName == req.name).firstOrNull;
          if (paramDef != null && params.extras.containsKey(paramDef.key)) {
            inputs[req.name] = params.extras[paramDef.key];
          } else if (req.defaultValue != null) {
            inputs[req.name] = req.defaultValue;
          }
        }
      }

      addNode(extra.key, extra.nodeType, inputs);
    }

    // -- Sampler --
    final samplerInputs = <String, dynamic>{
      'seed': params.seed,
      'steps': params.steps,
      'cfg': profile.showCfg ? params.cfg : 1.0,
      'sampler_name': params.samplerName,
      'scheduler': params.scheduler,
      'denoise': params.denoise,
    };

    samplerInputs['model'] = _ref(id, _modelSourceKey(profile, lastLoraKey), 0);
    samplerInputs['positive'] = _ref(id, _positiveSourceKey(profile), 0);
    samplerInputs['negative'] = _ref(id, _negativeSourceKey(profile), 0);
    samplerInputs['latent_image'] = _ref(id, 'latent', 0);

    addNode('sampler', profile.sampler, samplerInputs);

    // -- Decoder --
    final decoderInputs = <String, dynamic>{
      'samples': _ref(id, 'sampler', 0),
    };
    if (profile.vaeLoader != null && id.containsKey('vae_loader')) {
      decoderInputs['vae'] = _ref(id, 'vae_loader', 0);
    } else {
      decoderInputs['vae'] = _ref(id, 'loader', 2);
    }
    addNode('decoder', profile.decoder, decoderInputs);

    // -- Output --
    addNode('output', profile.output, {
      'images': _ref(id, 'decoder', 0),
      'filename_prefix': 'ComfyMobile',
    });

    return workflow;
  }

  List<dynamic> _ref(Map<String, String> id, String nodeKey, int outputIndex) =>
      [id[nodeKey]!, outputIndex];

  Map<String, dynamic> _buildEncoderInputs(
    ArchitectureProfile profile,
    GenerationParams params,
    String text,
    bool isPositive,
    Map<String, String> id,
    String? lastLoraKey,
  ) {
    final inputs = <String, dynamic>{};
    final encoderType = registry[profile.textEncoder];
    if (encoderType == null) return inputs;

    for (final req in encoderType.requiredInputs) {
      if (req.isConnection) {
        if (req.type == 'CLIP') {
          inputs[req.name] = _clipSource(profile, id, req.name, lastLoraKey);
        }
        continue;
      }

      switch (req.name) {
        case 'text':
          inputs['text'] = text;
        case 'text_g':
        case 'text_l':
          inputs[req.name] = text;
        case 'width':
          inputs['width'] = params.width;
        case 'height':
          inputs['height'] = params.height;
        case 'crop_w':
          inputs['crop_w'] = _intExtra(params, 'sdxlCropW');
        case 'crop_h':
          inputs['crop_h'] = _intExtra(params, 'sdxlCropH');
        case 'target_width':
          inputs['target_width'] = _intExtra(params, 'sdxlTargetWidth', params.width);
        case 'target_height':
          inputs['target_height'] = _intExtra(params, 'sdxlTargetHeight', params.height);
        case 'guidance':
          if (params.extras.containsKey('fluxGuidance')) {
            inputs['guidance'] = params.extras['fluxGuidance'];
          }
        case 'empty_padding':
          inputs['empty_padding'] = req.defaultValue ?? 0;
        default:
          if (req.defaultValue != null) inputs[req.name] = req.defaultValue;
      }
    }
    return inputs;
  }

  dynamic _clipSource(ArchitectureProfile profile, Map<String, String> id,
      String inputName, String? lastLoraKey) {
    if (lastLoraKey != null && inputName == 'clip') {
      return _ref(id, lastLoraKey, 1);
    }
    if (profile.clipLoader != null && id.containsKey('clip_loader')) {
      if (profile.textEncoder == 'CLIPTextEncodeFlux') {
        switch (inputName) {
          case 'clip': return _ref(id, 'clip_loader', 0);
          case 'clip_l': return _ref(id, 'clip_loader', 1);
          case 't5xxl': return _ref(id, 'clip_loader', 2);
        }
      }
      return _ref(id, 'clip_loader', 0);
    }
    if (profile.textEncoder == 'CLIPTextEncodeSD3') {
      return _ref(id, 'loader', 1);
    }
    return _ref(id, 'loader', 1);
  }

  /// CLIP reference for the first LoRA's input. Mirrors the encoder's
  /// `clip` source choice but ignores LoRA chaining (we're inserting
  /// _into_ the chain).
  dynamic _initialClipRef(ArchitectureProfile profile, Map<String, String> id) {
    if (profile.clipLoader != null && id.containsKey('clip_loader')) {
      return _ref(id, 'clip_loader', 0);
    }
    return _ref(id, 'loader', 1);
  }

  String _modelSourceKey(ArchitectureProfile profile, String? lastLoraKey) {
    for (final extra in profile.extraNodes) {
      final hasModelOutput = registry[extra.nodeType]?.outputNames.contains('MODEL') ?? false;
      if (hasModelOutput) return extra.key;
    }
    if (lastLoraKey != null) return lastLoraKey;
    return 'loader';
  }

  String _positiveSourceKey(ArchitectureProfile profile) {
    for (final extra in profile.extraNodes) {
      if (extra.outputWires.any((w) => w.toNodeKey == 'sampler' && w.toInput == 'positive')) {
        return extra.key;
      }
    }
    return 'encoder_pos';
  }

  String _negativeSourceKey(ArchitectureProfile profile) {
    for (final extra in profile.extraNodes) {
      if (extra.outputWires.any((w) => w.toNodeKey == 'sampler' && w.toInput == 'negative')) {
        return extra.key;
      }
    }
    return 'encoder_neg';
  }

  int _intExtra(GenerationParams p, String key, [int fallback = 0]) {
    final v = p.extras[key];
    if (v is int) return v;
    if (v is double) return v.toInt();
    return fallback;
  }

  String? _extraKeyForInput(ArchitectureProfile profile, String nodeKey, String inputName) {
    for (final p in profile.extraParams) {
      if (p.nodeKey == nodeKey && p.inputName == inputName) return p.key;
    }
    return null;
  }
}
