import 'package:flutter/material.dart';
import '../models/command_config.dart';

/// D-Pad controller widget for directional control
class DPadController extends StatefulWidget {
  final Function(String) onCommand;
  final CommandConfig commandConfig;
  final double size;
  final bool showTitle;

  const DPadController({
    Key? key,
    required this.onCommand,
    required this.commandConfig,
    this.size = 200,
    this.showTitle = true,
  }) : super(key: key);

  @override
  State<DPadController> createState() => _DPadControllerState();
}

class _DPadControllerState extends State<DPadController> {
  String? _currentDirection;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final buttonSize = size / 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle) ...[
          Text(
            'D-Pad',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
        ],
        Column(
          children: [
            // Up button
            _buildDPadButton(
              label: '▲',
              direction: 'up',
              size: buttonSize,
              onPressed: () => _handleDirection('up'),
              onReleased: () => _handleDirection(null),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Left button
                _buildDPadButton(
                  label: '◄',
                  direction: 'left',
                  size: buttonSize,
                  onPressed: () => _handleDirection('left'),
                  onReleased: () => _handleDirection(null),
                ),
                SizedBox(width: buttonSize),
                // Right button
                _buildDPadButton(
                  label: '►',
                  direction: 'right',
                  size: buttonSize,
                  onPressed: () => _handleDirection('right'),
                  onReleased: () => _handleDirection(null),
                ),
              ],
            ),
            // Down button
            _buildDPadButton(
              label: '▼',
              direction: 'down',
              size: buttonSize,
              onPressed: () => _handleDirection('down'),
              onReleased: () => _handleDirection(null),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDPadButton({
    required String label,
    required String direction,
    required double size,
    required VoidCallback onPressed,
    required VoidCallback onReleased,
  }) {
    final isActive = _currentDirection == direction;

    return GestureDetector(
      onTapDown: (_) => onPressed(),
      onTapUp: (_) => onReleased(),
      onTapCancel: onReleased,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive
                ? [Colors.blue.shade700, Colors.blue.shade900]
                : [Colors.blue.shade400, Colors.blue.shade600],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isActive ? 0.6 : 0.3),
              blurRadius: isActive ? 12 : 6,
              offset: isActive ? const Offset(0, 6) : const Offset(0, 3),
              spreadRadius: isActive ? 1 : 0,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black54,
                  offset: const Offset(1, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleDirection(String? direction) {
    setState(() {
      _currentDirection = direction;
    });

    if (direction == null) {
      widget.onCommand(widget.commandConfig.stop);
    } else {
      switch (direction) {
        case 'up':
          widget.onCommand(widget.commandConfig.forward);
          break;
        case 'down':
          widget.onCommand(widget.commandConfig.backward);
          break;
        case 'left':
          widget.onCommand(widget.commandConfig.left);
          break;
        case 'right':
          widget.onCommand(widget.commandConfig.right);
          break;
      }
    }
  }
}
