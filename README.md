# Comfy Mobile UI

A Flutter-based mobile/desktop frontend for [ComfyUI](https://github.com/comfyanonymous/ComfyUI). Connect to a running ComfyUI instance, generate images, browse your gallery, and persist/share configurations — all from a touch-friendly interface.

## Features

### Three-Tab Interface

| Tab | Description |
|-----|-------------|
| **Generate** | Prompt input, model selection, parameter tuning, and image generation |
| **Gallery** | Browse previously generated images with full metadata overlay |
| **Settings** | Server configuration, config export/import, connection management |

### Architecture Support

| Architecture | Workflow |
|--------------|----------|
| **SDXL** | `CheckpointLoaderSimple` → `CLIPTextEncodeSDXL` → `KSampler` |
| **Anima (CircleStone Labs)** | `UNETLoader` + `CLIPLoader` + `VAELoader` → `CLIPTextEncode` → `KSampler` |
| **Standard** | `CheckpointLoaderSimple` → `CLIPTextEncode` → `KSampler` |

- Architecture auto-detected from model name patterns (`xl`, `sdxl`, `anima`, etc.)
- Dedicated model picker with per-architecture filtering
- Samplers and schedulers fetched dynamically from the ComfyUI instance

### Config Persistence & Sharing

- Auto-saves settings (prompts, model, parameters) to local storage
- **Export**: copies full config JSON (server URL + all settings) to clipboard
- **Import**: paste a config JSON to restore settings on any device
- Saved on Generate, and explicitly via the Save button

### Gallery

- Images saved locally with full generation metadata
- Grid view with tap-to-expand and long-press-to-delete
- Metadata chips: model, architecture, steps, CFG, sampler, seed, prompt preview

## Getting Started

### Prerequisites

- Flutter SDK `^3.10.8`
- A running ComfyUI instance (local or remote)

### Installation

```bash
git clone <repo-url> comfy_mobileui
cd comfy_mobileui
flutter pub get
```

### Usage

```bash
flutter run
```

1. Launch the app — it defaults to `http://localhost:8188`
2. Tap the **wifi icon** in the Generate tab to set your ComfyUI server URL
3. Select a model via the Model picker (models are fetched live from the server)
4. Enter a prompt, adjust settings, tap **Generate**
5. View results in the **Gallery** tab

### Building for Release

```bash
flutter build apk        # Android
flutter build ios        # iOS
flutter build linux      # Linux
flutter build windows    # Windows
flutter build macos      # macOS
```

## Project Structure

```
lib/
├── main.dart                     # App entry point
├── models/
│   └── workflow.dart             # GenerationSettings, AppConfig, GalleryItem, ArchitectureType
├── screens/
│   ├── home_screen.dart          # Tab controller + global AppState (ChangeNotifier)
│   ├── generate_screen.dart      # Prompt input, generation, auto-save to gallery
│   ├── gallery_screen.dart       # Image grid, fullscreen viewer, metadata
│   └── settings_screen.dart      # Server URL, config export/import
├── services/
│   ├── comfyui_service.dart      # ComfyUI HTTP API client
│   ├── config_service.dart       # SharedPreferences persistence + clipboard export
│   └── gallery_service.dart      # Local file storage + gallery index
└── widgets/
    ├── settings_panel.dart       # Collapsible parameter panel with architecture-specific fields
    └── model_picker.dart         # Searchable model list with architecture badges
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter/material.dart` | UI framework |
| `provider` | State management (ChangeNotifierProvider) |
| `http` | ComfyUI API client |
| `shared_preferences` | Config persistence |
| `path_provider` | App documents directory for gallery storage |
| `uuid` | Unique IDs for gallery items and client identification |

## Environment

- Dart SDK: `^3.10.8`
- License: [MIT](LICENSE)

## Notes

- The app queries ComfyUI's `/object_info` endpoints to dynamically discover available models, samplers, and schedulers
- For Anima architecture, models are loaded via separate `UNETLoader`, `CLIPLoader`, and `VAELoader` nodes instead of a combined `CheckpointLoaderSimple`
- Config is stored as JSON in `SharedPreferences` — easily shareable across devices
