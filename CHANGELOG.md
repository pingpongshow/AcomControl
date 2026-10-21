# Changelog

## Firmware v7.0 / macOS app v3.0

Every item below came from checking the firmware against `ACOM Protocol.pdf`,
the specification that ships beside it. Section references are to that document.
Five of these are protocol-level: the code disagreed with the spec, and the spec
was right.

---

## Protocol bugs

### 1. Band codes were shifted — every band from 40m up selected the wrong one

Section 5.1 gives the amplifier's band numbering twice: command `0x09` takes
`0x01`–`0x0A`, and the command `0x0C` relay test names all ten in order,
`0x01` = 160m through `0x0A` = 6m. It is the same numbering the UI uses, and the
same one telemetry byte 69 reports as the active low-pass filter channel. **No
conversion is needed anywhere.**

v6.0 believed in an eleven-slot amplifier numbering with a separate 60m at 3 and
added 1 to every UI code from 40m upwards:

| You pressed | v6.0 sent | Amplifier selected |
|---|---|---|
| 40m | 4 | 30m |
| 20m | 6 | 17m |
| 10m | 10 | 6m |
| 6m | 11 (`0x0B`) | outside the documented range |

The matching reverse conversion on message 0x27 subtracted it again, so the
display agreed with the button you pressed while the amplifier sat on the wrong
filter. v5.0 had the read-side half of the same bug, and the v6.0 release notes
claimed to have fixed it.

*Fixed:* `uiBandToAmpBand`/`ampBandToUiBand` are gone. A band code is a band
code; `isValidBand()` range-checks it and nothing converts it.

As a footnote, the band-follow call site could never have compiled: it passed a
GCC compound literal containing runtime values to a `const uint8_t*` parameter,
which C++ rejects as taking the address of a temporary array. That code path was
not built.

### 2. Fan speed was scaled by 15 instead of 4

Section 3.4.8, byte 69: *"bit 4 – bit 7  FAN Speed **[0..4]**"*. Command `0x0C`'s
fan test agrees — it offers OFF plus speeds 1 to 3.

v5.0 published the raw level as `fanSpeed`, so clients rendered "3%" for a fan at
full tilt. v6.0 added a real percentage but divided by 15, so full tilt read 27%.

*Fixed:* divided by `FAN_LEVEL_MAX` (4), clamped to it, and `fanLevelMax` is now
published so clients scale by what the controller actually used rather than a
constant of their own.

### 3. Message 0x21 is a bitfield, not a list of codes

Section 3.4.1: ten 16-bit words, where bit *n* of word *k* means fault code
`(k × 16) + n` is active. v6.0 copied the ten raw words into `errors` and
published them as code values, so a single "excessive drive power" fault —
code `0x07`, word 0 bit 7 — appeared as fault `0x0080`. Every stored-fault
readout in both UIs was meaningless.

*Fixed:* `decodeFaultCodes()` turns the bitfield into real code numbers.

### 4. The fault code table was in the repository all along

Section 3.4.1 names **126 codes** and assigns each one a severity (warning, soft
fault, hard fault). v6.0 shipped no table, told operators in both UIs that the
specification was not available, and inferred a "likely cause" from whichever
telemetry threshold happened to be exceeded. The app went further and asked the
operator to supply their own JSON table.

*Fixed:* the table is generated from a single source (`tools/gen_faults.py`) into
the firmware's `acom_faults.h` and the app's `FaultCodes.swift`, and served at
`GET /api/faults` so the web UI needs no copy. The user-supplied table survives
as an override for wording and for the few codes the specification leaves blank.

Two documentation errors in the PDF are corrected in passing: word 9 prints its
codes as `0x80`–`0x8F`, duplicating word 8 (by bit position they are `0x90`–`0x9F`),
and byte 14 bit 7 prints `0x3F` where position gives `0x5F`. Codes are derived
from bit position throughout, never from the printed label.

### 5. 60m belongs with 40m, not 80m

Section 3.3.7, byte 13: *"Antenna Assigment and Selectivity for Bands **40m and
60m** (7,0 MHz and 5,0 MHz)"*. v6.0 labelled band 2 "80/60m" and routed
5.3 MHz to the 80m filter.

*Fixed:* band 3 is "40/60m" in the firmware, the web UI and the app, and
`getBandFromFrequency()` maps 5.25–5.45 MHz to code 3.

### 6. Hard/soft fault severity was guessed when the amplifier reports it

