import 'package:flutter_test/flutter_test.dart';
import 'package:koza_rc_car/models/command_config.dart';

void main() {
  group('CommandConfig Tests', () {
    test('Default values are initialized properly', () {
      final config = CommandConfig();
      expect(config.forward, 'F');
      expect(config.backward, 'B');
      expect(config.left, 'L');
      expect(config.right, 'R');
      expect(config.stop, 'S');
      expect(config.ledOn, 'L1');
      expect(config.ledOff, 'L0');
      expect(config.horn, 'H1');
      expect(config.speedLow, 85);
      expect(config.speedMedium, 170);
      expect(config.speedHigh, 255);
    });

    test('toJson and fromJson correctly serialize and deserialize', () {
      final custom = CommandConfig(
        forward: 'W',
        backward: 'S',
        left: 'A',
        right: 'D',
        stop: 'X',
        ledOn: 'LIGHT_ON',
        ledOff: 'LIGHT_OFF',
        horn: 'BEEP',
        speedLow: 50,
        speedMedium: 150,
        speedHigh: 250,
      );

      final json = custom.toJson();
      final fromJson = CommandConfig.fromJson(json);

      expect(fromJson.forward, 'W');
      expect(fromJson.backward, 'S');
      expect(fromJson.left, 'A');
      expect(fromJson.right, 'D');
      expect(fromJson.stop, 'X');
      expect(fromJson.ledOn, 'LIGHT_ON');
      expect(fromJson.ledOff, 'LIGHT_OFF');
      expect(fromJson.horn, 'BEEP');
      expect(fromJson.speedLow, 50);
      expect(fromJson.speedMedium, 150);
      expect(fromJson.speedHigh, 250);
    });

    test('copyWith updates only specified properties', () {
      final original = CommandConfig();
      final modified = original.copyWith(
        forward: 'UP',
        speedHigh: 200,
      );

      expect(modified.forward, 'UP');
      expect(modified.backward, 'B'); // unchanged
      expect(modified.speedHigh, 200);
      expect(modified.speedLow, 85); // unchanged
    });

    test('fromJson handles empty or partial JSON gracefully with defaults', () {
      final partialJson = <String, dynamic>{
        'forward': 'GO',
      };
      final config = CommandConfig.fromJson(partialJson);

      expect(config.forward, 'GO');
      expect(config.backward, 'B'); // fallback to default
      expect(config.stop, 'S');
      expect(config.speedHigh, 255);
    });
  });
}
