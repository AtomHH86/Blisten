/// The original selection and its absolute expiry; no callback/tick state.
class SleepTimerSchedule {
  SleepTimerSchedule({required this.duration, required DateTime startedAt})
      : deadline = startedAt.add(duration);

  final Duration duration;
  final DateTime deadline;

  Duration remainingAt(DateTime now) {
    final remaining = deadline.difference(now);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }
}
