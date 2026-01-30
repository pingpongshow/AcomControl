# ACOM Amplifier Control System

A complete wireless control solution for the ACOM 600S RF amplifier, consisting of an ESP32-S3 hardware interface and a native macOS application.

## System Overview

```
┌─────────────────┐     RS-232      ┌─────────────────┐      WiFi       ┌─────────────────┐
│   ACOM 600S     │◄───────────────►│    ESP32-S3     │◄───────────────►│   macOS App     │
│   Amplifier     │    9600 8N1     │   Controller    │   WebSocket     │   AcomControl   │
└─────────────────┘                 └─────────────────┘                 └─────────────────┘
```

The ESP32-S3 acts as a bridge between the amplifier's serial protocol and modern network interfaces, providing real-time telemetry and control via WebSocket and REST APIs.

---

## macOS Application

**AcomControl** is a native SwiftUI application providing professional monitoring and control of the ACOM 600S amplifier.

### Features

- **Real-Time Monitoring** — 10Hz WebSocket updates for live telemetry
  - Forward/Reflected Power with graphical meters
  - SWR with color-coded warnings (green/yellow/red)
  - PA Temperature monitoring
  - Current, Voltage, Frequency display
  
- **Amplifier Control**
  - Mode switching: Standby, Operate RX, Power Off
  - Band selection: 160m through 10m
  - Antenna switching (Ant 1 / Ant 2)
  - Error display and clearing

- **Network Features**
  - Automatic device discovery via mDNS/network scan
  - Manual IP connection
  - ESP32 WiFi configuration from the app
  - Automatic reconnection with exponential backoff

- **Modern Interface**
  - Native SwiftUI design
  - Dark mode support
  - Keyboard shortcuts
  - Responsive layout

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building from source)

### Building

```bash
cd AcomControl
open AcomControl.xcodeproj
# Select your development team in Signing & Capabilities
# Press Cmd+R to build and run
```

### Quick Start

1. Launch the application
2. Click **Discover** to scan for ESP32 controllers, or
3. Click **Settings** (⚙️) to enter an IP address manually
4. Once connected, the status indicator turns green and telemetry begins streaming

---

## ESP32-S3 Controller

The ESP32 firmware provides the hardware interface to the ACOM 600S amplifier and exposes network APIs for remote control.

### Features

- **ACOM Protocol Implementation** — Full support for the ACOM 600S serial protocol
  - Automatic telemetry parsing (message 0x2F)
  - Command transmission with proper checksums
  - Error code decoding
  
- **Network Interfaces**
  - WebSocket server (`/ws`) for real-time bidirectional communication
  - REST API for status and control
  - Server-Sent Events (`/api/telemetry`) for streaming updates
  - Built-in web interface for browser-based monitoring

- **WiFi Modes**
  - **Station Mode** — Connects to existing WiFi network
  - **AP Mode** — Creates its own network when no credentials configured
    - SSID: `AcomControl`
    - IP: `192.168.4.1`

### Hardware Setup

| ESP32-S3 Pin | Connection |
|--------------|------------|
| GPIO16 (RX)  | ACOM RS-232 TX (via level shifter) |
| GPIO17 (TX)  | ACOM RS-232 RX (via level shifter) |
| GND          | RS-232 Ground |

**Note:** The ACOM 600S uses RS-232 voltage levels (±12V). A level shifter (e.g., MAX3232) is required between the ESP32 (3.3V logic) and the amplifier.

### API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ws` | WebSocket | Real-time telemetry and commands |
| `/api/status` | GET | Current amplifier state (JSON) |
| `/api/mode` | POST | Set amplifier mode |
| `/api/band` | POST | Set operating band |
| `/api/wifi` | POST | Configure WiFi credentials |
| `/api/system` | GET | ESP32 system information |

### WebSocket Commands

```json
{"command": "setMode", "mode": "standby"}
{"command": "setMode", "mode": "operateRx"}
{"command": "setMode", "mode": "powerOff"}
{"command": "setBand", "band": 7}
{"command": "setAntenna", "antenna": 1}
{"command": "clearErrors"}
{"command": "saveWiFi", "ssid": "MyNetwork", "password": "secret"}
```

### Telemetry Data

The ESP32 broadcasts JSON telemetry at 10Hz:

```json
{
  "connected": true,
  "mode": "OPR/RX",
  "modeCode": 96,
  "band": "20m",
  "forwardPower": 0,
  "reflectedPower": 0,
  "swr": 100,
  "temperature": 298,
  "inputPower": 0,
  "current": 0,
  "frequency": 14200,
  "fanSpeed": 1,
  "hvVoltage": 480,
  "errors": []
}
```

**Units:**
- `temperature` — Kelvin (subtract 273 for Celsius)
- `swr` — Multiplied by 100 (e.g., 150 = 1.50:1)
- `inputPower` — Multiplied by 10 (e.g., 253 = 25.3W)
- `hvVoltage` — Multiplied by 10 (e.g., 480 = 48.0V)

### Building the Firmware

The ESP32 firmware uses PlatformIO:

```bash
cd ACOMESP32
pio run                    # Build
pio run -t upload          # Upload to connected ESP32
pio device monitor         # Serial monitor (115200 baud)
```

Further ESP32 documentation, including detailed setup and configuration, is available in the ACOMESP32 directory.

---

## Protocol Notes

The system implements the ACOM 600S serial protocol as documented in `ACOM_Protocol.pdf`:

- **Baud Rate:** 9600, 8N1
- **Start Byte:** 0x55
- **Checksum:** `256 - (SUM of bytes 0 to N-1) & 0xFF`
- **Main Telemetry:** Message 0x2F (72 bytes, sent automatically at ~10Hz)
- **Commands:** Message 0x81 (8 bytes)

---

## License

MIT License — See individual component directories for details.

## Disclaimer
Use this code and the app at your own risk - damage to your hardware from use will not be my responsibility, you use this code and app at your own risk.
