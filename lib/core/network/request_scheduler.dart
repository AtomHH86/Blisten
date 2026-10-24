import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Reserve before awaiting: concurrent callers cannot share the same send slot.
class RequestScheduler {
  RequestScheduler({
    Duration Function()? now,
    Future<void> Function(Duration)? delay,
    this.gap = const Duration(milliseconds: 450),
  }) : now = now ?? (() => _clock.elapsed),
       delay = delay ?? Future<void>.delayed;

  static final _clock = Stopwatch()..start();
  final Duration Function() now;
  final Future<void> Function(Duration) delay;
  final Duration gap;
  Duration? _lastGrant;
  Future<void>? _tail;

  Future<T> send<T>(RequestBudget budget, Future<T> Function() action) {
    // Register the turn synchronously. Re-check time when the preceding turn
    // completes, so overdue timers cannot release multiple sends together.
    final previous = _tail ?? Future<void>.value();
    final result = Completer<T>();
    final turn = previous.then((_) async {
      budget.check();
      final last = _lastGrant;
      if (last != null) {
        final wait = last + gap - now();
        if (wait > Duration.zero) await budget.wait(wait);
      }
      budget.check();
      _lastGrant = now();
      // Start transport now but release the send queue immediately. A slow
      // response must not block an independent login/logout request.
      result.complete(action());
    });
    final settled = turn.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    _tail = settled;
    settled.then((_) { if (identical(_tail, settled)) _tail = null; });
    return Future.any<T>([
      result.future,
      budget.token.whenCancel.then<T>((error) => throw error),
    ]);
  }
}

/// One budget covers WBI preparation, retries, backoff and the active Dio call.
class RequestBudget {
  RequestBudget(this.scheduler, {CancelToken? cancelToken,
    this.maxAttempts = 4, this.timeout = const Duration(seconds: 45)})
      : token = CancelToken(), started = scheduler.now() {
    if (cancelToken?.isCancelled ?? false) token.cancel();
    cancelToken?.whenCancel.then((error) {
      if (!_closed && !token.isCancelled) token.cancel(error);
    });
    _deadline = Timer(timeout, () {
      timedOut = true;
      if (!token.isCancelled) token.cancel('Request deadline');
    });
  }

  final RequestScheduler scheduler;
  final CancelToken token;
  final int maxAttempts;
  final Duration timeout;
  final Duration started;
  late final Timer _deadline;
  int attempts = 0;
  bool timedOut = false;
  bool _closed = false;
  Duration get remaining => timeout - (scheduler.now() - started);
  bool get canRetry => attempts < maxAttempts && remaining > Duration.zero && !token.isCancelled;

  void check() {
    if (timedOut || remaining <= Duration.zero) {
      throw TimeoutException('Request deadline');
    }
    if (token.isCancelled) throw token.cancelError!;
  }

  void beforeAttempt() {
    check();
    if (attempts >= maxAttempts) throw TimeoutException('Request attempt budget');
    attempts++;
  }

  Future<void> wait(Duration duration) async {
    check();
    if (duration >= remaining) throw TimeoutException('Request deadline');
    if (duration > Duration.zero) {
      await Future.any<void>([
        scheduler.delay(duration),
        token.whenCancel.then<void>((error) => throw error),
      ]);
    }
    check();
  }

  void close() {
    _closed = true;
    _deadline.cancel();
  }
}

/// Schedule at the transport boundary, after Dio interceptors/encoding. This
/// avoids multiple overdue preparation callbacks dispatching at the same time.
class ScheduledAdapter implements HttpClientAdapter {
  ScheduledAdapter(this.delegate, this.scheduler);
  static const budgetKey = 'blistenRequestBudget';
  final HttpClientAdapter delegate;
  final RequestScheduler scheduler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) {
    final budget = options.extra[budgetKey] as RequestBudget;
    return scheduler.send(budget, () {
      budget.beforeAttempt();
      return delegate.fetch(options, stream, cancelFuture);
    });
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}
