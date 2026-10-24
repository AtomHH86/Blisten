# Task 3 report

## Implemented

- `LibraryView { favorites, recent, cache, following }`, `HomeTabs.libraryView`, `HomeTabs.openLibrary(view)`; selecting a library view also selects main index 0.
- Bookshelf is the single hub. Four equal fixed slots in one 56 dp normal header; 24/16 sp, semibold/action color/short underline, common baseline, 180 ms transition, zero duration under reduced motion. At 200% scale header is 96 dp, horizontal scrolling ensures selected slot visible. Selected semantics included, no title/count/avatar duplication.
- Lazy visited-view IndexedStack plus PageStorage keeps independent view states. Favorites order snapshots counts on entry and remains stable during edits; re-entering view or bottom page recalculates order. Preview max 6, full group uses lazy grid. All-empty uses one empty state; partial empty groups link to matching discover mode.
- Long press move/remove; target options explain replay rules before selection. moveToMode preserves stored history/progress and does not call player. Recently heard uses actual recentBooks without progress>0 filtering, all/four-mode filters, explicit recent count and updated mode label.
- Cache/follow support embedded rendering without duplicate AppBars. Embedded cache retains clear action and all task/failure/management controls. Cache labels/offline launch mode resolve progressByBvid first, preserving moved BV identity.
- `UsableCacheCount` shared by cache summary and My menu uses fileOf + filesystem exists/nonzero length; excludes active/failed tasks and failures, shows checking state while pending. No cache_store API changes.
- My removes stat cards and duplicated continue-list; ordinary four menus route to openLibrary, recent count includes uncollected heard records. Removed old automatic-collection hint from Favorites.

## Validation evidence

- Red: `flutter test test/library_hub_test.dart --reporter compact` failed compile for missing LibraryView/libraryView/openLibrary (captured `/tmp/task3-red.log`). Sandbox Dart VM first attempt crashed; verified tests ran with approved escalated host runtime.
- Final: `flutter analyze --no-pub lib/pages/bookshelf_page.dart lib/pages/favorites_page.dart lib/pages/recent_page.dart lib/pages/cache_page.dart lib/pages/follow_page.dart lib/pages/my_page.dart lib/core/nav/home_tabs.dart test/library_hub_test.dart`: **No issues found**.
- Final: `flutter test --no-pub test/library_hub_test.dart test/recent_mode_ui_test.dart test/cache_empty_ui_test.dart test/listening_history_test.dart --reporter compact`: **22 passed** (`/tmp/task3-verified.log`).
- Dedicated new 7 tests: single title row + selected semantics + normal height; light/dark 320 dp with 200% typography; count order/edit stability/reentry/fixed tie order; My four menu redirects; user long-press move with replay rule and preserved progress/listened timestamp; HomeTabs routing interface.
- Existing tests cover moved mode recent playback shortcut behavior, cache last/all deletion and empty sheet, actual listening history data semantics.
- Reviewed v4 concept PNG and unified spec 4/5/8; concept image is design reference, not device evidence. No emulator, APK build, or online validation run by Task3. Full host suite is assigned to Task4 after this focused run.

## Limits / review points

- Cache count is a filesystem snapshot when cache index/task signature changes; it does not continuously poll files for out-of-band deletion while the view remains mounted. Startup cache reconciliation and cache changes cause new checks.
- Navigation, scroll restoration and full accessibility/visual behavior still need combined shell/device regression; new host tests do not constitute full device/reader verification.
- Shared widgets/mini player/player page/home shell/integration/tool script are outside Task3 ownership and were not edited. Other concurrent changes and root plan/docs were not staged.
