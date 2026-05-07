/// A user-configured LoRA in profile mode. Multiple instances are
/// chained as LoraLoader -> LoraLoader -> ... before the sampler.
class LoraConfig {
  String name;
  double strength;
  bool enabled;

  LoraConfig({
    this.name = '',
    this.strength = 1.0,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'strength': strength,
        'enabled': enabled,
      };

  factory LoraConfig.fromJson(Map<String, dynamic> j) => LoraConfig(
        name: j['name'] as String? ?? '',
        strength: (j['strength'] as num?)?.toDouble() ?? 1.0,
        enabled: j['enabled'] as bool? ?? true,
      );

  LoraConfig copy() => LoraConfig(
        name: name,
        strength: strength,
        enabled: enabled,
      );
}
