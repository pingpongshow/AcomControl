# AcomControl ESP32-S3 Quick Reference

## Network Access

### Default AP Mode
```
SSID: AcomControl
Password: acom1234
IP: 192.168.4.1
Web: http://192.168.4.1
```

### Station Mode
```
IP: Check serial monitor (115200 baud)
Web: http://[IP_ADDRESS]
```

---

## API Quick Reference

### Base URL
```
http://[ESP32_IP]/api
```

### Get Current Status
```bash
# cURL
curl http://192.168.4.1/api/status

# JavaScript
fetch('http://192.168.4.1/api/status')
  .then(r => r.json())
  .then(d => console.log(d.data));

# Python
import requests
r = requests.get('http://192.168.4.1/api/status')
print(r.json()['data'])
```

### Set Mode
```bash
# Standby (Mode 5)
curl -X POST http://192.168.4.1/api/mode \
  -H "Content-Type: application/json" \
  -d '{"mode": 5}'

# Operate (Mode 6)
curl -X POST http://192.168.4.1/api/mode \
  -H "Content-Type: application/json" \
  -d '{"mode": 6}'

# Power Off (Mode 10)
curl -X POST http://192.168.4.1/api/mode \
  -H "Content-Type: application/json" \
  -d '{"mode": 10}'
```

### Set Band
```bash
# 20m with Antenna 2
curl -X POST http://192.168.4.1/api/band \
  -H "Content-Type: application/json" \
  -d '{"band": 6, "antenna": 2}'

# 40m with Antenna 1
curl -X POST http://192.168.4.1/api/band \
  -H "Content-Type: application/json" \
  -d '{"band": 4, "antenna": 1}'
```

### System Information
```bash
curl http://192.168.4.1/api/system
```

### Clear Errors
```bash
curl -X POST http://192.168.4.1/api/command \
  -H "Content-Type: application/json" \
  -d '{"type": "clear_errors"}'
```

---

## Mode Codes

| Code | Mode | Description |
|------|------|-------------|
| 1 | RESET | Reset amplifier |
| 2 | INIT | Initialize |
| 3 | DEBUG | Debug mode |
| 4 | SERVICE | Service mode |
| 5 | STB | Standby |
| 6 | OPR-RX | Operate Receive |
| 7 | OPR-TX | Operate Transmit |
| 8 | ATAC | Auto Tune |
| 9 | MENU | Menu mode |
| 10 | OFF | Power Off |

---

## Band Codes

| Code | Band | Frequency Range |
|------|------|-----------------|
| 1 | 160m | 1.8-2.0 MHz |
| 2 | 80m | 3.5-4.0 MHz |
| 3 | 60m | 5.3-5.4 MHz |
| 4 | 40m | 7.0-7.3 MHz |
| 5 | 30m | 10.1-10.15 MHz |
| 6 | 20m | 14.0-14.35 MHz |
| 7 | 17m | 18.068-18.168 MHz |
| 8 | 15m | 21.0-21.45 MHz |
| 9 | 12m | 24.89-24.99 MHz |
| 10 | 10m | 28.0-29.7 MHz |

---

## WebSocket

### Connect
```javascript
const ws = new WebSocket('ws://192.168.4.1/ws');

ws.onopen = () => console.log('Connected');
ws.onmessage = (e) => {
  const data = JSON.parse(e.data);
  console.log('Power:', data.forwardPower, 'W');
};
```

### Send Commands
```javascript
// Set mode to Operate
ws.send(JSON.stringify({cmd: 'setMode', mode: 6}));

// Set band to 20m
ws.send(JSON.stringify({cmd: 'setBand', band: 6, antenna: 2}));

// Clear errors
ws.send(JSON.stringify({cmd: 'clearErrors'}));

// Save WiFi config
ws.send(JSON.stringify({
  cmd: 'saveWiFi', 
  ssid: 'Network', 
  password: 'Pass'
}));
```

---

## Server-Sent Events (SSE)

