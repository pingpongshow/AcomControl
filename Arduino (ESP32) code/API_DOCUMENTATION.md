# AcomControl ESP32-S3 API

Firmware **v7.0** — ACOM 600S amplifier controller.

The controller exposes three interfaces over the same port 80:

| Interface | Path | Use |
|---|---|---|
| REST | `/api/*` | One-shot reads and commands |
| WebSocket | `/ws` | 10 Hz telemetry stream and low-latency commands |
| Server-Sent Events | `/api/telemetry` | 5 Hz telemetry stream, one-way |

---

## Finding the controller

Firmware 6.0 and later runs an mDNS responder:

- **Hostname** — `http://acomcontrol.local` (configurable via `/api/config`)
- **Services** — `_http._tcp` and `_acom._tcp` on port 80

The `_acom._tcp` service carries TXT records `version`, `model` and `path`, so a
client can identify a controller without probing. Browsing for `_acom._tcp` is
the recommended discovery method; a subnet sweep of `/api/system` still works
for controllers that have not been updated.

**AP fallback**: with no Wi-Fi credentials stored, the controller starts an
access point named `AcomControl` at `192.168.4.1`. Firmware 7.0 generates a
random WPA2 passphrase for it on first boot, keeps it in NVS, prints it on the
serial console at every boot and reports it at `GET /api/config`, so it can
always be recovered from the station-mode side.

## Authentication

Set `apiPassword` via `POST /api/config` and the controller requires HTTP Basic
credentials on the web page, every `/api/*` endpoint, the WebSocket upgrade, the
SSE stream and firmware upload. `CORS` preflight (`OPTIONS`) is never
challenged. The user name defaults to `acom` and is settable as `apiUser`.

```bash
curl -u acom:secret http://acomcontrol.local/api/status
```

With no `apiPassword` set, the API stays open — upgrading does not lock anyone
out of their own controller — but `GET /api/system` then reports
`"authEnabled": false` and `"apOpen"` tells you whether the access point is
unprotected too, so a client can say so.

> Basic, not Digest: this is a LAN device on plain HTTP, so Digest would protect
> the password on the wire and nothing else. Treat the password as readable by
> anyone sniffing the network and rely on WPA2 for confidentiality.

> **Fixed in firmware 7.0.** v6.0 had no authentication of any kind and ran its
> access point wide open, so anyone within radio range could key a 600 W
> amplifier onto an arbitrary band or flash arbitrary firmware.

---

## Response envelope

**Every** REST response uses this shape. Firmware v5.0 returned bare objects with
different key names, which broke conforming clients — v6.0 matches this document.

```json
{
  "success": true,
  "timestamp": 123456789,
  "data": { }
}
```

On failure:

```json
{
  "success": false,
  "timestamp": 123456789,
  "error": "Invalid band"
}
```

`timestamp` is `millis()` since controller boot, not wall-clock time.

CORS is open (`Access-Control-Allow-Origin: *`) and `OPTIONS` preflight is handled
on every `/api/*` path.

---

## Units

Telemetry is reported in the amplifier's **raw wire units**. Clients scale them.
This keeps the controller free of lossy intermediate rounding.

| Field | Raw unit | To convert |
|---|---|---|
| `swr` | ×100 | `swr / 100` → 130 = 1.30:1 |
| `temperature` | Kelvin | `temperature - 273` → °C |
| `inputPower` | ×10 W | `inputPower / 10` → W |
| `current` | mA | `current / 1000` → A |
| `hvVoltage` | ×10 V | `hvVoltage / 10` → V |
| `vcc5` | mV | `vcc5 / 1000` → V |
| `vcc26` | ×10 V | `vcc26 / 10` → V |
| `pdcPower`, `disPower` | ×10 W | `/ 10` → W |
| `forwardPower`, `reflectedPower` | W | none |
| `frequency` | kHz | none |

`fanSpeed` is the exception: the amplifier reports a fan level in the upper
nibble of telemetry byte 69, documented in section 3.4.8 as **`[0..4]`**, and
the controller publishes the raw `fanLevel`, the maximum `fanLevelMax` (4) and a
derived `fanSpeed` percentage.

> **Fixed in firmware 7.0.** v5.0 published the raw level under the name
> `fanSpeed`, so clients rendered "3%" for a fan at full speed. v6.0 added a
> percentage but divided by 15 instead of 4, so a fan at full speed reported
> 27%. Clients should scale by `fanLevelMax` rather than assuming a constant.

---

