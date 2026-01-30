# AcomControl - Interface Design

## Visual Layout Description

Since this is a text-based delivery, here's a detailed description of what the interface looks like when running:

---

## Main Window Layout

### Window Dimensions
- **Size**: 900x700 pixels (resizable)
- **Style**: Hidden title bar with integrated controls
- **Theme**: Adapts to macOS system appearance (Light/Dark mode)

---

## Header Bar (Top Section)

```
┌─────────────────────────────────────────────────────────────────────┐
│  🌊 AcomControl              🟢 Connected  192.168.4.1   🔍 ⚙️      │
│     600S12345678                                        Discover     │
└─────────────────────────────────────────────────────────────────────┘
```

**Elements**:
- **Left**: Blue wave icon + "AcomControl" title + serial number
- **Center**: Connection status indicator with colored dot + IP address
- **Right**: "Discover" button + Settings gear icon

**Connection Status Colors**:
- 🔴 Red = Disconnected
- 🟠 Orange = Connecting...
- 🟢 Green = Connected

---

## Primary Meters Section

Four large meter cards arranged in a 2x2 grid:

```
┌────────────────────────┬────────────────────────┐
│  ⚡ Forward Power       │  〰️  SWR                │
│                        │                        │
│      450.0  W          │      1.2  :1           │
│  ▓▓▓▓▓▓▓▓▓▓░░░░░░      │  ▓▓░░░░░░░░░░░░░      │
│                        │                        │
├────────────────────────┼────────────────────────┤
│  🌡️  Temperature       │  📡 Band & Antenna     │
│                        │                        │
│      45.5  °C          │      20m               │
│  ▓▓▓▓▓▓░░░░░░░░░░      │                        │
│                        │  Antenna 2             │
└────────────────────────┴────────────────────────┘
```

**Each meter shows**:
- Icon + Title (top)
- Large numeric value + unit (center)
- Progress bar with colored zones (bottom)

**Color Coding**:
- **Power**: Green (RX) / Red (TX)
- **SWR**: Green (<2.0) / Orange (2.0-2.5) / Red (>2.5)
- **Temperature**: Blue (<60°C) / Orange (60-70°C) / Red (>70°C)
- **Band**: Purple highlight

---

## Control Buttons Section

### Mode Control
```
Mode Control
┌─────────────┬─────────────┬─────────────┐
│  ⏸️  Standby │ ▶️  Operate  │  ⏻  Power   │
│             │     RX      │     Off     │
└─────────────┴─────────────┴─────────────┘
```
- Blue background for active Standby
- Green background for active Operate
- Red background for active Power Off

### Band Selection
```
Band Selection
┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐
│160m│80m │60m │40m │30m │20m │17m │15m │12m │10m │
└────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘
```
- Purple background for active band
- Gray background for inactive bands

### Antenna Selection
```
Antenna
┌──────────────┬──────────────┐
│ 📡 Antenna 1 │ 📡 Antenna 2 │
└──────────────┴──────────────┘
```
- Purple background for active antenna

---

## Secondary Telemetry Section

Eight small info cards in a 4x2 grid:

```
Additional Telemetry
┌────────────┬────────────┬────────────┬────────────┐
│ ⚙️ Mode     │ ⬅️ Reflected│ ⬇️ Input    │ 🔌 Current  │
│ OPR-RX     │ 12 W       │ 5.0 W      │ 0.25 A     │
├────────────┼────────────┼────────────┼────────────┤
│ 〰️ Frequency│ 🌀 Fan Speed│ ⚡ HV Voltage│ 📡 TX Status│
│ 14200 kHz  │ 45%        │ 3200 V     │ Receiving  │
└────────────┴────────────┴────────────┴────────────┘
```

**Each card shows**:
- Tiny icon + label (top)
- Value (bottom, larger font)

---

## Error Display (When Active)

```
┌───────────────────────────────────────────────────┐
│ ⚠️  Active Errors                  [Clear Errors] │
│                                                   │
│  🔴 High SWR detected                             │
│  🔴 Temperature warning                           │
│                                                   │
└───────────────────────────────────────────────────┘
```

- Red background tint
- Red border
- List of error messages
- "Clear Errors" button on the right

---

## Settings Window

