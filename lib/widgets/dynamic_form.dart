import 'dart:math';

import 'package:flutter/material.dart';
import '../models/dynamic_workflow.dart';
import '../models/nodes.dart';

/// Renders a form for every editable input on a [DynamicWorkflow].
/// Inputs are grouped by node and rendered with widgets chosen from
/// [NodeInputDef] metadata: ENUM -> dropdown, BOOLEAN -> switch,
/// numeric with bounded range -> slider, otherwise a textfield.
class DynamicForm extends StatefulWidget {
  final DynamicWorkflow workflow;
  final NodeRegistry registry;
  final VoidCallback onChanged;

  const DynamicForm({
    super.key,
    required this.workflow,
    required this.registry,
    required this.onChanged,
  });

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  final _rng = Random();
  final _controllers = <String, TextEditingController>{};

  TextEditingController _ctrl(ExposedInput ex) {
    return _controllers.putIfAbsent(
      ex.key,
      () => TextEditingController(text: ex.value?.toString() ?? ''),
    );
  }

  void _syncCtrl(ExposedInput ex) {
    final c = _ctrl(ex);
    final s = ex.value?.toString() ?? '';
    if (c.text != s) {
      c.value = TextEditingValue(
        text: s,
        selection: TextSelection.collapsed(offset: s.length),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(ExposedInput ex, dynamic v) {
    ex.value = v;
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<ExposedInput>>{};
    for (final ex in widget.workflow.inputs) {
      groups.putIfAbsent(ex.group, () => []).add(ex);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          _GroupHeader(title: entry.key),
          for (final ex in entry.value) _buildInput(theme, ex),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildInput(ThemeData theme, ExposedInput ex) {
    final def = ex.def;

    if (_isSeedInput(ex)) {
      return _seedRow(theme, ex);
    }

    if (def != null && def.isEnum) {
      return _dropdown(theme, ex, def.options!);
    }

    final liveOptions = _liveOptionsFor(ex);
    if (liveOptions != null && liveOptions.isNotEmpty) {
      return _dropdown(theme, ex, liveOptions);
    }

    if (def?.type == 'BOOLEAN') {
      return _boolRow(theme, ex);
    }

    if (def != null && def.isNumber && def.min != null && def.max != null) {
      final isInt = def.type == 'INT';
      if (_useSlider(def)) {
        return _slider(theme, ex, def, isInt: isInt);
      }
      return _numberField(theme, ex, def);
    }

    if (def != null && def.isNumber) {
      return _numberField(theme, ex, def);
    }

    return _textField(theme, ex, multiline: _isLongText(ex));
  }

  bool _isSeedInput(ExposedInput ex) {
    final n = ex.inputName;
    return n == 'seed' || n == 'noise_seed';
  }

  bool _isLongText(ExposedInput ex) {
    final n = ex.inputName;
    return n == 'text' ||
        n == 'text_g' ||
        n == 'text_l' ||
        n == 't5xxl' ||
        n.contains('prompt') ||
        n.contains('description');
  }

  bool _useSlider(NodeInputDef def) {
    final min = def.min!;
    final max = def.max!;
    final range = max - min;
    if (range <= 0) return false;
    if (range > 100000) return false;
    return true;
  }

  /// For string inputs whose options come from the live registry rather
  /// than being baked into the workflow (e.g. ckpt_name, vae_name).
  List<String>? _liveOptionsFor(ExposedInput ex) {
    final node = widget.registry[ex.classType];
    if (node == null) return null;
    final input = node.input(ex.inputName);
    return input?.options;
  }

  Widget _seedRow(ThemeData theme, ExposedInput ex) {
    _syncCtrl(ex);
    return _row(
      theme,
      ex.label,
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl(ex),
              keyboardType: TextInputType.number,
              style: theme.textTheme.bodySmall,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null) {
                  ex.value = parsed;
                  widget.onChanged();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => _set(ex, _rng.nextInt(1 << 32)),
            icon: const Icon(Icons.shuffle, size: 18),
            tooltip: 'Randomize seed',
            style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(ThemeData theme, ExposedInput ex, List<String> options) {
    final current = ex.value?.toString() ?? '';
    final selectable = options.contains(current) ? current : null;
    return _row(
      theme,
      ex.label,
      DropdownButtonFormField<String>(
        key: ValueKey('${ex.key}_$current'),
        initialValue: selectable,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onChanged: (v) {
          if (v != null) _set(ex, v);
        },
        items: options
            .map((o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, style: theme.textTheme.bodySmall),
                ))
            .toList(),
      ),
    );
  }

  Widget _boolRow(ThemeData theme, ExposedInput ex) {
    final value = ex.value == true;
    return _row(
      theme,
      ex.label,
      Align(
        alignment: Alignment.centerLeft,
        child: Switch(
          value: value,
          onChanged: (v) => _set(ex, v),
        ),
      ),
    );
  }

  Widget _slider(ThemeData theme, ExposedInput ex, NodeInputDef def,
      {required bool isInt}) {
    final min = def.min!.toDouble();
    final max = def.max!.toDouble();
    final step = (def.step ?? (isInt ? 1 : 0.01)).toDouble();
    final rawValue = ex.value;
    final current = (rawValue is num)
        ? rawValue.toDouble()
        : (def.defaultValue is num
            ? (def.defaultValue as num).toDouble()
            : min);
    final clamped = current.clamp(min, max);
    final divisions = ((max - min) / step).round().clamp(1, 1000);
    final display = isInt
        ? clamped.round().toString()
        : clamped.toStringAsFixed(step < 1 ? 2 : 0);
    return _row(
      theme,
      ex.label,
      Row(
        children: [
          Expanded(
            child: Slider(
              value: clamped,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) {
                _set(ex, isInt ? v.round() : double.parse(v.toStringAsFixed(4)));
              },
            ),
          ),
          SizedBox(
            width: 64,
            child: TextFormField(
              key: ValueKey('${ex.key}_slider_$display'),
              initialValue: display,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: InputBorder.none,
              ),
              onFieldSubmitted: (v) {
                final parsed =
                    isInt ? int.tryParse(v)?.toDouble() : double.tryParse(v);
                if (parsed == null) return;
                final c = parsed.clamp(min, max);
                _set(ex, isInt ? c.round() : c);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(ThemeData theme, ExposedInput ex, NodeInputDef def) {
    final isInt = def.type == 'INT';
    _syncCtrl(ex);
    return _row(
      theme,
      ex.label,
      TextField(
        controller: _ctrl(ex),
        keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
        style: theme.textTheme.bodySmall,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) {
          final parsed = isInt ? int.tryParse(v) : double.tryParse(v);
          if (parsed != null) {
            ex.value = parsed;
            widget.onChanged();
          }
        },
      ),
    );
  }

  Widget _textField(ThemeData theme, ExposedInput ex, {bool multiline = false}) {
    _syncCtrl(ex);
    return _row(
      theme,
      ex.label,
      TextField(
        controller: _ctrl(ex),
        maxLines: multiline ? null : 1,
        minLines: multiline ? 2 : 1,
        textCapitalization: multiline
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        style: theme.textTheme.bodySmall,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) {
          ex.value = v;
          widget.onChanged();
        },
      ),
    );
  }

  Widget _row(ThemeData theme, String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
}
