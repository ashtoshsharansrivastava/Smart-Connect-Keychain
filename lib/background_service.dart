import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'keychain_foreground',
    'Safety Keychain Monitor',
    description: 'This service keeps your safety device connected.',
    importance: Importance.low, // Silent, but keeps app alive
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'keychain_foreground',
      initialNotificationTitle: 'Safety Keychain',
      initialNotificationContent: 'Monitoring for safety signals...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Every 10 seconds, check if the device dropped. If it did, ask Android to find it again.
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    String? lastId = prefs.getString('last_device_id');

    if (lastId != null && FlutterBluePlus.connectedDevices.isEmpty) {
      try {
        BluetoothDevice device = BluetoothDevice.fromId(lastId);
        // The autoConnect flag is the magic that tells Android to handshake
        // instantly when the ESP32 wakes from Deep Sleep.
        device.connect(autoConnect: true);
      } catch (e) {
        print("Background reconnect failed: $e");
      }
    }
  });
}