Section 3.4.8, byte 70 bit 0: *"Error Code is for last Hard Fault Error"*. Nobody
parsed byte 70. The app inferred severity from SWR and temperature thresholds.

*Fixed:* byte 70 is parsed and published as `errorIsHardFault`/`errorSeverity`;
the app uses it, and falls back to the specification's per-code severity.

---

## Functional bugs

### 7. Automatic telemetry was enabled once, two seconds after boot

v6.0 sent message 0x92 once at startup and set `telemetryEnabled = true`
unconditionally. If the amplifier was off or still starting, the enable was lost,
the link ran forever on the slower request/response fallback, and `/api/system`
reported telemetry as enabled anyway.

*Fixed:* the enable is re-sent every 3 s until streaming actually starts, re-armed
when the amplifier disconnects, and `telemetryEnabled` now reflects measured
reality — unsolicited frames outnumbering requests over a 2 s window.

### 8. POST endpoints never answered a body-less request

All six did their work in the body callback behind an empty `onRequest`, so a
`Content-Length: 0` POST was never answered and the client waited out its
timeout. They also ignored `index`/`total`, so a body split across TCP segments
was parsed from the first fragment alone — and because the callback runs once per
fragment, `request->send()` could fire twice.

*Fixed:* `readJsonBody()` accumulates and parses once on the final fragment, with
a bounds check against the buffer; `requireJsonBody()` answers the ones with no
body at all.

### 9. `/api/config` reported the access point as the configured network

In AP mode, `wifiSSID` was the controller's own SSID. The web form prefilled its
"WiFi SSID" field with it, so "Save WiFi & Reboot" stored `AcomControl` as the
network to join. The macOS app carried a hardcoded `!= "AcomControl"` guard
against exactly this.

*Fixed:* `wifiSSID` is the configured station SSID; `apSSID`, `apMode`, `apOpen`
and `apPassword` describe the access point separately. The app's workaround is
gone.

### 10. JSON was concatenated by hand

`/api/config`, `/api/wifi` and the error envelope built JSON with `+`, so an SSID
or hostname containing a quote or backslash produced invalid JSON — and
`/api/wifi` echoed a caller-supplied SSID straight back into it.

*Fixed:* built with ArduinoJson throughout.

### 11. No authentication, and an open access point

v6.0 ran `softAP()` with no passphrase and left every endpoint — including
firmware upload — unauthenticated. Anyone in radio range could key the amplifier
onto an arbitrary band or flash arbitrary firmware.

*Fixed:* a random WPA2 passphrase generated on first boot, kept in NVS, printed
on the serial console and readable at `/api/config`; plus optional HTTP Basic
auth across the web page, REST, WebSocket, SSE and OTA. Authentication is off by
default so upgrading cannot lock anyone out, but the serial log, `/api/system`,
the web UI and the app all say so when it is.

Implemented as server-wide middleware rather than a per-handler check: the
middleware chain runs once per request, while a check inside a body or upload
callback runs once per TCP fragment and would have fired a challenge per
fragment. Because that chain runs *after* the body callbacks have seen their
data, those callbacks check the credentials themselves and stay silent, leaving
the single 401 to the middleware.

### 12. Band and antenna changes under RF

The web UI claimed "Mode changes are refused while transmitting". Nothing refused
anything — not the page, not the firmware.

*Fixed:* the firmware refuses `setBand`, `setAntenna` and power-off while
transmitting unless the caller passes `force`, which is what both UIs' confirmation
dialogs now send. Standby and Operate are always allowed: dropping to standby
mid-carrier is the panic button, not a hazard. The web UI's note now describes
what actually happens.

### 13. Shared state read without its mutex

The band-follow logic and the command handlers read `ampState` directly from
tasks other than the one writing it, and `/api/history` read `historyCount`
outside the history mutex to size a response it then built inside it.

*Fixed:* both snapshot under the mutex; the history endpoint counts what it
actually emitted.

### 14. Dependencies pinned nothing

`platform = espressif32` and bare git URLs in `lib_deps`. "Pinned" meant
"whatever those point at today" — and today `espressif32` resolves to the
pioarduino 55.x line, whose build script fails outright on this project.

*Fixed:* `espressif32 @ 6.13.0`, `AsyncTCP @ 3.5.0`,
`ESPAsyncWebServer @ 3.12.0`, `ArduinoJson @ ~6.21.5`.

### 15. Other firmware fixes