### JavaScript
```javascript
const es = new EventSource('http://192.168.4.1/api/telemetry');

es.onmessage = (event) => {
  const response = JSON.parse(event.data);
  const data = response.data;
  
  console.log('Power:', data.forwardPower, 'W');
  console.log('SWR:', data.swr);
  console.log('Temp:', data.temperature, '°C');
};

es.onerror = (error) => {
  console.error('SSE error:', error);
  es.close();
};
```

### Python
```python
import sseclient
import requests
import json

response = requests.get('http://192.168.4.1/api/telemetry', stream=True)
client = sseclient.SSEClient(response)

for event in client.events():
    data = json.loads(event.data)
    if data['success']:
        amp = data['data']
        print(f"Power: {amp['forwardPower']}W")
```

---

## Data Conversions

### From Raw Values
```javascript
// SWR (raw value is * 100)
const swr = data.swr / 100;  // e.g., 105 → 1.05

// Temperature (Kelvin * 10)
const tempC = (data.temperature - 273) / 10;  // e.g., 298 → 25°C

// Input Power (Watts * 10)
const inputW = data.inputPower / 10;  // e.g., 150 → 15.0W

// Current (Milliamps)
const currentA = data.current / 1000;  // e.g., 5500 → 5.5A
```

---

## Common Tasks

### Monitor Power in Real-Time
```python
import websocket
import json

def on_message(ws, message):
    data = json.loads(message)
    print(f"FWD: {data['forwardPower']}W | "
          f"REF: {data['reflectedPower']}W | "
          f"SWR: {data['swr']/100:.2f}")

ws = websocket.WebSocketApp('ws://192.168.4.1/ws',
                           on_message=on_message)
ws.run_forever()
```

### Set Mode Based on Condition
```javascript
// Automatically switch to standby if temp > 80°C
async function checkTemp() {
  const response = await fetch('http://192.168.4.1/api/status');
  const data = await response.json();
  
  const tempC = (data.data.temperature - 273) / 10;
  
  if (tempC > 80) {
    // Switch to standby
    await fetch('http://192.168.4.1/api/mode', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({mode: 5})
    });
    console.log('High temp! Switched to standby');
  }
}

setInterval(checkTemp, 5000);  // Check every 5 seconds
```

### Log Data to File
```python
import requests
import time
import csv

with open('amplifier_log.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Timestamp', 'Mode', 'Power', 'SWR', 'Temp'])
    
    while True:
        try:
            r = requests.get('http://192.168.4.1/api/status', timeout=2)
            data = r.json()['data']
            
            temp_c = (data['temperature'] - 273) / 10
            swr = data['swr'] / 100
            
            writer.writerow([
                time.strftime('%Y-%m-%d %H:%M:%S'),
                data['mode'],
                data['forwardPower'],
                f"{swr:.2f}",
                f"{temp_c:.1f}"
            ])
            f.flush()
            
        except Exception as e:
            print(f"Error: {e}")
        
        time.sleep(1)
```

---

## Hardware Setup

### Wiring Diagram
```
ESP32-S3          MAX3232         ACOM 600S
────────────────────────────────────────────
GPIO 16 (RX)  →   T2OUT      →   RX (DB9-2)
GPIO 17 (TX)  →   R2IN       ←   TX (DB9-3)
GND           →   GND        →   GND (DB9-5)
3.3V          →   VCC (3.3V)
```

### Power
```
USB: 5V via USB-C or Micro-USB
External: 5V on VIN pin (regulated to 3.3V)
Current: ~200mA typical, 500mA max
```

---

## Troubleshooting

### Can't Connect to Web Interface
```bash
# 1. Check IP address (serial monitor at 115200 baud)
# 2. Ping ESP32
ping 192.168.4.1

# 3. Check if HTTP server is running
curl -I http://192.168.4.1

# 4. Try AP mode reset (hold BOOT button while powering on)
```

