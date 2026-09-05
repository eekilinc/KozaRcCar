import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TerminalMessage {
  final DateTime timestamp;
  final String text;
  final bool isOutgoing;

  TerminalMessage({
    required this.timestamp,
    required this.text,
    this.isOutgoing = true,
  });
}

/// A dark hacker/telemetry styled serial monitor bottom sheet
class SerialMonitorSheet extends StatefulWidget {
  final Future<bool> Function(String) onSendCommand;
  final List<TerminalMessage> messages;
  final VoidCallback onClearMessages;

  const SerialMonitorSheet({
    Key? key,
    required this.onSendCommand,
    required this.messages,
    required this.onClearMessages,
  }) : super(key: key);

  @override
  State<SerialMonitorSheet> createState() => _SerialMonitorSheetState();
}

class _SerialMonitorSheetState extends State<SerialMonitorSheet> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  final List<String> _quickCommands = [
    'F', 'B', 'L', 'R', 'S', 'L1', 'L0', 'H1', 'V255', 'V170', 'V85'
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;

    setState(() => _isSending = true);
    HapticFeedback.lightImpact();
    await widget.onSendCommand(trimmed);
    _inputController.clear();
    setState(() => _isSending = false);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF10141D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.terminal, color: Colors.greenAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seri Monitör & Terminal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Canlı Bluetooth komut akışı (9600 baud)',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, color: Colors.grey, size: 20),
                    tooltip: 'Konsolu Temizle',
                    onPressed: widget.onClearMessages,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF222B3D)),

            // Terminal Console Output
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E283C)),
                ),
                child: widget.messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.code, color: Colors.grey[700], size: 36),
                            const SizedBox(height: 8),
                            Text(
                              'Henüz komut akışı yok...\nAşağıdan hızlı komut seçebilir veya yazabilirsiniz.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: widget.messages.length,
                        itemBuilder: (context, index) {
                          final msg = widget.messages[index];
                          final timeStr =
                              '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}:${msg.timestamp.second.toString().padLeft(2, '0')}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '[$timeStr] ',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  msg.isOutgoing ? 'TX >> ' : 'RX << ',
                                  style: TextStyle(
                                    color: msg.isOutgoing ? Colors.cyanAccent : Colors.amberAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    msg.text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),

            // Quick command chips
            SizedBox(
              height: 36,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _quickCommands.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cmd = _quickCommands[index];
                  return ActionChip(
                    label: Text(
                      cmd,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    backgroundColor: const Color(0xFF162032),
                    side: const BorderSide(color: Color(0xFF263550)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    onPressed: () => _send(cmd),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            // Manual command input bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: 'Komut gir (örn: F, V200, H1)...',
                        hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF162032),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF263550)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF263550)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.cyanAccent),
                        ),
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSending ? null : () => _send(_inputController.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