## Band codes

Two numbering schemes exist and the controller translates between them:

| Code | Band | Frequency range |
|------|------|-----------------|
| 1 | 160m | 1.8–2.0 MHz |
| 2 | 80m | 3.5–4.0 MHz |
| 3 | 40m / 60m | 7.0–7.3 MHz, 5.25–5.45 MHz |
| 4 | 30m | 10.1–10.15 MHz |
| 5 | 20m | 14.0–14.35 MHz |
| 6 | 17m | 18.068–18.168 MHz |
| 7 | 15m | 21.0–21.45 MHz |
| 8 | 12m | 24.89–24.99 MHz |
| 9 | 10m | 28.0–29.7 MHz |
| 10 | 6m | 50.0–54.0 MHz |

There is **one** band numbering, shared by the amplifier, the low-pass filter
channel in telemetry byte 69, the REST and WebSocket API, and both user
interfaces. No conversion happens anywhere.

Section 5.1 of `ACOM Protocol.pdf` fixes it twice over: command `0x09` ("manual
changing of antenna and band") documents its band parameter as `0x01 - 0x0A`,
and the command `0x0C` band-select relay test spells the ten bands out in
order, `0x01` = 160m through `0x0A` = 6m.

60m has no band number of its own. Section 3.3.7 byte 13 groups it with 40m
("Antenna Assigment and Selectivity for Bands 40m and 60m"), so 5 MHz operation
uses the 40m low-pass filter and band code 3.

> **Fixed in firmware 7.0.** v6.0 believed the amplifier used an eleven-slot
> numbering with 60m at 3, and converted between that and the UI. The result was
> that every band from 40m upwards selected the next band up — asking for 40m
> gave 30m, asking for 20m gave 17m — and 6m sent `0x0B`, outside the documented
> range. The matching reverse conversion on message 0x27 hid it, so the display
> agreed with the button while the amplifier sat on the wrong filter.

---

## GET /api/status

Current amplifier telemetry.

```json
{
  "success": true,
  "timestamp": 123456789,
  "data": {
    "connected": true,
    "mode": "OPR",
    "modeCode": 96,
    "band": "20m",
    "bandCode": 5,
    "antenna": 2,
    "antennaType": 1,
    "isTx": false,
    "forwardPower": 0,
    "reflectedPower": 0,
    "swr": 105,
    "temperature": 301,
    "inputPower": 0,
    "current": 0,
    "frequency": 14200,
    "fanLevel": 2,
    "fanSpeed": 50,
    "fanLevelMax": 4,
    "hvVoltage": 3200,
    "vcc5": 5020,
    "vcc26": 262,
    "pdcPower": 0,
    "disPower": 0,
    "lpfChannel": 5,
    "errorCode": 13,
    "errorParam": 265,
    "errorSeverity": "soft",
    "errorIsHardFault": false,
    "errors": [13, 4],
    "serialNumber": "600S12345678",
    "lastUpdate": 123456700,
    "msgCount": 48210,
    "autoBandFollow": false
  }
}
```

`connected` reports the **amplifier's** serial link, not your HTTP connection.
It goes false after 5 s without a valid frame on the RS-232 port.

`errors` lists the **fault codes** that are currently active, decoded from
message 0x21, which the controller polls every 2 s. `errorCode` is the code on
the amplifier's own screen, with `errorParam` as its parameter and
`errorSeverity` (`"warning"`, `"soft"` or `"hard"`) as the amplifier's own
classification of it — taken from telemetry byte 70 bit 0 and the specification's
table, so no client has to guess severity from telemetry.

Names for every code are served by [GET /api/faults](#get-apifaults), so clients
need no table of their own.

> **Fixed in firmware 7.0.** Message 0x21 is a **bitfield**, not a list of code
> values: section 3.4.1 defines ten 16-bit words where bit *n* of word *k* means
> code `(k × 16) + n` is active. v6.0 copied the ten raw words into `errors` and
> published them as if they were codes, so one active "excessive drive power"
> fault (code `0x07`, word 0 bit 7) appeared as fault `0x0080`.

---

## GET /api/faults

The fault code table from section 3.4.1 of the ACOM RS-232 specification: 126
named codes, each with the severity the specification assigns it. Static for a
given firmware build, so fetch it once and cache it.

```json
{
  "success": true,
  "timestamp": 123456789,
  "data": {
    "count": 126,
    "codes": {
      "0": { "severity": "warning", "text": "Hot switching attempt" },
      "7": { "severity": "soft", "text": "Excessive drive power" },
      "13": { "severity": "soft", "text": "PA load SWR too high" },
      "16": { "severity": "hard", "text": "5 V too low" }
    }
  }
}
```

Keys are decimal code numbers, as strings. `severity` is one of `warning`
(transmission continues), `soft` (the amplifier reverts to standby) or `hard`
(the amplifier shuts its supply down). A handful of codes are left unnamed by
the specification and are absent from this table.

> **New in firmware 7.0.** v6.0 shipped no table and told operators the
> specification was unavailable. It is `ACOM Protocol.pdf`, in this directory.

---

## GET /api/system

Controller diagnostics.

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
    "heapSize": 327680,
    "psramSize": 0,
    "psramFree": 0,
    "uptime": 123456789,
    "wifiMode": "STA",
    "wifiSSID": "MyNetwork",
    "ipAddress": "192.168.1.100",
    "rssi": -45,
    "hostname": "acomcontrol",
    "firmwareVersion": "7.0",
    "telemetryEnabled": true,
    "autoBandFollow": false,
    "loggingEnabled": true,
    "historyCount": 600,
    "historyCapacity": 600,
    "logBytes": 40960,
    "fanLevelMax": 4,
    "authEnabled": false,
    "apOpen": false,
    "performance": {
      "wsUpdateCount": 51234,
      "sseUpdateCount": 1200,
      "serialRxCount": 98765,
      "wsClients": 1,
      "sseClients": 0
    }
  }
}
```

`uptime` is **milliseconds** since boot.

---

## POST /api/mode

```json
{ "mode": 5 }
```

| Code | Mode |
|---|---|
| 1, 2 | Restart |
| 3 | Debug |
| 4 | Service |
| 5 | Standby |
| 6 | Operate (RX) |
| 7 | Operate (TX) |
| 8 | ATAC |
| 9 | Menu |
| 10 | Power off |

Codes outside 1–10 are rejected with HTTP 400.

---

## POST /api/band

```json
{ "band": 5, "antenna": 2 }
```

`band` is a display code 1–10. `antenna` is 1–10 and **optional** — when omitted
the controller keeps the antenna the amplifier currently reports rather than
forcing antenna 1.

---

## POST /api/frequency

Feeds a transceiver frequency from rig-control software (Hamlib, N1MM, Node-RED).

```json
{ "frequency": 14250 }
```

`frequency` is in kHz, 1–65535. Response includes the band it maps to and
whether automatic band following is enabled:

```json
{ "success": true, "timestamp": 1, "data": { "frequency": 14250, "band": 5, "autoBandFollow": true } }
```

The value is retained for 10 s. It is used for band following only when the
amplifier's own frequency counter reads zero, so a keyed reading always wins.

Example with `rigctl`:

```bash
while true; do
  KHZ=$(( $(rigctl -m 2 f) / 1000 ))
  curl -s -X POST http://acomcontrol.local/api/frequency \
       -H 'Content-Type: application/json' -d "{\"frequency\":$KHZ}" > /dev/null
  sleep 2
