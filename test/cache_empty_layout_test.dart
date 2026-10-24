import 'package:blisten/core/storage/cache_store.dart';
import 'package:blisten/core/theme/app_theme.dart';
import 'package:blisten/pages/cache_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _EmptyCache extends ChangeNotifier implements CacheStore {
  @override
  List<CacheEntry> get entries => [];
  @override
  List<CacheTask> get tasks => [];
  @override
  List<CacheFailure> get failures => [];
  @override
  int get pendingCount => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'embedded cache empty fits constrained 320dp 200% ${dark ? 'dark' : 'light'}',
      (tester) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<CacheStore>.value(
            value: _EmptyCache(),
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: const Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 320,
                      height: 341,
                      child: CachePage(embedded: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final instructions = find.textContaining('在作品详情页点下载图标');
        await tester.ensureVisible(instructions);
        expect(instructions.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
