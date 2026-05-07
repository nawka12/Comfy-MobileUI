import 'package:flutter/material.dart';

import '../models/generation_params.dart';
import '../models/lora_config.dart';

/// Collapsible "LoRAs" section. Renders a list of LoRA rows; each row
/// has a name dropdown, strength slider, enable switch, and delete.
class LoraPanel extends StatefulWidget {
  final GenerationParams params;
  final List<String> availableLoras;
  final ValueChanged<GenerationParams> onChanged;

  const LoraPanel({
    super.key,
    required this.params,
    required this.availableLoras,
    required this.onChanged,
  });

  @override
  State<LoraPanel> createState() => _LoraPanelState();
}

class _LoraPanelState extends State<LoraPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnimation;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _update(void Function(GenerationParams p) fn) {
    final updated = widget.params.copy();
    fn(updated);
    widget.onChanged(updated);
  }

  void _addLora() {
    final first = widget.availableLoras.isNotEmpty
        ? widget.availableLoras.first
        : '';
    _update((p) => p.loras = [...p.loras, LoraConfig(name: first)]);
  }

  void _removeLora(int i) {
    _update((p) => p.loras = [...p.loras]..removeAt(i));
  }

  void _setName(int i, String name) {
    _update((p) {
      final list = [...p.loras];
      list[i] = list[i].copy()..name = name;
      p.loras = list;
    });
  }

  void _setStrength(int i, double s) {
    _update((p) {
      final list = [...p.loras];
      list[i] = list[i].copy()..strength = s;
      p.loras = list;
    });
  }

  void _setEnabled(int i, bool enabled) {
    _update((p) {
      final list = [...p.loras];
      list[i] = list[i].copy()..enabled = enabled;
      p.loras = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loras = widget.params.loras;
    final activeCount = loras.where((l) => l.enabled && l.name.isNotEmpty).length;

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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.layers,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('LoRAs',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                if (loras.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$activeCount/${loras.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.expand_more,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1,
          child: _buildContent(theme, loras),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, List<LoraConfig> loras) {
    final noLoras = widget.availableLoras.isEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < loras.length; i++)
            _LoraRow(
              key: ValueKey('lora_$i'),
              index: i,
              lora: loras[i],
              available: widget.availableLoras,
              onName: (v) => _setName(i, v),
              onStrength: (v) => _setStrength(i, v),
              onEnabled: (v) => _setEnabled(i, v),
              onDelete: () => _removeLora(i),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: noLoras ? null : _addLora,
              icon: const Icon(Icons.add, size: 18),
              label: Text(noLoras ? 'No LoRAs on server' : 'Add LoRA'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LoraRow extends StatelessWidget {
  final int index;
  final LoraConfig lora;
  final List<String> available;
  final ValueChanged<String> onName;
  final ValueChanged<double> onStrength;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onDelete;

  const _LoraRow({
    super.key,
    required this.index,
    required this.lora,
    required this.available,
    required this.onName,
    required this.onStrength,
    required this.onEnabled,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectable =
        available.contains(lora.name) ? lora.name : (available.isNotEmpty ? null : null);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch(
                value: lora.enabled,
                onChanged: onEnabled,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('lora_name_${index}_${lora.name}'),
                  initialValue: selectable,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  hint: const Text('Pick a LoRA',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) {
                    if (v != null) onName(v);
                  },
                  items: available
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text(
                              n.split('/').last,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Remove',
                onPressed: onDelete,
              ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text('Strength',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w500)),
              ),
              Expanded(
                child: Slider(
                  value: lora.strength.clamp(-2.0, 2.0),
                  min: -2.0,
                  max: 2.0,
                  divisions: 80,
                  label: lora.strength.toStringAsFixed(2),
                  onChanged: onStrength,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  lora.strength.toStringAsFixed(2),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