```
┌─────────────────────────────────────────────── Done ┐
│  Settings                                            │
├──────────────────────────────────────────────────────┤
│                                                      │
│  🌐 Connection                                       │
│  ┌────────────────────────────────────────────────┐ │
│  │ ESP32 IP Address                               │ │
│  │ [192.168.4.1              ] [Connect]          │ │
│  │                                                │ │
│  │ Quick Connect                                  │ │
│  │ [AP Mode (192.168.4.1)]                        │ │
│  │                                                │ │
│  │ Status: 🟢 Connected to 192.168.4.1            │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  📶 WiFi Configuration                               │
│  ┌────────────────────────────────────────────────┐ │
│  │ [Configure WiFi]                               │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ℹ️  System Information                              │
│  ┌────────────────────────────────────────────────┐ │
│  │ [Refresh System Info]                          │ │
│  │                                                │ │
│  │ Chip Model:      ESP32-S3                      │ │
│  │ CPU Frequency:   240 MHz                       │ │
│  │ Free Heap:       342 KB                        │ │
│  │ WiFi Mode:       STA                           │ │
│  │ SSID:            MyNetwork                     │ │
│  │ IP Address:      192.168.1.100                 │ │
│  │ Uptime:          02:15:30                      │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ℹ️  About                                           │
│  ┌────────────────────────────────────────────────┐ │
│  │ AcomControl                                    │ │
│  │ Version 1.0                                    │ │
│  │                                                │ │
│  │ macOS Application for ACOM 600S Amplifier      │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

**Size**: 600x700 pixels

---

## Discovery Window

```
┌────────────────────────────────────────────── Done ┐
│  Discover ESP32 Controllers                        │
│  Scanning local network for AcomControl devices    │
├────────────────────────────────────────────────────┤
│                                                    │
│  [🔍 Scan Network]                    Scanning... │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │  📡  ESP32-S3 Controller                     │ │
│  │      🌐 192.168.1.100    💻 ESP32-S3         │ │
│  │                              [Connect]       │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │  📡  ESP32-S3 Controller                     │ │
│  │      🌐 192.168.4.1      💻 ESP32-S3         │ │
│  │                              [Connect]       │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│  ℹ️  Scanning subnet: 192.168.1.x                 │
└────────────────────────────────────────────────────┘
```

**Size**: 600x500 pixels

**Features**:
- Scan button with progress indicator
- List of discovered devices with details
- Connect button for each device
- Current subnet display at bottom

---

## Color Palette

### Light Mode
- **Background**: System window background (off-white)
- **Cards**: Light gray with subtle shadow
- **Text**: Black/dark gray
- **Accents**: Blue, green, orange, red, purple

### Dark Mode
- **Background**: Dark gray (#1a1a1a)
- **Cards**: Darker gray (#2a2a2a)
- **Text**: White/light gray
- **Accents**: Same bright colors (blue, green, orange, red, purple)

### Status Colors
- **Blue**: Mode buttons, connection elements
- **Green**: Safe values, operate mode, connected status
- **Orange**: Warning values, connecting status
- **Red**: Danger values, power off mode, disconnected
- **Purple**: Band/antenna selection

---

## Typography

- **Headers**: System font, 14-20pt, semibold
- **Large Values**: System rounded font, 48pt, bold
- **Units**: System font, 20pt, medium
- **Labels**: System font, 12pt, medium
- **Body Text**: System font, 11-13pt, regular
- **Secondary**: System font, 11pt, secondary color

---

## Animations

- **Meter Updates**: Smooth 0.2s ease-in-out
- **Button Presses**: Instant feedback
- **Connection Status**: Fade transitions
- **Progress Bars**: Animated fill
- **Window Transitions**: System standard

---

## Responsiveness

- **Minimum Window Size**: 900x700
- **Maximum Window Size**: Unlimited
- **Content Scaling**: Adapts to window size
- **Scroll View**: Available when content exceeds height

---

## Keyboard Shortcuts

- **Cmd + ,**: Open Settings
- **Cmd + W**: Close window
- **Cmd + Q**: Quit application
- **Esc**: Close sheets/dialogs
- **Enter**: Confirm dialogs

---

## Accessibility

- **VoiceOver**: Full support for all UI elements
- **Dynamic Type**: Respects system text size
- **High Contrast**: Adapts to system settings
- **Reduced Motion**: Respects accessibility preferences
- **Keyboard Navigation**: Full keyboard control

---

This interface provides a professional, native macOS experience with real-time updates, clear visual feedback, and intuitive controls for managing your ACOM 600S amplifier.
