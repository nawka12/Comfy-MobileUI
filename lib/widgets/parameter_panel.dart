import 'package:flutter/material.dart';
import '../models/architecture_profile.dart';
import '../models/generation_params.dart';
import '../models/nodes.dart';

class ParameterPanel extends StatefulWidget {
  final GenerationParams params;
  final ValueChanged<GenerationParams> onChanged;
  final ArchitectureProfile profile;
  final NodeRegistry registry;
  final List<String> availableModels;
  final List<String> availableClipModels;
  final List<String> availableVaeModels;
  final VoidCallback? onPickModel;
  final VoidCallback? onPickClip;
  final VoidCallback? onPickVae;
  final bool isTams;

  const ParameterPanel({
    super.key,
    required this.params,
    required this.onChanged,
    required this.profile,
    required this.registry,
    this.availableModels = const [],
    this.availableClipModels = const [],
    this.availableVaeModels = const [],
    this.onPickModel,
    this.onPickClip,
    this.onPickVae,
    this.isTams = false,
  });

  @override
  State<ParameterPanel> createState() => _ParameterPanelState();
}

class _ParameterPanelState extends State<ParameterPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnimation;
  bool _expanded = false;
  final _seedCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  int _lastSeed = 0;
  int _lastWidth = 0;
  int _lastHeight = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeInOut,
    );
    _lastSeed = widget.params.seed;
    _seedCtrl.text = widget.params.seed.toString();
    _lastWidth = widget.params.width;
    _widthCtrl.text = widget.params.width.toString();
    _lastHeight = widget.params.height;
    _heightCtrl.text = widget.params.height.toString();
  }

  @override
  void didUpdateWidget(ParameterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.params.seed != _lastSeed) {
      _lastSeed = widget.params.seed;
      if (widget.params.seed.toString() != _seedCtrl.text) {
        _seedCtrl.text = widget.params.seed.toString();
      }
    }
    if (widget.params.width != _lastWidth) {
      _lastWidth = widget.params.width;
      if (widget.params.width.toString() != _widthCtrl.text) {
        _widthCtrl.text = widget.params.width.toString();
      }
    }
    if (widget.params.height != _lastHeight) {
      _lastHeight = widget.params.height;
      if (widget.params.height.toString() != _heightCtrl.text) {
        _heightCtrl.text = widget.params.height.toString();
      }
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _seedCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _update(void Function(GenerationParams s) fn) {
    final updated = widget.params.copy();
    fn(updated);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.params;
    final profile = widget.profile;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded) {
              _animCtrl.forward();
            } else {
              _animCtrl.reverse();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Generation Settings',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                _ProfileBadge(profile: profile),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1,
          child: _buildContent(theme, s, profile),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, GenerationParams s, ArchitectureProfile profile) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isTams) _buildProfileSelector(s, profile, theme),
          _buildModelPicker(s, profile, theme),
          _buildSeedRow(s, theme),
          const SizedBox(height: 4),
          _buildSlider('Steps', s.steps.toDouble(), 1, 150, 1,
              (v) => _update((s) => s.steps = v.round()), theme),
          if (profile.showCfg)
            _buildSlider('CFG', s.cfg, 1.0, 30.0, 0.5,
                (v) => _update((s) => s.cfg = v), theme),
          _buildSlider('Denoise', s.denoise, 0.0, 1.0, 0.05,
              (v) => _update((s) => s.denoise = v), theme),
          _buildDimensionRow(s, theme),
          _buildBatchRow(s, theme),
          _buildSamplerRow(s, theme),
          _buildSchedulerRow(s, theme),
          if (profile.extraParams.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSectionHeader('${profile.name} Settings', theme),
            for (final extra in profile.extraParams) ...[
              if (extra.widget == ParamWidgetType.slider)
                _buildExtraSlider(s, extra, theme)
              else if (extra.widget == ParamWidgetType.dropdown)
                _buildExtraDropdown(s, extra, theme)
              else
                _buildExtraTextField(s, extra, theme),
            ],
          ],
          if (profile.clipLoader != null) ...[
            const SizedBox(height: 8),
            _buildSectionHeader('Model Components', theme),
            if (widget.onPickClip != null)
              _buildFieldRow('CLIP', s.clipModel.isNotEmpty
                  ? s.clipModel.split('/').last.split('.').first
                  : 'Auto', widget.onPickClip, s.clipModel.isEmpty, theme),
            if (widget.onPickVae != null)
              _buildFieldRow('VAE', s.vaeModel.isNotEmpty
                  ? s.vaeModel.split('/').last.split('.').first
                  : 'Auto', widget.onPickVae, s.vaeModel.isEmpty, theme),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildProfileSelector(GenerationParams s, ArchitectureProfile profile, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          _label('Architecture', theme),
          const SizedBox(width: 12),
          Expanded(
              child: DropdownButtonFormField<String>(
              key: ValueKey('arch_${s.profileId}'),
              initialValue: s.profileId,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) {
                if (v != null) _update((s) => s.profileId = v);
              },
              items: ArchitectureProfile.all.map((p) {
                return DropdownMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(_iconFor(p.icon), size: 16, color: p.color),
                      const SizedBox(width: 8),
                      Text(p.name),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelPicker(GenerationParams s, ArchitectureProfile profile, ThemeData theme) {
    final noModels = widget.availableModels.isEmpty;
    final modelName = s.checkpoint.isNotEmpty
        ? s.checkpoint.split('/').last.split('.').first
        : noModels ? 'No models on server' : 'None selected';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label('Model', theme),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: widget.onPickModel,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    if (noModels)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.warning_amber_rounded,
                            size: 16, color: theme.colorScheme.error),
                      ),
                    Expanded(
                      child: Text(
                        modelName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: s.checkpoint.isEmpty
                              ? (noModels
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant)
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String value, VoidCallback? onTap,
      bool isEmpty, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label(label, theme),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    if (isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.auto_awesome,
                            size: 14, color: theme.colorScheme.primary),
                      ),
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isEmpty
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeedRow(GenerationParams s, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label('Seed', theme),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _seedCtrl,
              keyboardType: TextInputType.number,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: 'Auto',
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null) {
                  _lastSeed = parsed;
                  _update((s) => s.seed = parsed);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => _update((s) => s.randomizeSeed()),
            icon: const Icon(Icons.shuffle, size: 18),
            tooltip: 'Randomize seed',
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      double step, ValueChanged<double> onChanged, ThemeData theme) {
    return _SliderField(
      label: label,
      value: value,
      min: min,
      max: max,
      step: step,
      onChanged: onChanged,
    );
  }

  Widget _buildExtraSlider(GenerationParams s, ExtraParamDef extra, ThemeData theme) {
    final current = s.extras[extra.key] ?? extra.defaultValue ?? 0;
    final value = (current is num) ? current.toDouble() : 0.0;
    return _SliderField(
      label: extra.label,
      value: value,
      min: extra.min ?? 0,
      max: extra.max ?? 100,
      step: extra.step ?? 1,
      onChanged: (v) => _update((s) => s.extras[extra.key] = v),
    );
  }

  Widget _buildExtraDropdown(GenerationParams s, ExtraParamDef extra, ThemeData theme) {
    final current = s.extras[extra.key] ?? extra.defaultValue ?? '';
    final options = extra.options ??
        _getNodeInputOptions(extra.nodeKey, extra.inputName);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label(extra.label, theme),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('${extra.key}_$current'),
              initialValue: (options.contains(current) ? current : options.firstOrNull) as String?,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) {
                if (v != null) _update((s) => s.extras[extra.key] = v);
              },
              items: options
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item, style: theme.textTheme.bodySmall),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraTextField(GenerationParams s, ExtraParamDef extra, ThemeData theme) {
    final current = s.extras[extra.key] ?? extra.defaultValue ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label(extra.label, theme),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: current.toString(),
              key: ValueKey('extra_${extra.key}_$current'),
              keyboardType: extra.min != null ? TextInputType.number : null,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) {
                if (extra.min != null) {
                  final parsed = int.tryParse(v);
                  if (parsed != null) _update((s) => s.extras[extra.key] = parsed);
                } else {
                  _update((s) => s.extras[extra.key] = v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionRow(GenerationParams s, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label('Latents', theme),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                    child: _dimField('W', _widthCtrl, (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed >= 64 && parsed <= 16384) {
                        _lastWidth = parsed;
                        _update((s) => s.width = parsed);
                      }
                    }, theme)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.close, size: 14),
                ),
                Expanded(
                    child: _dimField('H', _heightCtrl, (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed >= 64 && parsed <= 16384) {
                        _lastHeight = parsed;
                        _update((s) => s.height = parsed);
                      }
                    }, theme)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.aspect_ratio, size: 20),
            tooltip: 'Preset resolutions',
            onSelected: (preset) {
              final parts = preset.split('x');
              if (parts.length == 2) {
                _update((s) {
                  s.width = int.parse(parts[0]);
                  s.height = int.parse(parts[1]);
                });
              }
            },
            itemBuilder: (_) => [
              '512x512', '512x768', '768x512', '768x768',
              '768x1024', '1024x768', '1024x1024',
              '1024x1280', '1280x1024', '1216x832', '832x1216',
            ].map((r) => PopupMenuItem(value: r, child: Text(r))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _dimField(String label, TextEditingController controller, ValueChanged<String> onChanged, ThemeData theme) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: theme.textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        labelText: label,
        labelStyle: theme.textTheme.labelSmall,
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildBatchRow(GenerationParams s, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label('Batch', theme),
          Expanded(
            child: Slider(
              value: s.batchSize.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              label: s.batchSize.toString(),
              onChanged: (v) => _update((s) => s.batchSize = v.round()),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              s.batchSize.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplerRow(GenerationParams s, ThemeData theme) {
    final samplers = widget.registry['KSampler']?.input('sampler_name')?.options ?? defaultSamplers;
    return _buildDropdown('Sampler', s.samplerName, samplers,
        (v) => _update((s) => s.samplerName = v), theme);
  }

  Widget _buildSchedulerRow(GenerationParams s, ThemeData theme) {
    final schedulers = widget.registry['KSampler']?.input('scheduler')?.options ?? defaultSchedulers;
    return _buildDropdown('Scheduler', s.scheduler, schedulers,
        (v) => _update((s) => s.scheduler = v), theme);
  }

  Widget _buildDropdown(String label, String val, List<String> items,
      ValueChanged<String> onChanged, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _label(label, theme),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('${label}_$val'),
              initialValue: items.contains(val) ? val : null,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              items: items
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item, style: theme.textTheme.bodySmall),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, ThemeData theme) {
    return SizedBox(
      width: 80,
      child: Text(text,
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getNodeInputOptions(String nodeKey, String inputName) {
    final typeName = _resolveNodeType(nodeKey);
    if (typeName == null) return [];
    final node = widget.registry[typeName];
    if (node == null) return [];
    final input = node.input(inputName);
    return input?.options ?? [];
  }

  String? _resolveNodeType(String key) {
    switch (key) {
      case 'loader': return widget.profile.modelLoader;
      case 'clip_loader': return widget.profile.clipLoader;
      case 'vae_loader': return widget.profile.vaeLoader;
      default:
        for (final extra in widget.profile.extraNodes) {
          if (extra.key == key) return extra.nodeType;
        }
        return key;
    }
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'auto_awesome': return Icons.auto_awesome;
      case 'bolt': return Icons.bolt;
      case 'code': return Icons.code;
      case 'palette': return Icons.palette;
      default: return Icons.auto_awesome;
    }
  }
}

class _ProfileBadge extends StatelessWidget {
  final ArchitectureProfile profile;

  const _ProfileBadge({required this.profile});

  @override
  Widget build(BuildContext context) {
    final icon = switch (profile.icon) {
      'auto_awesome' => Icons.auto_awesome,
      'bolt' => Icons.bolt,
      'code' => Icons.code,
      'palette' => Icons.palette,
      _ => Icons.auto_awesome,
    };
    final color = profile.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            profile.name,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _SliderField extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  State<_SliderField> createState() => _SliderFieldState();
}

class _SliderFieldState extends State<_SliderField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  late double _lastValue;

  @override
  void initState() {
    super.initState();
    _lastValue = widget.value;
    _ctrl = TextEditingController(text: _format(widget.value));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_SliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _lastValue) {
      _lastValue = widget.value;
      if (!_focus.hasFocus) {
        final formatted = _format(widget.value);
        if (_ctrl.text != formatted) {
          _ctrl.text = formatted;
        }
      }
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _format(double v) =>
      widget.step >= 1 ? v.round().toString() : v.toStringAsFixed(2);

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final text = _ctrl.text;
    final parsed = widget.step >= 1
        ? int.tryParse(text)?.toDouble()
        : double.tryParse(text);
    if (parsed != null && parsed >= widget.min && parsed <= widget.max) {
      if (parsed != widget.value) {
        _lastValue = parsed;
        widget.onChanged(parsed);
      }
    } else {
      final formatted = _format(widget.value);
      if (_ctrl.text != formatted) {
        _ctrl.text = formatted;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(widget.label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Slider(
              value: widget.value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: ((widget.max - widget.min) / widget.step)
                  .round()
                  .clamp(1, 1000),
              onChanged: widget.onChanged,
            ),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}

