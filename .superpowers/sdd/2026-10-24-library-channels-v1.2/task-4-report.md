# Task 4 implementation report

## Delivered

- Shared MiniPlayer remains in existing HomeShell Column above navigation; no extra instances and no expansion to secondary pages.
- Empty local history reserves row and offers 去发现. Local recentBooks provides metadata preview without play/open/resolve; active session (including failure/loading state) has priority.
- Cover/title opens PlayerPage(preview:) silently. Explicit preview play uses resumeShelf (music starts first part; long content resumes checkpoint), current-session control uses togglePlay. Matching record deletion immediately recomputes preview.
- Removed cover play overlay. Disc rotates only while loaded, playing, not loading/buffering/error, with reduced-motion settings honored. Current position uses positionTick; preview position comes only from local record.
- Error retry remains actionable; buffering/loading uses existing in-place progress control. No BookPlayer/core playback changes required.

## Test evidence

- Red: newly written persistent_mini_player_test.dart initially failed empty row and cold preview (0 widgets instead of expected content); existing current-session case passed.
- Green: `flutter test --no-pub test/persistent_mini_player_test.dart test/player_ux_test.dart` final run **12 passed** (5 focused mini cases plus 7 existing player UX). Includes silent opening/explicit play, empty row, current priority/toggle, clearing preview, real rotation freeze/reduced motion. Existing removal fixture now explicitly has lastListenedAt because the scenario describes an actually heard checkpoint.
- `flutter analyze --no-pub`: final rerun **No issues found** (7.0s).
- Full `flutter test test --no-pub`: **365 passed, 1 skipped, 10 failed**. Not claimed as passed. Log `/tmp/blisten-task4-full-host.log`.
  - api_facade_ui_test: real discovery facade keeps partial results and visibly retries.
  - ux_feedback_test: API failure retry expectation; narrow large-text import old mode lookup.
  - task5_ux_regression_test: three recent resume routing/duplicate/error cases (legacy history fixtures).
  - up_home_mode_test: dark/light narrow layout old 儿童 label.
  - theme_accessibility_test: dark/light My recent cards old layout/history fixture.
  - Root coordinating Task2/Task3 corrections. Own focused suite remained green after final mini subtitle update.
- Whitespace check with `core.whitespace=cr-at-eol`: clean for owned files.

## Native scenarios authored, NOT executed

`library_manual_collection_test.dart` registered in runner:
1. Four modes, real native position >=61 seconds at 1.0x AND Stopwatch >=60 seconds. No seek/controller injection in these minute cases. Before stop, assert no favorite and recent exists; persisted shelf empty; explicit add works.
2. Four modes, actual downloaded cache -> API/media unavailable -> native local playback advances; no favorite, recent exists.
3. Actual heard -> explicit favorite -> move to music without interrupting active old-mode session -> next P -> remove favorite playback continues -> last P near-tail seek and wait native completion -> record stays -> clear record stops matching player.

`library_preview_restart_test.dart` registered music/audiobook seed/verify pairs with force-stop performed by existing run_integration:
- Seed actual >2s native playback at P2, checkpoint18s, real prefs; audiobook also downloads valid P2 cache.
- Verify new PID, persisted record, no loaded book, native playlist empty, zero playURL/media requests from initialization onward.
- Mount actual HomeShell, switch 收藏/发现/我的, open mini preview without source requests/native playlist.
- Explicit Play alone starts source; song P1 near0, audiobook P2 >=17s (offline cache); current pause/toggle preserves position; no collection.

Fixture now records every /audio request on receipt including method, URI and Range, successful or failed.

Existing visual_design_test flows preserved; captures added for light/dark four library views, empty mini, active mini, paused mini at bounded320dp/200%, local preview and silent full preview. Screenshots and native suites require root execution and visual inspection. No native device, APK build, screenshot output, signing, release/version or artwork was performed by this task.

Commit: `79f7241` (only 9 owned files; report stays in ignored task workspace).

## Review follow-up: retained stopped metadata

Review correctly identified that real BookPlayer.stop() keeps `book` metadata while resetting loaded/loading/error. The initial `book != null` selector incorrectly treated it as a usable session. Updated MiniPlayer and PlayerPage to require book plus loaded/loading/error; an ordinary stopped record now uses its saved local checkpoint and a cleared record cannot reappear from stale metadata. Loading and failed unloaded selections remain current and retryable. No BookPlayer lifecycle changes were needed.

- Red: two new faithful fake-player cases failed before fix: ordinary stop lacked24s preview and active-record clear failed to show empty. Fake stop now deliberately keeps book, matching actual production semantics.
- Final green: focused mini/player UX **15 passed** (8 mini cases +7 existing); includes stopped checkpoint -> silent preview -> explicit resume, active clear -> empty, and unloaded loading/error priority. Log `/tmp/blisten-task4-stop-final.log`.
- Final analyzer: **No issues found**,8.7s.
- Added a real native case to manual suite (now10 cases): actually hear previous/current resources, stop retains production book while mini uses checkpoint, cover opens 上次收听 without requests, explicit play starts it, matching clear selects previous history and opens silently without resurrecting deleted resource. This new case was authored AFTER root's currently running APK was installed and is **not yet executed**.
- Visual silent-preview screenshot now asserts 上次收听 and saved position, proving the intended branch.
