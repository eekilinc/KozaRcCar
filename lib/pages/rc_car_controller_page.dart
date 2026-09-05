import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/command_config.dart';
import '../services/bluetooth_service.dart';
import '../services/connection_stats.dart';
import '../services/sound_service.dart';
import '../widgets/dpad_controller.dart';
import '../widgets/joystick_controller.dart';
import '../widgets/serial_monitor_dialog.dart';
import 'command_settings_page.dart';
import 'device_selection_page.dart';
import 'about_page.dart';
import 'settings_page.dart';

/// Main RC car controller page with Cockpit / Gamepad experience
class RCCarControllerPage extends StatefulWidget {
  const RCCarControllerPage({Key? key}) : super(key: key);

  @override
  State<RCCarControllerPage> createState() => _RCCarControllerPageState();
}

class _RCCarControllerPageState extends State<RCCarControllerPage> {
  final BluetoothServiceManager _bluetoothService = BluetoothServiceManager();
  CommandConfig _commandConfig = CommandConfig();
  BondedDevice? _connectedDevice;
  String _lastSentCommand = '';
  int _controlMode = 0; // 0: D-Pad, 1: Joystick
  int _commandCount = 0;
  int _disconnectCount = 0;

  // Extra control features
  bool _ledOn = false;
  int _speed = 170; // Default: ~66% (Normal)
  bool _hornActive = false;
  bool _speedSliderExpanded = false;

  // Serial Monitor Terminal logs (keep last 50)
  final List<TerminalMessage> _terminalMessages = [];

  @override
  void initState() {
    super.initState();
    _loadCommandConfig();
  }

  void _handleDisconnection() {
    if (!mounted) return;

    _disconnectCount = 0;
    final stats = ConnectionStats();
    stats.endConnection();
    _bluetoothService.disconnect();

    setState(() {
      _connectedDevice = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bluetooth bağlantısı kesildi!'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadCommandConfig() async {
    final config = await CommandConfig.loadFromPrefs();
    if (mounted) {
      setState(() {
        _commandConfig = config;
      });
    }
  }

  Future<void> _selectDevice() async {
    final device = await Navigator.push<BondedDevice>(
      context,
      MaterialPageRoute(builder: (context) => const DeviceSelectionPage()),
    );

    if (device != null) {
      final stats = ConnectionStats();
      stats.startConnection();

      setState(() {
        _connectedDevice = device;
      });
      _disconnectCount = 0;
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
    // Reload config in case it changed in settings
    await _loadCommandConfig();
  }

  Future<void> _openCommandSettings() async {
    final newConfig = await Navigator.push<CommandConfig>(
      context,
      MaterialPageRoute(
        builder: (context) => CommandSettingsPage(initialConfig: _commandConfig),
      ),
    );

    if (newConfig != null) {
      await newConfig.saveToPrefs();
      if (mounted) {
        setState(() {
          _commandConfig = newConfig;
        });
      }
    }
  }

  Future<bool> _sendCommand(String command) async {
    if (_connectedDevice == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cihaz bağlı değil'),
          duration: Duration(seconds: 1),
        ),
      );
      return false;
    }

    final soundService = SoundService();
    final stats = ConnectionStats();
    final success = await _bluetoothService.sendCommand(command);

    // Record command in stats
    stats.recordCommandSent(success);

    // Record to terminal log
    _terminalMessages.add(TerminalMessage(
      timestamp: DateTime.now(),
      text: command,
      isOutgoing: true,
    ));
    if (_terminalMessages.length > 50) {
      _terminalMessages.removeAt(0);
    }

    // Play sound feedback asynchronously
    if (soundService.soundEnabled) {
      soundService.playCommandSound();
    }

    if (success) {
      HapticFeedback.lightImpact();
      setState(() {
        _lastSentCommand = command;
        _commandCount++;
      });
      return true;
    } else {
      _disconnectCount++;
      if (_disconnectCount >= 3 && mounted) {
        _handleDisconnection();
      }
      return false;
    }
  }

  Future<void> _emergencyStop() async {
    HapticFeedback.heavyImpact();
    await _sendCommand(_commandConfig.stop);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Text('🛑 ACİL DURDURMA (E-STOP) UYGULANDI!'),
          ],
        ),
        backgroundColor: Colors.red[800],
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _disconnectDevice() async {
    final stats = ConnectionStats();
    stats.endConnection();
    await _bluetoothService.disconnect();
    setState(() {
      _connectedDevice = null;
      _lastSentCommand = '';
      _commandCount = 0;
      _ledOn = false;
      _speed = 170;
    });
  }

