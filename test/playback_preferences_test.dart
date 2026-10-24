import 'package:blisten/models/content_mode.dart';
import 'package:blisten/player/playback_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({'abts_rate': 1.75}));

  test('children rate is independent and its selection restores progress', () async {
    final children = ContentMode.fromJson('children');
    final preferences = PlaybackPreferences();
    expect(await preferences.rateFor(children), 1.0);
    await preferences.saveRate(children, 1.25);
    final reloaded = PlaybackPreferences();
    expect(await reloaded.rateFor(children), 1.25);
    expect(await reloaded.rateFor(ContentMode.audiobook), 1.75);
    expect(await reloaded.rateFor(ContentMode.music), 1.0);
    expect(await reloaded.rateFor(ContentMode.concert), 1.0);
    expect(PlaybackPreferences.selectionStart(children,
        index: 2, positionMs: 45000), (index: 2, positionMs: 45000));
  });

  test(
    'music and concert start at normal speed without inheriting audiobook rate',
    () async {
      final preferences = PlaybackPreferences();
      expect(await preferences.rateFor(ContentMode.audiobook), 1.75);
      expect(await preferences.rateFor(ContentMode.music), 1.0);
      expect(await preferences.rateFor(ContentMode.concert), 1.0);
    },
  );

  test(
    'speed choices persist independently across preferences reloads',
    () async {
      final preferences = PlaybackPreferences();
      await preferences.saveRate(ContentMode.music, 1.25);
      await preferences.saveRate(ContentMode.concert, 0.75);
      final reloaded = PlaybackPreferences();
      expect(await reloaded.rateFor(ContentMode.audiobook), 1.75);
      expect(await reloaded.rateFor(ContentMode.music), 1.25);
      expect(await reloaded.rateFor(ContentMode.concert), 0.75);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('abts_rate'), 1.75);
    },
  );

  test(
    'saved invalid speed falls back to normal speed for that mode',
    () async {
      SharedPreferences.setMockInitialValues({'abts_rate_music': 9.0});
      expect(await PlaybackPreferences().rateFor(ContentMode.music), 1.0);
    },
  );

  test('reselecting music restarts from the first part', () {
    final start = PlaybackPreferences.selectionStart(
      ContentMode.music,
      index: 3,
      positionMs: 47000,
    );
    expect(start, (index: 0, positionMs: 0));
  });

  test(
    'audiobook and concert selection restore their saved part and position',
    () {
      expect(
        PlaybackPreferences.selectionStart(
          ContentMode.audiobook,
          index: 3,
          positionMs: 47000,
        ),
        (index: 3, positionMs: 47000),
      );
      expect(
        PlaybackPreferences.selectionStart(
          ContentMode.concert,
          index: 2,
          positionMs: 180000,
        ),
        (index: 2, positionMs: 180000),
      );
    },
  );

  test(
    'explicit music part selection preserves the selected part but starts it anew',
    () {
      expect(
        PlaybackPreferences.selectionStart(
          ContentMode.music,
          index: 3,
          positionMs: 47000,
          explicitPart: true,
        ),
        (index: 3, positionMs: 0),
      );
    },
  );
}
