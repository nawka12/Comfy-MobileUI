# Bugs & Issues

All 17 items from the original bug list have been fixed in the current codebase.
This file now tracks remaining and newly discovered issues.

## Medium

1. **No per-step generation progress** (`lib/screens/generate_screen.dart:74-79`)
   - `_progressText()` shows "Generating" with running/queued counts from `/queue`, but does not display actual step progress (e.g. "step 5/30") or ETA. The `/queue` endpoint provides step-level data but it is not rendered.
   - *Previously bug #13, partially addressed.*

2. **`_queuePollTimer` not cancelled on dispose** (`lib/screens/generate_screen.dart:236-251`, `lib/screens/generate_screen.dart:64-70`)
   - `_queuePollTimer` (a `Timer.periodic`) is created in `_startQueuePolling()` and cancelled in `_stopQueuePolling()`. However, `dispose()` does not call `_stopQueuePolling()` — it only sets `_cancelRequested = true` and cancels `_cancelToken`. If the widget is disposed mid-generation, the timer keeps firing until it checks `mounted` (which prevents a crash but leaks the timer handle).

3. **Hidden gallery images not cleaned up on password clear** (`lib/screens/settings_screen.dart:429-460`)
   - `_clearHiddenLibrary()` calls `galleryService.deleteAllHidden()` then `configService.clearHiddenPassword()`. The image files on disk are deleted, but if `deleteAllHidden` throws mid-iteration, the password is still cleared — leaving stale index entries with missing files.

## Low

4. **Queue polling persists briefly after generation completes** (`lib/screens/generate_screen.dart:188-189`)
   - `_stopQueuePolling()` is called in the `finally` block of `_generate()`. Due to async timing, 1-2 extra poll cycles may fire after the generation result is displayed. Harmless but wasteful.

5. **`_syncPromptCtrls` is one-directional** (`lib/screens/generate_screen.dart:53-61`)
   - Syncs from `state.params` into the text controllers on every build. If the user types in a field and the widget rebuilds *before* the `onChanged` handler fires, the controller text overwrites the user's input. Mitigated by the fact that most rebuilds are triggered by the user's own changes.
