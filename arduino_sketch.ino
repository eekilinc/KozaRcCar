/*
 * RC Car Controller Arduino Sketch for HC-06 Bluetooth Module
 * 
 * This sketch controls a two-wheel RC car (or tank) using Bluetooth
 * commands received from the Flutter mobile application.
 * 
 * Hardware Setup:
 * - HC-06 Bluetooth Module:
 *   - VCC -> 5V
 *   - GND -> GND
 *   - TX -> Arduino RX (Pin 0) or Software Serial
 *   - RX -> Arduino TX (Pin 1) or Software Serial
 * 
 * - Motor Driver (L298N or similar):
 *   - IN1 -> Arduino Pin 5
 *   - IN2 -> Arduino Pin 6
 *   - IN3 -> Arduino Pin 9
 *   - IN4 -> Arduino Pin 10
 *   - GND -> Arduino GND
 *   - +5V -> Arduino 5V (or separate power)
 * 
 * Default Commands:
 * - 'F' or 'f' = Forward
 * - 'B' or 'b' = Backward
 * - 'L' or 'l' = Left (Turn left or strafe left)
 * - 'R' or 'r' = Right (Turn right or strafe right)
 * - 'S' or 's' = Stop
 */

#include <SoftwareSerial.h>

// Software Serial for HC-06 (RX, TX)
// Adjust pins if using different Arduino
SoftwareSerial hc06(8, 7); // RX on pin 8, TX on pin 7

// Motor control pins
const int motor1Pin1 = 5;  // Left motor direction 1
const int motor1Pin2 = 6;  // Left motor direction 2
const int motor2Pin1 = 9;  // Right motor direction 1
const int motor2Pin2 = 10; // Right motor direction 2

// Extra control pins
const int ledPin = 11;      // LED light
const int hornPin = 12;     // Buzzer/Horn
const int speedPin = 3;     // PWM for speed control (use PWM-capable pin)

// Motor speed (PWM value: 0-255)
// Motor speed (PWM value: 0-255)
int motorSpeed = 255; // Maximum speed (can be changed dynamically)

// Safety Watchdog & Non-blocking Horn
unsigned long lastCommandTime = 0;
const unsigned long WATCHDOG_TIMEOUT = 1500; // Auto-stop if no command received in 1.5s while moving
bool isMoving = false;

bool hornActive = false;
unsigned long hornStartTime = 0;
const unsigned long HORN_DURATION = 500; // 500ms horn pulse

// Function declarations
void processCommand(String cmd);
void processSingleChar(char moveCmd);
void moveForward();
void moveBackward();
void turnLeft();
void turnRight();
void stopMotors();
void activateHorn();
void checkHorn();

void setup() {
  // Initialize serial communication with computer (for debugging)
  Serial.begin(9600);
  
  // Initialize software serial for HC-06 (baud rate: 9600)
  hc06.begin(9600);
  
  // Set motor pins as outputs
  pinMode(motor1Pin1, OUTPUT);
  pinMode(motor1Pin2, OUTPUT);
  pinMode(motor2Pin1, OUTPUT);
  pinMode(motor2Pin2, OUTPUT);
  
  // Set extra control pins as outputs
  pinMode(ledPin, OUTPUT);
  pinMode(hornPin, OUTPUT);
  pinMode(speedPin, OUTPUT);
  
  // Initial states
  digitalWrite(ledPin, LOW);    // LED off
  digitalWrite(hornPin, LOW);   // Horn off
  
  // Stop motors initially
  stopMotors();
  
  Serial.println("RC Car Controller Initialized with Watchdog Safety");
  Serial.println("Waiting for Bluetooth commands...");
}

