# AcomControl - Quick Start Guide

## 5-Minute Setup

### Step 1: Open the Project in Xcode
```bash
open AcomControl.xcodeproj
```

### Step 2: Configure Code Signing
1. Click on the **AcomControl** project in the navigator (top-left)
2. Select the **AcomControl** target
3. Go to **"Signing & Capabilities"** tab
4. Select your **Team** from the dropdown menu

### Step 3: Build and Run
- Press `Cmd + R` or click the ▶ button
- The app will launch automatically

### Step 4: Connect to Your ESP32

#### First Time (AP Mode):
1. Connect your Mac to the ESP32's WiFi network:
   - SSID: `AcomControl`
   - Password: `acom1234`
2. In the app, click the **settings icon** (⚙️)
3. Enter IP: `192.168.4.1`
4. Click **"Connect"**

#### After WiFi Configuration:
1. Click **"Discover"** button
2. Click **"Scan Network"**
3. Wait for your device to appear
4. Click **"Connect"** next to it

### Step 5: Start Monitoring!

You should now see real-time telemetry from your amplifier:
- Forward Power, SWR, Temperature updating at 10Hz
- Current band and mode
- All control buttons active

---

## Key Features at a Glance

### Main Window
- **Top Section**: Large meters for Power, SWR, Temp, Band
- **Middle Section**: Control buttons for Mode, Band, Antenna
- **Bottom Section**: Additional telemetry (current, voltage, etc.)

### Buttons
- **Discover** (top-right): Scan network for ESP32 controllers
- **Settings** (⚙️): Manual IP entry and WiFi configuration
- **Mode Buttons**: Standby, Operate RX, Power Off
- **Band Buttons**: 160m through 10m
- **Antenna Buttons**: Switch between Ant 1 and Ant 2

### Connection Status
- 🔴 Red dot = Disconnected
- 🟠 Orange dot = Connecting...
- 🟢 Green dot = Connected (shows IP address)

---

## Common Tasks

### Connect to a Different IP
1. Click **⚙️ Settings**
2. Enter new IP address
3. Click **"Connect"**

### Configure ESP32 WiFi
1. Connect to ESP32 (AP mode or existing network)
2. Open **⚙️ Settings**
3. Under "WiFi Configuration", click **"Configure WiFi"**
4. Enter SSID and password
5. Click **"Save & Reboot ESP32"**
6. Note the new IP from serial console
7. Reconnect using discovery or manual IP

### View System Information
1. Open **⚙️ Settings**
2. Click **"Refresh System Info"**
3. View ESP32 stats (CPU, memory, WiFi, uptime)

### Change Operating Mode
- Click **"Standby"** for standby mode
- Click **"Operate RX"** for receive mode
- Click **"Power Off"** to power down

### Change Band
- Click any band button (160m - 10m)
- Active band is highlighted in purple

### Switch Antenna
- Click **"Antenna 1"** or **"Antenna 2"**
- Active antenna is highlighted in purple

### Clear Errors
- If errors appear at the bottom, click **"Clear Errors"**

---

## Troubleshooting Quick Fixes

### Can't Connect
1. Verify ESP32 is powered on
2. Ping the IP: `ping 192.168.4.1`
3. Try using **Discover** instead
4. Check firewall settings

### Meters Not Updating
1. Check connection status (should be green)
2. Disconnect and reconnect
3. Restart the app
4. Restart the ESP32

### Discovery Finds Nothing
1. Ensure you're on the same network as ESP32
2. Try manual IP entry instead
3. Disable VPN if active

### Commands Don't Work
1. Verify connection status is green
2. Wait a moment between commands
3. Check ESP32 serial console for errors

---

## File Structure

```
AcomControl/
├── AcomControl.xcodeproj/        # Xcode project
├── AcomControl/
│   ├── AcomControlApp.swift      # Main app
│   ├── ContentView.swift         # Main UI
│   ├── AmplifierController.swift # WebSocket manager
│   ├── SettingsView.swift        # Settings UI
│   ├── DiscoveryView.swift       # Network scanner
│   ├── Assets.xcassets/          # App icons & colors
│   └── AcomControl.entitlements  # Permissions
└── README.md                     # Full documentation
```

---

## Next Steps

1. **Read the full README.md** for detailed documentation
2. **Review ESP32 API documentation** for protocol details
3. **Customize the UI** if desired (colors, thresholds, layout)
4. **Build for release** to create a distributable .app

---

## Minimum Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- ESP32-S3 with AcomControl firmware v2.0+
- Network connectivity (WiFi or Ethernet)

---

## Getting Help

If you encounter issues:

1. Check the **Troubleshooting** section in README.md
2. Review ESP32 serial console output (115200 baud)
3. Verify network connectivity with `ping`
4. Try the "Quick Fixes" above
5. Open a GitHub issue with details

---

**You're ready to control your ACOM 600S!** 🎉