### No Amplifier Data
```
1. Check RS-232 connections (TX/RX crossed)
2. Verify 9600 baud rate
3. Check GND connection
4. Measure voltage levels on MAX3232
5. Test with serial terminal on PC
```

### WebSocket Disconnects
```javascript
// Implement auto-reconnect
let ws;
function connect() {
  ws = new WebSocket('ws://192.168.4.1/ws');
  ws.onclose = () => {
    console.log('Disconnected, reconnecting...');
    setTimeout(connect, 1000);
  };
}
connect();
```

---

## Performance Specs

```
Update Rates:
  Telemetry:     10Hz (100ms)
  WebSocket:     10Hz (100ms)
  SSE:           5Hz (200ms)
  
Response Times:
  API:           <50ms typical
  WebSocket:     <10ms
  
Connections:
  WebSocket:     10+ concurrent
  SSE:           10+ concurrent
  HTTP:          Multiple
  
CPU Usage:      15-20% (dual-core @ 240MHz)
Free Heap:      >300KB typical
Network:        1-2 Mbps
```

---

## Serial Console

### Monitor Commands
```bash
# Linux/Mac
screen /dev/ttyUSB0 115200

# Windows (PuTTY or Arduino Serial Monitor)
# Port: COMx, Baud: 115200
```

### Expected Output
```
╔════════════════════════════════════════╗
║  AcomControl ESP32-S3 Enhanced v2.0   ║
╚════════════════════════════════════════╝
CPU Frequency: 240 MHz
Free Heap: 342456 bytes
PSRAM Size: 2097152 bytes

📡 WiFi: MyNetwork
IP Address: 192.168.1.100

🌐 Web: http://192.168.1.100
✓ System ready
```

---

## Configuration Files

### WiFi Settings (stored in NVS)
```cpp
// Check current settings via serial
preferences.begin("wifi", false);
String ssid = preferences.getString("ssid", "");
preferences.end();
```

### Reset WiFi
```cpp
// Via serial console or code
preferences.begin("wifi", false);
preferences.clear();
preferences.end();
ESP.restart();
```

---

## Useful Code Snippets

### Check Connection Status
```javascript
async function isConnected() {
  try {
    const r = await fetch('http://192.168.4.1/api/system', 
                         {timeout: 1000});
    return r.ok;
  } catch {
    return false;
  }
}
```

### Auto-Discovery
```python
import requests
import socket

def find_esp32(subnet='192.168.1'):
    for i in range(1, 255):
        ip = f"{subnet}.{i}"
        try:
            r = requests.get(f"http://{ip}/api/system", timeout=0.5)
            if r.ok and 'ESP32-S3' in r.text:
                return ip
        except:
            continue
    return None

esp32_ip = find_esp32()
print(f"Found at {esp32_ip}" if esp32_ip else "Not found")
```

### Watchdog Timer
```javascript
let lastUpdate = 0;

setInterval(() => {
  if (Date.now() - lastUpdate > 5000) {
    console.warn('No updates for 5 seconds!');
    // Reconnect logic
  }
}, 1000);

ws.onmessage = (e) => {
  lastUpdate = Date.now();
  // Process data...
};
```

---

## API Response Examples

### /api/status
```json
{
  "success": true,
  "timestamp": 123456789,
  "data": {
    "connected": true,
    "mode": "STB",
    "modeCode": 5,
    "forwardPower": 0,
    "swr": 1.05,
    "temperature": 28.5
  }
}
```

### /api/system
```json
{
  "success": true,
  "data": {
    "chipModel": "ESP32-S3",
    "cpuFreqMHz": 240,
    "freeHeap": 342456,
    "ipAddress": "192.168.1.100",
    "performance": {
      "wsUpdateCount": 12345,
      "wsClients": 2
    }
  }
}
```

---

**For complete documentation, see:**
- [README.md](README.md) - Full setup guide
- [API_DOCUMENTATION.md](API_DOCUMENTATION.md) - Complete API reference
