// Scratch contract: migrate only after stage C authorization and create the
// tiny immutable value object after these behavior tests demonstrate RED.
import 'package:blisten/player/sleep_timer_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 10, 24, 12);

  test('deadline preserves the actual chosen duration', () {
    final schedule = SleepTimerSchedule(
      duration: const Duration(minutes: 10), startedAt: start,
    );
    expect(schedule.duration, const Duration(minutes: 10));
    expect(schedule.deadline, DateTime.utc(2026, 10, 24, 12, 10));
    expect(schedule.remainingAt(start), const Duration(minutes: 10));
  });

  test('remaining follows elapsed time even with no intermediate callbacks', () {
    final schedule = SleepTimerSchedule(
      duration: const Duration(minutes: 30), startedAt: start,
    );
    // A single lookup after a simulated background suspension; no decrementing
    // timer callbacks are supplied, so a tick-count implementation cannot pass.
    expect(schedule.remainingAt(DateTime.utc(2026, 10, 24, 12, 22, 17)),
      const Duration(minutes: 7, seconds: 43));
    expect(schedule.duration, const Duration(minutes: 30));
    expect(schedule.deadline, DateTime.utc(2026, 10, 24, 12, 30));
  });

  test('crossing smaller presets never changes original selected duration', () {
    final schedule = SleepTimerSchedule(
      duration: const Duration(minutes: 30), startedAt: start,
    );
    expect(schedule.remainingAt(DateTime.utc(2026, 10, 24, 12, 20)),
      const Duration(minutes: 10));
    expect(schedule.duration, const Duration(minutes: 30));
    expect(schedule.remainingAt(DateTime.utc(2026, 10, 24, 12, 25)),
      const Duration(minutes: 5));
    expect(schedule.duration, const Duration(minutes: 30));
  });

  test('expiry and later lookups clamp at zero without negative countdowns', () {
    final schedule = SleepTimerSchedule(
      duration: const Duration(minutes: 10), startedAt: start,
    );
    expect(schedule.remainingAt(DateTime.utc(2026, 10, 24, 12, 10)), Duration.zero);
    expect(schedule.remainingAt(DateTime.utc(2026, 10, 24, 15)), Duration.zero);
    expect(schedule.deadline, DateTime.utc(2026, 10, 24, 12, 10));
  });

  test('nonpreset custom duration keeps second precision at clock boundary', () {
    final schedule = SleepTimerSchedule(
      duration: const Duration(minutes: 17, milliseconds: 250), startedAt: start,
    );
    expect(schedule.remainingAt(start.add(const Duration(minutes: 17))),
      const Duration(milliseconds: 250));
    expect(schedule.remainingAt(start.add(const Duration(minutes: 17, milliseconds: 251))),
      Duration.zero);
    expect(schedule.duration, const Duration(minutes: 17, milliseconds: 250));
  });
}