- Rig-control frequency was only consulted when the amplifier reported no carrier
  at all, so a stale non-zero reading shadowed a live rig feed indefinitely.
- `getSystemInfoJSON` had 768 bytes for 22 fields plus a nested object and four
  copied strings. ArduinoJson 6 drops members silently on overflow, and discovery
  keys off `chipModel` being present. Both state and system documents are now
  sized with headroom and log a warning if they ever overflow anyway.
- `Preferences` was a single global object written from two tasks; now mutexed.
- Clearing faults re-requests the fault list immediately instead of waiting out
  the 2 s poll.
- `send_P` is deprecated in ESPAsyncWebServer 3.x; replaced.

---

## macOS app

### 16. "Load Controller History" fetched the data and threw it away

`HistoryView.importDeviceHistory()` awaited `fetchDeviceHistory()`, reported how
many samples came back, and then had nowhere to put them — `history` was
`private(set)` with no merge method. Both buttons that called it did nothing.

*Fixed:* `mergeHistory(_:)` folds them in, de-duplicating against what the app
recorded itself, and reports how many were actually added.

### 17. CSV export could not write anything

The target is sandboxed, `com.apple.security.files.user-selected.read-only` was
explicitly `false` and the read-write entitlement was absent — so `NSSavePanel`
appeared and the write then failed.

*Fixed:* `com.apple.security.files.user-selected.read-write` added. (The
`com.apple.security.network.local` key that was there is not a real entitlement;
local network access comes from `NSLocalNetworkUsageDescription`, which was
already present. Removed.)

### 18. Tooltips promised shortcuts that did not exist

The header advertised ⌘K for Connect and ⌘H for History. Neither command
existed; ⌘K was unbound. "Show Connection Log" fired the private
`showSettingsWindow:` selector, which opened Settings on whichever tab was last
used — not the log.

*Fixed:* an `AppRouter` owns the sheet and tab state, so ⌘K, ⌘H and a
Diagnostics-targeted "Show Connection Log" all work. The private selector is
gone.

### 19. The high-SWR alert could latch for the rest of the session

The latch cleared only below 2.2:1, but the amplifier holds its last SWR reading
after you unkey. An SWR that settled at or above 2.2 left it set permanently and
silenced every later alert. Alerts were also evaluated against stale telemetry
after the amplifier dropped off the serial link.

*Fixed:* the latch clears when transmission stops, and evaluation is skipped
entirely when the amplifier is not connected.

### 20. Every authorised alert chimed twice

`post()` played an `NSSound` and then set `content.sound = .default`.

*Fixed:* the notification carries its sound; the manual `NSSound` is now only the
fallback for when notifications are denied.

### 21. Chart legends rendered empty

`powerChart` and `thermalChart` declared a `chartForegroundStyleScale` but
coloured each mark with a literal `foregroundStyle(_:)`. Only
`foregroundStyle(by:)` feeds that scale or the legend, so the scales did nothing
and `chartLegend` had nothing to list. `swrChart` varied a single series' colour
per point, which resolves to whichever point drew last.

*Fixed:* marks style themselves `by:` series; the SWR line is one colour.

### 22. 10 Hz churn over an 18,000-element array

`removeFirst(1)` on a full history shifted the whole array on every frame —
~180,000 element moves a second. `recentSamples(seconds:)` found its cutoff with
`firstIndex(where:)`, a linear scan from the *oldest* sample, so a 60-second
window over a 30-minute history walked ~17,400 elements — per gauge, per body
evaluation, ten times a second.

*Fixed:* trimming happens in blocks (amortised to one copy per 200 s) and the
cutoff is found by binary search. `TelemetrySample.id` is a counter rather than a
`UUID`, which were being allocated ten a second for an identity that never leaves
the process.

### 23. `AmplifierState` round-tripped incorrectly

It declared `Codable`, but its hand-written decoder rescales as it reads (SWR
÷100, Kelvin → °C). The synthesised `encode(to:)` wrote the *scaled* values back
under the same keys, so encode-then-decode scaled twice. Nothing encoded it yet.

*Fixed:* `Decodable` only.

### 24. Other app fixes

- REST calls went through `URLSession.shared`, ignoring the session configured in
  `init()`. Now they use it, and carry credentials.
- The antenna picker fired a command and showed nothing while it was in flight,
  so a refused change silently snapped back. It now shows a pending state and
  clears it when the amplifier confirms.
