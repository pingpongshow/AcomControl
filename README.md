# ACOM Amplifier Control System

Wireless control for the ACOM 600S RF amplifier: an ESP32-S3 serial bridge plus a
native macOS application.

```
┌─────────────────┐     RS-232      ┌─────────────────┐      WiFi       ┌─────────────────┐
│   ACOM 600S     │◄───────────────►│    ESP32-S3     │◄───────────────►│   macOS App     │
│   Amplifier     │    9600 8N1     │   Controller    │   WebSocket     │   AcomControl   │
└─────────────────┘                 └─────────────────┘                 └─────────────────┘
                                            │
                                            ├── Web UI (any browser)
                                            ├── REST API + SSE
                                            └── mDNS: acomcontrol.local
```

**Firmware v7.0 · macOS app v3.0.** See [CHANGELOG.md](CHANGELOG.md) for what
changed and why.

## Download

Prebuilt binaries are on the
[latest release](https://github.com/pingpongshow/AcomControl/releases/latest):

| File | Use |
|---|---|
| `AcomControl-7.0-esp32s3-full.bin` | First-time flash — bootloader, partitions and app in one image, written to `0x0` |
| `AcomControl-7.0-esp32s3-ota.bin` | Updating a controller already running firmware 6.0+ |
| `AcomControl-3.0-macOS.zip` | macOS app, universal, macOS 13+ |

```bash
# new controller
esptool.py --chip esp32s3 --baud 921600 write_flash 0x0 AcomControl-7.0-esp32s3-full.bin

# existing controller
curl -F "firmware=@AcomControl-7.0-esp32s3-ota.bin" http://acomcontrol.local/api/ota
```

The macOS app is signed with a Developer ID certificate but is **not notarized**,
so Gatekeeper blocks it on first launch: right-click the app and choose *Open*,
or `xattr -dr com.apple.quarantine /Applications/AcomControl.app`.

> **Update the firmware before the app.** v3.0 of the app relies on the
> controller decoding fault codes and reporting their severity, which firmware
> 6.0 and earlier do not do.

---

## macOS Application

Native SwiftUI, macOS 13+.

**Monitoring**
- Arc gauges with peak-hold needles for forward power, SWR and PA temperature
- 60-second sparklines under each gauge
- Full-width transmit banner with live power and SWR while keyed
- Band, frequency in MHz, antenna, and a warning when the rig's frequency implies
  a different band than the selected low-pass filter
- Twelve secondary telemetry readouts: reflected and drive power, drain current,
  HV supply, fan level (0–4) and percentage, dissipation, DC input, VCC, LPF
  channel

**Control**
- Standby / Operate / Power Off, with confirmation on Power Off
- Bands 160m–6m in a grid that wraps to the window
- Antenna 1–10 selector; band changes keep the selected antenna
- Clear soft faults
- Confirmation before changing band while transmitting

**Faults**
- Code, name and severity from the ACOM RS-232 specification's own table (126
  codes), plus the parameter and the telemetry captured alongside it
- Severity comes from the amplifier, not from guesswork: telemetry byte 70 says
  whether the live code belongs to a hard fault
- Optional override table for your own wording (Settings → Alerts)

**Alerts** — notifications and sound for high SWR, overtemperature, faults and
disconnection, with hysteresis so a sustained condition produces one banner.

**Session** — peak and average power, peak SWR and temperature, transmit time,
transmission count, duty cycle. History window with Swift Charts, CSV export, and
import of the controller's own stored telemetry.

**Menu bar extra** — TX state, power, SWR and temperature, plus Standby/Operate/
Clear, without keeping the window in front.

**Networking** — Bonjour discovery, subnet sweep fallback, multiple saved
controllers with auto-connect, manual address entry, Wi-Fi configuration.

**Shortcuts** — ⌘1 Standby · ⌘2 Operate · ⇧⌘K Clear Faults · ⌘D Disconnect ·
⌘R Reconnect · ⌘E Export CSV · ⌘, Settings

### Build

```bash
open "Mac OSX (Xcode) app/AcomControl.xcodeproj"
```

Build and run (⌘R). Signing uses the team already in the project; change it under
Signing & Capabilities if you are not on that team.

---

## ESP32-S3 Firmware

### Hardware

- ESP32-S3-DevKitC-1 (8 MB flash; N8/N8R2/N8R8/N16R8 all work)
- MAX3232 or equivalent RS-232 level converter
- DB9 cable to the amplifier's RS-232 port

| ESP32-S3 | Level converter |
|---|---|
| GPIO16 | RX (from amplifier TX) |
| GPIO17 | TX (to amplifier RX) |
| 3V3 | VCC |
| GND | GND |

### Build and flash

```bash
cd "Arduino (ESP32) code/AcomControl"
pio run -t upload
```

Once v6.0 or later is running, updates can go over the air — uncomment `upload_protocol`
and `upload_port` in `platformio.ini`, or upload `firmware.bin` from the web UI.

> **4 MB boards:** `platformio.ini` uses `default_8MB.csv` because LittleFS
> logging plus OTA does not fit the 1.31 MB app slot in `default.csv`. On a 4 MB
> board switch to `min_spiffs.csv` and lower `LOG_MAX_BYTES` in `src/main.cpp` to
> about 128 KB.

### First run

With no Wi-Fi credentials stored, the controller starts a WPA2 access point:

- **SSID** `AcomControl` → `http://192.168.4.1`
- **Passphrase** generated on first boot and printed on the serial console at
  115200 baud. Watch the console on first power-up, or read it back later at
  `GET /api/config` once the controller is on your LAN.

