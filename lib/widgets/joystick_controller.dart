import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import '../models/command_config.dart';

/// Joystick controller widget with scroll prevention
class JoystickController extends StatefulWidget {
  final Function(String) onCommand;
  final CommandConfig commandConfig;
  final double size;
  final double deadzone;
  final bool showTitle;

  const JoystickController({
    Key? key,
    required this.onCommand,
    required this.commandConfig,
    this.size = 200,
    this.deadzone = 0.2,
    this.showTitle = true,
  }) : super(key: key);

  @override
  State<JoystickController> createState() => _JoystickControllerState();
}

class _JoystickControllerState extends State<JoystickController> {
  late Offset _joystickPosition;
  late Offset _centerPosition;
  bool _isPressed = false;
  bool _isPointerDown = false;
  String? _lastCommand;
  DateTime? _movementStartTime; // Track when movement started
  static const int _stabilizationDelayMs = 200; // Wait for movement to stabilize

  @override
  void initState() {
    super.initState();
    _centerPosition = Offset(widget.size / 2, widget.size / 2);
    _joystickPosition = _centerPosition;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle) ...[
          Text(
            'Joystick',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
        ],
        // Joystick with gesture detection - prevents scroll conflicts
        Listener(
          onPointerDown: (_) => _isPointerDown = true,
          onPointerUp: (_) => _isPointerDown = false,
          child: GestureDetector(
            onPanStart: (_) {
              setState(() => _isPressed = true);
              // Mark movement start time for stabilization
              _movementStartTime = DateTime.now();
            },
            onPanUpdate: (details) {
              _updateJoystickPosition(details.localPosition);
            },
            onPanEnd: (_) {
              setState(() {
                _isPressed = false;
                _joystickPosition = _centerPosition;
              });
              _movementStartTime = null; // Reset movement start time
              widget.onCommand(widget.commandConfig.stop);
              _lastCommand = null;
            },
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                // 3D Gradient background
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    Colors.grey[100]!,
                    Colors.grey[300]!,
                  ],
                ),
                border: Border.all(
                  color: Colors.grey[400]!,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(widget.size / 2),
                boxShadow: [
                  // Outer shadow with depth
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isPressed ? 0.5 : 0.2),
                    blurRadius: _isPressed ? 16 : 8,
                    offset: _isPressed ? const Offset(0, 8) : const Offset(0, 4),
                    spreadRadius: _isPressed ? 2 : 1,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Center circle
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.grey[500],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  // Direction indicators
                  CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: DirectionIndicatorPainter(widget.size),
                  ),
                  // Joystick thumb (control ball)
                  Positioned(
                    left: _joystickPosition.dx - 30,
                    top: _joystickPosition.dy - 30 + (_isPressed ? 4 : 0),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.3, -0.3),
                          colors: [
                            Colors.blue.shade300,
                            Colors.blue.shade600,
                            Colors.blue.shade800,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          // Inner highlight
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(-2, -2),
                          ),
                          // Main shadow
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.8),
                            blurRadius: 12,
                            spreadRadius: 3,
                          ),
                          // Drop shadow
                          BoxShadow(
                            color: Colors.black.withValues(alpha: _isPressed ? 0.4 : 0.3),
                            blurRadius: 10,
                            offset: _isPressed ? const Offset(0, 4) : const Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildStatusText(),
      ],
    );
  }

  void _updateJoystickPosition(Offset position) {
    final dx = position.dx - _centerPosition.dx;
    final dy = position.dy - _centerPosition.dy;
    final distance = sqrt(dx * dx + dy * dy);
    final maxDistance = widget.size / 2 - 25;

    late Offset newPosition;

    if (distance <= maxDistance) {
      newPosition = position;
    } else {
      final angle = atan2(dy, dx);
      newPosition = Offset(
        _centerPosition.dx + cos(angle) * maxDistance,
        _centerPosition.dy + sin(angle) * maxDistance,
      );
    }

    setState(() {
      _joystickPosition = newPosition;
    });

    // Check stabilization delay - wait for movement to stabilize
    if (_movementStartTime != null) {
      final timeSinceStart = DateTime.now().difference(_movementStartTime!).inMilliseconds;
      if (timeSinceStart < _stabilizationDelayMs) {
        // Movement not yet stabilized, don't send command
        return;
      }
    }

    // Calculate direction based on joystick position
    final normalizedDx = (newPosition.dx - _centerPosition.dx) / maxDistance;
    final normalizedDy = (newPosition.dy - _centerPosition.dy) / maxDistance;
    final distance2 = sqrt(normalizedDx * normalizedDx + normalizedDy * normalizedDy);

    late String command;
    
    if (distance2 < widget.deadzone) {
      // In deadzone, stop
      command = widget.commandConfig.stop;
    } else {
      // Determine primary direction
      final angle = atan2(normalizedDy, normalizedDx);
      final angleDegrees = (angle * 180 / pi + 360) % 360;

      if (angleDegrees < 45 || angleDegrees > 315) {
        command = widget.commandConfig.right;
      } else if (angleDegrees < 135) {
        command = widget.commandConfig.backward;
      } else if (angleDegrees < 225) {
        command = widget.commandConfig.left;
      } else {
        command = widget.commandConfig.forward;
      }
    }

    // Send command when direction changes
    if (command != _lastCommand) {
      widget.onCommand(command);
      _lastCommand = command;
    }
  }

  Widget _buildStatusText() {
    return Text(
      _lastCommand != null ? 'Komut: $_lastCommand' : 'Joystick\'i hareket ettir',
      style: TextStyle(
        fontSize: 14,
        color: _lastCommand != null ? Colors.blue : Colors.grey,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Custom painter for direction indicators
class DirectionIndicatorPainter extends CustomPainter {
  final double size;

  DirectionIndicatorPainter(this.size);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1;

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final radius = canvasSize.width / 2 - 30;

    // Draw crosshairs
    canvas.drawLine(
      Offset(center.dx - radius / 2, center.dy),
      Offset(center.dx + radius / 2, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius / 2),
      Offset(center.dx, center.dy + radius / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(DirectionIndicatorPainter oldDelegate) => false;
}
