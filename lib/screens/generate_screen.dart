import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/architecture_profile.dart';
import '../models/backend_mode.dart';
import '../models/config_preset.dart';
import '../services/android_foreground_service.dart';
import '../services/comfyui_service.dart';
import '../services/tams_service.dart' show TamsCreditsException, TamsException, TamsService;
import '../widgets/dynamic_form.dart';
import '../widgets/lora_panel.dart';
import '../widgets/parameter_panel.dart';
import '../widgets/model_picker.dart';
import 'home_screen.dart';

class GenerateScreen extends StatefulWidget {
  final ComfyUIService service;
  final TamsService tamsService;

  const GenerateScreen({super.key, required this.service, required this.tamsService});

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
  List<Uint8List> _currentImages = [];
  CancelToken? _cancelToken;
  Timer? _queuePollTimer;
  int _queueRunning = 0;
  int _queueRemaining = 0;
  int? _lastUsedSeed;

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

  String _progressText() {
    final parts = <String>['Generating'];
    if (_queueRunning > 0) parts.add('· step $_queueRunning');
    if (_queueRemaining > 0) parts.add('· $_queueRemaining queued');
    return '${parts.join(' ')}...';
  }

  Future<void> _generate() async {
    if (_generating) return;
    final state = _state;
    final useCustom = state.customMode && state.activeWorkflow != null;
    final isTams = state.backendMode == BackendMode.tams;

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

    if (state.params.seed == -1) {
      state.params.randomizeSeed();
    }
    _lastUsedSeed = state.params.seed;

    setState(() {
      _generating = true;
      _cancelRequested = false;
      _currentImages = [];
    });

    _cancelToken = CancelToken();
    _startQueuePolling();

    try {
      final Map<String, dynamic> workflow;
      if (useCustom) {
        workflow = state.activeWorkflow!.applyValues();
        await state.persistActiveWorkflowValues();
      } else {
        final profile = ArchitectureProfile.byId(state.params.profileId);
        workflow = state.workflowBuilder.build(profile, state.params);
      }

      await AndroidForegroundService.start();

      if (!mounted || _cancelRequested) {
        _cancelRequested = false;
        if (mounted) setState(() => _generating = false);
        return;
      }

      final List<Uint8List> imageList;
      if (isTams) {
        final tamsBody = state.workflowBuilder.toTamsFormat(workflow);
        final single = await _tamsGenerate(tamsBody, _cancelToken!);
        imageList = [single];
      } else {
        final promptId = await widget.service.queuePrompt(workflow);
        imageList = await _pollForResult(promptId, _cancelToken!);
      }

      if (!mounted || _cancelRequested) {
        _cancelRequested = false;
        if (mounted) setState(() => _generating = false);
        return;
      }
      setState(() {
        _currentImages = imageList;
        _generating = false;
      });

      if (state.autoSave) {
        await state.saveConfig();
      }
      final workflowJson = const JsonEncoder.withIndent('  ').convert(workflow);
      final mobileConfig = const JsonEncoder.withIndent('  ').convert({
        'params': state.params.toJson(),
        'serverUrl': state.currentBackendUrl,
      });
      for (final imageData in imageList) {
        await state.galleryService.addImage(
          imageData, state.params.copy(),
          workflowJson: workflowJson,
          comfyConfig: mobileConfig,
        );
      }
      HapticFeedback.mediumImpact();
    } on ComfyUIException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      HapticFeedback.heavyImpact();
      _showSnack(e.message);
    } on TamsCreditsException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      HapticFeedback.heavyImpact();
      _showCreditsError(e.message);
    } on TamsException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      HapticFeedback.heavyImpact();
      _showSnack('TAMS error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      HapticFeedback.heavyImpact();
      _showSnack('Generation failed: $e');
    } finally {
      _stopQueuePolling();
      await AndroidForegroundService.stop();
    }
  }

  Future<Uint8List> _tamsGenerate(Map<String, dynamic> tamsBody, CancelToken cancelToken) async {
    final resp = await widget.tamsService.createWorkflowJob(
      const Uuid().v4(),
      tamsBody['params'] as Map<String, dynamic>,
    );
    final jobId = resp.id;

    const maxAttempts = 300;
    const delay = Duration(seconds: 2);

    for (int i = 0; i < maxAttempts; i++) {
      if (cancelToken.isCancelled) throw ComfyUIException('Generation cancelled');
      await Future.delayed(delay);
      if (cancelToken.isCancelled || !mounted) {
        throw ComfyUIException('Generation cancelled');
      }

      final status = await widget.tamsService.getJobStatus(jobId);
      if (status.isComplete) {
        if (status.isSuccess && status.successInfo != null) {
          if (status.successInfo!.images.isNotEmpty) {
            return widget.tamsService.downloadImage(status.successInfo!.images.first.url);
          }
          throw ComfyUIException('No images in TAMS response');
        }
        final reason = status.failedInfo?.reason ?? 'Unknown error';
        throw ComfyUIException('TAMS job failed: $reason');
      }
    }
    throw ComfyUIException('TAMS job timed out');
  }

  void _cancelGeneration() {
    _cancelRequested = true;
    _cancelToken?.cancel();
    _stopQueuePolling();
    if (_state.backendMode == BackendMode.local) {
      widget.service.interrupt().catchError((_) {});
    }
    setState(() => _generating = false);
    AndroidForegroundService.stop();
  }

  void _startQueuePolling() {
    _queuePollTimer?.cancel();
    _queuePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      try {
        if (_state.backendMode == BackendMode.tams) return;
        final queue = await widget.service.getQueue();
        if (!mounted) return;
        final running = (queue['queue_running'] as List<dynamic>?)?.length ?? 0;
        final remaining = (queue['queue_remaining'] as List<dynamic>?)?.length ?? 0;
        setState(() {
          _queueRunning = running;
          _queueRemaining = remaining;
        });
      } catch (_) {}
    });
  }

  void _stopQueuePolling() {
    _queuePollTimer?.cancel();
    _queuePollTimer = null;
    _queueRunning = 0;
    _queueRemaining = 0;
  }

  Future<void> _showQueueDialog() async {
    Map<String, dynamic>? queueData;
    try {
      queueData = await widget.service.getQueue();
    } catch (_) {}
    if (!mounted) return;
    final running = (queueData?['queue_running'] as List<dynamic>?) ?? [];
    final remaining = (queueData?['queue_remaining'] as List<dynamic>?) ?? [];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generation Queue'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Running: ${running.length}', style: Theme.of(ctx).textTheme.bodyMedium),
              if (running.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${running.length} prompt(s) in progress', style: Theme.of(ctx).textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              Text('Queued: ${remaining.length}', style: Theme.of(ctx).textTheme.bodyMedium),
              if (remaining.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${remaining.length} prompt(s) waiting', style: Theme.of(ctx).textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await widget.service.interrupt();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showSnack('Generation interrupted');
                      } catch (e) {
                        if (mounted) _showSnack('Failed to interrupt: $e');
                      }
                    },
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Interrupt'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<List<Uint8List>> _pollForResult(String promptId, CancelToken cancelToken) async {
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
              final results = <Uint8List>[];
              for (final img in images) {
                final data = img as Map<String, dynamic>;
                final bytes = await widget.service.getImage(
                  data['filename'] as String,
                  subfolder: data['subfolder'] as String? ?? '',
                  type: data['type'] as String? ?? 'output',
                );
                results.add(bytes);
              }
              return results;
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

  Future<void> _showCreditsError(String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.monetization_on_outlined, size: 24),
            SizedBox(width: 8),
            Text('Insufficient Credits'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your TAMS account does not have enough credits for this job.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '1 credit = \$0.003 USD',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Visit the TAMS console to top up:',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              'https://tams.tensor.art/app',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.primary,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
              if (state.backendMode == BackendMode.local)
                IconButton(
                  icon: const Icon(Icons.list_alt),
                  onPressed: _showQueueDialog,
                  tooltip: 'Generation queue',
                ),
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
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _currentImages.isNotEmpty
            ? _currentImages.length == 1
                ? InteractiveViewer(
                    child: Center(
                      child: Image.memory(_currentImages.first, fit: BoxFit.contain),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(4),
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    children: _currentImages.map((bytes) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      );
                    }).toList(),
                  )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _generating ? Icons.hourglass_bottom : Icons.image_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _generating ? _progressText() : 'Your image will appear here',
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
              isTams: state.backendMode == BackendMode.tams,
              lastSeed: _lastUsedSeed,
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
    final isTams = state.backendMode == BackendMode.tams;
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

    if (isTams) {
      final controller = TextEditingController(text: current);
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Model ID',
                  hintText: 'Enter model ID from tensor.art',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Text(
                'TAMS model IDs are found on tensor.art/model pages.\n'
                'The numeric ID is in the URL.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(96, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Set'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (result != null && result.isNotEmpty && mounted) {
        final updated = state.params.copy();
        switch (type) {
          case 'clip':
            updated.clipModel = result;
          case 'vae':
            updated.vaeModel = result;
          default:
            updated.checkpoint = result;
        }
        state.updateParams(updated);
      }
      return;
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
            Semantics(
              label: 'Cancel generation',
              button: true,
              child: OutlinedButton(
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
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showConnectionDialog(AppState state) async {
    final controller = TextEditingController(
      text: state.backendMode == BackendMode.tams
          ? widget.tamsService.baseUrl
          : widget.service.baseUrl,
    );
    final label = state.backendMode == BackendMode.tams ? 'TAMS URL' : 'ComfyUI URL';
    final hint = state.backendMode == BackendMode.tams
        ? 'https://ap-east-1.tensorart.cloud/v1'
        : 'http://192.168.1.100:8188';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server Connection'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
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
      if (state.backendMode == BackendMode.tams) {
        widget.tamsService.updateBaseUrl(result);
        await state.configService.saveTamsBaseUrl(result);
      } else {
        widget.service.updateBaseUrl(result);
        await state.configService.saveServerUrl(result);
      }
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