Set your network in the web UI or the macOS app, and it will reboot onto your
LAN and be reachable at **`http://acomcontrol.local`**.

Then **set an API password** (Access card in the web UI, or Settings ▸ Controller
in the app). Without one the controller is open to everything on your network.

### Features

- 10 Hz WebSocket telemetry, 5 Hz SSE, full REST API — see
  [API_DOCUMENTATION.md](Arduino%20(ESP32)%20code/API_DOCUMENTATION.md)
- mDNS with an `_acom._tcp` service for zero-configuration discovery
- OTA updates over espota or HTTP upload
- Telemetry history in RAM plus a rotating CSV session log on flash
- Automatic band following from the amplifier's frequency counter or from
  rig-control software posting to `/api/frequency`
- Optional HTTP Basic authentication across the web UI, REST, WebSocket, SSE and
  firmware upload
- The specification's fault code table served at `/api/faults`
- Built-in responsive web UI with the same gauges as the macOS app

---

## Security

This controller can key a 600 W amplifier onto an arbitrary band and accept
arbitrary firmware, so treat network access to it as physical access to the
amplifier.

**Set an API password.** With one set, firmware 7.0 requires HTTP Basic
credentials on the web page, every `/api/*` endpoint, the WebSocket upgrade, the
SSE stream and firmware upload:

```bash
curl -u acom:secret -X POST http://acomcontrol.local/api/config \
  -H 'Content-Type: application/json' -d '{"apiPassword":"secret"}'
```

The macOS app keeps its copy in your login keychain and prompts when a
controller answers 401. The web UI and `GET /api/system` both report
`authEnabled: false` until you set one.

**The access point has a WPA2 passphrase**, generated on first boot and kept in
NVS. Setting `apPassword` to an empty string deliberately reopens it; anything
else must be 8 characters or more.

**What this does not protect against.** Basic auth over plain HTTP means the
password is readable by anyone who can sniff the network — WPA2 is what provides
confidentiality. There is no TLS, no rate limiting and no lockout. This raises
the bar from "anyone in radio range" to "anyone with the password"; it is not a
substitute for keeping the controller off hostile networks.

> **Changed in firmware 7.0.** v6.0 had no authentication at all and ran its
> access point with no passphrase.

---

## Repository layout

```
├── Arduino (ESP32) code/
│   └── AcomControl/
│       ├── platformio.ini
│       └── src/
│           ├── main.cpp        firmware
│           └── web_page.h      built-in web UI (PROGMEM)
├── Mac OSX (Xcode) app/
│   └── AcomControl/
│       ├── Models.swift              wire formats, faults, history, stats
│       ├── AmplifierController.swift connection, commands, session state
│       ├── NotificationManager.swift alerts
│       ├── FaultCodes.swift          generated fault table (see tools/)
│       ├── Credentials.swift         per-controller keychain credentials
│       ├── Gauges.swift              arc gauges, sparklines, tiles
│       ├── ContentView.swift         main window
│       ├── HistoryView.swift         charts, statistics, CSV export
│       ├── MenuBarView.swift         menu bar extra
│       ├── SettingsView.swift        settings
│       └── DiscoveryView.swift       Bonjour + subnet discovery
├── tools/
│   └── gen_faults.py                 generates both fault tables from one source
├── CHANGELOG.md
└── ACOM_500S_User_Manual_EN_04_2023_3b3b.pdf   reference only - see note below
```

### A note on the amplifier model

Everything here targets the **ACOM 600S**, which is what `ACOM Protocol.pdf`
describes: it reports amplifier type 1 = A600S, and its bias fields are marked
`(A600S)`. The gauge full-scale values assume it too — 600 W forward power in
both the web page (`MAX_FWD`) and the app (`range: 0...600`).

The 500S manual in this directory is reference material for the shared parts of
the protection system, not the target. **On a different model, change those
full-scale values** — the protocol is the same but 600 W is not.

### Regenerating the fault table

The fault code table lives in one place, `tools/gen_faults.py`, which writes both
the firmware's `acom_faults.h` and the app's `FaultCodes.swift`. Edit the Python
source and re-run it rather than editing either generated file:

```bash
python3 tools/gen_faults.py .
```

## Troubleshooting

**The app finds no controllers.** Bonjour needs firmware 6.0+. For older
firmware use *Scan Subnet*, or type the address directly. Confirm the controller
answers: `curl http://acomcontrol.local/api/system`.

**Connected, but "no amp".** The app reached the ESP32 but the ESP32 is not
getting valid RS-232 frames. Check TX/RX are not swapped, the level converter has
power, and the amplifier's RS-232 port is enabled.

**Wrong band selected.** Update to firmware v7.0. v6.0 shifted every band code
from 40m upwards by one, so asking for 40m selected 30m and asking for 20m
selected 17m — and because it applied the same shift in reverse when reading the
band back, the display agreed with the button while the amplifier sat on the
wrong low-pass filter. v5.0 had the matching read-side version of the same bug.

**Fan reads about a quarter of what it should.** Update to firmware v7.0. The
amplifier's fan level runs 0–4; v6.0 scaled the percentage by 15.

**Fault codes show as hex with no name.** Update both the firmware and the app to
v7.0 / v3.0. The code-to-text table is in `Arduino (ESP32) code/ACOM Protocol.pdf`
and is now built into both — v6.0 shipped no table at all, and v2.0 of the app
asked you to supply your own.

**Fault numbers look nonsensical** (`0x0080`, `0x0100`). Update to firmware
v7.0. Message 0x21 is a bitfield; v6.0 published its raw 16-bit words as if they
were code values.