void loop() {
  // Check if data is available from HC-06
  while (hc06.available()) {
    char c = (char)hc06.read();
    
    // Ignore whitespace and line endings
    if (c == '\r' || c == '\n' || c == ' ') continue;
    
    char lowerC = tolower(c);
    
    // Single character movement commands (F, B, L, R, S)
    // Note: 'L' followed by digit (L0, L1) is handled as multi-char command below
    if (lowerC == 'f' || lowerC == 'b' || lowerC == 'r' || lowerC == 's') {
      processSingleChar(lowerC);
    } else if (c == 'l' || c == 'L') {
      // Check if it's LED command (L0 / L1) or Left command (L)
      delay(5);
      if (hc06.available() && (hc06.peek() == '0' || hc06.peek() == '1')) {
        char val = (char)hc06.read();
        String cmd = "L";
        cmd += val;
        processCommand(cmd);
      } else {
        processSingleChar('l');
      }
    } else {
      // Multi-character command (e.g. V128, H1)
      String multiCmd = "";
      multiCmd += c;
      unsigned long readStart = millis();
      while (millis() - readStart < 30) {
        if (hc06.available()) {
          char nextC = (char)hc06.read();
          if (nextC == '\r' || nextC == '\n') break;
          multiCmd += nextC;
        }
      }
      processCommand(multiCmd);
    }
  }

  // Safety Watchdog: stop motors if signal is lost while moving
  if (isMoving && (millis() - lastCommandTime > WATCHDOG_TIMEOUT)) {
    stopMotors();
    Serial.println("⚠️ Watchdog Triggered: Signal lost, motors safely stopped.");
  }

  // Non-blocking horn check
  checkHorn();
}

void processSingleChar(char moveCmd) {
  lastCommandTime = millis();
  switch(moveCmd) {
    case 'f':
      isMoving = true;
      moveForward();
      break;
    case 'b':
      isMoving = true;
      moveBackward();
      break;
    case 'l':
      isMoving = true;
      turnLeft();
      break;
    case 'r':
      isMoving = true;
      turnRight();
      break;
    case 's':
      isMoving = false;
      stopMotors();
      break;
  }
}

void processCommand(String cmd) {
  cmd.trim();
  if (cmd.length() == 0) return;
  
  lastCommandTime = millis();
  
  // LED Control (L0 = OFF, L1 = ON)
  if (cmd.startsWith("L") || cmd.startsWith("l")) {
    String value = cmd.substring(1);
    if (value == "0") {
      digitalWrite(ledPin, LOW);
      Serial.println("LED turned OFF");
    } else if (value == "1") {
      digitalWrite(ledPin, HIGH);
      Serial.println("LED turned ON");
    }
  }
  // Speed Control (V000-V255)
  else if (cmd.startsWith("V") || cmd.startsWith("v")) {
    String speedStr = cmd.substring(1);
    int speed = speedStr.toInt();
    
    if (speed >= 0 && speed <= 255) {
      motorSpeed = speed;
      Serial.print("Motor speed set to: ");
      Serial.println(motorSpeed);
    }
  }
  // Horn Control (H1 = activate)
  else if (cmd.equalsIgnoreCase("H1") || cmd.equalsIgnoreCase("H")) {
    activateHorn();
  }
  else {
    Serial.print("Unknown command: ");
    Serial.println(cmd);
  }
}

void moveForward() {
  analogWrite(motor1Pin1, motorSpeed);
  analogWrite(motor1Pin2, 0);
  analogWrite(motor2Pin1, motorSpeed);
  analogWrite(motor2Pin2, 0);
  Serial.println("Moving Forward");
}

void moveBackward() {
  analogWrite(motor1Pin1, 0);
  analogWrite(motor1Pin2, motorSpeed);
  analogWrite(motor2Pin1, 0);
  analogWrite(motor2Pin2, motorSpeed);
  Serial.println("Moving Backward");
}

void turnLeft() {
  analogWrite(motor1Pin1, 0);
  analogWrite(motor1Pin2, 0);
  analogWrite(motor2Pin1, motorSpeed);
  analogWrite(motor2Pin2, 0);
  Serial.println("Turning Left");
}

void turnRight() {
  analogWrite(motor1Pin1, motorSpeed);
  analogWrite(motor1Pin2, 0);
  analogWrite(motor2Pin1, 0);
  analogWrite(motor2Pin2, 0);
  Serial.println("Turning Right");
}

void stopMotors() {
  isMoving = false;
  analogWrite(motor1Pin1, 0);
  analogWrite(motor1Pin2, 0);
  analogWrite(motor2Pin1, 0);
  analogWrite(motor2Pin2, 0);
  Serial.println("Motors Stopped");
}

void activateHorn() {
  digitalWrite(hornPin, HIGH);
  hornActive = true;
  hornStartTime = millis();
  Serial.println("Horn activated");
}

void checkHorn() {
  if (hornActive && (millis() - hornStartTime >= HORN_DURATION)) {
    digitalWrite(hornPin, LOW);
    hornActive = false;
    Serial.println("Horn deactivated");
  }
}

