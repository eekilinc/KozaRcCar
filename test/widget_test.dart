import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koza_rc_car/models/command_config.dart';
import 'package:koza_rc_car/pages/command_settings_page.dart';

void main() {
  testWidgets('CommandSettingsPage renders all fields and default values', (WidgetTester tester) async {
    final initialConfig = CommandConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: CommandSettingsPage(initialConfig: initialConfig),
      ),
    );

    // Verify AppBar title
    expect(find.text('Komut Ayarları'), findsOneWidget);

    // Verify section titles
    expect(find.text('Hareket Komutları'), findsOneWidget);
    expect(find.text('Ek Kontroller'), findsOneWidget);
    expect(find.text('Hız Hazır Ayarları (0-255)'), findsOneWidget);

    // Verify fields exist with default values
    expect(find.text('İleri Komutu'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);

    // Verify action buttons
    expect(find.text('İptal'), findsOneWidget);
    expect(find.text('Kaydet'), findsOneWidget);
  });
}