  // LED Light Toggle
  Future<void> _toggleLED() async {
    final command = _ledOn ? _commandConfig.ledOff : _commandConfig.ledOn;
    final success = await _sendCommand(command);
    if (success) {
      HapticFeedback.mediumImpact();
      setState(() {
        _ledOn = !_ledOn;
      });
    }
  }

  // Speed Adjustment
  Future<void> _setSpeed(int speed) async {
    setState(() => _speed = speed);
    final command = 'V${speed.toString().padLeft(3, '0')}';
    await _sendCommand(command);
  }

  // Horn Trigger
  Future<void> _activateHorn() async {
    setState(() => _hornActive = true);
    HapticFeedback.heavyImpact();
    await _sendCommand(_commandConfig.horn);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _hornActive = false);
    }
  }

  void _openSerialMonitor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SerialMonitorSheet(
        onSendCommand: _sendCommand,
        messages: _terminalMessages,
        onClearMessages: () {
          setState(() {
            _terminalMessages.clear();
          });
        },
      ),
    );
  }

  void _stepSpeed(int delta) {
    final newSpeed = (_speed + delta).clamp(0, 255);
    if (newSpeed != _speed) {
      _setSpeed(newSpeed);
    }
  }

  void _showDisconnectConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bağlantıyı Kes'),
        content: Text('${_connectedDevice?.name ?? "Cihaz"} bağlantısını kesmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _disconnectDevice();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bağlantıyı Kes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String get _gearName {
    if (_speed <= 100) return 'ECO';
    if (_speed <= 190) return 'NORMAL';
    return 'SPORT';
  }

  Color get _gearColor {
    if (_speed <= 100) return Colors.greenAccent;
    if (_speed <= 190) return Colors.amberAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        return Scaffold(
          appBar: isLandscape
              ? null
              : AppBar(
                  leading: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AboutPage()),
                        );
                      },
                      child: Image.asset(
                        'assets/images/koza_logo.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  title: const Text('Koza RC Car'),
                  centerTitle: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.terminal),
                      onPressed: _openSerialMonitor,
                      tooltip: 'Seri Monitör / Konsol',
                    ),
                    IconButton(
                      icon: const Icon(Icons.help_outline),
                      onPressed: _showControllerHelpDialog,
                      tooltip: 'Kontroller Hakkında',
                    ),
                    PopupMenuButton(
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          child: const Row(
                            children: [
                              Icon(Icons.settings, size: 18, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Ayarlar'),
                            ],
                          ),
                          onTap: _openSettings,
                        ),
                        PopupMenuItem(
                          child: const Row(
                            children: [
                              Icon(Icons.tune, size: 18, color: Colors.purple),
                              SizedBox(width: 8),
                              Text('Komut Tuşları'),
                            ],
                          ),
                          onTap: _openCommandSettings,
                        ),
                        PopupMenuItem(
                          child: const Row(
                            children: [
                              Icon(Icons.info, size: 18, color: Colors.grey),
                              SizedBox(width: 8),
                              Text('Hakkımda'),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const AboutPage()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
          body: isLandscape ? _buildLandscapeGamepad() : _buildPortraitLayout(),
          floatingActionButton: isLandscape
              ? null
              : FloatingActionButton.small(
                  onPressed: _showCommandReferenceDialog,
                  tooltip: 'Komut Referansı',
                  backgroundColor: Colors.blueGrey,
                  child: const Icon(Icons.info_outline, color: Colors.white),
                ),
        );
      },
    );
  }

  // ==========================================
  // PORTRAIT (DİKEY) GÖRÜNÜM
  // ==========================================
  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          // Connection status
          _buildConnectionCard(),
          const SizedBox(height: 12),

          // Cockpit Dashboard (Speedometer + Neon LEDs)
          _buildCockpitDashboard(),
          const SizedBox(height: 12),

          // Controller Mode Switcher (D-Pad vs Joystick)
          _buildControllerModeSwitcher(),
          const SizedBox(height: 12),

          // Driving Controller (D-Pad or Joystick)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _controlMode == 0
                ? DPadController(
                    onCommand: _sendCommand,
                    commandConfig: _commandConfig,
                    size: 210,
                  )
                : JoystickController(
                    onCommand: _sendCommand,
                    commandConfig: _commandConfig,
                    size: 220,
                  ),
          ),
          const SizedBox(height: 14),

          // Big Emergency Stop Button (E-STOP)
          _buildEmergencyStopButton(),
          const SizedBox(height: 14),

          // Quick Action Bar (Far, Korna, Vites)
          _buildQuickActionBar(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ==========================================
  // LANDSCAPE (YATAY) GAMEPAD KOKPİT GÖRÜNÜMÜ
  // ==========================================
  Widget _buildLandscapeGamepad() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          children: [
            // 1. Sleek Cockpit Top Bar (Height: 34)
            _buildLandscapeTopBar(),
            const SizedBox(height: 6),

            // 2. Main Gamepad Body (3 balanced wings, fits without any scrolling)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Wing: Steering (D-Pad or Joystick)
                  Expanded(
                    flex: 10,
                    child: _buildLandscapeSteeringWing(),
                  ),
                  const SizedBox(width: 8),

                  // Center Wing: Cockpit HUD, Neon LEDs, and Emergency Stop
                  Expanded(
                    flex: 9,
                    child: _buildLandscapeCenterHUD(),
                  ),
                  const SizedBox(width: 8),

                  // Right Wing: Auxiliary Controls (Far, Korna, Vites, Hız)
                  Expanded(
                    flex: 11,
                    child: _buildLandscapeActionWing(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Landscape Sleek Top Bar
  Widget _buildLandscapeTopBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141923) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF222B3D) : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          // Logo & Title
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/koza_logo.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 6),
                const Text(
                  'KOZA RC',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Bluetooth Connection Chip (Tap to connect / disconnect)
          InkWell(
            onTap: _connectedDevice != null ? _showDisconnectConfirmation : _selectDevice,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _connectedDevice != null
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _connectedDevice != null
                      ? Colors.greenAccent.withValues(alpha: 0.4)
                      : Colors.redAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _connectedDevice != null ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    size: 13,
                    color: _connectedDevice != null ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      _connectedDevice != null ? _connectedDevice!.name : 'Cihaza Bağlan',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _connectedDevice != null ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // D-Pad / Joystick mode switcher
          _buildControllerModeSwitcher(compact: true),
          const SizedBox(width: 6),

          // Serial Monitor
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.terminal, size: 18),
            onPressed: _openSerialMonitor,
            tooltip: 'Seri Monitör / Konsol',
          ),

          // Menu Popup
          PopupMenuButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.more_vert, size: 18),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Row(
                  children: [
                    Icon(Icons.settings, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Ayarlar'),
                  ],
                ),
                onTap: _openSettings,
              ),
              PopupMenuItem(
                child: const Row(
                  children: [
                    Icon(Icons.tune, size: 18, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('Komut Tuşları'),
                  ],
                ),
                onTap: _openCommandSettings,
              ),
              PopupMenuItem(
                child: const Row(
                  children: [
                    Icon(Icons.help_outline, size: 18, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('Yardım / Rehber'),
                  ],
                ),
                onTap: _showControllerHelpDialog,
              ),
              PopupMenuItem(
                child: const Row(
                  children: [
                    Icon(Icons.info, size: 18, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('Hakkımda'),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AboutPage()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Left Wing: Steering with dynamic sizing to prevent any overflow
  Widget _buildLandscapeSteeringWing() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141923) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF222B3D) : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxDim = constraints.maxHeight < constraints.maxWidth
              ? constraints.maxHeight
              : constraints.maxWidth;
          final controllerSize = (maxDim - 8).clamp(130.0, 195.0);

          return Center(
            child: _controlMode == 0
                ? DPadController(
                    onCommand: _sendCommand,
                    commandConfig: _commandConfig,
                    size: controllerSize,
                    showTitle: false,
                  )
                : JoystickController(
                    onCommand: _sendCommand,
                    commandConfig: _commandConfig,
                    size: controllerSize,
                    showTitle: false,
                  ),
          );
        },
      ),
    );
  }

  // Center Wing: Cockpit HUD, Neon Indicators & Emergency Stop
  Widget _buildLandscapeCenterHUD() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final speedPercent = (_speed * 100 ~/ 255);
    final isF = _lastSentCommand == _commandConfig.forward;
    final isB = _lastSentCommand == _commandConfig.backward;
    final isL = _lastSentCommand == _commandConfig.left;
    final isR = _lastSentCommand == _commandConfig.right;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141923) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF222B3D) : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Top: Speedometer & Gear Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.speed, color: _gearColor, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '$speedPercent%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _gearColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _gearColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _gearColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  _gearName,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: _gearColor,
                  ),
                ),
              ),
            ],
          ),

          // Speed progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _speed / 255.0,
              minHeight: 4,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(_gearColor),
            ),
          ),

          // Neon Direction Indicators (Centered with FittedBox)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLedItem(Icons.arrow_upward, isF, 'İLERİ', Colors.cyanAccent, size: 14),
                const SizedBox(width: 4),
                _buildLedItem(Icons.arrow_downward, isB, 'GERİ', Colors.amberAccent, size: 14),
                const SizedBox(width: 4),
                _buildLedItem(Icons.arrow_back, isL, 'SOL', Colors.greenAccent, size: 14),
                const SizedBox(width: 4),
                _buildLedItem(Icons.arrow_forward, isR, 'SAĞ', Colors.greenAccent, size: 14),
              ],
            ),
          ),

          // Emergency Stop Button (E-STOP)
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton(
              onPressed: _connectedDevice != null ? _emergencyStop : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[400],
                elevation: 4,
                shadowColor: Colors.red.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dangerous, size: 18, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'ACİL STOP',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Telemetry Ticker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _lastSentCommand.isNotEmpty ? 'TX: $_lastSentCommand' : 'TX: -',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.cyanAccent,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'PWM: $_speed',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[400],
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Right Wing: Auxiliary Controls (Far, Korna, Vites, Hız)
  Widget _buildLandscapeActionWing() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141923) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF222B3D) : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Row 1: Far & Korna buttons with FittedBox
          Row(
            children: [
              // Far button
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: _connectedDevice != null ? _toggleLED : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ledOn
                          ? Colors.amber[700]
                          : (isDark ? const Color(0xFF1E2838) : Colors.grey[300]),
                      foregroundColor: _ledOn
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.black87),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: _ledOn ? 3 : 0,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _ledOn ? Icons.light_mode : Icons.light_mode_outlined,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _ledOn ? 'FAR: AÇIK' : 'FAR: KAPALI',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Korna button
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: _connectedDevice != null
                        ? (_hornActive ? null : _activateHorn)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hornActive ? Colors.deepOrange : Colors.orange[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.volume_up, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _hornActive ? 'ÇALIYOR' : 'KORNA',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Row 2: Vites Seçimleri (ECO, NORMAL, SPORT)
          Row(
            children: [
              Expanded(
                child: _buildGearButton(
                  label: 'ECO',
                  sub: '%33',
                  speedVal: _commandConfig.speedLow,
                  color: Colors.green,
                  compact: true,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildGearButton(
                  label: 'NORMAL',
                  sub: '%66',
                  speedVal: _commandConfig.speedMedium,
                  color: Colors.orange,
                  compact: true,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildGearButton(
                  label: 'SPORT',
                  sub: '%100',
                  speedVal: _commandConfig.speedHigh,
                  color: Colors.red,
                  compact: true,
                ),
              ),
            ],
          ),

          // Row 3: Hız Slider with micro-adjust buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F131C) : Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _connectedDevice != null ? () => _stepSpeed(-15) : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(Icons.remove, size: 16, color: Colors.grey[400]),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                      value: _speed.toDouble(),
                      min: 0,
                      max: 255,
                      activeColor: _gearColor,
                      inactiveColor: Colors.grey.withValues(alpha: 0.2),
                      onChanged: _connectedDevice != null ? (v) => _setSpeed(v.toInt()) : null,
                    ),
                  ),
                ),
                InkWell(
                  onTap: _connectedDevice != null ? () => _stepSpeed(15) : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(Icons.add, size: 16, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BİLEŞEN: KOKPİT HIZ & YÖN GÖSTERGESİ
  // ==========================================
  Widget _buildCockpitDashboard({bool compact = false}) {
    final speedPercent = (_speed * 100 ~/ 255);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF181E29)
            : const Color(0xFFF2F5FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF26334A)
              : Colors.blue.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Speedometer badge
              Row(
                children: [
                  Icon(Icons.speed, color: _gearColor, size: compact ? 22 : 28),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$speedPercent',
                            style: TextStyle(
                              fontSize: compact ? 20 : 26,
                              fontWeight: FontWeight.w900,
                              color: _gearColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const Text('%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _gearColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _gearColor.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              _gearName,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _gearColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'PWM: $_speed / 255',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),

              // Neon Direction Indicator LEDs
              _buildNeonDirectionLeds(size: compact ? 16 : 20),
            ],
          ),
          const SizedBox(height: 8),

          // Speed progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _speed / 255.0,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(_gearColor),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BİLEŞEN: NEON YÖN OKLARI (LED'LER)
  // ==========================================
  Widget _buildNeonDirectionLeds({double size = 18}) {
    final isF = _lastSentCommand == _commandConfig.forward;
    final isB = _lastSentCommand == _commandConfig.backward;
    final isL = _lastSentCommand == _commandConfig.left;
    final isR = _lastSentCommand == _commandConfig.right;

    return Row(
      children: [
        _buildLedItem(Icons.arrow_upward, isF, 'İLERİ', Colors.cyanAccent),
        const SizedBox(width: 4),
        _buildLedItem(Icons.arrow_downward, isB, 'GERİ', Colors.amberAccent),
        const SizedBox(width: 4),
        _buildLedItem(Icons.arrow_back, isL, 'SOL', Colors.greenAccent),
        const SizedBox(width: 4),
        _buildLedItem(Icons.arrow_forward, isR, 'SAĞ', Colors.greenAccent),
      ],
    );
  }

  Widget _buildLedItem(IconData icon, bool active, String tooltip, Color activeColor, {double size = 16}) {
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(size > 14 ? 6 : 4),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? activeColor : Colors.grey.withValues(alpha: 0.2),
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: size,
          color: active ? activeColor : Colors.grey[500],
        ),
      ),
    );
  }

  // ==========================================
  // BİLEŞEN: ACİL DURDURMA (E-STOP) BUTONU
  // ==========================================
  Widget _buildEmergencyStopButton({bool compact = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _connectedDevice != null ? _emergencyStop : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[400],
          elevation: 4,
          shadowColor: Colors.red.withValues(alpha: 0.5),
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 14, horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.dangerous, size: compact ? 20 : 24, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'ACİL STOP (E-STOP)',
                style: TextStyle(
                  fontSize: compact ? 12 : 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // BİLEŞEN: HIZLI AKSİYON ÇUBUĞU (FAR, KORNA, VİTES)
  // ==========================================
  Widget _buildQuickActionBar({bool isLandscape = false}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Far (LED) & Korna
            Row(
              children: [
                // Far (LED) Butonu
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _connectedDevice != null ? _toggleLED : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ledOn ? Colors.amber[700] : Colors.grey[300],
                      foregroundColor: _ledOn ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: _ledOn ? 4 : 1,
                      shadowColor: _ledOn ? Colors.amber : Colors.transparent,
                    ),
                    icon: Icon(
                      _ledOn ? Icons.light_mode : Icons.light_mode_outlined,
                      size: 20,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _ledOn ? 'FAR AÇIK' : 'FAR KAPALI',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Korna Butonu
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _connectedDevice != null
                        ? (_hornActive ? null : _activateHorn)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hornActive ? Colors.deepOrange : Colors.orange[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.volume_up, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _hornActive ? 'ÇALIYOR...' : 'KORNA',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Row 2: Vites / Hız Hazır Ayarları (Eco / Normal / Sport)
            Row(
              children: [
                Expanded(
                  child: _buildGearButton(
                    label: 'ECO',
                    sub: '%33',
                    speedVal: _commandConfig.speedLow,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildGearButton(
                    label: 'NORMAL',
                    sub: '%66',
                    speedVal: _commandConfig.speedMedium,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildGearButton(
                    label: 'SPORT',
                    sub: '%100',
                    speedVal: _commandConfig.speedHigh,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    _speedSliderExpanded ? Icons.tune : Icons.tune_outlined,
                    color: Colors.blue,
                    size: 20,
                  ),
                  tooltip: 'Hassas Hız Ayarı',
                  onPressed: () => setState(() => _speedSliderExpanded = !_speedSliderExpanded),
                ),
              ],
            ),

            // Expandable fine-tuning slider
            if (_speedSliderExpanded) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Hassas Gaz (0-255):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('$_speed', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
              Slider(
                value: _speed.toDouble(),
                min: 0,
                max: 255,
                divisions: 25,
                label: '$_speed',
                onChanged: _connectedDevice != null ? (val) => _setSpeed(val.toInt()) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGearButton({
    required String label,
    required String sub,
    required int speedVal,
    required MaterialColor color,
    bool compact = false,
  }) {
    final isSelected = (_speed - speedVal).abs() < 25;

    return InkWell(
      onTap: _connectedDevice != null ? () => _setSpeed(speedVal) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8, horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                sub,
                style: TextStyle(
                  fontSize: compact ? 8 : 9,
                  color: isSelected ? color[700] : Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // BİLEŞEN: D-PAD / JOYSTICK SEÇİCİ
  // ==========================================
  Widget _buildControllerModeSwitcher({bool compact = false}) {
    Widget dpadBtn = GestureDetector(
      onTap: () => setState(() => _controlMode = 0),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 4 : 8,
          horizontal: compact ? 8 : 0,
        ),
        decoration: BoxDecoration(
          color: _controlMode == 0 ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 6 : 8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(
              Icons.apps,
              color: _controlMode == 0 ? Colors.white : Colors.grey,
              size: compact ? 14 : 16,
            ),
            const SizedBox(width: 4),
            Text(
              'D-Pad',
              style: TextStyle(
                color: _controlMode == 0 ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: compact ? 10 : 12,
              ),
            ),
          ],
        ),
      ),
    );

    Widget joystickBtn = GestureDetector(
      onTap: () => setState(() => _controlMode = 1),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 4 : 8,
          horizontal: compact ? 8 : 0,
        ),
        decoration: BoxDecoration(
          color: _controlMode == 1 ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 6 : 8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(
              Icons.sports_esports,
              color: _controlMode == 1 ? Colors.white : Colors.grey,
              size: compact ? 14 : 16,
            ),
            const SizedBox(width: 4),
            Text(
              'Joystick',
              style: TextStyle(
                color: _controlMode == 1 ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: compact ? 10 : 12,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: compact
            ? [dpadBtn, const SizedBox(width: 2), joystickBtn]
            : [
                Expanded(child: dpadBtn),
                const SizedBox(width: 4),
                Expanded(child: joystickBtn),
              ],
      ),
    );
  }

  // ==========================================
  // BİLEŞEN: BAĞLANTI DURUM KARTI
  // ==========================================
  Widget _buildConnectionCard() {
    final stats = ConnectionStats();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _connectedDevice != null ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_connectedDevice != null ? Colors.green : Colors.red)
                            .withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _connectedDevice != null
                            ? _connectedDevice!.name
                            : 'Bağlı Değil',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _connectedDevice != null
                            ? _connectedDevice!.address
                            : 'Araca bağlanmak için dokunun',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontFamily: _connectedDevice != null ? 'monospace' : null,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _connectedDevice != null ? _disconnectDevice : _selectDevice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _connectedDevice != null ? Colors.red[400] : Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    _connectedDevice != null ? 'Kes' : 'Bağlan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (_connectedDevice != null) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(Icons.timer, 'Süre', stats.connectionTimeString),
                  _buildStatItem(Icons.send, 'Komut', '${stats.commandsSent}'),
                  _buildStatItem(Icons.percent, 'Başarı', '${stats.successRate.toStringAsFixed(1)}%'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.blue),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
      ],
    );
  }

  void _showControllerHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎮 Kontroller Rehberi'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• D-Pad: 4 yönlü klasik bas-tut kontrolü.'),
              SizedBox(height: 6),
              Text('• Joystick: 360 derece hassas analog kontrol.'),
              SizedBox(height: 6),
              Text('• ACİL STOP: Her durumda aracı anında durdurur.'),
              SizedBox(height: 6),
              Text('• Far & Korna: Sürüş ekranından ayrılmadan anlık kontrol.'),
              SizedBox(height: 6),
              Text('• Yatay Mod: Telefonu yatay çevirerek tam ekran gamepad kokpitine geçebilirsiniz!'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  void _showCommandReferenceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Komut Referansı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDialogRow('İleri', _commandConfig.forward),
              _buildDialogRow('Geri', _commandConfig.backward),
              _buildDialogRow('Sol', _commandConfig.left),
              _buildDialogRow('Sağ', _commandConfig.right),
              _buildDialogRow('Dur', _commandConfig.stop),
              _buildDialogRow('Far Aç', _commandConfig.ledOn),
              _buildDialogRow('Far Kapat', _commandConfig.ledOff),
              _buildDialogRow('Korna', _commandConfig.horn),
              _buildDialogRow('Hız Eco', 'V${_commandConfig.speedLow}'),
              _buildDialogRow('Hız Normal', 'V${_commandConfig.speedMedium}'),
              _buildDialogRow('Hız Sport', 'V${_commandConfig.speedHigh}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openCommandSettings();
            },
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Düzenle'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
