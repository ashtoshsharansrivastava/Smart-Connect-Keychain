# 🛡️ Safety Keeper

**A smart, wearable safety ecosystem powered by ESP32-C3 and Flutter.** Safety Keeper is an open-source hardware and software project designed to keep loved ones safe. It consists of a custom ESP32-C3 wearable keychain with a dynamic OLED display, paired via Bluetooth Low Energy (BLE) to a persistent Android companion app. With a single button press, the app silently fetches live GPS coordinates and fires a customized alert via the Telegram API, completely bypassing expensive SMS gateways.

---

## 1. ✨ Key Features

* **Dual-Trigger Smart Button:** * **Short Hold (2 Seconds):** Triggers a customized "Personal Message" (e.g., "Just checking in, I'm safe!").
  * **Long Hold (5 Seconds):** Triggers a high-priority SOS alert with an automatically generated Google Maps link pinpointing the user's exact GPS location.
* **Custom OLED UI:** Features a dynamic, animated robotic face that reacts to button presses, displays battery percentage, and confirms when messages are successfully sent over the network.
* **Always-On Background Engine:** The Android app runs a 24/7 foreground service. Even if the app is closed or the screen is off, it listens for the keychain's BLE signal.
* **Auto-Reconnect & Deep Sleep:** The keychain intelligently enters deep sleep after 15 seconds of inactivity to preserve battery. If it wakes up or goes out of range, the app silently re-establishes the connection in the background.
* **Robust BLE Pipeline:** Features a custom Android GATT 1-second stabilization delay and a "Ghost-Byte Decoder" to ensure Bluetooth payloads are never dropped or misread by modern Android OS restrictions.

---

## 2. 🛠️ Tech Stack

**Hardware Ecosystem:**
* **Microcontroller:** ESP32-C3 SuperMini
* **Display:** 0.96" I2C OLED (SSD1306)
* **Protocol:** Bluetooth Low Energy (NimBLE Library)
* **Language:** C++ (Arduino IDE)

**Software (Android App):**
* **Framework:** Flutter (Dart)
* **State Management:** Stateful Widgets & Shared Preferences
* **Native Bridges:** `flutter_blue_plus` (BLE), `geolocator` (GPS), `flutter_background_service`
* **API:** Telegram Bot API (HTTP GET requests)

---

## 3. 🚀 Getting Started & App Setup

### Hardware Setup (ESP32-C3)
1. Wire a push button to `GPIO 2` and GND.
2. Wire the OLED `SDA` to `GPIO 5` and `SCL` to `GPIO 6`.
3. Wire your battery output to `GPIO 0` for battery percentage tracking.
4. Open the Arduino IDE and install the `NimBLE-Arduino` and `Adafruit_SSD1306` libraries.
5. Upload the provided `.ino` firmware to your ESP32-C3.

### Telegram Bot Setup
1. Open Telegram and search for `@BotFather`.
2. Send `/newbot` and follow the steps to get your **Bot Token**.
3. Search for `@userinfobot` to get your personal **Chat ID**.
4. **Important:** Send a message to your new bot and press "Start" to open the communication channel.

### App Setup (Flutter)
1. Ensure you have the Flutter SDK installed on your machine.
2. Clone this repository:
   ```bash
   git clone [https://github.com/ashtoshsharansrivastava/Smart-Connect-Keychain.git](https://github.com/ashtoshsharansrivastava/Smart-Connect-Keychain.git)
  ## 4. Navigate to the project folder and install dependencies:

```bash
flutter pub get
Build the release APK:

```bash
flutter build apk --release
Install the APK on your Android device.

##5. Permissions: 
Open the app and grant all requested permissions (Location/GPS, Bluetooth, and Notifications). Note: Android requires physical GPS to be turned ON to scan for BLE devices.

1. Tap the Gear Icon (Settings), paste your Telegram Bot Token and Chat ID, and customize your messages.

2. Tap Tap to Connect Device, select the Safety Keeper from the scanner, and you are fully protected!

##6. 📸 System Architecture & Logic
The magic of this project lies in the seamless bridge between C++ and Dart:

Idle State: The keychain sleeps to save battery. The Flutter app listens quietly via flutter_background_service.

Trigger: Pressing the physical button wakes the ESP32. The OLED animates a loading bar and calculates the hold duration.

Transmission: Depending on the hold time, the ESP32 sends a lightweight string payload ("1" for Love, "2" for SOS) over the beb5483e TX characteristic.

Execution: The phone catches the payload, decodes the raw bytes, pings the GPS satellites using geolocator, packages the data, and fires the HTTP request to Telegram.