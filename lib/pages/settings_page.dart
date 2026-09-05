import 'package:flutter/material.dart';
import '../models/command_config.dart';
import '../services/sound_service.dart';
import '../services/theme_service.dart';
import 'command_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Theme Section
            _buildSectionTitle('Tema Ayarları'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          themeService.currentTheme == ThemeMode.dark
                              ? Icons.dark_mode
                              : Icons.light_mode,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Tema Seçimi',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(label: Text('Açık'), value: ThemeMode.light),
                        ButtonSegment(label: Text('Koyu'), value: ThemeMode.dark),
                        ButtonSegment(label: Text('Sistem'), value: ThemeMode.system),
                      ],
                      selected: {themeService.currentTheme},
                      onSelectionChanged: (Set<ThemeMode> newSelection) async {
                        await themeService.setTheme(newSelection.first);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // Sound Section
            _buildSectionTitle('Ses & Bildirim'),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                secondary: Icon(
                  SoundService().soundEnabled ? Icons.volume_up : Icons.volume_off,
                  color: Colors.blue,
                ),
                title: const Text('Komut Ses Efektleri'),
                subtitle: const Text('Komut gönderildiğinde sesli geri bildirim ver'),
                value: SoundService().soundEnabled,
                onChanged: (bool value) async {
                  await SoundService().setSoundEnabled(value);
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 24),

            // Controls & Commands Section
            _buildSectionTitle('Kontrol & Komutlar'),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune, color: Colors.blue),
                title: const Text('Komut Yapılandırması'),
                subtitle: const Text('İleri, Geri, Sol, Sağ, LED ve Korna komutlarını özelleştir'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final currentConfig = await CommandConfig.loadFromPrefs();
                  if (!context.mounted) return;
                  final newConfig = await Navigator.push<CommandConfig>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CommandSettingsPage(initialConfig: currentConfig),
                    ),
                  );
                  if (newConfig != null) {
                    await newConfig.saveToPrefs();
                  }
                },
              ),
            ),
            const SizedBox(height: 32),
            
            // Close Button
            Center(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Kapat'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.blue,
      ),
    );
  }
}
