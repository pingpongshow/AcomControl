# AcomControl ESP32-S3 API Documentation
## External Application Integration Guide

This document provides comprehensive information for building desktop applications (Windows/macOS) that interface with the AcomControl ESP32-S3 controller.

---

## Table of Contents

1. [Overview](#overview)
2. [Network Configuration](#network-configuration)
3. [REST API Reference](#rest-api-reference)
4. [WebSocket Protocol](#websocket-protocol)
5. [Server-Sent Events (SSE)](#server-sent-events-sse)
6. [Data Models](#data-models)
7. [Example Code](#example-code)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The ESP32-S3 controller exposes multiple interfaces for external application control:

- **REST API**: Request/response for commands and status queries
- **WebSocket**: Bidirectional real-time communication (10Hz updates)
- **Server-Sent Events (SSE)**: Unidirectional telemetry streaming (5Hz updates)

All interfaces support **CORS** for cross-origin requests from desktop applications.

### Performance Characteristics

- **Telemetry Update Rate**: 10Hz (every 100ms)
- **WebSocket Broadcast**: 10Hz (every 100ms)
- **SSE Broadcast**: 5Hz (every 200ms)
- **API Response Time**: <50ms typical
- **Dual-Core Processing**: Serial on Core 0, Network on Core 1

---

## Network Configuration

### Finding the Controller

**AP Mode** (default):
- SSID: `AcomControl`
- Password: `acom1234`
- IP Address: `192.168.4.1`

**Station Mode** (connected to WiFi):
- IP Address: Assigned by DHCP (check router or serial console)
- Access via local network

### Configuring WiFi

**Via Web Interface**:
```
http://[IP_ADDRESS]/
```
Enter SSID and password in the WiFi Configuration section.

**Via API**:
```bash
curl -X POST http://192.168.4.1/api/wifi \
  -H "Content-Type: application/json" \
  -d '{"ssid":"YourNetwork","password":"YourPassword"}'
```

---

## REST API Reference

All REST endpoints return JSON with CORS headers enabled.

### Base URL

```
http://[ESP32_IP_ADDRESS]/api
```

### Response Format

All API responses follow this structure:

```json
{
  "success": true,
  "timestamp": 123456789,
  "data": { ... },
  "error": "Error message if success=false"
}
```

---

### GET /api/status

Get current amplifier state (snapshot).

**Request**:
```http
GET /api/status HTTP/1.1
Host: 192.168.4.1
```

**Response**:
```json
{
  "success": true,
  "timestamp": 123456789,
  "data": {
    "connected": true,
    "mode": "STB",
    "modeCode": 5,
    "band": "20m",
    "bandCode": 6,
    "antenna": 2,
    "isTx": false,
    "forwardPower": 0,
    "reflectedPower": 0,
    "swr": 1.05,
    "temperature": 28.5,
    "inputPower": 0.0,
    "current": 0.0,
    "frequency": 14200,
    "fanSpeed": 35,
    "hvVoltage": 3200,
    "errors": [],
    "serialNumber": "600S12345678",
    "lastUpdate": 123456700
  }
}
```

**Example (JavaScript)**:
```javascript
fetch('http://192.168.4.1/api/status')
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      console.log('Amplifier mode:', data.data.mode);
      console.log('Forward power:', data.data.forwardPower, 'W');
    }
  });
```

**Example (Python)**:
```python
import requests

response = requests.get('http://192.168.4.1/api/status')
data = response.json()

if data['success']:
    print(f"Mode: {data['data']['mode']}")
    print(f"Power: {data['data']['forwardPower']}W")
```

**Example (C#)**:
```csharp
using System.Net.Http;
using System.Text.Json;

var client = new HttpClient();
var response = await client.GetStringAsync("http://192.168.4.1/api/status");
var data = JsonSerializer.Deserialize<ApiResponse>(response);

if (data.Success) {
    Console.WriteLine($"Mode: {data.Data.Mode}");
}
```

---

### GET /api/system

Get ESP32-S3 system information and performance metrics.

**Request**:
```http
GET /api/system HTTP/1.1
```

**Response**:
```json
{
  "success": true,
  "timestamp": 123456789,
  "data": {
    "chipModel": "ESP32-S3",
    "chipRevision": 0,
    "cpuFreqMHz": 240,
    "flashSize": 8388608,
    "freeHeap": 234567,
    "psramSize": 2097152,
    "psramFree": 1800000,
    "uptime": 123456789,
    "wifiMode": "STA",
    "wifiSSID": "MyNetwork",
    "ipAddress": "192.168.1.100",
    "rssi": -45,
    "performance": {
      "wsUpdateCount": 12345,
      "sseUpdateCount": 6789,
      "serialRxCount": 98765,
      "wsClients": 1,
      "sseClients": 1
    }
  }
}
```

---

### POST /api/mode

Set amplifier operating mode.

**Request**:
```http
POST /api/mode HTTP/1.1
Content-Type: application/json

{
  "mode": 6
}
```

**Mode Values**:
- `1` - RESET
- `2` - INIT
- `3` - DEBUG
- `4` - SERVICE
- `5` - STB (Standby)
- `6` - OPR-RX (Operate Receive)
- `7` - OPR-TX (Operate Transmit)
- `8` - ATAC
- `9` - MENU
- `10` - OFF (Power Off)

**Response**:
```json
{
  "success": true,
  "mode": 6,
  "timestamp": 123456789
}
```

**Example (JavaScript)**:
```javascript
fetch('http://192.168.4.1/api/mode', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({mode: 6})
})
.then(r => r.json())
.then(data => console.log('Mode set:', data.success));
```

**Example (Python)**:
```python
import requests

response = requests.post(
    'http://192.168.4.1/api/mode',
    json={'mode': 6}
)
print(response.json())
```

---

### POST /api/band

Set band and antenna.

**Request**:
```http
POST /api/band HTTP/1.1
Content-Type: application/json

{
  "band": 6,
  "antenna": 2
}
```

**Band Values**:
- `1` - 160m
- `2` - 80m
- `3` - 60m
- `4` - 40m
- `5` - 30m
- `6` - 20m
- `7` - 17m
- `8` - 15m
- `9` - 12m
- `10` - 10m

**Antenna Values**:
- `1` - Antenna 1
- `2` - Antenna 2 (default)

**Response**:
```json
{
  "success": true,
  "band": 6,
  "antenna": 2,
  "timestamp": 123456789
}
```

---

### POST /api/command

Generic command interface for advanced operations.

**Request**:
```http
POST /api/command HTTP/1.1
Content-Type: application/json

{
  "type": "reset"
}
```

**Command Types**:
- `"reset"` - Reset amplifier
- `"clear_errors"` - Clear error codes

**Response**:
```json
{
  "success": true,
  "command": "reset"
}
```

**Example (Clear Errors)**:
```javascript
fetch('http://192.168.4.1/api/command', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({type: 'clear_errors'})
});
```

---

### POST /api/wifi

Configure WiFi settings (requires reboot).

**Request**:
```http
POST /api/wifi HTTP/1.1
Content-Type: application/json

{
  "ssid": "MyNetwork",
  "password": "MyPassword"
}
```

**Response**:
```json
{
  "success": true,
  "message": "WiFi configured, rebooting..."
}
```

**Note**: ESP32 will reboot after this command. Allow 10-15 seconds for reconnection.

---

## WebSocket Protocol

WebSocket provides **bidirectional** real-time communication with 10Hz updates.

### Connection

```javascript
const ws = new WebSocket('ws://192.168.4.1/ws');
```

### Message Format

**Server → Client** (State Updates):
```json
{
  "connected": true,
  "mode": "STB",
  "modeCode": 5,
  "band": "20m",
  "bandCode": 6,
  "antenna": 2,
  "isTx": false,
  "forwardPower": 0,
  "reflectedPower": 0,
  "swr": 100,
  "temperature": 273,
  "inputPower": 0,
  "current": 0,
  "frequency": 14200,
  "fanSpeed": 35,
  "hvVoltage": 3200,
  "serialNumber": "600S12345678",
  "lastUpdate": 123456789,
  "errors": []
}
```

**Client → Server** (Commands):

Set Mode:
```json
{"cmd": "setMode", "mode": 6}
```

Set Band:
```json
{"cmd": "setBand", "band": 6, "antenna": 2}
```

Clear Errors:
```json
{"cmd": "clearErrors"}
```

Save WiFi:
```json
{"cmd": "saveWiFi", "ssid": "Network", "password": "Pass"}
```

### Complete Example (JavaScript)

```javascript
const ws = new WebSocket('ws://192.168.4.1/ws');

ws.onopen = () => {
  console.log('Connected to AcomControl');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Forward Power:', data.forwardPower, 'W');
  console.log('SWR:', (data.swr / 100).toFixed(2));
  
  // Temperature conversion
  const tempC = (data.temperature - 273) / 10;
  console.log('Temperature:', tempC.toFixed(1), '°C');
  
  // Check TX state
  if (data.isTx) {
    console.log('TRANSMITTING');
  }
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};

ws.onclose = () => {
  console.log('Disconnected');
  // Implement reconnection logic
  setTimeout(() => {
    // Reconnect
  }, 1000);
};

// Send command
function setMode(mode) {
  ws.send(JSON.stringify({cmd: 'setMode', mode}));
}

// Example: Set to Operate mode
setMode(6);
```

### Complete Example (Python)

```python
import websocket
import json
import threading

def on_message(ws, message):
    data = json.loads(message)
    print(f"Power: {data['forwardPower']}W")
    print(f"SWR: {data['swr'] / 100:.2f}")
    
    # Temperature conversion
    temp_c = (data['temperature'] - 273) / 10
    print(f"Temperature: {temp_c:.1f}°C")
    
    if data['isTx']:
        print("TRANSMITTING!")

def on_error(ws, error):
    print(f"Error: {error}")

def on_close(ws, close_status_code, close_msg):
    print("Connection closed")

def on_open(ws):
    print("Connected to AcomControl")
    
    # Send a command
    ws.send(json.dumps({"cmd": "setMode", "mode": 6}))

# Create WebSocket connection
ws = websocket.WebSocketApp(
    "ws://192.168.4.1/ws",
    on_open=on_open,
    on_message=on_message,
    on_error=on_error,
    on_close=on_close
)

# Run in separate thread
wst = threading.Thread(target=ws.run_forever)
wst.daemon = True
wst.start()
```

---

## Server-Sent Events (SSE)

SSE provides **unidirectional** real-time streaming at 5Hz (lower bandwidth than WebSocket).

### Connection

**URL**: `http://192.168.4.1/api/telemetry`

### Event Format

```
event: state
data: {"success":true,"timestamp":123456789,"data":{...}}
id: 123456789
```

### JavaScript Example

```javascript
const eventSource = new EventSource('http://192.168.4.1/api/telemetry');

eventSource.onmessage = (event) => {
  const response = JSON.parse(event.data);
  
  if (response.success) {
    const data = response.data;
    console.log('Forward Power:', data.forwardPower, 'W');
    console.log('Mode:', data.mode);
    console.log('Band:', data.band);
    
    // Update UI elements
    updatePowerMeter(data.forwardPower);
    updateTemperature(data.temperature);
  }
};

eventSource.onerror = (error) => {
  console.error('SSE error:', error);
  eventSource.close();
  
  // Reconnect after delay
  setTimeout(() => {
    // Create new EventSource
  }, 5000);
};

function updatePowerMeter(power) {
  // Update your UI
  document.getElementById('power').textContent = power + ' W';
}

function updateTemperature(temp) {
  const tempC = (temp - 273) / 10;
  document.getElementById('temp').textContent = tempC.toFixed(1) + '°C';
}
```

### Python Example

```python
import sseclient
import requests
import json

def stream_telemetry():
    url = 'http://192.168.4.1/api/telemetry'
    response = requests.get(url, stream=True)
    client = sseclient.SSEClient(response)
    
    for event in client.events():
        data = json.loads(event.data)
        
        if data['success']:
            amp_data = data['data']
            print(f"Power: {amp_data['forwardPower']}W")
            print(f"SWR: {amp_data['swr']:.2f}")
            print(f"Mode: {amp_data['mode']}")
            print("---")

# Run streaming
stream_telemetry()
```

---

## Data Models

### State Object

```typescript
interface AmplifierState {
  connected: boolean;         // Amplifier connection status
  mode: string;              // Mode name (e.g., "STB", "OPR-TX")
  modeCode: number;          // Mode code (1-10)
  band: string;              // Band name (e.g., "20m", "40m")
  bandCode: number;          // Band code (1-10)
  antenna: number;           // Antenna number (1-2)
  isTx: boolean;             // Transmitting state
  forwardPower: number;      // Forward power (watts)
  reflectedPower: number;    // Reflected power (watts)
  swr: number;               // SWR (1.00 - 3.00)
  temperature: number;       // Temperature (celsius)
  inputPower: number;        // Input power (watts)
  current: number;           // Current (amps)
  frequency: number;         // Frequency (kHz)
  fanSpeed: number;          // Fan speed (0-100%)
  hvVoltage: number;         // HV voltage (volts)
  errors: number[];          // Error codes
  serialNumber: string;      // Amplifier serial number
  lastUpdate: number;        // Last update timestamp (millis)
}
```

### System Info Object

```typescript
interface SystemInfo {
  chipModel: string;         // "ESP32-S3"
  chipRevision: number;      // Chip revision
  cpuFreqMHz: number;        // CPU frequency (240 MHz)
  flashSize: number;         // Flash size (bytes)
  freeHeap: number;          // Free heap (bytes)
  psramSize: number;         // PSRAM size (bytes)
  psramFree: number;         // Free PSRAM (bytes)
  uptime: number;            // Uptime (milliseconds)
  wifiMode: string;          // "AP" or "STA"
  wifiSSID: string;          // WiFi SSID
  ipAddress: string;         // IP address
  rssi: number;              // WiFi signal strength (dBm)
  performance: {
    wsUpdateCount: number;   // WebSocket update counter
    sseUpdateCount: number;  // SSE update counter
    serialRxCount: number;   // Serial messages received
    wsClients: number;       // Connected WebSocket clients
    sseClients: number;      // Connected SSE clients
  }
}
```

---

## Example Code

### Complete Desktop Application Example (Electron/JavaScript)

```javascript
// main.js - Electron main process
const { app, BrowserWindow } = require('electron');

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });
  
  win.loadFile('index.html');
}

app.whenReady().then(createWindow);
```

```html
<!-- index.html -->
<!DOCTYPE html>
<html>
<head>
  <title>AcomControl Desktop</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      background: #1a1a1a;
      color: white;
      padding: 20px;
    }
    .meter {
      margin: 10px 0;
      padding: 15px;
      background: #2a2a2a;
      border-radius: 8px;
    }
    .value {
      font-size: 2em;
      color: #4CAF50;
    }
    button {
      padding: 10px 20px;
      margin: 5px;
      background: #4CAF50;
      border: none;
      color: white;
      border-radius: 5px;
      cursor: pointer;
    }
    button:hover {
      background: #45a049;
    }
  </style>
</head>
<body>
  <h1>AcomControl Desktop</h1>
  
  <div id="status">Connecting...</div>
  
  <div class="meter">
    <div>Forward Power</div>
    <div class="value" id="fwdPower">0 W</div>
  </div>
  
  <div class="meter">
    <div>SWR</div>
    <div class="value" id="swr">1.00</div>
  </div>
  
  <div class="meter">
    <div>Temperature</div>
    <div class="value" id="temp">0°C</div>
  </div>
  
  <div>
    <button onclick="setMode(5)">Standby</button>
    <button onclick="setMode(6)">Operate</button>
    <button onclick="setMode(10)">Power Off</button>
  </div>
  
  <script>
    const ESP32_IP = '192.168.4.1';
    let ws;
    
    function connect() {
      ws = new WebSocket(`ws://${ESP32_IP}/ws`);
      
      ws.onopen = () => {
        document.getElementById('status').textContent = 'Connected';
        document.getElementById('status').style.color = '#4CAF50';
      };
      
      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        
        document.getElementById('fwdPower').textContent = data.forwardPower + ' W';
        document.getElementById('swr').textContent = (data.swr / 100).toFixed(2);
        
        const tempC = (data.temperature - 273) / 10;
        document.getElementById('temp').textContent = tempC.toFixed(1) + '°C';
      };
      
      ws.onclose = () => {
        document.getElementById('status').textContent = 'Disconnected';
        document.getElementById('status').style.color = '#f44336';
        
        setTimeout(connect, 1000);
      };
    }
    
    function setMode(mode) {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({cmd: 'setMode', mode}));
      }
    }
    
    connect();
  </script>
</body>
</html>
```

### Python Desktop Application (tkinter)

```python
import tkinter as tk
from tkinter import ttk
import websocket
import json
import threading

class AcomControlApp:
    def __init__(self, root):
        self.root = root
        self.root.title("AcomControl Desktop")
        self.root.geometry("600x400")
        self.root.configure(bg='#1a1a1a')
        
        # Connection status
        self.status_label = tk.Label(root, text="Connecting...", 
                                     bg='#1a1a1a', fg='yellow', font=('Arial', 12))
        self.status_label.pack(pady=10)
        
        # Power display
        self.power_frame = tk.Frame(root, bg='#2a2a2a', padx=20, pady=20)
        self.power_frame.pack(fill='x', padx=10, pady=5)
        
        tk.Label(self.power_frame, text="Forward Power", 
                bg='#2a2a2a', fg='white').pack()
        self.power_label = tk.Label(self.power_frame, text="0 W", 
                                   bg='#2a2a2a', fg='#4CAF50', font=('Arial', 24))
        self.power_label.pack()
        
        # SWR display
        self.swr_frame = tk.Frame(root, bg='#2a2a2a', padx=20, pady=20)
        self.swr_frame.pack(fill='x', padx=10, pady=5)
        
        tk.Label(self.swr_frame, text="SWR", 
                bg='#2a2a2a', fg='white').pack()
        self.swr_label = tk.Label(self.swr_frame, text="1.00", 
                                 bg='#2a2a2a', fg='#4CAF50', font=('Arial', 24))
        self.swr_label.pack()
        
        # Temperature display
        self.temp_frame = tk.Frame(root, bg='#2a2a2a', padx=20, pady=20)
        self.temp_frame.pack(fill='x', padx=10, pady=5)
        
        tk.Label(self.temp_frame, text="Temperature", 
                bg='#2a2a2a', fg='white').pack()
        self.temp_label = tk.Label(self.temp_frame, text="0°C", 
                                  bg='#2a2a2a', fg='#4CAF50', font=('Arial', 24))
        self.temp_label.pack()
        
        # Control buttons
        btn_frame = tk.Frame(root, bg='#1a1a1a')
        btn_frame.pack(pady=20)
        
        tk.Button(btn_frame, text="Standby", command=lambda: self.set_mode(5),
                 bg='#4CAF50', fg='white', padx=20, pady=10).pack(side='left', padx=5)
        tk.Button(btn_frame, text="Operate", command=lambda: self.set_mode(6),
                 bg='#FF9800', fg='white', padx=20, pady=10).pack(side='left', padx=5)
        tk.Button(btn_frame, text="Power Off", command=lambda: self.set_mode(10),
                 bg='#f44336', fg='white', padx=20, pady=10).pack(side='left', padx=5)
        
        # WebSocket
        self.ws = None
        self.connect_websocket()
    
    def connect_websocket(self):
        def on_message(ws, message):
            data = json.loads(message)
            
            # Update UI in main thread
            self.root.after(0, self.update_display, data)
        
        def on_error(ws, error):
            print(f"Error: {error}")
        
        def on_close(ws, close_status_code, close_msg):
            self.root.after(0, self.status_label.config, 
                          {'text': 'Disconnected', 'fg': 'red'})
            # Reconnect after delay
            self.root.after(1000, self.connect_websocket)
        
        def on_open(ws):
            self.root.after(0, self.status_label.config, 
                          {'text': 'Connected', 'fg': '#4CAF50'})
        
        self.ws = websocket.WebSocketApp(
            "ws://192.168.4.1/ws",
            on_open=on_open,
            on_message=on_message,
            on_error=on_error,
            on_close=on_close
        )
        
        # Run WebSocket in separate thread
        wst = threading.Thread(target=self.ws.run_forever)
        wst.daemon = True
        wst.start()
    
    def update_display(self, data):
        self.power_label.config(text=f"{data['forwardPower']} W")
        self.swr_label.config(text=f"{data['swr'] / 100:.2f}")
        
        temp_c = (data['temperature'] - 273) / 10
        self.temp_label.config(text=f"{temp_c:.1f}°C")
        
        # Change color based on TX state
        if data['isTx']:
            self.power_label.config(fg='#ff5252')
        else:
            self.power_label.config(fg='#4CAF50')
    
    def set_mode(self, mode):
        if self.ws and self.ws.sock and self.ws.sock.connected:
            self.ws.send(json.dumps({"cmd": "setMode", "mode": mode}))

# Run application
root = tk.Tk()
app = AcomControlApp(root)
root.mainloop()
```

---

## Best Practices

### 1. Connection Management

**Always implement reconnection logic**:

```javascript
let reconnectAttempts = 0;
const maxReconnectAttempts = 10;

function connect() {
  const ws = new WebSocket('ws://192.168.4.1/ws');
  
  ws.onclose = () => {
    if (reconnectAttempts < maxReconnectAttempts) {
      reconnectAttempts++;
      const delay = Math.min(1000 * reconnectAttempts, 10000);
      console.log(`Reconnecting in ${delay}ms...`);
      setTimeout(connect, delay);
    }
  };
  
  ws.onopen = () => {
    reconnectAttempts = 0; // Reset on successful connection
  };
}
```

### 2. Error Handling

**Always handle API errors**:

```javascript
async function getStatus() {
  try {
    const response = await fetch('http://192.168.4.1/api/status');
    
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    const data = await response.json();
    
    if (!data.success) {
      console.error('API error:', data.error);
      return null;
    }
    
    return data.data;
  } catch (error) {
    console.error('Request failed:', error);
    return null;
  }
}
```

### 3. Efficient Polling

If using REST API instead of WebSocket, implement efficient polling:

```javascript
let pollInterval = null;

function startPolling() {
  // Poll every 500ms (maximum 2Hz to avoid overwhelming ESP32)
  pollInterval = setInterval(async () => {
    const status = await getStatus();
    if (status) {
      updateUI(status);
    }
  }, 500);
}

function stopPolling() {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
}
```

**Important**: Polling faster than 500ms (2Hz) is not recommended. Use WebSocket or SSE for higher update rates.

### 4. UI Update Throttling

Throttle UI updates to prevent excessive rendering:

```javascript
let lastUpdate = 0;
const updateThreshold = 50; // 50ms = 20Hz max

function updateUI(data) {
  const now = Date.now();
  if (now - lastUpdate < updateThreshold) {
    return; // Skip this update
  }
  lastUpdate = now;
  
  // Update UI elements
  document.getElementById('power').textContent = data.forwardPower + ' W';
  // ...
}
```

### 5. Data Validation

Always validate incoming data:

```javascript
function isValidState(data) {
  return (
    typeof data.forwardPower === 'number' &&
    typeof data.swr === 'number' &&
    typeof data.mode === 'string' &&
    data.forwardPower >= 0 &&
    data.forwardPower <= 1000 &&
    data.swr >= 0 &&
    data.swr <= 500
  );
}

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  
  if (isValidState(data)) {
    updateUI(data);
  } else {
    console.warn('Invalid state data received');
  }
};
```

### 6. Network Discovery

For automatic network discovery, implement mDNS/Bonjour or scan local network:

```python
import socket

def find_esp32(subnet='192.168.1'):
    """Scan subnet for ESP32 controller"""
    for i in range(1, 255):
        ip = f"{subnet}.{i}"
        try:
            response = requests.get(f"http://{ip}/api/system", timeout=0.5)
            data = response.json()
            if data.get('success') and data['data']['chipModel'] == 'ESP32-S3':
                return ip
        except:
            continue
    return None

# Usage
esp32_ip = find_esp32()
if esp32_ip:
    print(f"Found ESP32 at {esp32_ip}")
```

---

## Troubleshooting

### Cannot Connect to ESP32

1. **Check network connectivity**:
   ```bash
   ping 192.168.4.1
   ```

2. **Verify ESP32 is in correct WiFi mode**:
   - Check serial console for IP address
   - Verify WiFi credentials are correct

3. **Check firewall settings**:
   - Allow port 80 (HTTP)
   - Allow WebSocket connections

### WebSocket Disconnects Frequently

1. **Disable WiFi power saving on ESP32** (already configured in code)
2. **Check network stability**
3. **Reduce update frequency** if needed
4. **Implement robust reconnection logic**

### API Returns Errors

1. **Check CORS headers** in browser console
2. **Verify JSON format** of POST requests
3. **Check ESP32 serial console** for error messages

### Slow Performance

1. **Use WebSocket instead of polling REST API**
2. **Reduce update frequency** if system is overloaded
3. **Check ESP32 free heap** via `/api/system`
4. **Limit number of concurrent connections**

### Data Appears Incorrect

1. **Apply correct conversions**:
   - SWR: Divide by 100
   - Temperature: `(value - 273) / 10` for Celsius
   - Input Power: Divide by 10
   - Current: Divide by 1000

2. **Check `lastUpdate` timestamp** to ensure fresh data

---

## Summary

The ESP32-S3 controller provides three interfaces for external applications:

| Interface | Update Rate | Use Case | Bidirectional |
|-----------|------------|----------|---------------|
| REST API | On-demand | Status queries, commands | No |
| WebSocket | 10Hz | Real-time monitoring & control | Yes |
| SSE | 5Hz | Real-time monitoring (lower bandwidth) | No |

**Recommended approach**:
- Use **WebSocket** for desktop applications requiring real-time bidirectional communication
- Use **SSE** for read-only monitoring applications
- Use **REST API** for infrequent status checks or simple control interfaces

All interfaces include CORS support for cross-origin requests from desktop applications.

For questions or issues, check the ESP32 serial console output (115200 baud) for diagnostic information.
