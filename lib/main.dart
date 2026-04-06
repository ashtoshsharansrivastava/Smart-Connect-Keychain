import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart'; // Added for GPS

import 'telegram_service.dart';
import 'ble_scanner.dart'; // Imports your scanner!
import 'background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService(); // Starts your background task
  runApp(const SafetyKeychainApp());
}

class SafetyKeychainApp extends StatelessWidget {
  const SafetyKeychainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Safety Keeper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// =====================================================================
// 1. THE HOME SCREEN
// =====================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isConnected = false;
  String _deviceName = "No Device";

  // Progress Bar Variables for Manual Screen Button
  double _pressProgress = 0.0;
  Timer? _holdTimer;
  bool _isPressing = false;
  String _actionStatus = "Tap & Hold to Send Alert";
  Color _statusColor = Colors.deepPurple;

  // The Exact UUIDs from your ESP32
  final String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String TX_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    _listenToConnection();
  }

  void _listenToConnection() async {
    FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
      if (mounted) {
        setState(() {
          _isConnected =
              event.connectionState == BluetoothConnectionState.connected;
          _deviceName = _isConnected ? event.device.advName : "Disconnected";
        });
      }

      // The invisible pipeline listening to the hardware
      if (event.connectionState == BluetoothConnectionState.connected) {
        try {
          print(
            "BLE: Connected! Waiting 1 second for Android GATT to stabilize...",
          );
          // CRITICAL FIX: Give Android time to finish its internal connection process
          await Future.delayed(const Duration(seconds: 1));

          List<BluetoothService> services = await event.device
              .discoverServices();
          for (BluetoothService service in services) {
            if (service.uuid.toString() == SERVICE_UUID) {
              for (BluetoothCharacteristic c in service.characteristics) {
                if (c.uuid.toString() == TX_CHARACTERISTIC_UUID) {
                  print("BLE: Found the TX Pipeline! Subscribing...");

                  // NEW FLUTTER BLUE PUSH NOTIFICATION LISTENER
                  c.onValueReceived.listen((value) {
                    if (value.isNotEmpty) {
                      print("RAW BYTES FROM ESP32: $value");

                      // Safely Decode to bypass Ghost Bytes
                      String messageFromKeychain = String.fromCharCodes(value);
                      print("DECODED STRING: '$messageFromKeychain'");

                      // Decode specific signals ("1" for Love, "2" for SOS)
                      if (messageFromKeychain.contains("2")) {
                        _triggerTelegram(isSos: true);
                        if (mounted) {
                          setState(
                            () => _actionStatus =
                                "🚨 SOS TRIGGERED VIA KEYCHAIN! 🚨",
                          );
                        }
                      } else if (messageFromKeychain.contains("1")) {
                        _triggerTelegram(isSos: false);
                        if (mounted) {
                          setState(
                            () => _actionStatus = "Personal Message Sent 💙",
                          );
                        }
                      }
                    }
                  });

                  // FALLBACK LISTENER (Just in case the new pipeline drops it)
                  c.lastValueStream.listen((value) {
                    if (value.isNotEmpty && !c.isNotifying) {
                      String fallbackMsg = String.fromCharCodes(value);
                      if (fallbackMsg.contains("2")) {
                        _triggerTelegram(isSos: true);
                        if (mounted) {
                          setState(
                            () => _actionStatus =
                                "🚨 SOS TRIGGERED VIA KEYCHAIN! 🚨",
                          );
                        }
                      } else if (fallbackMsg.contains("1")) {
                        _triggerTelegram(isSos: false);
                        if (mounted) {
                          setState(
                            () => _actionStatus = "Personal Message Sent 💙",
                          );
                        }
                      }
                    }
                  });

                  // Turn the notifications ON in Android
                  await c.setNotifyValue(true);
                  print("BLE: SUCCESS! Actively listening for button presses!");
                }
              }
            }
          }
        } catch (e) {
          debugPrint("Error subscribing to keychain: $e");
        }
      }
    });
  }

  // --- LIVE GPS LOCATION GETTER ---
  Future<String> _getLocationLink() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return "";

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return "";
    }
    if (permission == LocationPermission.deniedForever) return "";

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    // Creates a clickable Google Maps link!
    return "📍 Live Location: https://maps.google.com/?q=${position.latitude},${position.longitude}";
  }

  // --- APP SCREEN MANUAL TRIGGER LOGIC ---
  void _onPressStart(TapDownDetails details) {
    setState(() {
      _isPressing = true;
      _pressProgress = 0.0;
      _actionStatus = "Holding...";
      _statusColor = Colors.deepPurple;
    });

    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _pressProgress += 0.01;
        if (_pressProgress >= 0.4 && _pressProgress < 1.0) {
          _actionStatus = "Personal Alert Ready. Keep holding!";
          _statusColor = Colors.orange;
        } else if (_pressProgress >= 1.0) {
          _actionStatus = "🚨 SOS TRIGGERED! 🚨";
          _statusColor = Colors.redAccent;
          _holdTimer?.cancel();
          _triggerTelegram(isSos: true); // Fire Manual SOS
        }
      });
    });
  }

  void _onPressEnd() {
    _holdTimer?.cancel();
    if (_pressProgress >= 0.4 && _pressProgress < 1.0) {
      setState(() {
        _actionStatus = "Personal Message Sent 💙";
        _statusColor = Colors.green;
      });
      _triggerTelegram(isSos: false); // Fire Manual Personal
    } else if (_pressProgress < 0.4) {
      setState(() {
        _actionStatus = "Hold longer to send alert";
        _statusColor = Colors.deepPurple;
      });
    }

    setState(() {
      _isPressing = false;
      _pressProgress = 0.0;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isPressing) {
        setState(() {
          _actionStatus = "Tap & Hold to Send Alert";
          _statusColor = Colors.deepPurple;
        });
      }
    });
  }

  // --- THE MASTER TELEGRAM SENDER ---
  Future<void> _triggerTelegram({required bool isSos}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('botToken') ?? '';
    final chatId = prefs.getString('chatId') ?? '';

    // Grab your custom messages
    String message = isSos
        ? prefs.getString('sosMessage') ??
              '🚨 URGENT SOS! I need help immediately!'
        : prefs.getString('personalMessage') ??
              '💙 Just checking in. I am safe.';

    if (token.isNotEmpty && chatId.isNotEmpty) {
      // IF SOS IS TRIGGERED, ADD GOOGLE MAPS LINK
      if (isSos) {
        String locationLink = await _getLocationLink();
        if (locationLink.isNotEmpty) {
          message = "$message\n\n$locationLink";
        }
      }

      bool success = await TelegramService.sendMessage(
        botToken: token,
        chatId: chatId,
        message: message,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? "Alert Sent via Telegram!" : "Failed to send",
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Setup Telegram tokens in Settings first!"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- OPENS YOUR BLUETOOTH SCANNER UI ---
  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows the sheet to take up more screen space
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return BleScannerScreen(
          onDeviceConnected: (device) {
            Navigator.pop(context); // Close the sheet when connected
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Safety Keeper',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.settings,
              color: Colors.deepPurple,
              size: 28,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // BLUETOOTH CONNECTION PILL
            GestureDetector(
              onTap: _openScanner,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _isConnected
                        ? Colors.green[200]!
                        : Colors.orange[200]!,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bluetooth_connected,
                      color: _isConnected ? Colors.green : Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected
                          ? "Linked: $_deviceName"
                          : "Tap to Connect Device",
                      style: TextStyle(
                        color: _isConnected
                            ? Colors.green[800]
                            : Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // ACTION TEXT
            Text(
              _actionStatus,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _statusColor,
              ),
            ),
            const SizedBox(height: 20),

            // GIANT INTERACTIVE SHIELD
            GestureDetector(
              onTapDown: _onPressStart,
              onTapUp: (details) => _onPressEnd(),
              onTapCancel: _onPressEnd,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: CircularProgressIndicator(
                      value: _pressProgress,
                      strokeWidth: 12,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: _isPressing ? 190 : 200,
                    height: _isPressing ? 190 : 200,
                    decoration: BoxDecoration(
                      color: _isPressing
                          ? _statusColor.withValues(alpha: 0.8)
                          : Colors.deepPurple,
                      shape: BoxShape.circle,
                      boxShadow: _isPressing
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.deepPurple.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 80,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // INSTRUCTION FOOTER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildGuideStep("2 Sec", "Personal Msg", Colors.orange),
                  Container(height: 30, width: 2, color: Colors.grey[300]),
                  _buildGuideStep("5 Sec", "SOS + GPS", Colors.redAccent),
                ],
              ),
            ),

            const Spacer(),

            // BRANDING
            Container(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  const Text(
                    "Designed & Developed by",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Ashutosh",
                    style: TextStyle(
                      color: Colors.deepPurple[800],
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(String time, String action, Color color) {
    return Column(
      children: [
        Text(
          time,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(action, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

// =====================================================================
// 2. THE SETTINGS SCREEN (Where you store custom messages & tokens)
// =====================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _botTokenController = TextEditingController();
  final TextEditingController _chatIdController = TextEditingController();
  final TextEditingController _personalMsgController = TextEditingController();
  final TextEditingController _sosMsgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _botTokenController.text = prefs.getString('botToken') ?? '';
      _chatIdController.text = prefs.getString('chatId') ?? '';
      _personalMsgController.text =
          prefs.getString('personalMessage') ??
          '💙 Just checking in. I am safe.';
      _sosMsgController.text =
          prefs.getString('sosMessage') ??
          '🚨 URGENT SOS! I need help immediately!';
    });
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('botToken', _botTokenController.text.trim());
    await prefs.setString('chatId', _chatIdController.text.trim());
    await prefs.setString(
      'personalMessage',
      _personalMsgController.text.trim(),
    );
    await prefs.setString('sosMessage', _sosMsgController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings Saved!')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Telegram Bot Token",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            TextField(
              controller: _botTokenController,
              decoration: const InputDecoration(hintText: "8751888647:AAFD..."),
            ),
            const SizedBox(height: 20),

            const Text(
              "Your Chat ID",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            TextField(
              controller: _chatIdController,
              decoration: const InputDecoration(hintText: "8507220867"),
            ),
            const SizedBox(height: 30),

            const Text(
              "Personal Message (2-sec hold)",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            TextField(
              controller: _personalMsgController,
              maxLines: 2,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            const Text(
              "SOS Message (5-sec hold)",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            TextField(
              controller: _sosMsgController,
              maxLines: 2,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const Text(
              "Note: Your live GPS location will automatically be attached to the SOS message.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.all(15),
              ),
              child: const Text(
                "Save & Return",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
