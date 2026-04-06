import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // To check if GPS is physically ON

class BleScannerScreen extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceConnected;
  const BleScannerScreen({super.key, required this.onDeviceConnected});

  @override
  State<BleScannerScreen> createState() => _BleScannerScreenState();
}

class _BleScannerScreenState extends State<BleScannerScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndScan();
  }

  void _checkPermissionsAndScan() async {
    setState(() => _errorMessage = "");

    // 1. Check if Bluetooth is actually ON
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      if (mounted) setState(() => _errorMessage = "Please turn on Bluetooth.");
      return;
    }

    // 2. CRITICAL ANDROID FIX: Check if physical Location/GPS is ON
    bool locationOn = await Geolocator.isLocationServiceEnabled();
    if (!locationOn) {
      if (mounted) {
        setState(
          () => _errorMessage =
              "Android requires your phone's GPS/Location to be turned ON to scan for Bluetooth. Please turn it on.",
        );
      }
      return;
    }

    // 3. Request aggressive permissions (Like the Kotlin app)
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    _startScan();
  }

  void _startScan() async {
    if (mounted) setState(() => _isScanning = true);

    // Listen to the raw, unfiltered stream of devices (Just like Kotlin)
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Filter out unnamed ghost devices to keep the list clean
          _scanResults = results
              .where((r) => r.device.advName.isNotEmpty)
              .toList();
        });
      }
    });

    try {
      // Unfiltered scan, grabbing everything nearby
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      debugPrint("Scan Error: $e");
    }

    if (mounted) setState(() => _isScanning = false);
    subscription.cancel();
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      FlutterBluePlus.stopScan(); // Stop scanning before connecting

      // THE KOTLIN AUTO-CONNECT MAGIC
      // This maps directly to device?.connectGatt(this, true, gattCallback)
      await device.connect(autoConnect: true);

      // SAVE MAC ADDRESS FOR THE BACKGROUND SERVICE
      // This maps directly to sharedPreferences.edit().putString("saved_device_mac", macAddress)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_device_id', device.remoteId.toString());

      // Tell main.dart we are connected!
      widget.onDeviceConnected(device);
    } catch (e) {
      debugPrint("Connection Error: $e");
      if (mounted) {
        setState(() => _errorMessage = "Failed to connect. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // Make it tall enough to see the list
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            "Pair Your Keychain",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // Show error messages (like GPS being off)
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _errorMessage,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          if (_isScanning)
            const LinearProgressIndicator(color: Colors.deepPurple),

          if (!_isScanning && _scanResults.isEmpty && _errorMessage.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "No devices found. Press the button on the keychain to wake it up, then tap 'Scan Again'.",
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),

          // THE DEVICE LIST
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final d = _scanResults[index].device;
                return Card(
                  elevation: 0,
                  color: Colors.grey[100],
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.deepPurple,
                      child: Icon(
                        Icons.bluetooth,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      d.advName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      d.remoteId.toString(),
                      style: const TextStyle(fontSize: 10),
                    ), // Shows the MAC address
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () => _connect(d),
                  ),
                );
              },
            ),
          ),

          // SCAN AGAIN BUTTON
          if (!_isScanning)
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0, top: 10.0),
              child: ElevatedButton(
                onPressed: _checkPermissionsAndScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                child: const Text(
                  "Scan Again",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
