import 'dart:math';

import 'lora_config.dart';

class GenerationParams {
  String positivePrompt;
  String negativePrompt;
  int seed;
  int steps;
  double cfg;
  double denoise;
  int width;
  int height;
  int batchSize;
  String samplerName;
  String scheduler;
  String profileId;
  String checkpoint;
  String clipModel;
  String vaeModel;

  Map<String, dynamic> extras;
  List<LoraConfig> loras;

  GenerationParams({
    this.positivePrompt = '',
    this.negativePrompt = '',
    int? seed,
    this.steps = 20,
    this.cfg = 7.0,
    this.denoise = 1.0,
    this.width = 1024,
    this.height = 1024,
    this.batchSize = 1,
    this.samplerName = 'euler',
    this.scheduler = 'normal',
    this.profileId = 'standard',
    this.checkpoint = '',
    this.clipModel = '',
    this.vaeModel = '',
    Map<String, dynamic>? extras,
    List<LoraConfig>? loras,
  })  : seed = seed ?? Random().nextInt(1 << 32),
        extras = extras ?? {},
        loras = loras ?? [];

  void randomizeSeed() => seed = Random().nextInt(1 << 32);

  Map<String, dynamic> toJson() => {
    'positivePrompt': positivePrompt,
    'negativePrompt': negativePrompt,
    'seed': seed,
    'steps': steps,
    'cfg': cfg,
    'denoise': denoise,
    'width': width,
    'height': height,
    'batchSize': batchSize,
    'samplerName': samplerName,
    'scheduler': scheduler,
    'profileId': profileId,
    'checkpoint': checkpoint,
    'clipModel': clipModel,
    'vaeModel': vaeModel,
    'extras': extras,
    'loras': loras.map((l) => l.toJson()).toList(),
  };

  factory GenerationParams.fromJson(Map<String, dynamic> json) =>
      GenerationParams(
        positivePrompt: json['positivePrompt'] as String? ?? '',
        negativePrompt: json['negativePrompt'] as String? ?? '',
        seed: json['seed'] as int?,
        steps: json['steps'] as int? ?? 20,
        cfg: (json['cfg'] as num?)?.toDouble() ?? 7.0,
        denoise: (json['denoise'] as num?)?.toDouble() ?? 1.0,
        width: json['width'] as int? ?? 1024,
        height: json['height'] as int? ?? 1024,
        batchSize: json['batchSize'] as int? ?? 1,
        samplerName: json['samplerName'] as String? ?? 'euler',
        scheduler: json['scheduler'] as String? ?? 'normal',
        profileId: json['profileId'] as String? ?? 'standard',
        checkpoint: json['checkpoint'] as String? ?? '',
        clipModel: json['clipModel'] as String? ?? '',
        vaeModel: json['vaeModel'] as String? ?? '',
        extras: (json['extras'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v),
            ) ?? {},
        loras: (json['loras'] as List<dynamic>?)
                ?.map((e) => LoraConfig.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  GenerationParams copy() => GenerationParams(
    positivePrompt: positivePrompt,
    negativePrompt: negativePrompt,
    seed: seed,
    steps: steps,
    cfg: cfg,
    denoise: denoise,
    width: width,
    height: height,
    batchSize: batchSize,
    samplerName: samplerName,
    scheduler: scheduler,
    profileId: profileId,
    checkpoint: checkpoint,
    clipModel: clipModel,
    vaeModel: vaeModel,
    extras: Map.from(extras),
    loras: loras.map((l) => l.copy()).toList(),
  );
}
