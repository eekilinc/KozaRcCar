import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/command_config.dart';
import '../services/bluetooth_service.dart';
import '../services/connection_stats.dart';
import '../services/sound_service.dart';
import '../widgets/dpad_controller.dart';
import '../widgets/joystick_controller.dart';
import 'command_settings_page.dart';
import 'device_selection_page.dart';
import 'about_page.dart';
import 'settings_page.dart';

/// Main RC car controller page
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
  int _controlMode = 0; // 0: D-Pad, 1: Joystick, 2: Extra Features
  int _commandCount = 0;
  bool _isMonitoring = false; // Track if monitoring is active
  int _disconnectCount = 0; // Counter for debouncing
  static const int _disconnectThreshold = 3; // Need 3 consecutive failures before disconnect
  
  // Extra control features
  bool _ledOn = false;
  int _speed = 128; // 0-255
  bool _hornActive = false;

  @override
  void initState() {
    super.initState();
    _loadCommandConfig();
  }

  void _startMonitoring() {
    // Monitoring disabled - connection is checked via command failures
    _isMonitoring = false;
  }

  void _stopMonitoring() {
    _isMonitoring = false;
  }

  void _monitorConnectionState() {
    // Monitoring disabled - connection is checked via command failures
  }

  void _handleDisconnection() {
    if (!mounted) return;
    
    _stopMonitoring();
    _disconnectCount = 0; // Reset counter
    
    final stats = ConnectionStats();
    stats.endConnection();
    _bluetoothService.disconnect();

    setState(() {
      _connectedDevice = null;
    });

    // Show snackbar
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
      print('Device selected: ${device.name}');
      
      // Start connection stats tracking
      final stats = ConnectionStats();
      stats.startConnection();
      
      setState(() {
        _connectedDevice = device;
      });
      
      // Connection established, user can now use controls
      // Monitoring will start only if commands fail
      _disconnectCount = 0;
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
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

  Future<void> _sendCommand(String command) async {
    if (_connectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cihaz bağlı değil'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final soundService = SoundService();
    final stats = ConnectionStats();
    final success = await _bluetoothService.sendCommand(command);
    
    // Record command in stats
    stats.recordCommandSent(success);
    
    // Play sound feedback asynchronously without blocking command throughput
    if (soundService.soundEnabled) {
      soundService.playCommandSound();
    }
    
    if (success) {
      // Haptic feedback
      HapticFeedback.mediumImpact();
      setState(() {
        _lastSentCommand = command;
        _commandCount++;
      });
    } else {
      // Command failed - likely connection lost
      _disconnectCount++;
      if (_disconnectCount >= 3 && mounted) {
        _handleDisconnection();
      }
    }
  }

  Future<void> _disconnectDevice() async {
    final stats = ConnectionStats();
    stats.endConnection();
    
    _stopMonitoring();
    await _bluetoothService.disconnect();
    setState(() {
      _connectedDevice = null;
      _lastSentCommand = '';
      _commandCount = 0;
      _ledOn = false;
      _speed = 128;
    });
  }

  // LED Işık Kontrol
  Future<void> _toggleLED() async {
    if (_connectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cihaz bağlı değil'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final command = _ledOn ? _commandConfig.ledOff : _commandConfig.ledOn;
    final success = await _bluetoothService.sendCommand(command);
    if (success) {
      // Haptic feedback
      HapticFeedback.mediumImpact();
      setState(() {
        _ledOn = !_ledOn;
        _lastSentCommand = command;
        _commandCount++;
      });
    }
  }

  // Hız Ayarı
  Future<void> _setSpeed(int speed) async {
    if (_connectedDevice == null) return;

    setState(() => _speed = speed);

    // Hızı komut olarak gönder (V + 0-255 değeri)
    final command = 'V${speed.toString().padLeft(3, '0')}';
    final success = await _bluetoothService.sendCommand(command);
    if (success) {
      // Light haptic feedback for speed changes
      HapticFeedback.lightImpact();
      setState(() {
        _lastSentCommand = command;
        _commandCount++;
      });
    }
  }

  // Korna
  Future<void> _activateHorn() async {
    if (_connectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cihaz bağlı değil'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() => _hornActive = true);
    await _bluetoothService.sendCommand(_commandConfig.horn);
    
    // Strong haptic feedback for horn
    await HapticFeedback.heavyImpact();

    setState(() {
      _lastSentCommand = _commandConfig.horn;
      _commandCount++;
      _hornActive = false;
    });
  }

  void _showControllerHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎮 Kontroller Rehberi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // D-Pad Section
              _buildHelpSection(
                title: '↑↓←→ D-Pad Kontrolü',
                description: 'Dört yönlü hareket kontrolü',
                details: [
                  '↑ Yukarı tuşuna basılı tutun = İleri git',
                  '↓ Aşağı tuşuna basılı tutun = Geri git',
                  '← Sol tuşuna basılı tutun = Sola dön',
                  '→ Sağ tuşuna basılı tutun = Sağa dön',
                  '💡 İpucu: Diagonal hareket için iki tuşa birden basın',
                ],
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              
              // Joystick Section
              _buildHelpSection(
                title: '🕹️ Joystick Kontrolü',
                description: 'Analog joystick hareket sistemi',
                details: [
                  'Parmağınızı sürükleyin = Joystick noktasını hareket ettirin',
                  'Yukarı sürükleme = İleri',
                  'Aşağı sürükleme = Geri',
                  'Sol sürükleme = Sola dön',
                  'Sağ sürükleme = Sağa dön',
                  '💡 Analog kontrolü: Sürükleme mesafesi = hız',
                ],
                color: Colors.green,
              ),
              const SizedBox(height: 16),

              // Instant Mode Section
              _buildHelpSection(
                title: '⚡ Instant Mode',
                description: 'Hızlı reaksiyonlu kontrol modu',
                details: [
                  'Parmak kaldırıldığında komut gönderilir',
                  'Daha duyarlı ve hızlı yanıt verir',
                  'Video oyunu oynarken gibi hissettirir',
                  'Pil tüketimi: YÜKSEK',
                ],
                color: Colors.orange,
              ),
              const SizedBox(height: 16),

              // Extra Features Section
              _buildHelpSection(
                title: '⚙️ Ekstra Kontroller',
                description: 'İnce ayarlamalar',
                details: [
                  '💡 Işık: Ön/Arka ışıkları aç-kapat',
                  '🏎️ Hız: Hareket hızını 0-100% ayarla',
                  '📣 Korna: Sese veya uyarı sinyaline',
                  '🎯 Hazır Hızlar: Düşük, Orta, Yüksek butonları',
                ],
                color: Colors.purple,
              ),
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

  Widget _buildHelpSection({
    required String title,
    required String description,
    required List<String> details,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          ...details.map((detail) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              detail,
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
          )).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
            icon: const Icon(Icons.help_outline),
            onPressed: _showControllerHelpDialog,
            tooltip: 'Kontroller Hakkında',
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Ayarlar'),
                onTap: () {
                  _openSettings();
                },
              ),
              PopupMenuItem(
                child: const Text('Hakkımda'),
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
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Connection status card
              _buildConnectionCard(),
              const SizedBox(height: 16),

              // Tab selector (D-Pad / Joystick / Extra Features)
              _buildControlModeSelector(),
              const SizedBox(height: 16),

              // Show selected tab content
              if (_controlMode == 0)
                // D-Pad Tab
                DPadController(
                  onCommand: _sendCommand,
                  commandConfig: _commandConfig,
                  size: 200,
                )
              else if (_controlMode == 1)
                // Joystick Tab
                JoystickController(
                  onCommand: _sendCommand,
                  commandConfig: _commandConfig,
                  size: 220,
                )
              else
                // Extra Features Tab
                _buildExtraControls(),

              const SizedBox(height: 20),

              // Command info
              _buildCommandInfo(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCommandReferenceDialog,
        tooltip: 'Komut Referansı',
        backgroundColor: Colors.blue,
        child: const Icon(Icons.info_outline),
      ),
    );
  }

  Widget _buildConnectionCard() {
    final stats = ConnectionStats();
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _connectedDevice != null
                            ? 'Bağlı'
                            : 'Bağlı Değil',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_connectedDevice != null)
                        Text(
                          _connectedDevice!.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (_connectedDevice != null)
                        Text(
                          _connectedDevice!.address,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontFamily: 'monospace',
                          ),
                        ),
                      if (_connectedDevice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.signal_cellular_4_bar, size: 14, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Bağlantı: Mükemmel',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _connectedDevice != null
                      ? _disconnectDevice
                      : _selectDevice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _connectedDevice != null
                        ? Colors.red[400]
                        : Colors.blue,
                  ),
                  child: Text(
                    _connectedDevice != null ? 'Bağlantıyı Kes' : 'Bağlan',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            // Connection stats - show only if connected
            if (_connectedDevice != null) ...[
              const SizedBox(height: 12),
              Divider(color: Colors.grey[300]),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.timer,
                    label: 'Bağlantı Süresi',
                    value: stats.connectionTimeString,
                  ),
                  _buildStatItem(
                    icon: Icons.send,
                    label: 'Komut Gönderilen',
                    value: '${stats.commandsSent}',
                  ),
                  _buildStatItem(
                    icon: Icons.percent,
                    label: 'Başarı Oranı',
                    value: '${stats.successRate.toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildControlModeSelector() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seçim',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // D-Pad Tab
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _controlMode = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _controlMode == 0 ? Colors.blue : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.apps,
                            color: _controlMode == 0 ? Colors.white : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'D-Pad',
                            style: TextStyle(
                              color: _controlMode == 0 ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Joystick Tab
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _controlMode = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _controlMode == 1 ? Colors.blue : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videogame_asset,
                            color: _controlMode == 1 ? Colors.white : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Joystick',
                            style: TextStyle(
                              color: _controlMode == 1 ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Extra Features Tab
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _controlMode = 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _controlMode == 2 ? Colors.blue : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tune,
                            color: _controlMode == 2 ? Colors.white : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Özellik',
                            style: TextStyle(
                              color: _controlMode == 2 ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandInfo() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Son Komut',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _lastSentCommand.isEmpty
                      ? 'Hiçbiri'
                      : '"$_lastSentCommand"',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _lastSentCommand.isEmpty
                        ? Colors.grey
                        : Colors.blue,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'Toplam: $_commandCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Extra Controls Widget (LED, Speed, Horn)
  Widget _buildExtraControls() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Title
            Text(
              'Ekstra Kontroller',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),

            // LED Light Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.light_mode,
                      color: _ledOn ? Colors.amber : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Işık'),
                        Text(
                          _ledOn ? 'Açık' : 'Kapalı',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _toggleLED,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ledOn ? Colors.amber : Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _ledOn ? 'KAP' : 'AÇ',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Speed Control Slider
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed, size: 28),
                        const SizedBox(width: 12),
                        const Text('Hız Kontrol'),
                      ],
                    ),
                    Text(
                      '${(_speed * 100 ~/ 255)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _speed.toDouble(),
                  min: 0,
                  max: 255,
                  divisions: 25,
                  label: '${(_speed * 100 ~/ 255)}%',
                  onChanged: (value) => _setSpeed(value.toInt()),
                ),
                const SizedBox(height: 8),
                // Speed Gauge/Meter
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _speed / 255.0,
                    minHeight: 8,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _speed < 85
                          ? Colors.green
                          : _speed < 170
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Speed markers
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    Text('25%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    Text('50%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    Text('75%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    Text('100%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  ],
                ),
                const SizedBox(height: 8),
                // Speed Preset Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _setSpeed(_commandConfig.speedLow),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _speed == _commandConfig.speedLow 
                            ? Colors.green 
                            : Colors.grey[400],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text(
                          'Düşük',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _setSpeed(_commandConfig.speedMedium),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _speed == _commandConfig.speedMedium 
                            ? Colors.orange 
                            : Colors.grey[400],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text(
                          'Orta',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _setSpeed(_commandConfig.speedHigh),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _speed == _commandConfig.speedHigh 
                            ? Colors.red 
                            : Colors.grey[400],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text(
                          'Yüksek',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Horn Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _hornActive ? null : _activateHorn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hornActive ? Colors.red[300] : Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.volume_up, color: Colors.white),
                label: Text(
                  _hornActive ? 'KORNA ÇALIYOR...' : 'KORNA ÇAL',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // }

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
              _buildDialogSection('Hareket Komutları', [
                ('İleri', _commandConfig.forward),
                ('Geri', _commandConfig.backward),
                ('Sol', _commandConfig.left),
                ('Sağ', _commandConfig.right),
                ('Dur', _commandConfig.stop),
              ]),
              const SizedBox(height: 16),
              _buildDialogSection('Ek Kontroller', [
                ('LED Aç', _commandConfig.ledOn),
                ('LED Kapat', _commandConfig.ledOff),
                ('Korna', _commandConfig.horn),
              ]),
              const SizedBox(height: 16),
              _buildDialogSection('Hız Presetleri', [
                ('Düşük', 'V${_commandConfig.speedLow.toString().padLeft(3, '0')}'),
                ('Orta', 'V${_commandConfig.speedMedium.toString().padLeft(3, '0')}'),
                ('Yüksek', 'V${_commandConfig.speedHigh.toString().padLeft(3, '0')}'),
              ]),
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
            icon: const Icon(Icons.edit),
            label: const Text('Değiştir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogSection(String title, List<(String label, String value)> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.$1,
                style: const TextStyle(fontSize: 12),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.grey[400]!,
                  ),
                ),
                child: Text(
                  '"${item.$2}"',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        )).toList(),
      ],
    );
  }
}


