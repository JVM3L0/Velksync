import 'package:flutter_test/flutter_test.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/ui/schedule.dart';

void main() {
  final now = DateTime(2026, 10, 25, 23, 0);
  PowerSchedule at(Duration d, {String action = 'shutdown', bool media = false}) => PowerSchedule.fromJson({
    'action': action,
    'at': now.add(d).millisecondsSinceEpoch ~/ 1000,
    'when_media_stops': media,
  });

  test('descreve o agendamento', () {
    expect(describeSchedule(at(const Duration(minutes: 30)), now), 'Desliga às 23:30 · em 30 min');
    expect(
      describeSchedule(at(const Duration(hours: 1, minutes: 5), action: 'sleep'), now),
      'Suspende às 00:05 · em 1 h 05',
    );
    expect(describeSchedule(at(const Duration(seconds: 20)), now), 'Desliga às 23:00 · em menos de 1 min');
    expect(
      describeSchedule(PowerSchedule.fromJson({'action': 'shutdown', 'when_media_stops': true}), now),
      'Desliga quando a mídia parar',
    );
    expect(
      describeSchedule(at(const Duration(minutes: 1), media: true), now),
      'A mídia parou: Desliga às 23:01 · em 1 min',
    );
  });

  test('lê o agendamento do /api/info', () {
    final info = AgentInfo.fromJson({
      'os': 'windows',
      'features': ['live', 'schedule'],
      'schedule': {'action': 'sleep', 'at': 1793000000},
    });
    expect(info.has('schedule'), isTrue);
    expect(info.schedule!.action, 'sleep');
    expect(AgentInfo.fromJson({'os': 'linux', 'schedule': null}).schedule, isNull);
    expect(AgentInfo.fromJson({'os': 'linux'}).has('live'), isFalse, reason: 'agente antigo');
  });
}
