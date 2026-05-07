import 'dart:ui' show Color;

class ParamWidgetType {
  final String name;
  const ParamWidgetType._(this.name);

  static const slider = ParamWidgetType._('slider');
  static const dropdown = ParamWidgetType._('dropdown');
  static const textfield = ParamWidgetType._('textfield');
  static const spinner = ParamWidgetType._('spinner');

  static ParamWidgetType fromString(String s) {
    switch (s) {
      case 'slider': return slider;
      case 'dropdown': return dropdown;
      case 'textfield': return textfield;
      case 'spinner': return spinner;
      default: return textfield;
    }
  }
}

class ExtraParamDef {
  final String key;
  final String label;
  final String nodeKey;
  final String inputName;
  final dynamic defaultValue;
  final ParamWidgetType widget;
  final double? min;
  final double? max;
  final double? step;
  final List<String>? options;

  const ExtraParamDef({
    required this.key,
    required this.label,
    required this.nodeKey,
    required this.inputName,
    this.defaultValue,
    this.widget = ParamWidgetType.textfield,
    this.min,
    this.max,
    this.step,
    this.options,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'nodeKey': nodeKey,
    'inputName': inputName,
    'defaultValue': defaultValue,
    'widget': widget.name,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (step != null) 'step': step,
    if (options != null) 'options': options,
  };

  factory ExtraParamDef.fromJson(Map<String, dynamic> j) => ExtraParamDef(
    key: j['key'] as String,
    label: j['label'] as String,
    nodeKey: j['nodeKey'] as String,
    inputName: j['inputName'] as String,
    defaultValue: j['defaultValue'],
    widget: ParamWidgetType.fromString(j['widget'] as String? ?? 'textfield'),
    min: (j['min'] as num?)?.toDouble(),
    max: (j['max'] as num?)?.toDouble(),
    step: (j['step'] as num?)?.toDouble(),
    options: (j['options'] as List<dynamic>?)?.cast<String>(),
  );
}

class ExtraNodeDef {
  final String key;
  final String nodeType;
  final String label;
  final Map<String, dynamic> fixedInputs;

  /// List of wires: from this node's output index -> (destNodeKey, destInput)
  final List<WireDef> outputWires;

