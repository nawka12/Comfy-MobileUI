import 'package:flutter/material.dart';

class ModelPickerScreen extends StatefulWidget {
  final List<String> models;
  final String selected;
  final String title;

  const ModelPickerScreen({
    super.key,
    required this.models,
    required this.selected,
    this.title = 'Select Model',
  });

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  String _search = '';

  List<String> get _filtered {
    var list = widget.models;
    if (_search.isNotEmpty) {
      list = list
          .where((c) => c.toLowerCase().contains(_search.toLowerCase()))
          .toList();
    }
    return list;
  }

  void _select(String model) {
    Navigator.of(context).pop(model);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search models...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _search = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _search = v),
              autofocus: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${filtered.length} of ${widget.models.length} models',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: widget.models.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text('No models available',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                        const SizedBox(height: 8),
                        Text('Add models to your ComfyUI server',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            )),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Go back'),
                        ),
                      ],
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('No models match your search',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final model = filtered[index];
                          final isSelected = model == widget.selected;
                          return Card(
                            margin:
                                const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            child: ListTile(
                              selected: isSelected,
                              selectedTileColor:
                                  theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.3),
                              leading: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                size: 22,
                              ),
                              title: Text(
                                model.split('/').last.split('.').first,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight:
                                      isSelected ? FontWeight.w600 : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                model,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onTap: () => _select(model),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
