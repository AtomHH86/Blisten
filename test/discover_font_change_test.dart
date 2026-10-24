import 'package:blisten/core/nav/home_tabs.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/models/book.dart';
import 'package:blisten/models/content_mode.dart';
import 'package:blisten/pages/discover_page.dart';
import 'package:blisten/services/bili_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyApi implements BiliApi {
  int searches = 0;

  @override
  Future<List<Book>> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    String? order,
    Function(int total)? onFirstPage,
    Function(int rawCount)? onRawCount,
    ContentMode mode = ContentMode.audiobook,
    CancelToken? cancelToken,
  }) async {
    searches++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeTabs.discoverMode.value = null;
  });

  testWidgets('font changes refresh only Web channel text measurement', (
    tester,
  ) async {
    final api = _EmptyApi();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: DiscoverPage(api: api)),
    );
    await tester.pumpAndSettle();
    expect(api.searches, 1);

    Finder chip(ContentMode mode) =>
        find.byKey(ValueKey('discover-channel-${mode.name}'));
    RenderParagraph paragraph(ContentMode mode) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(mode.label), matching: find.byType(RichText)),
        );

    final chipElements = {
      for (final mode in ContentMode.values) mode: tester.element(chip(mode)),
    };
    var paragraphs = {
      for (final mode in ContentMode.values) mode: paragraph(mode),
    };

    for (var change = 0; change < 2; change++) {
      await tester.binding.handleSystemMessage({'type': 'fontsChange'});
      await tester.pumpAndSettle();

      for (final mode in ContentMode.values) {
        expect(
          identical(paragraph(mode), paragraphs[mode]),
          !kIsWeb,
          reason: kIsWeb
              ? 'Web fallback fonts must discard the old intrinsic measurement'
              : 'Native channel labels retain their existing render objects',
        );
        expect(tester.element(chip(mode)), same(chipElements[mode]));
        expect(
          tester.widget<ChoiceChip>(chip(mode)).selected,
          mode == ContentMode.audiobook,
        );
      }
      expect(api.searches, 1);
      paragraphs = {
        for (final mode in ContentMode.values) mode: paragraph(mode),
      };
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