  const ExtraNodeDef({
    required this.key,
    required this.nodeType,
    required this.label,
    this.fixedInputs = const {},
    this.outputWires = const [],
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'nodeType': nodeType,
    'label': label,
    'fixedInputs': fixedInputs,
    'outputWires': outputWires.map((w) => w.toJson()).toList(),
  };

  factory ExtraNodeDef.fromJson(Map<String, dynamic> j) => ExtraNodeDef(
    key: j['key'] as String,
    nodeType: j['nodeType'] as String,
    label: j['label'] as String,
    fixedInputs: (j['fixedInputs'] as Map<String, dynamic>?) ?? {},
    outputWires: ((j['outputWires'] as List<dynamic>?) ?? [])
        .map((e) => WireDef.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class WireDef {
  final int fromOutput;
  final String toNodeKey;
  final String toInput;

  const WireDef({
    required this.fromOutput,
    required this.toNodeKey,
    required this.toInput,
  });

  Map<String, dynamic> toJson() => {
    'fromOutput': fromOutput,
    'toNodeKey': toNodeKey,
    'toInput': toInput,
  };

  factory WireDef.fromJson(Map<String, dynamic> j) => WireDef(
    fromOutput: j['fromOutput'] as int,
    toNodeKey: j['toNodeKey'] as String,
    toInput: j['toInput'] as String,
  );
}

class ArchitectureProfile {
  final String id;
  final String name;
  final int colorValue;
  final String icon;
  final List<String> detectPatterns;

  // Node type assignments for each role
  final String modelLoader;
  final String? clipLoader;
  final String? vaeLoader;
  final String textEncoder;
  final String sampler;
  final String decoder;
  final String output;
  final String latentSource;

  // Which params the profile exposes
  final bool showCfg;
  final bool showDenoise;

  // Extra params beyond the common set
  final List<ExtraParamDef> extraParams;

  // Extra nodes to inject into the pipeline
  final List<ExtraNodeDef> extraNodes;

  const ArchitectureProfile({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.icon,
    this.detectPatterns = const [],
    this.modelLoader = 'CheckpointLoaderSimple',
    this.clipLoader,
    this.vaeLoader,
    this.textEncoder = 'CLIPTextEncode',
    this.sampler = 'KSampler',
    this.decoder = 'VAEDecode',
    this.output = 'SaveImage',
    this.latentSource = 'EmptyLatentImage',
    this.showCfg = true,
    this.showDenoise = true,
    this.extraParams = const [],
    this.extraNodes = const [],
  });

  Color get color => Color(colorValue);

  static const standard = ArchitectureProfile(
    id: 'standard',
    name: 'Standard',
    colorValue: 0xFF9E9E9E,
    icon: 'code',
    detectPatterns: [],
    showCfg: true,
    showDenoise: true,
  );

  static const sdxl = ArchitectureProfile(
    id: 'sdxl',
    name: 'SDXL',
    colorValue: 0xFF2196F3,
    icon: 'auto_awesome',
    detectPatterns: ['xl', 'sdxl', 'sd_xl'],
    textEncoder: 'CLIPTextEncodeSDXL',
    showCfg: true,
    showDenoise: true,
    extraParams: [
      ExtraParamDef(
        key: 'sdxlTargetWidth', label: 'Target Width',
        nodeKey: 'encoder', inputName: 'target_width',
        defaultValue: 1024, widget: ParamWidgetType.spinner,
        min: 64, max: 16384, step: 8,
      ),
      ExtraParamDef(
        key: 'sdxlTargetHeight', label: 'Target Height',
        nodeKey: 'encoder', inputName: 'target_height',
        defaultValue: 1024, widget: ParamWidgetType.spinner,
        min: 64, max: 16384, step: 8,
      ),
      ExtraParamDef(
        key: 'sdxlCropW', label: 'Crop W',
        nodeKey: 'encoder', inputName: 'crop_w',
        defaultValue: 0, widget: ParamWidgetType.spinner,
        min: 0, max: 16384, step: 8,
      ),
      ExtraParamDef(
        key: 'sdxlCropH', label: 'Crop H',
        nodeKey: 'encoder', inputName: 'crop_h',
        defaultValue: 0, widget: ParamWidgetType.spinner,
        min: 0, max: 16384, step: 8,
      ),
    ],
  );

  static const anima = ArchitectureProfile(
    id: 'anima',
    name: 'Anima',
    colorValue: 0xFF9C27B0,
    icon: 'palette',
    detectPatterns: ['anima', 'circle'],
    modelLoader: 'UNETLoader',
    clipLoader: 'CLIPLoader',
    vaeLoader: 'VAELoader',
    textEncoder: 'CLIPTextEncode',
    showCfg: true,
    showDenoise: true,
    extraParams: [
      ExtraParamDef(
        key: 'weightDtype',
        label: 'Weight Dtype',
        nodeKey: 'loader',
        inputName: 'weight_dtype',
        defaultValue: 'default', widget: ParamWidgetType.dropdown,
      ),
      ExtraParamDef(
        key: 'clipType',
        label: 'CLIP Type',
        nodeKey: 'clip_loader',
        inputName: 'type',
        defaultValue: 'stable_diffusion', widget: ParamWidgetType.dropdown,
      ),
    ],
  );

  static const flux = ArchitectureProfile(
    id: 'flux',
    name: 'Flux',
    colorValue: 0xFFFF6B35,
    icon: 'bolt',
    detectPatterns: ['flux', 'schnell'],
    modelLoader: 'UNETLoader',
    clipLoader: 'CLIPLoader',
    textEncoder: 'CLIPTextEncodeFlux',
    showCfg: false,
    showDenoise: true,
    extraNodes: [
      ExtraNodeDef(
        key: 'flux_guidance',
        nodeType: 'FluxGuidance',
        label: 'Flux Guidance',
        outputWires: [
          WireDef(fromOutput: 0, toNodeKey: 'sampler', toInput: 'positive'),
        ],
      ),
      ExtraNodeDef(
        key: 'neg_flux_guidance',
        nodeType: 'FluxGuidance',
        label: 'Negative Flux Guidance',
        outputWires: [
          WireDef(fromOutput: 0, toNodeKey: 'sampler', toInput: 'negative'),
        ],
      ),
    ],
    extraParams: [
      ExtraParamDef(
        key: 'fluxGuidance',
        label: 'Guidance',
        nodeKey: 'flux_guidance',
        inputName: 'guidance',
        defaultValue: 3.5, widget: ParamWidgetType.slider,
        min: 0.0, max: 30.0, step: 0.5,
      ),
      ExtraParamDef(
        key: 'negFluxGuidance',
        label: 'Neg Guidance',
        nodeKey: 'neg_flux_guidance',
        inputName: 'guidance',
        defaultValue: 1.0, widget: ParamWidgetType.slider,
        min: 0.0, max: 30.0, step: 0.5,
      ),
      ExtraParamDef(
        key: 'weightDtype',
        label: 'Weight Dtype',
        nodeKey: 'loader',
        inputName: 'weight_dtype',
        defaultValue: 'default', widget: ParamWidgetType.dropdown,
      ),
      ExtraParamDef(
        key: 'clipType',
        label: 'CLIP Type',
        nodeKey: 'clip_loader',
        inputName: 'type',
        defaultValue: 'flux', widget: ParamWidgetType.dropdown,
      ),
    ],
  );

  static const sd3 = ArchitectureProfile(
    id: 'sd3',
    name: 'SD3',
    colorValue: 0xFF4CAF50,
    icon: 'auto_awesome',
    detectPatterns: ['sd3', 'sd3.5', 'sd_3'],
    textEncoder: 'CLIPTextEncodeSD3',
    latentSource: 'EmptySD3LatentImage',
    showCfg: true,
    showDenoise: true,
    extraNodes: [
      ExtraNodeDef(
        key: 'model_sampling',
        nodeType: 'ModelSamplingSD3',
        label: 'Model Sampling',
        fixedInputs: {},
        outputWires: [
          WireDef(fromOutput: 0, toNodeKey: 'sampler', toInput: 'model'),
        ],
      ),
    ],
    extraParams: [
      ExtraParamDef(
        key: 'shift',
        label: 'Shift',
        nodeKey: 'model_sampling',
        inputName: 'shift',
        defaultValue: 3.0, widget: ParamWidgetType.slider,
        min: 0.0, max: 10.0, step: 0.1,
      ),
    ],
  );

  static const all = [standard, sdxl, anima, flux, sd3];

  static ArchitectureProfile byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => standard);

  static ArchitectureProfile? detect(String modelName) {
    final lower = modelName.toLowerCase();
    for (final profile in all) {
      for (final pattern in profile.detectPatterns) {
        if (lower.contains(pattern)) return profile;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorValue,
    'icon': icon,
    'detectPatterns': detectPatterns,
    'modelLoader': modelLoader,
    'clipLoader': clipLoader,
    'vaeLoader': vaeLoader,
    'textEncoder': textEncoder,
    'sampler': sampler,
    'decoder': decoder,
    'output': output,
    'latentSource': latentSource,
    'showCfg': showCfg,
    'showDenoise': showDenoise,
    'extraParams': extraParams.map((p) => p.toJson()).toList(),
    'extraNodes': extraNodes.map((n) => n.toJson()).toList(),
  };

  static ArchitectureProfile? fromJson(Map<String, dynamic> j) {
    return ArchitectureProfile(
      id: j['id'] as String,
      name: j['name'] as String,
      colorValue: j['color'] as int,
      icon: j['icon'] as String? ?? 'code',
      detectPatterns: (j['detectPatterns'] as List<dynamic>?)?.cast<String>() ?? [],
      modelLoader: j['modelLoader'] as String? ?? 'CheckpointLoaderSimple',
      clipLoader: j['clipLoader'] as String?,
      vaeLoader: j['vaeLoader'] as String?,
      textEncoder: j['textEncoder'] as String? ?? 'CLIPTextEncode',
      sampler: j['sampler'] as String? ?? 'KSampler',
      decoder: j['decoder'] as String? ?? 'VAEDecode',
      output: j['output'] as String? ?? 'SaveImage',
      latentSource: j['latentSource'] as String? ?? 'EmptyLatentImage',
      showCfg: j['showCfg'] as bool? ?? true,
      showDenoise: j['showDenoise'] as bool? ?? true,
      extraParams: ((j['extraParams'] as List<dynamic>?) ?? [])
          .map((e) => ExtraParamDef.fromJson(e as Map<String, dynamic>))
          .toList(),
      extraNodes: ((j['extraNodes'] as List<dynamic>?) ?? [])
          .map((e) => ExtraNodeDef.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