done
```

---

## GET / POST /api/config

```json
{
  "hostname": "acomcontrol",
  "autoBandFollow": false,
  "logging": true,
  "otaPasswordSet": false,
  "wifiSSID": "MyNetwork",
  "apMode": false,
  "apSSID": "AcomControl",
  "apPassword": "qm4xr7tkbd",
  "apOpen": false,
  "authEnabled": false,
  "apiUser": "acom"
}
```

`wifiSSID` is the network the controller is configured to **join**, which is not
the same thing as the network it is currently serving: `apSSID` is the setup
access point's own name, and `apMode` says which of the two is in use.

> **Fixed in firmware 7.0.** v6.0 reported the access point's own name in
> `wifiSSID` whenever it was in AP mode, so the web form offered to make the
> controller join itself and the macOS app had to special-case the string
> `"AcomControl"`.

POST accepts any subset of `autoBandFollow`, `logging`, `hostname`,
`otaPassword`, `apiUser`, `apiPassword` and `apPassword`. Everything except
`autoBandFollow` and `logging` reboots the controller; the response reports
`"rebooting": true` and is delivered before the restart.

`apPassword` must be 8 characters or more (a WPA2 minimum) or empty, which
deliberately reopens the access point. An empty `apiPassword` disables
authentication.

**Automatic band following** changes bands to match the operating frequency. It
never fires while the amplifier is transmitting, and it holds off 3 s between
changes.

---

## POST /api/wifi

```json
{ "ssid": "MyNetwork", "password": "secret" }
```

An empty `password` is accepted for open networks. The controller replies first
and reboots ~1 s later, so the client sees the success response. (v5.0 restarted
inside the request handler, so the reply was usually lost.)

---

## GET /api/history

Telemetry ring buffer held in RAM — 600 samples at 1 Hz, or 1800 with PSRAM.

Optional `?points=N` limits the response to the newest N samples.

```json
{
  "success": true,
  "timestamp": 123456789,
  "data": {
    "fields": ["t","forwardPower","reflectedPower","swr","temperature","current","frequency","band","tx"],
    "count": 600,
    "capacity": 600,
    "samples": [
      [120000, 480, 12, 130, 318, 24500, 14250, 5, 1],
      [121000, 0, 0, 105, 315, 0, 14250, 5, 0]
    ]
  }
}
```

Samples are arrays in `fields` order, oldest first. `t` is `millis()` at capture.
Values use the same raw units as `/api/status`.

## GET /api/history/download

The rotating CSV session log from LittleFS, as a file download. Columns:
`ms,forwardW,reflectedW,swr100,tempK,currentmA,freqkHz,band,tx`.

Written every second while transmitting and every 30 s otherwise, to limit flash
wear. Rotates to `acomlog.1.csv` at 384 KB.

## POST /api/history/clear

Empties both the RAM ring buffer and the flash log.

---

## POST /api/ota

Firmware update by `multipart/form-data` upload of a `firmware.bin`.

```bash
curl -F "firmware=@.pio/build/esp32-s3-devkitc-1/firmware.bin" \
     http://acomcontrol.local/api/ota
