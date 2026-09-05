import 'package:flutter_test/flutter_test.dart';
import 'package:koza_rc_car/services/connection_stats.dart';

void main() {
  group('ConnectionStats Tests', () {
    late ConnectionStats stats;

    setUp(() {
      stats = ConnectionStats();
      stats.reset();
    });

    test('Initial or reset state has 0 commands and 100% success rate', () {
      expect(stats.commandsSent, 0);
      expect(stats.commandsFailed, 0);
      expect(stats.totalCommands, 0);
      expect(stats.successRate, 100.0);
      expect(stats.connectionTimeString, '00:00');
    });

    test('Record successful and failed commands calculates correct rates', () {
      stats.startConnection();

      // Send 3 successful commands
      stats.recordCommandSent(true);
      stats.recordCommandSent(true);
      stats.recordCommandSent(true);

      expect(stats.commandsSent, 3);
      expect(stats.commandsFailed, 0);
      expect(stats.totalCommands, 3);
      expect(stats.successRate, 100.0);

      // Send 1 failed command (3 out of 4 success = 75%)
      stats.recordCommandSent(false);

      expect(stats.commandsSent, 3);
      expect(stats.commandsFailed, 1);
      expect(stats.totalCommands, 4);
      expect(stats.successRate, 75.0);
    });

    test('RSSI getter and setter work properly', () {
      expect(stats.rssi, 0);
      stats.setRSSI(-65);
      expect(stats.rssi, -65);
    });

    test('Ending connection stops duration tracking', () {
      stats.startConnection();
      expect(stats.connectionDuration, isNotNull);
      stats.endConnection();
      expect(stats.connectionDuration, Duration.zero);
    });
  });
}