- Info.plist hardcoded `2.0`/`2` while the project said `1.0`/`1`; with
  `GENERATE_INFOPLIST_FILE=NO` the plist won. Both now come from
  `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`, and the `INFOPLIST_KEY_*`
  settings that were being ignored are real plist keys instead.
- `AccentColor` was an empty colour set that `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`
  pointed at; the app icon had one of ten slots filled. Both filled in.
- Credentials are stored per host in the login keychain, and the app prompts when
  a controller answers 401.

---

## Documentation

The band tables in `Arduino (ESP32) code/README.md` and `QUICK_REFERENCE.md`
documented the buggy eleven-slot numbering rather than the specification.
`API_DOCUMENTATION.md` documented the conversion as intended behaviour.
`INTERFACE_DESIGN.md` showed ten buttons ending at 10m with a 60m button that
never existed, while the app shipped 6m. Both app documents said "160m – 10m".
The fan range was documented as 0–15. All corrected, and the README now says
plainly that the gauge full-scale values assume a 600S even though a 500S manual
sits in the directory.

---

## Firmware v6.0 / macOS app v2.0

Every item below was found by reviewing the v5.0 firmware and v1.0 app.

---

## Bugs fixed

### 1. REST API contract was broken — network discovery could never succeed

`API_DOCUMENTATION.md` and the macOS app both expected a `{success, timestamp, data}`
envelope with a documented `SystemInfo` schema. The firmware returned bare JSON
with different key names (`chip` not `chipModel`, `ip` not `ipAddress`, no
`performance` object, no `chipRevision`/`flashSize`/`psramSize`/`wifiSSID`).

The app's `SystemInfo` used non-optional `let`s, so decoding threw for **every**
address probed. Consequences:

- **The Discover button could never find a device**, even one answering HTTP 200.
- `fetchStatus()` and `getSystemInfo()` always threw; "Refresh System Info"
  silently did nothing because the error was swallowed into a `print`.

The WebSocket path worked, which is why the app looked functional until you
touched anything REST.

*Fixed:* firmware emits the documented envelope and full schema. The app decodes
leniently and falls back to the bare v5.0 format, so an un-updated controller
still appears in discovery.

### 2. "Clear Errors" was unreachable and the fault list was always empty

`MSG_ERROR_CODES` (0x21) was **never requested** — `requestMessage()` was only
ever called with PCB versions, band info and telemetry. So `errorCodes[]` stayed
zero, `errors` was always `[]`, and `ErrorDisplayView` — gated on
`!errors.isEmpty` — never rendered. The Clear Errors button lived inside that
view, so it existed only in the web UI.

`errorCode`/`errorParam` arrived on every telemetry frame, were parsed and
serialised, and were never displayed anywhere.

*Fixed:* the fault log is polled every 2 s. Faults are shown with severity, the
live fault code and parameter, and a cause inferred from telemetry. Clear Soft
Faults is also reachable from the menu bar and ⇧⌘K.

### 3. Band display was wrong on 40m and above

`setBand` converted display→amplifier codes because the amplifier carries a
separate 60m slot. The reverse conversion was missing: `MSG_BAND_INFO` byte 5 was
stored raw and then rendered as a display code. On 40m the amplifier reports 4,
so the UI showed "30m" and highlighted the wrong button. Because band info is
re-polled every 10 s, the wrong value always won over the correct LPF-derived one.

*Fixed:* `uiBandToAmpBand()` / `ampBandToUiBand()` are applied in both
directions. Display codes 1–10 are the only numbering that leaves the controller.

### 4. `strcmp` on a NULL pointer crashed the controller

`const char* cmd = doc["cmd"];` followed by `strcmp(cmd, …)`. Any WebSocket
client sending valid JSON without a `cmd` key panicked the device — a one-packet
remote reboot on the open AP. `data[len] = 0` also wrote one byte past the frame.

*Fixed:* null-checked, bounds-checked into a fixed buffer, and unknown commands
return an error envelope instead of being ignored.

### 5. Blocking `delay()` inside the AsyncTCP callback

`sendMessage()` did `delay()` + `Serial2.flush()` while holding a mutex, and was
called from the WebSocket handler and the `/api/mode` and `/api/band` handlers —
all of which run on the AsyncTCP task. Blocking there stalls the whole web server
and can trip the watchdog. This is the most common cause of ESPAsyncWebServer
crashes.

*Fixed:* all amplifier writes go through a FreeRTOS queue drained by the serial
task. No web handler touches the UART.

