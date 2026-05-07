import 'dart:convert';

class NodeInputDef {
  final String name;
  final String type;
  final dynamic defaultValue;
  final num? min;
  final num? max;
  final num? step;
  final List<String>? options;
  final String? tooltip;
  final bool advanced;

  NodeInputDef({
    required this.name,
    required this.type,
    this.defaultValue,
    this.min,
    this.max,
    this.step,
    this.options,
    this.tooltip,
    this.advanced = false,
  });

  factory NodeInputDef.fromApi(String name, List<dynamic> spec) {
    dynamic typeOrDef;
    Map<String, dynamic> meta = {};
    if (spec.length >= 2) {
      typeOrDef = spec[0];
      if (spec[1] is Map) meta = spec[1] as Map<String, dynamic>;
    } else if (spec.length == 1) {
      typeOrDef = spec[0];
    } else {
      return NodeInputDef(name: name, type: 'UNKNOWN');
    }

    String type;
    dynamic defaultValue;
    num? min, max, step;
    List<String>? options;
    bool advanced = meta['advanced'] == true;

    if (typeOrDef is List) {
      options = typeOrDef.cast<String>();
      type = 'ENUM';
    } else if (typeOrDef is String) {
      type = typeOrDef;
    } else {
      type = typeOrDef.toString();
    }

    if (meta case {'default': dynamic def}) defaultValue = def;
    if (meta case {'min': num v}) min = v;
    if (meta case {'max': num v}) max = v;
    if (meta case {'step': num v}) step = v;

    return NodeInputDef(
      name: name,
      type: type,
      defaultValue: defaultValue,
      min: min,
      max: max,
      step: step,
      options: options,
      tooltip: meta['tooltip'] as String?,
      advanced: advanced,
    );
  }

  bool get isConnection => ['MODEL', 'CONDITIONING', 'LATENT', 'IMAGE', 'CLIP', 'VAE', 'MASK']
      .contains(type);

  bool get isNumber => type == 'INT' || type == 'FLOAT';
  bool get isString => type == 'STRING';
  bool get isEnum => options != null;
}

class NodeType {
  final String name;
  final String displayName;
  final String category;
  final String pythonModule;
  final List<String> outputNames;
  final List<NodeInputDef> requiredInputs;
  final List<NodeInputDef> optionalInputs;
  final bool outputNode;

  NodeType({
    required this.name,
    required this.displayName,
    required this.category,
    required this.pythonModule,
    required this.outputNames,
    required this.requiredInputs,
    required this.optionalInputs,
    required this.outputNode,
  });

  factory NodeType.fromApi(String name, Map<String, dynamic> json) {
    final input = json['input'] as Map<String, dynamic>? ?? {};
    final requiredRaw = input['required'] as Map<String, dynamic>? ?? {};
    final optionalRaw = input['optional'] as Map<String, dynamic>? ?? {};

    return NodeType(
      name: name,
      displayName: json['display_name'] as String? ?? name,
      category: json['category'] as String? ?? '',
      pythonModule: json['python_module'] as String? ?? '',
      outputNames: (json['output_name'] as List<dynamic>?)?.cast<String>() ?? [],
      requiredInputs: requiredRaw.entries
          .map((e) => NodeInputDef.fromApi(e.key, e.value as List<dynamic>))
          .toList(),
      optionalInputs: optionalRaw.entries
          .map((e) => NodeInputDef.fromApi(e.key, e.value as List<dynamic>))
          .toList(),
      outputNode: json['output_node'] == true,
    );
  }

  List<NodeInputDef> get allInputs => [...requiredInputs, ...optionalInputs];

  NodeInputDef? input(String name) {
    final idx = requiredInputs.indexWhere((i) => i.name == name);
    if (idx != -1) return requiredInputs[idx];
    final idx2 = optionalInputs.indexWhere((i) => i.name == name);
    if (idx2 != -1) return optionalInputs[idx2];
    return null;
  }
}

class NodeRegistry {
  final Map<String, NodeType> _types = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  void loadFromApi(Map<String, dynamic> raw) {
    _types.clear();
    for (final entry in raw.entries) {
      _types[entry.key] = NodeType.fromApi(entry.key, entry.value as Map<String, dynamic>);
    }
    _loaded = true;
  }

  void loadFromJson(String json) {
    loadFromApi(jsonDecode(json) as Map<String, dynamic>);
  }

  NodeType? operator [](String name) => _types[name];

  List<NodeType> byCategory(String category) =>
      _types.values.where((n) => n.category == category).toList();

  List<NodeType> byModule(String module) =>
      _types.values.where((n) => n.pythonModule == module).toList();

  List<NodeType> get all => _types.values.toList();

  List<NodeType> withOutput(String type) => _types.values
      .where((n) => n.outputNames.contains(type))
      .toList();

  List<NodeType> withInput(String type) => _types.values
      .where((n) => n.allInputs.any((i) => i.type == type))
      .toList();

  String exportJson() {
    const encoder = JsonEncoder.withIndent('  ');
    final map = <String, dynamic>{};
    for (final entry in _types.entries) {
      map[entry.key] = {
        'name': entry.key,
        'display_name': entry.value.displayName,
      };
    }
    return encoder.convert(map);
  }

  List<String> getCheckpoints(String loaderType) {
    final node = _types[loaderType];
    if (node == null) return [];
    for (final input in node.requiredInputs) {
      if (input.options != null && input.options!.isNotEmpty) return input.options!;
    }
    return [];
  }
}
