import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/architecture_profile.dart';
import '../models/config_preset.dart';
import '../services/android_foreground_service.dart';
import '../services/comfyui_service.dart';
import '../widgets/dynamic_form.dart';
import '../widgets/lora_panel.dart';
import '../widgets/parameter_panel.dart';
import '../widgets/model_picker.dart';
import 'home_screen.dart';

class GenerateScreen extends StatefulWidget {
  final ComfyUIService service;

  const GenerateScreen({super.key, required this.service});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final TextEditingController _posCtrl = TextEditingController();
  final TextEditingController _negCtrl = TextEditingController();

  bool _generating = false;
  bool _cancelRequested = false;
  Uint8List? _currentImage;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPromptCtrls();
    });
  }

  void _syncPromptCtrls() {
    final state = context.read<AppState>();
    if (_posCtrl.text != state.params.positivePrompt) {
      _posCtrl.text = state.params.positivePrompt;
    }
    if (_negCtrl.text != state.params.negativePrompt) {
      _negCtrl.text = state.params.negativePrompt;
    }
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _cancelToken?.cancel();
    _posCtrl.dispose();
    _negCtrl.dispose();
    super.dispose();
  }

  AppState get _state => context.read<AppState>();

  Future<void> _generate() async {
    if (_generating) return;
    final state = _state;
    final useCustom = state.customMode && state.activeWorkflow != null;

    if (!useCustom) {
      if (state.params.positivePrompt.isEmpty) {
        _showSnack('Please enter a prompt');
        return;
      }
      if (state.params.checkpoint.isEmpty) {
        _showSnack('No model selected');
        return;
      }
      _syncPromptCtrls();
    }

    setState(() {
      _generating = true;
      _cancelRequested = false;
      _currentImage = null;
    });

    _cancelToken = CancelToken();

    try {
      final Map<String, dynamic> workflow;
      if (useCustom) {
        workflow = state.activeWorkflow!.applyValues();
        await state.persistActiveWorkflowValues();
      } else {
        final profile = ArchitectureProfile.byId(state.params.profileId);
        workflow = state.workflowBuilder.build(profile, state.params);
      }
      final promptId = await widget.service.queuePrompt(workflow);

      await AndroidForegroundService.start();

      if (!mounted || _cancelRequested) {
        _cancelRequested = false;
        if (mounted) setState(() => _generating = false);
        return;
      }

      final imageData = await _pollForResult(promptId, _cancelToken!);

      if (!mounted || _cancelRequested) {
        _cancelRequested = false;
        if (mounted) setState(() => _generating = false);
        return;
      }
      setState(() {
        _currentImage = imageData;
        _generating = false;
      });

      if (state.autoSave) {
        await state.saveConfig();
      }
      final workflowJson = const JsonEncoder.withIndent('  ').convert(workflow);
      final mobileConfig = const JsonEncoder.withIndent('  ').convert({
        'params': state.params.toJson(),
        'serverUrl': widget.service.baseUrl,
      });
      await state.galleryService.addImage(
        imageData, state.params.copy(),
        workflowJson: workflowJson,
        comfyConfig: mobileConfig,
      );
    } on ComfyUIException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showSnack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showSnack('Generation failed: $e');
    } finally {
      await AndroidForegroundService.stop();
    }
  }

  void _cancelGeneration() {
    _cancelRequested = true;
    _cancelToken?.cancel();
    setState(() => _generating = false);
    AndroidForegroundService.stop();
  }

  Future<Uint8List> _pollForResult(String promptId, CancelToken cancelToken) async {
    const maxAttempts = 300;
    const delay = Duration(seconds: 1);

    for (int i = 0; i < maxAttempts; i++) {
      if (cancelToken.isCancelled) throw ComfyUIException('Generation cancelled');
      await Future.delayed(delay);
      if (cancelToken.isCancelled || !mounted) {
        throw ComfyUIException('Generation cancelled');
      }
      final history = await widget.service.getHistory(promptId);
      if (history != null && history['status']?['completed'] == true) {
        final outputs = history['outputs'] as Map<String, dynamic>?;
        if (outputs != null) {
          dynamic outputNode;
          final node9 = outputs['9'] as Map<String, dynamic>?;
          if (node9 != null) {
            outputNode = node9;
          } else {
            for (final entry in outputs.entries) {
              final val = entry.value as Map<String, dynamic>?;
              if (val != null && val['images'] != null) {
                outputNode = val;
                break;
              }
            }
          }
          if (outputNode != null) {
            final images = outputNode['images'] as List<dynamic>?;
            if (images != null && images.isNotEmpty) {
              final img = images.first as Map<String, dynamic>;
              return widget.service.getImage(
                img['filename'] as String,
                subfolder: img['subfolder'] as String? ?? '',
                type: img['type'] as String? ?? 'output',
              );
            }
          }
        }
      }
    }
    throw ComfyUIException('Timed out waiting for generation');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<AppState>(
      builder: (context, state, _) {
        _syncPromptCtrls();
        final profile = ArchitectureProfile.byId(state.params.profileId);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Generate'),
            actions: [
              _connectionIndicator(state),
              IconButton(
                icon: const Icon(Icons.wifi_find),
                onPressed: () => _showConnectionDialog(state),
                tooltip: 'Server settings',
              ),
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: () async {
                  _posCtrl.text = state.params.positivePrompt;
                  _negCtrl.text = state.params.negativePrompt;
                  await state.saveConfig();
                  if (mounted) _showSnack('Config saved');
                },
                tooltip: 'Save config',
              ),
            ],
          ),
          body: OrientationBuilder(
            builder: (context, orientation) {
              if (orientation == Orientation.landscape) {
                return _buildLandscapeLayout(state, profile);
              }
              return _buildPortraitLayout(state, profile);
            },
          ),
        );
      },
    );
  }

  Widget _buildPortraitLayout(AppState state, ArchitectureProfile profile) {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: _buildImageArea(state),
        ),
        Expanded(
          flex: 3,
          child: _buildControls(state, profile),
        ),
        _buildActionBar(state),
      ],
    );
  }

  Widget _buildLandscapeLayout(AppState state, ArchitectureProfile profile) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildImageArea(state),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _buildControls(state, profile)),
              _buildActionBar(state),
            ],
          ),
        ),
      ],
    );
  }

  Widget _connectionIndicator(AppState state) {
    return Semantics(
      label: state.connected ? 'Connected to server' : 'Disconnected from server',
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state.connected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              state.status,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageArea(AppState state) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _currentImage != null
            ? InteractiveViewer(
                child: Center(
                  child: Image.memory(_currentImage!, fit: BoxFit.contain),
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _generating ? Icons.hourglass_bottom : Icons.image_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _generating ? 'Generating...' : 'Your image will appear here',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                    ),
                    if (_generating) ...[
                      const SizedBox(height: 16),
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildControls(AppState state, ArchitectureProfile profile) {
    final hasCustom = state.activeWorkflow != null;
    final useCustom = hasCustom && state.customMode;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasCustom) _CustomHeader(state: state),
          if (useCustom)
            DynamicForm(
              key: ValueKey('dyn_${state.activeWorkflowId}'),
              workflow: state.activeWorkflow!,
              registry: widget.service.registry,
              onChanged: state.notifyActiveWorkflowChanged,
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _posCtrl,
                maxLines: null,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Enter your prompt...',
                  labelText: 'Positive Prompt',
                ),
                onChanged: (v) => state.params.positivePrompt = v,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _negCtrl,
                maxLines: null,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Things to avoid...',
                  labelText: 'Negative Prompt',
                ),
                onChanged: (v) => state.params.negativePrompt = v,
              ),
            ),
            _PresetSelector(state: state),
            ParameterPanel(
              params: state.params,
              onChanged: (updated) => state.updateParams(updated),
              profile: profile,
              registry: widget.service.registry,
              availableModels: state.availableModels,
              availableClipModels: state.availableClipModels,
              availableVaeModels: state.availableVaeModels,
              onPickModel: () => _showModelPicker(state, 'model'),
              onPickClip: profile.clipLoader != null
                  ? () => _showModelPicker(state, 'clip')
                  : null,
              onPickVae: profile.vaeLoader != null
                  ? () => _showModelPicker(state, 'vae')
                  : null,
            ),
            LoraPanel(
              params: state.params,
              availableLoras: state.availableLoras,
              onChanged: (updated) => state.updateParams(updated),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _showModelPicker(AppState state, String type) async {
    final List<String> models;
    final String current;
    final String title;
    switch (type) {
      case 'clip':
        models = state.availableClipModels;
        current = state.params.clipModel;
        title = 'Select CLIP Model';
      case 'vae':
        models = state.availableVaeModels;
        current = state.params.vaeModel;
        title = 'Select VAE Model';
      default:
        models = state.availableModels;
        current = state.params.checkpoint;
        title = 'Select Model';
    }
    if (models.isEmpty) {
      _showSnack('No models available on server');
      return;
    }
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ModelPickerScreen(
          models: models,
          selected: current,
          title: title,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final updated = state.params.copy();
    switch (type) {
      case 'clip':
        updated.clipModel = result;
      case 'vae':
        updated.vaeModel = result;
      default:
        updated.checkpoint = result;
        final detected = ArchitectureProfile.detect(result);
        if (detected != null) {
          updated.profileId = detected.id;
        }
    }
    state.updateParams(updated);
  }

  Widget _buildActionBar(AppState state) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5))
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _generating ? 'Generating...' : 'Generate',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_generating) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _cancelGeneration,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
                minimumSize: const Size(52, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Icon(Icons.close),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showConnectionDialog(AppState state) async {
    final controller = TextEditingController(text: widget.service.baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server Connection'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ComfyUI URL',
            hintText: 'http://192.168.1.100:8188',
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Connect')),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty) {
      widget.service.updateBaseUrl(result);
      await state.configService.saveServerUrl(result);
      await state.checkConnection();
    }
  }
}