`ws.textAll()` also ran at a fixed 10 Hz with no queue check, letting one slow
client exhaust the heap. Broadcasts are now gated on `availableForWriteAll()`.

### 6. No Wi-Fi reconnection

`setupWiFi()` connected once at boot. If the access point dropped afterwards
there was no retry and no event handler — the controller stayed off the network
until someone power-cycled it.

*Fixed:* `setAutoReconnect`, sleep disabled, and a 5 s watchdog in `loop()`.

### 7. Fan speed displayed as a percentage that wasn't one

Telemetry byte 69 carries a 0–15 level in its upper nibble. Both clients rendered
it as `"\(fanSpeed)%"`, so a fan running flat out showed "15%".

*Fixed:* firmware publishes `fanLevel` (0–15) and a derived `fanSpeed` percentage;
the UI shows both.

### 8. The debug log was unusable

`receiveMessage()` logged two lines per frame at 10 Hz — 20 entries/second into a
50-entry buffer, so it held 2.5 seconds of noise and any real error scrolled away
before Settings could be opened. Each line also did a `DispatchQueue.main.async`
plus a `@Published` mutation, re-rendering the log list 20×/second.

*Fixed:* one summary line per 10 seconds, a 300-entry buffer, errors and successes
colour-coded, and a Copy button.

### 9. Reboots inside async callbacks dropped the HTTP response

`/api/wifi` called `delay(500); ESP.restart()` inside the request handler, so the
client usually saw a dropped connection rather than the success reply.

*Fixed:* reboots are deferred to `loop()` via a timestamp, after the response is
flushed.

### 10. Smaller defects

- **⌘, opened a broken second Settings window.** `SettingsView` was designed as a
  sheet — own "Done" header, `@Environment(\.dismiss)` — but was also placed in a
  `Settings` scene where `dismiss` does nothing. Now one view with an `isSheet`
  flag, rendered as a proper tabbed Settings window from ⌘,.
- **Negative progress-bar widths.** Meter bars had `min(…)` but no `max(0, …)`;
  a garbage temperature frame reads `0 K − 273 = −273 °C` and produced negative
  frame widths. Gauge fractions are now clamped to 0…1.
- **Duplicate SwiftUI IDs.** `ForEach(errors, id: \.self)` collided when the
  amplifier reported the same code in two log slots. Fault identity now combines
  slot index and code.
- **Band buttons silently reset the antenna.** `setBand` hardcoded `"antenna": 1`,
  overriding the operator's selection with no indication. Band changes now keep
  the current antenna, and there is an antenna picker.
- **Discovery progress was a lie.** `scannedCount = i` counted tasks *launched*,
  so the bar hit 254/254 in milliseconds then sat there. It now counts completions.
- **Redundant timer installation.** `Timer.scheduledTimer` already installs on the
  run loop; the extra `RunLoop.main.add` was removed.
- **Open-network Wi-Fi could not be configured** — Save was disabled until a
  password was typed.
- **Inconsistent Settings padding** — two of five GroupBoxes had extra horizontal
  padding, so they were visibly inset from the rest.
- **`getWebPage()` built a ~9 KB String on every request**, fragmenting the heap.
  Now served from PROGMEM via `send_P`.
- **`platformio.ini` declared `me-no-dev/ESPAsyncWebServer`** but actually resolved
  to the ESP32Async fork — declared and built sources disagreed. Now pinned to the
  fork genuinely in use.
- **SWR shown as `1.3`** rather than `1.30`; **forward power as `450.0 W`** for an
  integer watt count; **frequency as `14250 kHz`** rather than `14.250 MHz`.

---

## Interface work

- **Arc gauges with peak-hold needles** for forward power, SWR and PA temperature,
  with coloured warning and danger arcs — the instrument idiom from the
  amplifier's own front panel, replacing flat horizontal bars.
- **Per-gauge sparklines** showing the last 60 seconds.
- **Full-width transmit banner** that turns the top of the window red and shows
  live power and SWR while keyed. Transmit state was previously one small tile
  among eight.
- **Peak and average forward power** — SSB peaks are what matter; a bar at 10 Hz
  just flickers.
- **Confirmation dialogs** for Power Off and for band changes while transmitting
  (hot-switching the antenna relays is exactly what the amplifier protects against).
- **Connection-failure banner with a Retry button.** The controller previously
  gave up permanently after ten attempts and said so only in the debug log.
- **Human-readable faults** with severity badges, the live fault code and
  parameter, and an inferred cause.
