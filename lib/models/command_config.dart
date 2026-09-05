import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Command configuration model for RC car control
class CommandConfig {
  static const String _prefsKey = 'custom_command_config';

  String forward;
  String backward;
  String left;
  String right;
  String stop;
  
  // Extra controls
  String ledOn;
  String ledOff;
  String horn;
  int speedLow;
  int speedMedium;
  int speedHigh;

  CommandConfig({
    this.forward = 'F',
    this.backward = 'B',
    this.left = 'L',
    this.right = 'R',
    this.stop = 'S',
    this.ledOn = 'L1',
    this.ledOff = 'L0',
    this.horn = 'H1',
    this.speedLow = 85,      // ~33%
    this.speedMedium = 170,  // ~66%
    this.speedHigh = 255,    // 100%
  });

  // Copy with method for easy modification
  CommandConfig copyWith({
    String? forward,
    String? backward,
    String? left,
    String? right,
    String? stop,
    String? ledOn,
    String? ledOff,
    String? horn,
    int? speedLow,
    int? speedMedium,
    int? speedHigh,
  }) {
    return CommandConfig(
      forward: forward ?? this.forward,
      backward: backward ?? this.backward,
      left: left ?? this.left,
      right: right ?? this.right,
      stop: stop ?? this.stop,
      ledOn: ledOn ?? this.ledOn,
      ledOff: ledOff ?? this.ledOff,
      horn: horn ?? this.horn,
      speedLow: speedLow ?? this.speedLow,
      speedMedium: speedMedium ?? this.speedMedium,
      speedHigh: speedHigh ?? this.speedHigh,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'forward': forward,
      'backward': backward,
      'left': left,
      'right': right,
      'stop': stop,
      'ledOn': ledOn,
      'ledOff': ledOff,
      'horn': horn,
      'speedLow': speedLow,
      'speedMedium': speedMedium,
      'speedHigh': speedHigh,
    };
  }

  // Create from JSON
  factory CommandConfig.fromJson(Map<String, dynamic> json) {
    return CommandConfig(
      forward: json['forward'] ?? 'F',
      backward: json['backward'] ?? 'B',
      left: json['left'] ?? 'L',
      right: json['right'] ?? 'R',
      stop: json['stop'] ?? 'S',
      ledOn: json['ledOn'] ?? 'L1',
      ledOff: json['ledOff'] ?? 'L0',
      horn: json['horn'] ?? 'H1',
      speedLow: json['speedLow'] ?? 85,
      speedMedium: json['speedMedium'] ?? 170,
      speedHigh: json['speedHigh'] ?? 255,
    );
  }

  /// Save current configuration to SharedPreferences
  Future<bool> saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_prefsKey, jsonEncode(toJson()));
    } catch (e) {
      return false;
    }
  }

  /// Load configuration from SharedPreferences or return default
  static Future<CommandConfig> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        return CommandConfig.fromJson(json);
      }
    } catch (_) {}
    return CommandConfig();
  }
}

