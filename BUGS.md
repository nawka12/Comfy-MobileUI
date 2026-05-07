# Bugs & Issues

## Critical

1. **Gallery does not refresh after generation** (`lib/screens/gallery_screen.dart:64`, `lib/services/gallery_service.dart:9`)
   - `GalleryService` is not a `ChangeNotifier`. After `GenerateScreen` calls `addImage()`, the Gallery tab reads a stale snapshot of `items`. Only manual pull-to-refresh triggers a rebuild.

2. **Seed TextField controller is recreated every build** (`lib/widgets/settings_panel.dart:345`)
   - `_buildSeedRow()` creates a new `TextEditingController` every build but never disposes it. Causes memory leak and discards user input when the widget rebuilds. Also only commits on `onSubmitted` (Enter key), not on blur.

3. **Dimension controllers out of sync with external settings** (`lib/widgets/settings_panel.dart:42-53`)
   - `_dimCtrls` are initialized once in `initState` but never updated when settings change externally (e.g. config import, preset selection). Displays stale values.

4. **Dead code in GalleryScreen.initState** (`lib/screens/gallery_screen.dart:21-23`)
   - `context.read<AppState>().galleryService;` reads the service but does nothing. Leftover from incomplete initialization.

5. **"Auto-save on Generate" switch is a placebo** (`lib/screens/settings_screen.dart:78-83`)
   - `value` is hardcoded to `true` and `onChanged` is a no-op `(_) {}`. Cannot be toggled and never used by the generate flow.

6. **Race condition in parallel model loading** (`lib/screens/home_screen.dart:129-134`)
   - `Future.wait` runs `loadCheckpoints()` and `loadAnimaModels()` concurrently. Both independently set `settings.checkpoint` to the first available model if empty. Whichever finishes last overwrites the other — a UNET model may overwrite a checkpoint or vice versa.

## Medium

7. **ComfyUIService http.Client never disposed** (`lib/services/comfyui_service.dart:14`, `lib/services/comfyui_service.dart:199-201`)
   - `dispose()` is defined on the service but never called from `AppState` or `HomeScreen`. Resource leak.

8. **Polling loop is not cancellable** (`lib/screens/generate_screen.dart:93-118`)
   - `_pollForResult()` uses `Future.delayed` in a for-loop for up to 300 iterations (5 minutes). No cancellation mechanism — continues even if the user navigates away.

9. **Prompt text controllers can desync from settings** (`lib/screens/generate_screen.dart:28-34`, `lib/screens/generate_screen.dart:247`)
   - `_posCtrl` / `_negCtrl` are populated only in `initState`. If settings are imported or changed externally (config import), the text fields do not update.

10. **Gallery thumbnail loading failure shows infinite spinner** (`lib/screens/gallery_screen.dart:162-165`, `lib/screens/gallery_screen.dart:176-178`)
    - If `loadImageBytes` returns null (file missing), `_bytes` stays null permanently, showing an infinite `CircularProgressIndicator`.

11. **`getCheckpointsForArchitecture` defined but never called** (`lib/screens/home_screen.dart:197-217`)
    - This method filters checkpoints by architecture but is never used. The `ModelPickerScreen` has its own `_guessArchitecture` but does not filter.

12. **Anima CLIP/VAE auto-name derivation is fragile** (`lib/models/workflow.dart:197-203`)
    - When `clipModel` or `vaeModel` are empty, names are derived from the checkpoint by stripping extension and appending `_clip.safetensors` / `_vae.safetensors`. Does not handle non-.safetensors extensions or unconventional naming.

13. **No generation progress feedback** (`lib/screens/generate_screen.dart:93-118`)
    - Only shows "Generating..." with no queue position, ETA, or progress indication despite ComfyUI's `/queue` endpoint providing this data.

## Low

14. **Redundant theme/darkTheme configuration** (`lib/main.dart:18-27`)
    - Both `theme` and `darkTheme` are set to identical `Brightness.dark` with `themeMode: ThemeMode.dark`. Light theme is never available.

15. **Web index.html has generic title** (`web/index.html:32`)
    - `<title>` is `comfy_mobileui` (snake_case package name) instead of a user-friendly name.

16. **Web PWA manifest has scaffold description** (`web/manifest.json:8`)
    - `description` is `"A new Flutter project."` — default Flutter template was never updated.

17. **`_randomSeed` uses epoch ms not crypto RNG** (`lib/models/workflow.dart:66`)
    - `DateTime.now().millisecondsSinceEpoch % (1 << 32)` — rapid successive calls produce identical seeds. Should use `Random().nextInt(1 << 32)`.