- **Disconnect/Connect in the main window**, not buried in Settings.
- **Wrapping band grid** (`LazyVGrid` adaptive) instead of a fixed ten-wide row.
- **Antenna selector** — the amplifier supports 1–10 and the field was read-only.
- **Band mismatch warning** when the rig's frequency implies a different band
  than the selected low-pass filter.
- **Accessibility** — labels, values and selected traits throughout; danger states
  carry text and icons, not colour alone.
- **Controller vs amplifier state distinguished** in the status pill: reaching the
  ESP32 and reaching the amplifier are different things.

---

## New features

### Firmware

- **mDNS** — `acomcontrol.local`, advertising `_http._tcp` and `_acom._tcp` with
  version/model TXT records. Discovery no longer needs a 254-address sweep.
- **OTA updates** — ArduinoOTA (espota) plus browser upload at `POST /api/ota`.
- **Telemetry history** — an in-RAM ring buffer (600 samples, 1800 with PSRAM) at
  `GET /api/history`, plus a rotating CSV session log on LittleFS at
  `/api/history/download`. Logged every second while transmitting and every 30 s
  otherwise, to limit flash wear.
- **CAT / rig integration** — automatic band following from the amplifier's own
  frequency counter or from an external rig-control client posting to
  `/api/frequency`. Never switches bands while transmitting; 3 s hold-off.
- **`/api/config`** for hostname, band-follow, logging and OTA password.
- **`/api/command`** generic endpoint mirroring the WebSocket commands.
- **v5.0 credential migration** — Wi-Fi settings stored under the old `wifi`
  namespace are carried across automatically.
- Rebuilt web UI: arc gauges, sparklines, TX banner, fault panel, antenna
  selector, config toggles, OTA upload, log download, light/dark adaptive.

### macOS app

- **Auto-connect on launch.** v1.0 loaded `lastConnectedIP` into `connectedIP`
  and then deliberately never used it.
- **Multiple saved controllers** with naming, per-device auto-connect and forget,
  replacing the single `UserDefaults` string.
- **Menu bar extra** showing TX state, power, SWR and temperature, with Standby /
  Operate / Clear controls — status without keeping the window in front.
- **Notifications and audible alerts** for high SWR, overtemperature, faults and
  disconnection. Edge-triggered with hysteresis and a 30 s floor, so a sustained
  condition produces one banner, not a stream. Falls back to bouncing the Dock
  icon when notifications are denied.
- **Session statistics** — peak and average power, peak SWR, peak temperature and
  drain current, transmit time, transmission count, duty cycle.
- **History window** with Swift Charts time series (power, SWR with the 2.0:1
  protection line, temperature and drain current) over 1/5/15-minute or
  whole-session windows, plus CSV export and import of the controller's own
  stored telemetry.
- **Keyboard shortcuts** — ⌘1 Standby, ⌘2 Operate, ⇧⌘K clear faults, ⌘D
  disconnect, ⌘R reconnect, ⌘E export, plus a Band submenu.
- **Bonjour discovery** via `NWBrowser` with the subnet sweep kept as a fallback.
- **User-supplied fault code table** (see below).

---

## A deliberate omission: fault code text

The ACOM user manual bundled with this project documents the three protection
levels (WARNING, SOFT FAULT, HARD FAULT) and example message wording, but the
numeric **code-to-text table lives in the ACOM RS-232 specification**, which is
not in this repository.

Rather than invent a mapping that would confidently mislabel faults on real
hardware, the app:

1. shows the raw code and parameter verbatim;
2. infers a likely cause from the telemetry captured at the moment of the fault
   (SWR, reflected power, PA temperature, drain current, drive power, missing
   LPF) against the thresholds the manual documents; and
3. reads an **optional user-supplied table** so anyone with the specification can
   supply real names.

Settings → Alerts → *Reveal Fault Code Table* creates and opens:

```
~/Library/Containers/com.acomcontrol.AcomControl/Data/Library/Application Support/AcomControl/fault-codes.json
```

```json
{ "0x2A": "Excessive reflected power", "0x31": "PA overtemperature" }
```

Codes may be written as `"0x2A"`, `"2A"` or `"42"`.

---

## Not done, by request

- Authentication on control endpoints. The API remains unauthenticated and the
  fallback AP remains open — anyone who can reach port 80 can switch the
  amplifier off or rewrite its Wi-Fi credentials. Keep it on a trusted network.
- iOS/iPadOS target.