```

The controller reboots ~1.5 s after a successful write. The serial task is
suspended during the flash write and resumed if the update fails.

ArduinoOTA (espota) is also available:

```bash
pio run -t upload --upload-port acomcontrol.local
```

---

## POST /api/command

Generic endpoint accepting the same payloads as the WebSocket (below). Useful
for scripting without a WebSocket client.

---

## WebSocket `/ws`

On connect the controller sends the current state immediately, then broadcasts
at 10 Hz. **Telemetry frames are bare state objects, not enveloped** — they are
the `data` object from `/api/status`.

Broadcasts are skipped when any client's send queue is backed up, so a slow
client cannot exhaust the controller's heap.

### Commands

Send JSON text frames:

```json
{"cmd": "setMode",     "mode": 5}
{"cmd": "setBand",     "band": 5, "antenna": 2}
{"cmd": "setAntenna",  "antenna": 2, "band": 5}
{"cmd": "clearErrors"}
{"cmd": "requestInfo"}
{"cmd": "setFrequency","frequency": 14250}
{"cmd": "saveWiFi",    "ssid": "MyNetwork", "password": "secret"}
```

A rejected command produces an envelope instead of a state frame:

```json
{"success": false, "error": "Invalid band"}
```

Distinguish the two by the presence of `success`. A frame without `cmd` is
rejected rather than dereferenced — in v5.0 it crashed the controller.

Commands are queued and executed by the serial task, so a web request never
blocks on the 9600 baud UART.

---

## SSE `/api/telemetry`

```javascript
const events = new EventSource('http://acomcontrol.local/api/telemetry');
events.addEventListener('state', e => console.log(JSON.parse(e.data)));
```

Event name `state`, 5 Hz, same bare state object as the WebSocket.

---

## Amplifier serial protocol

RS-232, 9600 8N1, on UART2 (RX GPIO16, TX GPIO17).

Frame: `| 0x55 | Address | Length | Data… | Checksum |` where `Length` counts
every byte including the start byte and checksum, and
`Checksum = 256 - (sum of preceding bytes & 0xFF)`. A correctly received frame
sums to zero across all bytes.

Messages handled:

| Address | Direction | Meaning |
|---|---|---|
| 0x11 | from amp | PCB versions (carries serial number) |
| 0x13 | from amp | Serial number |
| 0x21 | from amp | Fault log, 10 × 16-bit codes |
| 0x27 | from amp | Band and antenna |
| 0x2F | from amp | Telemetry, 72 bytes |
| 0x81 | to amp | Command (request, mode, clear faults, band) |
| 0x86 | to amp | Acknowledge |
| 0x91 / 0x92 | to amp | Disable / enable automatic telemetry |

Polling: telemetry 5 Hz, fault log every 2 s, band info every 10 s.