class _PresetSelector extends StatefulWidget {
  final AppState state;
  const _PresetSelector({required this.state});

  @override
  State<_PresetSelector> createState() => _PresetSelectorState();
}

class _PresetSelectorState extends State<_PresetSelector> {
  List<ConfigPreset> _presets = [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final presets = await widget.state.loadPresets();
    if (mounted) setState(() => _presets = presets);
  }

  Future<void> _saveCurrent() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Preset'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Preset name',
            hintText: 'e.g. My style',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await widget.state.savePreset(name);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preset "$name" saved')),
        );
      }
    }
  }

  Future<void> _applyPreset(ConfigPreset preset) async {
    await widget.state.applyPreset(preset);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "${preset.name}" applied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.bookmark_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: null,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                hintText: 'Load preset...',
              ),
              onChanged: (v) {
                if (v != null) {
                  final preset = _presets.firstWhere((p) => p.id == v);
                  _applyPreset(preset);
                }
              },
              items: _presets
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, style: theme.textTheme.bodySmall),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 20),
            tooltip: 'Save current as preset',
            onPressed: _saveCurrent,
            style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh presets',
            onPressed: _load,
            style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
          ),
        ],
      ),
    );
  }
}

class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class _CustomHeader extends StatelessWidget {
  final AppState state;
  const _CustomHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = state.activeSavedWorkflow;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Profile'),
                icon: Icon(Icons.tune, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text('Custom'),
                icon: Icon(Icons.account_tree_outlined, size: 16),
              ),
            ],
            selected: {state.customMode},
            onSelectionChanged: (s) => state.setCustomMode(s.first),
            style: SegmentedButton.styleFrom(
              textStyle: theme.textTheme.bodySmall,
            ),
          ),
          if (state.customMode && saved != null) ...[
            const SizedBox(height: 6),
            Text(
              'Active: ${saved.name}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
