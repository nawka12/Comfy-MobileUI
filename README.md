# Comfy Mobile UI

A Flutter-based mobile/desktop frontend for [ComfyUI](https://github.com/comfyanonymous/ComfyUI). Connect to a running ComfyUI instance, generate images with multiple model architectures, import custom workflows, and manage a local gallery — all from a touch-friendly interface.

## Features

### Four-Tab Interface

| Tab | Description |
|-----|-------------|
| **Generate** | Prompt input, model/LoRA selection, parameter tuning, preset switcher, image generation with progress and queue management |
| **Workflows** | Import and manage custom ComfyUI API-format workflows |
| **Gallery** | Browse, search, filter, and sort generated images; multi-select for batch operations |
| **Settings** | Backend mode, server config, config export/import as `.json`, presets, privacy controls |

Focused inputs unfocus automatically when you change tabs (swipe or tap), so the keyboard never lingers across screens.

### Backends

Two backends, switchable from **Settings → Backend**:

- **Local** — talks to a self-hosted ComfyUI instance over HTTP. Full feature set (any architecture, custom workflows, LoRAs, queue management and interrupt support).
- **TAMS Cloud** — TensorArt's hosted workflow API. Bearer-token auth, job-poll based, locked to the SDXL profile.

### Architecture Profiles

Five built-in profiles, auto-detected from the model filename:

| Profile | Detected by | Pipeline |
|---------|-------------|----------|
| **Standard** | (default fallback) | `CheckpointLoaderSimple` → `CLIPTextEncode` → `KSampler` |
| **SDXL** | `xl`, `sdxl`, `sd_xl` | `CheckpointLoaderSimple` → `CLIPTextEncodeSDXL` (with target/crop dims) → `KSampler` |
| **Anima** | `anima`, `circle` | `UNETLoader` + `CLIPLoader` + `VAELoader` → `CLIPTextEncode` → `KSampler` |
| **Flux** | `flux`, `schnell` | `UNETLoader` + `CLIPLoader` → `CLIPTextEncodeFlux` → `FluxGuidance` → `KSampler` |
| **SD3** | `sd3`, `sd3.5`, `sd_3` | `CheckpointLoaderSimple` → `CLIPTextEncodeSD3` → `ModelSamplingSD3` → `KSampler` |

Each profile declares its own loader nodes, text encoder, latent source, and any extra params (e.g. SDXL target/crop dimensions, Flux guidance, SD3 shift) as data — adding a new architecture is a single entry in `ArchitectureProfile.all`.

### Custom Workflow Import

- Load any ComfyUI **API-format** JSON workflow from a file
- Editor-format JSONs (with `nodes` + `links`) are rejected with a clear error
- Editable inputs are extracted into a dynamic form; values persist per-workflow
- Switch between built-in profiles and custom workflows from the Generate tab

### LoRA Support

- Multiple LoRAs can be stacked with individual model and CLIP weights
- Model list pulled live from the server's `LoraLoader` node options

### Config Persistence & Sharing

- **Auto-save**: optional toggle saves params on every generate
- **Save**: explicit save button persists current state
- **Presets**: save multiple named configurations and switch between them inline on the Generate tab
- **Export / Import**: full config (server URL + params) round-trips as a `.json` file via the system file picker

### Gallery

- Images saved locally with full generation metadata (model, architecture, steps, CFG, sampler, seed, prompt)
- **Search, filter, and sort**: find images by prompt text, model, or architecture profile; sort newest or oldest first
- **Multi-select mode**: long-press to enter selection mode, then batch delete or batch move to hidden library
- **Send to Generate**: tap an image and load its full generation params back into the Generate tab
- **PNG metadata embedded**: workflow JSON is written into the saved PNG and can be re-read later
- Grid view with tap-to-expand fullscreen, swipe to step through neighboring images, share to OS

### Generation

- **Queue progress**: during generation the app polls ComfyUI's queue and shows running prompt count and remaining queue length
- **Queue management**: view running and queued prompts, interrupt the current generation from the Generate tab
- **Batch results**: when batch size > 1, all generated images are displayed in a grid and saved to the gallery
- **Recycle seed**: after generation, the last used seed is remembered — one tap to reuse it or hit shuffle for a random seed on next generate
- **Server interrupt**: the cancel button sends `POST /interrupt` to ComfyUI, not just stops local polling

### Privacy

- **Hidden Library**: password-protected secondary gallery (PBKDF2-style salted hash, no plaintext storage)
- **Secure Window** (Android): enables `FLAG_SECURE` — blurs the app preview in the recents switcher and blocks screenshots
- **Background generation** (Android): a foreground service keeps the HTTP polling alive while the app is backgrounded

### Theming

- Material 3 with light, dark, and system theme modes
- Indigo primary color, rounded surfaces, navigation bar with PageView swiping between tabs

## Getting Started

### Prerequisites

- Flutter SDK `^3.10.8` (project pins `3.41.9` via FVM in `.fvmrc`)
- A running ComfyUI instance (local or remote, reachable from the device)

### Installation

```bash
git clone https://github.com/nawka12/Comfy-MobileUI.git
cd Comfy-MobileUI
flutter pub get
```

If you use [FVM](https://fvm.app):

```bash
fvm install
fvm flutter pub get
```

### Usage

```bash
flutter run
```

1. Launch the app — it defaults to Local backend at `http://localhost:8188`
2. Open **Settings → Backend** to pick **Local** (ComfyUI) or **TAMS Cloud** (TensorArt); for TAMS, paste your bearer token under **API Token**
3. Open **Settings → Server** to point at your ComfyUI instance (Local mode only)
4. The Generate tab auto-detects the architecture from the selected model (TAMS is locked to SDXL)
5. Enter a prompt, adjust parameters (or load a preset / custom workflow), tap **Generate**
6. View results in the **Gallery** tab — tap to expand, swipe to flip between images, long-press for actions

### Building for Release

```bash
flutter build apk --release    # Android
flutter build ios              # iOS
flutter build linux            # Linux
flutter build windows          # Windows
flutter build macos            # macOS
flutter build web              # Web (PWA)
```

For signed Android release builds, configure `android/key.properties` with your keystore details (gitignored by default).

## Project Structure

```
lib/
├── main.dart                            # App entry, Material 3 theme (light/dark/system)
├── models/
│   ├── architecture_profile.dart        # Profile definitions + detection (Standard, SDXL, Anima, Flux, SD3)
│   ├── backend_mode.dart                # Local vs. TAMS Cloud selector
│   ├── config_preset.dart               # Named preset (params + server URL)
│   ├── dynamic_workflow.dart            # Parsed custom workflow w/ editable inputs
│   ├── generation_params.dart           # Prompt, dims, sampler, profile-specific extras, LoRA list
│   ├── lora_config.dart                 # LoRA entry (model, weights)
│   ├── nodes.dart                       # ComfyUI node-type registry helpers
│   ├── saved_workflow.dart              # Persisted user-imported workflow
│   └── workflow.dart                    # AppConfig (export/import payload)
├── screens/
│   ├── home_screen.dart                 # 4-tab shell + AppState (ChangeNotifier), tab navigation
│   ├── generate_screen.dart             # Prompt, generation, progress tracking, queue management, foreground-service hookup
│   ├── workflows_screen.dart            # Custom workflow list, file picker, validation
│   ├── gallery_screen.dart              # Grid with search/filter/sort, multi-select, fullscreen viewer, share
│   ├── hidden_gallery_screen.dart       # Password-gated secondary gallery
│   └── settings_screen.dart             # Server, config, presets, privacy, about
├── services/
│   ├── comfyui_service.dart             # HTTP client, /object_info registry, queue/interrupt support
│   ├── tams_service.dart                # TensorArt cloud client (bearer auth, job polling)
│   ├── config_service.dart              # SharedPreferences, presets, hidden-library password hash
│   ├── gallery_service.dart             # Local file storage, main + hidden indices, share to OS
│   ├── workflow_builder.dart            # Builds API-format workflow from profile + params
│   ├── png_metadata.dart                # Read/write tEXt chunks (workflow JSON in PNG)
│   ├── android_foreground_service.dart  # Keeps generation alive when backgrounded
│   └── secure_window_service.dart       # Android FLAG_SECURE toggle
└── widgets/
    ├── parameter_panel.dart             # Profile-aware parameter form
    ├── dynamic_form.dart                # Editable-input form for imported workflows
    ├── lora_panel.dart                  # LoRA stack editor
    └── model_picker.dart                # Searchable model list with architecture badges
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter/material.dart` | UI framework (Material 3) |
| `provider` | State management (ChangeNotifierProvider) |
| `http` | ComfyUI REST client |
| `cupertino_icons` | iOS-style icons |
| `shared_preferences` | Config and preset persistence |
| `path_provider` | App documents directory for gallery storage |
| `file_picker` | Workflow / config `.json` import & export |
| `crypto` | Salted password hashing for hidden library |
| `uuid` | IDs for gallery items, presets, workflows, client |

## How the Workflow Builder Works

The architecture-profile system is data-driven: each profile declares its loader nodes, text encoder, latent source, and any architecture-specific parameters (`extraParams`) and nodes (`extraNodes`) — for example, Flux's `FluxGuidance` chain or SD3's `ModelSamplingSD3` shift parameter.

`WorkflowBuilder` walks the active profile, materializes a node graph, applies the user's `GenerationParams` (and any LoRA stack), and emits an API-format JSON that `ComfyUIService.queuePrompt` posts to `/prompt`.

For imported workflows, `DynamicWorkflow.parse` scans the user-supplied API JSON for editable inputs (string/int/float/bool primitives), builds a form, and re-injects edited values at submit time.

## Notes

- The app polls ComfyUI's `/history` and `/queue` endpoints for generation results and progress — no WebSocket dependency
- Anima-style split loaders auto-derive sibling CLIP/VAE filenames (`<base>_clip.safetensors`, `<base>_vae.safetensors`) when fields are blank
- Generated PNGs include the workflow JSON in a tEXt chunk — drag a generated image back into the ComfyUI editor to recover the workflow
- Presets and saved workflows are stored as JSON in `SharedPreferences` and travel with config exports

## License

[MIT](LICENSE) © 2026 nawka12
