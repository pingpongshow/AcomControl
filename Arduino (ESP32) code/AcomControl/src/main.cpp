/*
 * AcomControl - ACOM 600S Amplifier Controller
 * ESP32-S3 firmware with REST/WebSocket/SSE API
 *
 * VERSION: 7.0
 *
 * CHANGES FROM v6.0
 * -----------------
 * Every item below was found by checking this firmware against the protocol
 * document that ships beside it ("ACOM Protocol.pdf"). Section references are
 * to that document.
 *
 *  1. BAND CODES ARE NO LONGER SHIFTED. Section 5.1 (command 0x09 accepts
 *     0x01-0x0A, and the command 0x0C band-relay table) gives the amplifier's
 *     band numbering as 1=160m 2=80m 3=40m 4=30m 5=20m 6=17m 7=15m 8=12m
 *     9=10m 10=6m, which is exactly the numbering the UI uses. There is no
 *     separate 60m band number. v6.0 added +1 to every code from 40m upwards,
 *     so asking for 40m selected 30m, asking for 20m selected 17m, and asking
 *     for 6m sent 0x0B - outside the documented range entirely. The matching
 *     reverse conversion on message 0x27 hid the error, so the display agreed
 *     with the button while the amplifier sat on the wrong low-pass filter.
 *  2. FAN SPEED SCALE. Section 3.4.8 byte 69: "FAN Speed [0..4]". v6.0 divided
 *     by 15, so a fan at full speed reported 27%.
 *  3. MESSAGE 0x21 IS A BITFIELD. Section 3.4.1: ten 16-bit words where bit n
 *     of word k means fault code (k*16)+n is active. v6.0 published the raw
 *     words as if they were code values, so a single "excessive drive power"
 *     fault appeared as fault 0x0080. Now decoded into real code numbers.
 *  4. FAULT CODE TABLE. Section 3.4.1 names 126 codes and gives each a
 *     severity. v6.0 shipped no table and told operators the specification was
 *     unavailable. It is in acom_faults.h and served at GET /api/faults.
 *  5. 60m BELONGS WITH 40m. Section 3.3.7 byte 13 covers "Bands 40m and 60m".
 *     v6.0 folded 60m into the 80m slot.
 *  6. HARD/SOFT FAULT FLAG. Section 3.4.8 byte 70 bit 0 says whether the
 *     reported error code belongs to the last hard fault. Now parsed.
 *  7. AUTOMATIC TELEMETRY IS RE-ARMED. v6.0 sent message 0x92 once, two
 *     seconds after boot. If the amplifier was off at that moment the link ran
 *     forever on the slower request/response fallback while /api/system still
 *     claimed telemetry was enabled.
 *  8. POST HANDLERS ANSWER EVERY REQUEST. v6.0 did all its work in the body
 *     callback behind an empty onRequest, so a body-less POST was never
 *     answered, and a body split across TCP segments was parsed from the first
 *     fragment alone (and could send two responses).
 *  9. /api/config NO LONGER CONFUSES THE AP SSID WITH THE CONFIGURED ONE, so
 *     the web form stops offering to join the controller's own access point.
 * 10. JSON IS BUILT WITH ArduinoJson, NOT STRING CONCATENATION, so an SSID or
 *     hostname containing a quote or backslash can no longer produce invalid
 *     JSON or inject into a response.
 * 11. OPTIONAL AUTHENTICATION, AND A CLOSED ACCESS POINT. v6.0 ran an open AP
 *     and left every endpoint - including firmware upload - unauthenticated.
 * 12. Shared state is read under its mutex in the band-follow logic and the
 *     command handlers; the history endpoint no longer reads its count outside
 *     the history mutex.
 * 13. Band and antenna changes are refused while transmitting unless the
 *     caller passes "force", which is what the UIs' confirmation dialogs now
 *     send. Powering off mid-transmission needs the same flag.
 *
 * FEATURES
 * --------
 *  - mDNS: reachable at http://acomcontrol.local, advertises _http._tcp and
 *    _acom._tcp so clients can discover it without scanning the subnet.
 *  - OTA updates: ArduinoOTA (espota) plus browser upload at POST /api/ota.
 *  - Telemetry history: in-RAM ring buffer exposed at /api/history plus a
 *    rotating CSV session log on LittleFS at /api/history/download.
 *  - CAT / rig integration: automatic band following from the amplifier's own
 *    frequency reading or from an external rig-control client that POSTs to
 *    /api/frequency. Never switches bands while transmitting.
 *  - /api/config for runtime settings (hostname, band follow, logging, AP and
 *    API passwords).
 *  - GET /api/faults serves the fault code table so clients need no copy.
 *
 * HARDWARE: ESP32-S3 DevKit
 *  - UART2 for RS-232 to the amplifier. RX: GPIO16, TX: GPIO17, 9600 8N1.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <Update.h>
#include <ESPAsyncWebServer.h>
#include <AsyncTCP.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <esp_chip_info.h>
#include <esp_heap_caps.h>

#include "acom_faults.h"
#include "web_page.h"

#define FIRMWARE_VERSION "7.0"

// ============================================================================
// ACOM PROTOCOL CONSTANTS (from official documentation)
// ============================================================================

#define ACOM_START_BYTE 0x55

// Message addresses - From Amplifier to Computer
#define MSG_ERROR_REPLY     0x01
#define MSG_REQUEST         0x02
#define MSG_PCB_VERSIONS    0x11  // PCB Versions (30 bytes)
#define MSG_SETTINGS        0x12  // Amplifier settings (13 bytes)
#define MSG_SERIAL_NUMBER   0x13  // Serial number (16 bytes)
#define MSG_USER_SIGN_1     0x14
#define MSG_USER_SIGN_2     0x15
#define MSG_ATU_PARAMS      0x16
#define MSG_ASEL_PARAMS     0x17
#define MSG_ANTENNA_NAMES   0x18
#define MSG_ERROR_CODES     0x21  // Error codes (24 bytes)
#define MSG_BAND_INFO       0x27  // Band info (17 bytes)
#define MSG_BAND_SEGMENTS   0x28
#define MSG_TELEMETRY       0x2F  // Main telemetry (72 bytes)

// Message addresses - From Computer to Amplifier
#define MSG_CMD_AMPLIFIER   0x81  // Commands for amplifier management (8 bytes)
#define MSG_SET_SERIAL      0x82
#define MSG_SET_HELLO_1     0x83
#define MSG_SET_HELLO_2     0x84
#define MSG_SET_ANTENNA     0x85
#define MSG_ACKNOWLEDGE     0x86  // Acknowledge message (5 bytes)
#define MSG_TELEMETRY_DIS   0x91  // Disable automatic telemetry (4 bytes)
#define MSG_TELEMETRY_EN    0x92  // Enable automatic telemetry (4 bytes)

// Amplifier commands (parameter of message 0x81)
#define ACOM_CMD_REQUEST      0x01  // Request for a specific message
#define ACOM_CMD_SET_MODE     0x02  // Request for amplifier mode change
#define ACOM_CMD_CLEAR_ERRORS 0x08  // Clear SOFT FAULT errors
#define ACOM_CMD_SET_BAND     0x09  // Manual changing of antenna and band

// Amplifier modes (payload of command 0x02)
#define AMP_MODE_RESTART    0x01
#define AMP_MODE_RESTART2   0x02
#define AMP_MODE_DEBUG      0x03
#define AMP_MODE_SERVICE    0x04
#define AMP_MODE_STB        0x05
#define AMP_MODE_OPR_RX     0x06
#define AMP_MODE_OPR_TX     0x07
#define AMP_MODE_ATAC       0x08
#define AMP_MODE_MENU       0x09
#define AMP_MODE_POWEROFF   0x0A

// Telemetry byte 69 (section 3.4.8): fan speed in bits 4-7, active low-pass
// filter channel in bits 0-3. The fan range is 0..4, not 0..15.
#define FAN_LEVEL_MAX 4

// Telemetry byte 70 (section 3.4.8)
#define SYS_STATUS_ERROR_IS_HARD_FAULT 0x01

// Amplifier state codes (high nibble of the telemetry mode byte)
#define STATE_RESET         0x10
#define STATE_INIT          0x20
#define STATE_DEBUG         0x30
#define STATE_SERVICE       0x40
#define STATE_STB           0x50
#define STATE_OPR_RX        0x60
#define STATE_OPR_TX        0x70
#define STATE_ATAC          0x80
#define STATE_MENU          0x90
#define STATE_POWEROFF      0xA0

// ============================================================================
// HARDWARE CONFIGURATION
// ============================================================================

#define RXD2 16
#define TXD2 17
#define BAUD_RATE 9600

// ============================================================================
// GLOBAL OBJECTS
// ============================================================================

AsyncWebServer server(80);
AsyncWebSocket ws("/ws");
AsyncEventSource events("/api/telemetry");
Preferences preferences;

struct AmplifierState {
  bool connected = false;
  uint8_t mode = 0;
  uint16_t forwardPower = 0;    // [W]
  uint16_t reflectedPower = 0;  // [W]
  uint16_t swr = 100;           // [100x] so 150 = 1.50
  uint16_t temperature = 273;   // [deg K]
  uint16_t inputPower = 0;      // [10 x W] so 253 = 25.3 W
  uint16_t current = 0;         // [mA]
  uint16_t frequency = 0;       // [kHz]
  uint8_t band = 0;             // band code 1..10 (see BAND CODES below)
  uint8_t antennaNum = 0;
  uint8_t antennaType = 0;
  bool isTx = false;

  // Fault codes decoded from message 0x21. That message is a bitfield of ten
  // 16-bit words, so up to 160 codes can be active at once; in practice the
  // amplifier reverts to standby long before that, and 32 is ample. v6.0
  // stored the ten raw words here and published them as if they were codes.
  uint8_t faultCodes[32] = {0};
  uint8_t faultCount = 0;

  char serialNumber[13] = {0};
  uint8_t fanLevel = 0;         // raw 0..FAN_LEVEL_MAX
  uint16_t hvVoltage = 0;       // [10 x V]
  uint16_t vcc5 = 0;            // [mV]
  uint16_t vcc26 = 0;           // [10 x V]
  uint16_t pdcPower = 0;        // [10 x W]
  uint16_t disPower = 0;        // [10 x W]
  uint8_t lpfChannel = 0;
  uint8_t errorCode = 0;        // code on the amplifier's screen (byte 66)
  uint16_t errorParam = 0;
  bool errorIsHardFault = false;  // byte 70 bit 0
  uint32_t lastUpdate = 0;
  uint32_t msgCount = 0;
} ampState;

SemaphoreHandle_t stateMutex;
SemaphoreHandle_t serialMutex;
SemaphoreHandle_t prefsMutex;

// ---------------------------------------------------------------------------
// Persisted configuration
// ---------------------------------------------------------------------------

String cfgSsid = "";
String cfgPassword = "";
String cfgHostname = "acomcontrol";
String cfgOtaPassword = "";
bool cfgAutoBandFollow = false;
bool cfgLogEnabled = true;

// Access point passphrase. v6.0 ran softAP() with no passphrase at all, so
// anyone in radio range could change bands or flash firmware on a 600 W
// amplifier. A random one is generated on first boot and kept in NVS; it is
// printed on the serial console at every boot and readable at GET /api/config
// over the station link, so it can always be recovered. Setting it to the empty
// string deliberately reopens the AP.
String cfgApPassword = "";

// Optional HTTP Basic credentials for the web UI and the whole API. Empty means
// no authentication, which is still the default so that upgrading does not lock
// anyone out of their own controller - but /api/system and the serial log now
// say so out loud.
String cfgApiUser = "acom";
String cfgApiPassword = "";

bool apMode = true;
const char* apSSID = "AcomControl";

#define AP_PASSWORD_LENGTH 10
#define MIN_WPA2_PASSWORD 8

// ---------------------------------------------------------------------------
// Outbound command queue (drained by serialTask, never blocks the caller)
// ---------------------------------------------------------------------------

struct OutboundMessage {
  uint8_t address;
  uint8_t dataLen;
  uint8_t data[6];
};

QueueHandle_t txQueue = NULL;
#define TX_QUEUE_DEPTH 24

// ---------------------------------------------------------------------------
// Telemetry history ring buffer
// ---------------------------------------------------------------------------

struct HistorySample {
  uint32_t t;        // millis()
  uint16_t fwd;      // [W]
  uint16_t ref;      // [W]
  uint16_t swr;      // [100x]
  uint16_t tempK;    // [deg K]
  uint16_t mA;       // [mA]
  uint16_t freq;     // [kHz]
  uint8_t band;      // UI band code
  uint8_t flags;     // bit0 = TX, bit1 = amplifier connected
};

HistorySample* history = NULL;
uint16_t historyCapacity = 0;
uint16_t historyCount = 0;
uint16_t historyHead = 0;
SemaphoreHandle_t historyMutex;

#define HISTORY_CAPACITY_PSRAM 1800  // 30 minutes at 1 Hz
#define HISTORY_CAPACITY_HEAP  600   // 10 minutes at 1 Hz

// ---------------------------------------------------------------------------
// Session log on LittleFS
// ---------------------------------------------------------------------------

#define LOG_PATH      "/acomlog.csv"
#define LOG_PATH_PREV "/acomlog.1.csv"
#define LOG_MAX_BYTES (384UL * 1024UL)

bool fsReady = false;
uint32_t logBytes = 0;

// ---------------------------------------------------------------------------
// Serial framing
// ---------------------------------------------------------------------------

uint8_t rxBuffer[128];
uint8_t txBuffer[128];
int rxIndex = 0;
unsigned long rxStartTime = 0;
unsigned long lastMessageTime = 0;
unsigned long lastRxTime = 0;

// Automatic telemetry (message 0x92) state. v6.0 sent 0x92 once, two seconds
// into boot, and set this flag unconditionally - so if the amplifier was off or
// still starting, the enable was lost, the link quietly fell back to polling
// forever, and /api/system reported telemetry as enabled anyway. The enable is
// now re-sent whenever the amplifier appears, and the flag only goes true once
// frames actually start arriving unprompted.
bool telemetryEnabled = false;
unsigned long telemetryEnableSentAt = 0;
uint32_t telemetryRequests = 0;  // requests we sent this evaluation window
uint32_t telemetryFrames = 0;    // 0x2F frames that arrived this window

const unsigned long TELEMETRY_ENABLE_RETRY = 3000;
const unsigned long TELEMETRY_EVAL_INTERVAL = 2000;
const unsigned long RX_FRAME_TIMEOUT = 100;

// Performance tuning
const int TELEMETRY_INTERVAL = 200;      // Poll telemetry every 200 ms
const int ERRORS_INTERVAL = 2000;        // Poll error codes every 2 s
const int BAND_INFO_INTERVAL = 10000;    // Poll band info every 10 s
const int MESSAGE_DELAY = 15;            // Minimum gap between messages (spec: 10 ms)
const int WS_BROADCAST_INTERVAL = 100;   // WebSocket broadcast at 10 Hz
const int SSE_BROADCAST_INTERVAL = 200;  // SSE at 5 Hz
const int CONNECTION_TIMEOUT = 5000;     // 5 s without data = amplifier gone

// Counters exposed through /api/system
uint32_t wsUpdateCount = 0;
uint32_t sseUpdateCount = 0;
uint32_t serialRxCount = 0;

// Deferred reboot (never restart from inside an async callback)
uint32_t rebootAt = 0;

// External rig-control frequency (POST /api/frequency)
uint16_t externalFreq = 0;
uint32_t externalFreqTime = 0;
#define EXTERNAL_FREQ_TTL 10000

uint32_t lastAutoBandChange = 0;
#define AUTO_BAND_HOLDOFF 3000

TaskHandle_t serialTaskHandle = NULL;

#define DEBUG_SERIAL 0
#define DEBUG_RX 0
#define DEBUG_TX 0

// ============================================================================
// FUNCTION PROTOTYPES
// ============================================================================

void loadConfig();
void saveWiFiConfig(const String& ssid, const String& pass);
bool isAuthenticated(AsyncWebServerRequest* request);
void setupAuthMiddleware();
void setupWiFi();
void setupMDNS();
void setupOTA();
void setupFilesystem();
void setupWebServer();
void setupAPIEndpoints();
void serialTask(void* parameter);
void handleSerial();
void processMessage(uint8_t* msg, int len);
void sendMessage(uint8_t address, const uint8_t* data, int dataLen);
uint8_t calculateChecksum(const uint8_t* msg, int len);
bool verifyChecksum(const uint8_t* msg, int len);
void queueMessage(uint8_t address, const uint8_t* data, int dataLen);
void queueAmplifierCommand(uint8_t cmd, uint8_t paramHW, uint8_t paramLW, uint8_t buttons);
void queueRequestMessage(uint8_t msgNum);
void sendAcknowledge(uint8_t msgAddr);
void broadcastState();
void broadcastSSE();
void recordHistory();
void appendLogLine(const HistorySample& s);
String getModeString(uint8_t mode);
String getBandString(uint8_t band);
String getStateJSON();
String getSystemInfoJSON();
void addCORSHeaders(AsyncWebServerResponse* response);
bool handleClientCommand(const JsonDocument& doc, String& errorOut);
uint8_t getBandFromFrequency(uint16_t freqKHz);
uint8_t decodeFaultCodes(const uint8_t* msg, uint8_t* out, uint8_t outMax);

// ============================================================================
// BAND CODES
// ============================================================================
//
// There is ONE band numbering, shared by the amplifier, the low-pass filter
// channel in telemetry byte 69 and both user interfaces:
//
//   1=160m  2=80m  3=40m  4=30m  5=20m  6=17m  7=15m  8=12m  9=10m  10=6m
//
// Section 5.1 of the protocol document fixes this twice over: command 0x09
// ("manual changing of antenna and band") documents its band parameter as
// "0x01 - 0x0A", and the command 0x0C band-select relay test spells the ten
// bands out in order, 0x01 = 160m through 0x0A = 6m. Telemetry byte 69
// documents the active LPF channel as [0..10] to match.
//
// 60m has no band number of its own. Section 3.3.7 byte 13 groups it with 40m
// ("Antenna Assigment and Selectivity for Bands 40m and 60m"), so 5 MHz
// operation uses the 40m low-pass filter and band code 3.
//
// v6.0 believed in an eleven-slot amplifier numbering with 60m at 3 and
// converted between that and the UI, which shifted every band from 40m
// upwards by one. No conversion is needed or wanted; a band code is a band
// code. The only thing worth doing here is validating the range.

#define BAND_CODE_MIN 1
#define BAND_CODE_MAX 10
#define ANTENNA_MIN   1
#define ANTENNA_MAX   10

inline bool isValidBand(uint8_t band) {
  return band >= BAND_CODE_MIN && band <= BAND_CODE_MAX;
}

inline bool isValidAntenna(uint8_t antenna) {
  return antenna >= ANTENNA_MIN && antenna <= ANTENNA_MAX;
}

uint8_t getBandFromFrequency(uint16_t freqKHz) {
  if (freqKHz >= 1800 && freqKHz <= 2000) return 1;    // 160m
  if (freqKHz >= 3500 && freqKHz <= 4000) return 2;    // 80m
  if (freqKHz >= 5250 && freqKHz <= 5450) return 3;    // 60m -> 40m LPF
  if (freqKHz >= 7000 && freqKHz <= 7300) return 3;    // 40m
  if (freqKHz >= 10100 && freqKHz <= 10150) return 4;  // 30m
  if (freqKHz >= 14000 && freqKHz <= 14350) return 5;  // 20m
  if (freqKHz >= 18068 && freqKHz <= 18168) return 6;  // 17m
  if (freqKHz >= 21000 && freqKHz <= 21450) return 7;  // 15m
  if (freqKHz >= 24890 && freqKHz <= 24990) return 8;  // 12m
  if (freqKHz >= 28000 && freqKHz <= 29700) return 9;  // 10m
  if (freqKHz >= 50000 && freqKHz <= 54000) return 10; // 6m
  return 0;
}

// ============================================================================
// FAULT CODE DECODING (message 0x21, section 3.4.1)
// ============================================================================
//
// Ten 16-bit words, little-endian, starting at byte 3. Bit n of word k means
// fault code (k * 16) + n is active. v6.0 copied the ten words out verbatim
// and published them as "errors", so one active fault showed up as a nonsense
// code like 0x0080 (word 0, bit 7 = code 0x07, "excessive drive power").
//
// Returns the number of codes written to `out`.
uint8_t decodeFaultCodes(const uint8_t* msg, uint8_t* out, uint8_t outMax) {
  uint8_t count = 0;
  for (uint8_t word = 0; word < 10; word++) {
    int offset = 3 + (word * 2);
    uint16_t bits = (uint16_t)msg[offset] | ((uint16_t)msg[offset + 1] << 8);
    if (bits == 0) continue;
    for (uint8_t bit = 0; bit < 16 && count < outMax; bit++) {
      if (bits & (1u << bit)) out[count++] = (uint8_t)((word * 16) + bit);
    }
  }
  return count;
}

// ============================================================================
// SETUP
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println("\n\n========================================");
  Serial.println("  AcomControl ESP32-S3 v" FIRMWARE_VERSION);
  Serial.println("  ACOM 600S Serial Protocol Controller");
  Serial.println("========================================");

  setCpuFrequencyMhz(240);
  Serial.printf("CPU Frequency: %d MHz\n", getCpuFrequencyMhz());

  Serial2.setRxBufferSize(1024);
  Serial2.setTxBufferSize(512);
  Serial2.begin(BAUD_RATE, SERIAL_8N1, RXD2, TXD2);
  Serial.printf("UART2 initialized: %d baud, RX=%d, TX=%d\n", BAUD_RATE, RXD2, TXD2);

  stateMutex = xSemaphoreCreateMutex();
  serialMutex = xSemaphoreCreateMutex();
  historyMutex = xSemaphoreCreateMutex();
  prefsMutex = xSemaphoreCreateMutex();
  txQueue = xQueueCreate(TX_QUEUE_DEPTH, sizeof(OutboundMessage));

  if (!stateMutex || !serialMutex || !historyMutex || !prefsMutex || !txQueue) {
    Serial.println("FATAL: Failed to create RTOS primitives!");
    while (1) delay(1000);
  }

  // Telemetry history ring, preferring PSRAM when the board has it
  historyCapacity = HISTORY_CAPACITY_HEAP;
  if (ESP.getPsramSize() > 0) {
    history = (HistorySample*)ps_malloc(sizeof(HistorySample) * HISTORY_CAPACITY_PSRAM);
    if (history) historyCapacity = HISTORY_CAPACITY_PSRAM;
  }
  if (!history) {
    history = (HistorySample*)malloc(sizeof(HistorySample) * HISTORY_CAPACITY_HEAP);
    historyCapacity = history ? HISTORY_CAPACITY_HEAP : 0;
  }
  Serial.printf("Telemetry history: %u samples (%u bytes)\n",
                historyCapacity, (unsigned)(historyCapacity * sizeof(HistorySample)));

  loadConfig();
  setupFilesystem();
  setupWiFi();
  setupMDNS();
  setupOTA();

  setupAuthMiddleware();
  setupWebServer();
  setupAPIEndpoints();
  server.addHandler(&events);
  server.begin();

  Serial.println("Web server started!");
  Serial.print("Access web interface at: http://");
  Serial.println(apMode ? WiFi.softAPIP().toString() : WiFi.localIP().toString());
  Serial.printf("               or at: http://%s.local\n", cfgHostname.c_str());

  // Say this in both WiFi modes, not just AP: on a shared home network an
  // unauthenticated controller is reachable by every other device on it.
  if (cfgApiPassword.length() == 0) {
    Serial.println();
    Serial.println("WARNING: the API is unauthenticated. Anyone who can reach this");
    Serial.println("         controller can change bands, rewrite the WiFi settings");
    Serial.println("         or flash firmware. Set a password with:");
    Serial.println("         POST /api/config {\"apiPassword\":\"...\"}");
  } else {
    Serial.printf("API authentication enabled for user '%s'\n", cfgApiUser.c_str());
  }

  xTaskCreatePinnedToCore(serialTask, "SerialTask", 8192, NULL, 2, &serialTaskHandle, 0);

  Serial.println("\nSetup complete! Waiting for ACOM amplifier...\n");
}

// ============================================================================
// MAIN LOOP (Core 1)
// ============================================================================

void loop() {
  static unsigned long lastWsBroadcast = 0;
  static unsigned long lastSseBroadcast = 0;
  static unsigned long lastCleanup = 0;
  static unsigned long lastHistory = 0;
  static unsigned long lastWifiCheck = 0;

  unsigned long now = millis();

  ArduinoOTA.handle();

  // Deferred reboot, so async HTTP responses actually get flushed first
  if (rebootAt != 0 && now >= rebootAt) {
    Serial.println("Restarting...");
    ESP.restart();
  }

  if (now - lastCleanup >= 1000) {
    ws.cleanupClients();
    lastCleanup = now;
  }

  if (now - lastWsBroadcast >= WS_BROADCAST_INTERVAL) {
    broadcastState();
    lastWsBroadcast = now;
  }

  if (now - lastSseBroadcast >= SSE_BROADCAST_INTERVAL) {
    broadcastSSE();
    lastSseBroadcast = now;
  }

  if (now - lastHistory >= 1000) {
    recordHistory();
    lastHistory = now;
  }

  // Station-mode watchdog: v5.0 connected once at boot and never retried.
  if (!apMode && now - lastWifiCheck >= 5000) {
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("WiFi lost, reconnecting...");
      WiFi.reconnect();
    }
    lastWifiCheck = now;
  }

  delay(10);
}

// ============================================================================
// SERIAL TASK (Core 0) - sole owner of the UART
// ============================================================================

void serialTask(void* parameter) {
  Serial.println("Serial task started on Core 0");

  delay(2000);
  Serial.println("Enabling automatic telemetry...");
  sendMessage(MSG_TELEMETRY_EN, NULL, 0);
  telemetryEnableSentAt = millis();

  delay(100);
  queueRequestMessage(MSG_PCB_VERSIONS);
  queueRequestMessage(MSG_BAND_INFO);

  TickType_t xLastWakeTime = xTaskGetTickCount();
  const TickType_t xFrequency = pdMS_TO_TICKS(50);  // 20 Hz

  unsigned long lastBandInfoRequest = 0;
  unsigned long lastErrorRequest = 0;
  unsigned long lastTelemetryRequest = 0;
  unsigned long lastTelemetryEval = millis();

  for (;;) {
    handleSerial();

    unsigned long now = millis();

    // Drain queued commands from the web handlers
    OutboundMessage out;
    while (xQueueReceive(txQueue, &out, 0) == pdTRUE) {
      sendMessage(out.address, out.data, out.dataLen);
      handleSerial();  // keep the RX pipe moving between writes
    }

    // Snapshot the shared state once per pass. v6.0 read ampState fields
    // directly from this task while the AsyncTCP task could be writing them.
    bool ampConnected = false;
    bool ampIsTx = false;
    uint8_t ampBand = 0;
    uint8_t ampAntenna = 0;
    uint16_t ampFrequency = 0;
    if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(20)) == pdTRUE) {
      ampConnected = ampState.connected;
      ampIsTx = ampState.isTx;
      ampBand = ampState.band;
      ampAntenna = ampState.antennaNum;
      ampFrequency = ampState.frequency;
      xSemaphoreGive(stateMutex);
    }

    if (ampConnected && (now - lastRxTime > CONNECTION_TIMEOUT)) {
      if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        ampState.connected = false;
        Serial.println("ACOM amplifier disconnected (timeout)");
        xSemaphoreGive(stateMutex);
      }
      ampConnected = false;
      // Re-arm the enable so the next amplifier we see gets asked again.
      telemetryEnabled = false;
    }

    // Keep asking the amplifier to stream telemetry until it does. Message
    // 0x92 is fire-and-forget with no reply, so the only honest test of
    // "streaming" is frames arriving that we did not ask for: compare the
    // frames received against the requests sent over a fixed window.
    if (now - lastTelemetryEval >= TELEMETRY_EVAL_INTERVAL) {
      telemetryEnabled = telemetryFrames > telemetryRequests + 2;
      telemetryFrames = 0;
      telemetryRequests = 0;
      lastTelemetryEval = now;
    }

    if (!telemetryEnabled && (now - telemetryEnableSentAt >= TELEMETRY_ENABLE_RETRY)) {
      sendMessage(MSG_TELEMETRY_EN, NULL, 0);
      telemetryEnableSentAt = now;
    }

    if (now - lastTelemetryRequest >= TELEMETRY_INTERVAL) {
      if (!telemetryEnabled || (now - lastRxTime > 1000)) {
        const uint8_t req[4] = {ACOM_CMD_REQUEST, MSG_TELEMETRY, MSG_TELEMETRY, 0x00};
        sendMessage(MSG_CMD_AMPLIFIER, req, 4);
        telemetryRequests++;
      }
      lastTelemetryRequest = now;
    }

    // v5.0 never asked for message 0x21, so the error list was always empty.
    if (now - lastErrorRequest >= ERRORS_INTERVAL) {
      const uint8_t req[4] = {ACOM_CMD_REQUEST, MSG_ERROR_CODES, MSG_ERROR_CODES, 0x00};
      sendMessage(MSG_CMD_AMPLIFIER, req, 4);
      lastErrorRequest = now;
    }

    if (now - lastBandInfoRequest >= BAND_INFO_INTERVAL) {
      const uint8_t req[4] = {ACOM_CMD_REQUEST, MSG_BAND_INFO, MSG_BAND_INFO, 0x00};
      sendMessage(MSG_CMD_AMPLIFIER, req, 4);
      lastBandInfoRequest = now;
    }

    // ---- CAT / rig integration: follow the operating frequency ----
    if (cfgAutoBandFollow && ampConnected && !ampIsTx &&
        (now - lastAutoBandChange > AUTO_BAND_HOLDOFF)) {

      // An external rig-control feed wins while it is fresh. v6.0 only
      // consulted it when the amplifier reported no carrier at all, so a stale
      // non-zero reading from the amplifier shadowed the rig indefinitely.
      uint16_t freq = ampFrequency;
      bool externalFresh = externalFreq != 0 && (now - externalFreqTime) < EXTERNAL_FREQ_TTL;
      if (externalFresh) freq = externalFreq;

      uint8_t wanted = getBandFromFrequency(freq);
      if (wanted != 0 && wanted != ampBand) {
        uint8_t antenna = isValidAntenna(ampAntenna) ? ampAntenna : ANTENNA_MIN;
        Serial.printf("Band follow: %u kHz -> band %u (antenna %u)\n", freq, wanted, antenna);
        const uint8_t cmd[4] = {ACOM_CMD_SET_BAND, antenna, wanted, 0x00};
        sendMessage(MSG_CMD_AMPLIFIER, cmd, 4);
        lastAutoBandChange = now;
      }
    }

    vTaskDelayUntil(&xLastWakeTime, xFrequency);
  }
}

// ============================================================================
// SERIAL COMMUNICATION
// ============================================================================

void handleSerial() {
  unsigned long now = millis();

  if (rxIndex > 0 && (now - rxStartTime > RX_FRAME_TIMEOUT)) {
    rxIndex = 0;
  }

  while (Serial2.available()) {
    uint8_t b = Serial2.read();

    if (rxIndex == 0) {
      if (b != ACOM_START_BYTE) continue;
      rxStartTime = now;
    }

    if (rxIndex >= (int)sizeof(rxBuffer)) {
      Serial.println("RX buffer overflow, resetting");
      rxIndex = 0;
      continue;
    }

    rxBuffer[rxIndex++] = b;

    if (rxIndex >= 3) {
      uint8_t msgLen = rxBuffer[2];

      if (msgLen < 4 || msgLen > 72) {
        if (DEBUG_SERIAL) {
          Serial.printf("Invalid message length: %d (addr=0x%02X), resetting\n",
                        msgLen, rxBuffer[1]);
        }
        rxIndex = 0;
        continue;
      }

      if (rxIndex >= msgLen) {
        if (verifyChecksum(rxBuffer, msgLen)) {
          lastRxTime = millis();
          serialRxCount++;
          processMessage(rxBuffer, msgLen);
        } else if (DEBUG_SERIAL) {
          Serial.printf("Checksum error for address 0x%02X\n", rxBuffer[1]);
        }
        rxIndex = 0;
      }
    }
  }
}

// CHKSUM = 256 - (SUM of preceding bytes & 0xFF); a correct frame sums to 0.
uint8_t calculateChecksum(const uint8_t* msg, int len) {
  uint32_t sum = 0;
  for (int i = 0; i < len; i++) sum += msg[i];
  return (uint8_t)(256 - (sum & 0xFF));
}

bool verifyChecksum(const uint8_t* msg, int len) {
  uint32_t sum = 0;
  for (int i = 0; i < len; i++) sum += msg[i];
  return (sum & 0xFF) == 0;
}

// Blocking UART write. Only ever called from serialTask, so the inter-message
// pacing delay cannot stall the AsyncTCP task the way v5.0 did.
void sendMessage(uint8_t address, const uint8_t* data, int dataLen) {
  if (dataLen < 0 || dataLen > (int)sizeof(txBuffer) - 4) return;
  if (xSemaphoreTake(serialMutex, pdMS_TO_TICKS(100)) != pdTRUE) return;

  unsigned long now = millis();
  if (now - lastMessageTime < MESSAGE_DELAY) {
    delay(MESSAGE_DELAY - (now - lastMessageTime));
  }

  // Format: |Start(0x55)|Address|Length|...Data...|Checksum|
  // Length counts every byte including the start byte and the checksum.
  int msgLen = 4 + dataLen;

  txBuffer[0] = ACOM_START_BYTE;
  txBuffer[1] = address;
  txBuffer[2] = msgLen;
  if (dataLen > 0 && data != NULL) memcpy(&txBuffer[3], data, dataLen);
  txBuffer[3 + dataLen] = calculateChecksum(txBuffer, 3 + dataLen);

  Serial2.write(txBuffer, msgLen);
  Serial2.flush();

  if (DEBUG_TX) {
    Serial.printf("TX [%d bytes]: ", msgLen);
    for (int i = 0; i < msgLen; i++) Serial.printf("%02X ", txBuffer[i]);
    Serial.println();
  }

  lastMessageTime = millis();
  xSemaphoreGive(serialMutex);
}

// Non-blocking enqueue; safe to call from any task, including AsyncTCP.
void queueMessage(uint8_t address, const uint8_t* data, int dataLen) {
  if (!txQueue || dataLen < 0 || dataLen > (int)sizeof(((OutboundMessage*)0)->data)) return;

  OutboundMessage msg;
  msg.address = address;
  msg.dataLen = (uint8_t)dataLen;
  memset(msg.data, 0, sizeof(msg.data));
  if (dataLen > 0 && data != NULL) memcpy(msg.data, data, dataLen);

  if (xQueueSend(txQueue, &msg, 0) != pdTRUE) {
    Serial.println("TX queue full, command dropped");
  }
}

void queueAmplifierCommand(uint8_t cmd, uint8_t paramHW, uint8_t paramLW, uint8_t buttons) {
  const uint8_t data[4] = {cmd, paramHW, paramLW, buttons};
  queueMessage(MSG_CMD_AMPLIFIER, data, 4);
}

void queueRequestMessage(uint8_t msgNum) {
  queueAmplifierCommand(ACOM_CMD_REQUEST, msgNum, msgNum, 0x00);
}

void sendAcknowledge(uint8_t msgAddr) {
  const uint8_t data[1] = {msgAddr};
  sendMessage(MSG_ACKNOWLEDGE, data, 1);
}

// ============================================================================
// MESSAGE PROCESSING
// ============================================================================

void processMessage(uint8_t* msg, int len) {
  uint8_t address = msg[1];

  if (DEBUG_RX) {
    Serial.printf("RX [0x%02X, %d bytes]\n", address, len);
  }

  if (address == MSG_TELEMETRY || address == MSG_ERROR_CODES ||
      address == MSG_BAND_INFO || address == MSG_PCB_VERSIONS) {
    sendAcknowledge(address);
  }

  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(100)) != pdTRUE) return;

  ampState.connected = true;
  ampState.msgCount++;

  switch (address) {
    case MSG_TELEMETRY:  // 0x2F - 72 bytes
      if (len >= 72) {
        telemetryFrames++;
        ampState.mode = msg[3];
        ampState.isTx = (ampState.mode & 0xF0) == STATE_OPR_TX;

        ampState.pdcPower       = msg[8]  | (msg[9]  << 8);   // [10 x W]
        ampState.temperature    = msg[16] | (msg[17] << 8);   // [deg K]
        ampState.inputPower     = msg[20] | (msg[21] << 8);   // [10 x W]
        ampState.forwardPower   = msg[22] | (msg[23] << 8);   // [W]
        ampState.reflectedPower = msg[24] | (msg[25] << 8);   // [W]
        ampState.swr            = msg[26] | (msg[27] << 8);   // [100x]
        ampState.disPower       = msg[28] | (msg[29] << 8);   // [10 x W]
        ampState.vcc5           = msg[36] | (msg[37] << 8);   // [mV]
        ampState.vcc26          = msg[38] | (msg[39] << 8);   // [10 x V]
        ampState.hvVoltage      = msg[40] | (msg[41] << 8);   // [10 x V]
        ampState.current        = msg[44] | (msg[45] << 8);   // [mA]
        ampState.frequency      = msg[48] | (msg[49] << 8);   // [kHz]

        ampState.errorCode  = msg[66];
        ampState.errorParam = msg[67] | (msg[68] << 8);

        // Byte 69: fan speed in bits 4-7, active LPF channel in bits 0-3.
        // The specification gives the fan range as [0..4]; v6.0 treated the
        // nibble as 0..15 and scaled the percentage by 15.
        ampState.fanLevel   = (msg[69] >> 4) & 0x0F;
        if (ampState.fanLevel > FAN_LEVEL_MAX) ampState.fanLevel = FAN_LEVEL_MAX;
        ampState.lpfChannel = msg[69] & 0x0F;

        // Byte 70 bit 0: the reported error code belongs to the last hard
        // fault. The amplifier hands us the severity for the live code here,
        // so there is no need to guess it from telemetry thresholds.
        ampState.errorIsHardFault = (msg[70] & SYS_STATUS_ERROR_IS_HARD_FAULT) != 0;

        // The LPF channel IS the band code - same numbering, no conversion.
        if (isValidBand(ampState.lpfChannel)) {
          ampState.band = ampState.lpfChannel;
        } else if (ampState.frequency > 0) {
          ampState.band = getBandFromFrequency(ampState.frequency);
        }

        if (ampState.antennaNum == 0) ampState.antennaNum = ANTENNA_MIN;

        ampState.lastUpdate = millis();
      }
      break;

    case MSG_BAND_INFO:  // 0x27 - 17 bytes
      if (len >= 17) {
        uint8_t antNum  = msg[3];
        uint8_t antType = msg[4];
        uint8_t bandNum = msg[5];

        if (isValidAntenna(antNum)) ampState.antennaNum = antNum;
        if (antType > 0)            ampState.antennaType = antType;

        // Byte 5 uses the same band numbering as everything else. v6.0 ran it
        // through a conversion that does not exist in the protocol.
        if (isValidBand(bandNum)) ampState.band = bandNum;
      }
      break;

    case MSG_ERROR_CODES:  // 0x21 - 24 bytes
      if (len >= 24) {
        ampState.faultCount = decodeFaultCodes(msg, ampState.faultCodes,
                                               sizeof(ampState.faultCodes));
      }
      break;

    case MSG_PCB_VERSIONS:  // 0x11 - 30 bytes
      if (len >= 30) {
        memcpy(ampState.serialNumber, &msg[16], 12);
        ampState.serialNumber[12] = '\0';
      }
      break;

    case MSG_SERIAL_NUMBER:  // 0x13 - 16 bytes
      if (len >= 16) {
        memcpy(ampState.serialNumber, &msg[3], 12);
        ampState.serialNumber[12] = '\0';
      }
      break;

    default:
      break;
  }

  xSemaphoreGive(stateMutex);
}

// ============================================================================
// CONFIGURATION
// ============================================================================

// Preferences is a single global object shared by every writer, and the config
// endpoints run on the AsyncTCP task while setup() runs on the main one. Guard
// every open/close pair so two writers cannot interleave.
static bool prefsLock() {
  return prefsMutex && xSemaphoreTake(prefsMutex, pdMS_TO_TICKS(2000)) == pdTRUE;
}

static void prefsUnlock() {
  if (prefsMutex) xSemaphoreGive(prefsMutex);
}

// A WPA2 passphrase for the setup access point, generated once and kept. Using
// anything derived from the MAC would be pointless: the MAC is the BSSID, which
// every device in range already sees.
static String randomApPassword() {
  static const char alphabet[] = "abcdefghijkmnopqrstuvwxyz23456789";
  String out;
  out.reserve(AP_PASSWORD_LENGTH);
  for (int i = 0; i < AP_PASSWORD_LENGTH; i++) {
    out += alphabet[esp_random() % (sizeof(alphabet) - 1)];
  }
  return out;
}

void loadConfig() {
  if (!prefsLock()) return;
  preferences.begin("acom", true);
  cfgSsid = preferences.getString("ssid", "");
  cfgPassword = preferences.getString("password", "");
  cfgHostname = preferences.getString("hostname", "acomcontrol");
  cfgOtaPassword = preferences.getString("otapass", "");
  cfgApiUser = preferences.getString("apiuser", "acom");
  cfgApiPassword = preferences.getString("apipass", "");
  cfgAutoBandFollow = preferences.getBool("bandfollow", false);
  cfgLogEnabled = preferences.getBool("logging", true);

  // isKey() distinguishes "never set" from "deliberately set to empty", which
  // is how an operator reopens the access point on purpose.
  bool haveApPassword = preferences.isKey("appass");
  cfgApPassword = preferences.getString("appass", "");
  preferences.end();
  prefsUnlock();

  if (!haveApPassword) {
    cfgApPassword = randomApPassword();
    if (prefsLock()) {
      preferences.begin("acom", false);
      preferences.putString("appass", cfgApPassword);
      preferences.end();
      prefsUnlock();
    }
    Serial.println("Generated an access point passphrase for first boot.");
  }

  // Migrate credentials written by firmware v5.0 under the "wifi" namespace
  if (cfgSsid.length() == 0) {
    if (prefsLock()) {
      preferences.begin("wifi", true);
      String oldSsid = preferences.getString("ssid", "");
      String oldPass = preferences.getString("password", "");
      preferences.end();
      prefsUnlock();
      if (oldSsid.length() > 0) {
        cfgSsid = oldSsid;
        cfgPassword = oldPass;
        saveWiFiConfig(oldSsid, oldPass);
        Serial.println("Migrated WiFi credentials from v5.0 storage");
      }
    }
  }

  if (cfgHostname.length() == 0) cfgHostname = "acomcontrol";
  if (cfgApiUser.length() == 0) cfgApiUser = "acom";
}

void saveWiFiConfig(const String& ssid, const String& pass) {
  if (!prefsLock()) return;
  preferences.begin("acom", false);
  preferences.putString("ssid", ssid);
  preferences.putString("password", pass);
  preferences.end();
  prefsUnlock();
}

// ============================================================================
// WIFI / mDNS / OTA
// ============================================================================

void setupWiFi() {
  WiFi.mode(WIFI_MODE_NULL);
  delay(100);

  if (cfgSsid.length() > 0) {
    Serial.printf("Connecting to WiFi: %s\n", cfgSsid.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.setHostname(cfgHostname.c_str());
    WiFi.setAutoReconnect(true);
    WiFi.setSleep(false);
    WiFi.begin(cfgSsid.c_str(), cfgPassword.c_str());

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
      delay(500);
      Serial.print(".");
      attempts++;
    }

    if (WiFi.status() == WL_CONNECTED) {
      apMode = false;
      Serial.println("\nWiFi Connected!");
      Serial.print("IP: ");
      Serial.println(WiFi.localIP());
      return;
    }
    Serial.println("\nWiFi connection failed, starting AP mode");
  }

  Serial.println("Starting AP mode");
  WiFi.mode(WIFI_AP);

  // v6.0 called softAP() with no passphrase, leaving band changes, the WiFi
  // credentials and firmware upload open to anyone in radio range.
  bool open = cfgApPassword.length() < MIN_WPA2_PASSWORD;
  if (open) {
    WiFi.softAP(apSSID);
  } else {
    WiFi.softAP(apSSID, cfgApPassword.c_str());
  }
  delay(100);

  apMode = true;
  Serial.printf("AP SSID: %s\nAP IP: %s\n", apSSID, WiFi.softAPIP().toString().c_str());
  if (open) {
    Serial.println("WARNING: access point is OPEN. Set an 8+ character");
    Serial.println("         passphrase via POST /api/config {\"apPassword\":\"...\"}");
  } else {
    Serial.printf("AP passphrase: %s\n", cfgApPassword.c_str());
  }
}

void setupMDNS() {
  if (!MDNS.begin(cfgHostname.c_str())) {
    Serial.println("mDNS responder failed to start");
    return;
  }

  MDNS.addService("http", "tcp", 80);
  MDNS.addService("acom", "tcp", 80);
  MDNS.addServiceTxt("acom", "tcp", "version", FIRMWARE_VERSION);
  MDNS.addServiceTxt("acom", "tcp", "model", "ACOM 600S");
  MDNS.addServiceTxt("acom", "tcp", "path", "/api/status");

  Serial.printf("mDNS started: %s.local\n", cfgHostname.c_str());
}

void setupOTA() {
  ArduinoOTA.setHostname(cfgHostname.c_str());
  if (cfgOtaPassword.length() > 0) {
    ArduinoOTA.setPassword(cfgOtaPassword.c_str());
  }

  ArduinoOTA.onStart([]() {
    // Stop touching the UART and the radio broadcast path during a flash write
    if (serialTaskHandle) vTaskSuspend(serialTaskHandle);
    Serial.println("OTA update starting...");
  });
  ArduinoOTA.onEnd([]() { Serial.println("\nOTA update complete"); });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("OTA progress: %u%%\r", (progress * 100) / total);
  });
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("OTA error [%u]\n", error);
    if (serialTaskHandle) vTaskResume(serialTaskHandle);
  });

  ArduinoOTA.begin();
  Serial.println("ArduinoOTA ready");
}

// ============================================================================
// FILESYSTEM / SESSION LOG
// ============================================================================

void setupFilesystem() {
  if (!LittleFS.begin(true)) {
    Serial.println("LittleFS mount failed; session logging disabled");
    fsReady = false;
    return;
  }
  fsReady = true;

  File f = LittleFS.open(LOG_PATH, FILE_READ);
  logBytes = f ? f.size() : 0;
  if (f) f.close();

  Serial.printf("LittleFS ready: %u/%u bytes used, log %u bytes\n",
                (unsigned)LittleFS.usedBytes(), (unsigned)LittleFS.totalBytes(), (unsigned)logBytes);
}

void appendLogLine(const HistorySample& s) {
  if (!fsReady || !cfgLogEnabled) return;

  if (logBytes >= LOG_MAX_BYTES) {
    LittleFS.remove(LOG_PATH_PREV);
    LittleFS.rename(LOG_PATH, LOG_PATH_PREV);
    logBytes = 0;
  }

  bool needHeader = (logBytes == 0);
  File f = LittleFS.open(LOG_PATH, FILE_APPEND);
  if (!f) return;

  if (needHeader) {
    logBytes += f.println("ms,forwardW,reflectedW,swr100,tempK,currentmA,freqkHz,band,tx");
  }

  char line[96];
  int n = snprintf(line, sizeof(line), "%lu,%u,%u,%u,%u,%u,%u,%u,%u\n",
                   (unsigned long)s.t, s.fwd, s.ref, s.swr, s.tempK, s.mA,
                   s.freq, s.band, (unsigned)(s.flags & 0x01));
  if (n > 0) logBytes += f.write((const uint8_t*)line, n);
  f.close();
}

void recordHistory() {
  if (historyCapacity == 0) return;

  HistorySample s;
  bool isTx = false;
  bool connected = false;

  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(20)) != pdTRUE) return;
  s.t     = millis();
  s.fwd   = ampState.forwardPower;
  s.ref   = ampState.reflectedPower;
  s.swr   = ampState.swr;
  s.tempK = ampState.temperature;
  s.mA    = ampState.current;
  s.freq  = ampState.frequency;
  s.band  = ampState.band;
  isTx = ampState.isTx;
  connected = ampState.connected;
  s.flags = (isTx ? 0x01 : 0x00) | (connected ? 0x02 : 0x00);
  xSemaphoreGive(stateMutex);

  if (!connected) return;

  if (xSemaphoreTake(historyMutex, pdMS_TO_TICKS(20)) == pdTRUE) {
    history[historyHead] = s;
    historyHead = (historyHead + 1) % historyCapacity;
    if (historyCount < historyCapacity) historyCount++;
    xSemaphoreGive(historyMutex);
  }

  // Flash wear control: log every second while transmitting, otherwise a
  // 30 second heartbeat is enough to reconstruct a session.
  static uint32_t lastHeartbeat = 0;
  if (isTx || (s.t - lastHeartbeat >= 30000)) {
    appendLogLine(s);
    if (!isTx) lastHeartbeat = s.t;
  }
}

// ============================================================================
// WEB SERVER
// ============================================================================

// Shared handler for WebSocket and REST commands. Returns false with a reason
// in errorOut when the command is malformed.
// Reads the few state fields the command handlers need, under the mutex.
// v6.0 touched ampState directly from the AsyncTCP task.
struct CommandContext {
  bool isTx = false;
  uint8_t band = 0;
  uint8_t antenna = 0;
};

static CommandContext commandContext() {
  CommandContext ctx;
  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
    ctx.isTx = ampState.isTx;
    ctx.band = ampState.band;
    ctx.antenna = ampState.antennaNum;
    xSemaphoreGive(stateMutex);
  }
  return ctx;
}

bool handleClientCommand(const JsonDocument& doc, String& errorOut) {
  // v5.0 assigned doc["cmd"] straight into a const char* and passed it to
  // strcmp, so any JSON without a "cmd" key panicked the chip.
  const char* cmd = doc["cmd"] | (const char*)nullptr;
  if (cmd == nullptr) {
    errorOut = "Missing cmd";
    return false;
  }

  // Switching the low-pass filter or the antenna relays under RF is the
  // hot-switching case the amplifier protects against, and cutting the supply
  // mid-transmission is no better. Both UIs confirm with the operator and then
  // resend with "force", so the firmware can hold the line by default.
  bool force = doc["force"] | false;
  CommandContext ctx = commandContext();

  if (strcmp(cmd, "setMode") == 0) {
    if (!doc.containsKey("mode")) { errorOut = "Missing mode"; return false; }
    uint8_t mode = doc["mode"] | 0;
    if (mode == 0 || mode > 0x0A) { errorOut = "Invalid mode"; return false; }
    if (mode == AMP_MODE_POWEROFF && ctx.isTx && !force) {
      errorOut = "Transmitting - resend with force to power off anyway";
      return false;
    }
    queueAmplifierCommand(ACOM_CMD_SET_MODE, 0x00, mode, 0x00);
    return true;
  }

  if (strcmp(cmd, "setBand") == 0) {
    if (!doc.containsKey("band")) { errorOut = "Missing band"; return false; }
    uint8_t band = doc["band"] | 0;
    if (!isValidBand(band)) { errorOut = "Invalid band"; return false; }
    if (ctx.isTx && !force) {
      errorOut = "Transmitting - resend with force to change band anyway";
      return false;
    }

    uint8_t antenna = doc["antenna"] | 0;
    if (!isValidAntenna(antenna)) {
      antenna = isValidAntenna(ctx.antenna) ? ctx.antenna : ANTENNA_MIN;
    }

    queueAmplifierCommand(ACOM_CMD_SET_BAND, antenna, band, 0x00);
    return true;
  }

  if (strcmp(cmd, "setAntenna") == 0) {
    if (!doc.containsKey("antenna")) { errorOut = "Missing antenna"; return false; }
    uint8_t antenna = doc["antenna"] | 0;
    if (!isValidAntenna(antenna)) { errorOut = "Invalid antenna"; return false; }
    uint8_t band = doc["band"] | ctx.band;
    if (!isValidBand(band)) { errorOut = "No band selected"; return false; }
    if (ctx.isTx && !force) {
      errorOut = "Transmitting - resend with force to change antenna anyway";
      return false;
    }
    queueAmplifierCommand(ACOM_CMD_SET_BAND, antenna, band, 0x00);
    return true;
  }

  if (strcmp(cmd, "clearErrors") == 0) {
    queueAmplifierCommand(ACOM_CMD_CLEAR_ERRORS, 0x00, 0x00, 0x00);
    // Ask for the fault list straight away so the UI reflects the result
    // instead of waiting out the 2 s poll.
    queueRequestMessage(MSG_ERROR_CODES);
    return true;
  }

  if (strcmp(cmd, "requestInfo") == 0) {
    queueRequestMessage(MSG_PCB_VERSIONS);
    queueRequestMessage(MSG_BAND_INFO);
    queueRequestMessage(MSG_ERROR_CODES);
    return true;
  }

  if (strcmp(cmd, "setFrequency") == 0) {
    uint32_t f = doc["frequency"] | 0UL;
    if (f == 0 || f > 65535UL) { errorOut = "Invalid frequency"; return false; }
    externalFreq = (uint16_t)f;
    externalFreqTime = millis();
    return true;
  }

  if (strcmp(cmd, "saveWiFi") == 0) {
    const char* newSsid = doc["ssid"] | (const char*)nullptr;
    if (newSsid == nullptr || strlen(newSsid) == 0) { errorOut = "Missing ssid"; return false; }
    const char* newPass = doc["password"] | "";
    saveWiFiConfig(newSsid, newPass);
    rebootAt = millis() + 1000;
    return true;
  }

  errorOut = "Unknown command";
  return false;
}

void setupWebServer() {
  server.on("/", HTTP_GET, [](AsyncWebServerRequest* request) {
    // Served straight from flash instead of building a ~9 KB String per hit.
    // send_P is deprecated in ESPAsyncWebServer 3.x; on ESP32 flash is memory
    // mapped, so the const char* overload reads PROGMEM directly.
    request->send(200, "text/html", PAGE_INDEX);
  });

  // The WebSocket carries the same commands as the REST API, and the event
  // stream carries the same telemetry, so both need the same gate. These are
  // checked on the upgrade/subscribe request. Only arm them when a password is
  // actually set - handing the handler an empty one would challenge every
  // client for credentials that cannot be satisfied.
  if (cfgApiPassword.length() > 0) {
    ws.setAuthentication(cfgApiUser.c_str(), cfgApiPassword.c_str(),
                         AsyncAuthType::AUTH_BASIC);
    events.setAuthentication(cfgApiUser.c_str(), cfgApiPassword.c_str(),
                             AsyncAuthType::AUTH_BASIC);
  }

  ws.onEvent([](AsyncWebSocket* server, AsyncWebSocketClient* client,
                AwsEventType type, void* arg, uint8_t* data, size_t len) {
    if (type == WS_EVT_CONNECT) {
      Serial.printf("WebSocket client #%u connected\n", client->id());
      client->text(getStateJSON());

    } else if (type == WS_EVT_DISCONNECT) {
      Serial.printf("WebSocket client #%u disconnected\n", client->id());

    } else if (type == WS_EVT_DATA) {
      AwsFrameInfo* info = (AwsFrameInfo*)arg;
      if (info->final && info->index == 0 && info->len == len && info->opcode == WS_TEXT) {
        // v5.0 wrote a NUL one byte past the frame; copy into a bounded buffer.
        if (len == 0 || len > 255) return;
        char body[256];
        memcpy(body, data, len);
        body[len] = '\0';

        StaticJsonDocument<256> doc;
        if (deserializeJson(doc, body) != DeserializationError::Ok) return;

        String err;
        if (!handleClientCommand(doc, err)) {
          String reply = "{\"success\":false,\"error\":\"" + err + "\"}";
          client->text(reply);
        }
      }
    }
  });

  server.addHandler(&ws);
}

void addCORSHeaders(AsyncWebServerResponse* response) {
  response->addHeader("Access-Control-Allow-Origin", "*");
  response->addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  response->addHeader("Access-Control-Allow-Headers", "Content-Type");
}

static void sendJSON(AsyncWebServerRequest* request, int code, const String& body) {
  AsyncWebServerResponse* response = request->beginResponse(code, "application/json", body);
  addCORSHeaders(response);
  request->send(response);
}

static void sendEnvelope(AsyncWebServerRequest* request, const String& dataJson) {
  String body = "{\"success\":true,\"timestamp\":" + String(millis()) + ",\"data\":" + dataJson + "}";
  sendJSON(request, 200, body);
}

static void sendError(AsyncWebServerRequest* request, int code, const String& message) {
  // Built with ArduinoJson so a message containing a quote cannot break the
  // envelope. v6.0 concatenated these by hand.
  StaticJsonDocument<256> doc;
  doc["success"] = false;
  doc["timestamp"] = millis();
  doc["error"] = message;
  String body;
  serializeJson(doc, body);
  sendJSON(request, code, body);
}

// Serialises `data` as the "data" member of the documented envelope.
static void sendEnvelopeDoc(AsyncWebServerRequest* request, const JsonDocument& data) {
  String payload;
  serializeJson(data, payload);
  sendEnvelope(request, payload);
}

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

// Side-effect-free credential check. v6.0 had no authentication of any kind,
// including on firmware upload.
//
// Basic rather than Digest: this is a LAN device served over plain HTTP, so
// Digest would protect the password on the wire but nothing else, and Basic is
// what browsers, curl and URLSession all handle without extra work. Treat the
// password as readable by anyone sniffing the network and rely on WPA2 for
// confidentiality.
bool isAuthenticated(AsyncWebServerRequest* request) {
  if (cfgApiPassword.length() == 0) return true;
  return request->authenticate(cfgApiUser.c_str(), cfgApiPassword.c_str());
}

// Sends the 401 challenge. Registered as server-wide middleware, which runs
// exactly once per request - unlike a check inside a body or upload callback,
// which runs once per TCP fragment and would fire a challenge per fragment.
//
// The middleware chain runs when the request is complete, i.e. AFTER the body
// and upload callbacks have already seen their data, so those callbacks check
// isAuthenticated() themselves and simply do nothing. The challenge still
// comes from here, so every outcome produces exactly one response.
void setupAuthMiddleware() {
  server.addMiddleware([](AsyncWebServerRequest* request, ArMiddlewareNext next) {
    // Preflight requests carry no credentials by design; challenging them
    // would break CORS for the real request that follows.
    if (request->method() == HTTP_OPTIONS || isAuthenticated(request)) {
      next();
      return;
    }
    request->requestAuthentication(AsyncAuthType::AUTH_BASIC, "AcomControl");
  });
}

// ---------------------------------------------------------------------------
// JSON request bodies
// ---------------------------------------------------------------------------
//
// v6.0 parsed (data, len) straight out of the body callback. That works only
// when the whole body arrives in one segment: a split body was parsed from the
// first fragment, and because the callback runs once per fragment it could call
// request->send() more than once. Accumulate into a buffer and parse once the
// final fragment has landed.

#define MAX_JSON_BODY 1024

typedef void (*JsonBodyHandler)(AsyncWebServerRequest*, JsonDocument&);

static void readJsonBody(AsyncWebServerRequest* request, uint8_t* data, size_t len,
                         size_t index, size_t total, JsonBodyHandler handler) {
  if (index == 0) {
    if (request->_tempObject) {
      free(request->_tempObject);
      request->_tempObject = nullptr;
    }
    if (total == 0 || total > MAX_JSON_BODY) {
      sendError(request, 413, "Request body too large");
      return;
    }
    request->_tempObject = malloc(total + 1);
    if (!request->_tempObject) {
      sendError(request, 500, "Out of memory");
      return;
    }
  }

  if (!request->_tempObject) return;  // already answered with an error

  // Never trust the offsets against the buffer we sized from Content-Length.
  if (index > total || len > total - index) {
    free(request->_tempObject);
    request->_tempObject = nullptr;
    sendError(request, 400, "Malformed request body");
    return;
  }

  memcpy((char*)request->_tempObject + index, data, len);
  if (index + len < total) return;    // more fragments on the way
  ((char*)request->_tempObject)[total] = '\0';

  StaticJsonDocument<MAX_JSON_BODY> doc;
  DeserializationError err = deserializeJson(doc, (const char*)request->_tempObject);
  free(request->_tempObject);
  request->_tempObject = nullptr;

  if (err) {
    sendError(request, 400, "Invalid JSON");
    return;
  }
  handler(request, doc);
}

// onRequest companion for every endpoint that takes a JSON body. The body
// callback answers any request that has a body; this answers the ones that do
// not, which v6.0 left hanging until the client timed out. It only runs when
// the auth middleware let the request through, so an unauthenticated POST gets
// the 401 from the middleware and nothing from here.
//
// A chunked request also reports a content length of zero, so it lands here
// too. Every client of this API sends a small JSON body with a Content-Length,
// and answering 400 is still better than leaving the socket open until the
// client gives up, which is what v6.0 did with both cases.
static void requireJsonBody(AsyncWebServerRequest* request) {
  if (request->contentLength() == 0) {
    sendError(request, 400, "A JSON request body with a Content-Length is required");
  }
}

void setupAPIEndpoints() {
  // ---- GET /api/status ----
  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest* request) {
    sendEnvelope(request, getStateJSON());
  });

  // ---- GET /api/system ----
  server.on("/api/system", HTTP_GET, [](AsyncWebServerRequest* request) {
    sendEnvelope(request, getSystemInfoJSON());
  });

  // ---- GET /api/faults ----
  // The fault code table from section 3.4.1 of the protocol document, so
  // clients can name codes without carrying their own copy. v6.0 shipped no
  // table at all and told operators the specification was unavailable.
  server.on("/api/faults", HTTP_GET, [](AsyncWebServerRequest* request) {

    AsyncResponseStream* response = request->beginResponseStream("application/json");
    addCORSHeaders(response);
    response->print("{\"success\":true,\"timestamp\":");
    response->print(millis());
    response->print(",\"data\":{\"count\":");
    response->print(ACOM_FAULT_COUNT);
    response->print(",\"codes\":{");
    for (size_t i = 0; i < ACOM_FAULT_COUNT; i++) {
      if (i) response->print(',');
      response->printf("\"%u\":{\"severity\":\"%s\",\"text\":\"%s\"}",
                       ACOM_FAULTS[i].code,
                       acomSeverityName(ACOM_FAULTS[i].severity),
                       ACOM_FAULTS[i].text);
    }
    response->print("}}}");
    request->send(response);
  });

  // ---- POST /api/command (generic) ----
  server.on("/api/command", HTTP_POST, requireJsonBody, NULL,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
      // Body callbacks run per TCP fragment and before the auth middleware, so
      // they check the credentials themselves and stay silent; the middleware
      // sends the single 401.
      if (!isAuthenticated(request)) return;
      readJsonBody(request, data, len, index, total,
        [](AsyncWebServerRequest* request, JsonDocument& doc) {
          String err;
          if (handleClientCommand(doc, err)) sendEnvelope(request, "{}");
          else sendError(request, 400, err);
        });
    });

  // ---- POST /api/mode ----
  server.on("/api/mode", HTTP_POST, requireJsonBody, NULL,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
      // Body callbacks run per TCP fragment and before the auth middleware, so
      // they check the credentials themselves and stay silent; the middleware
      // sends the single 401.
      if (!isAuthenticated(request)) return;
      readJsonBody(request, data, len, index, total,
        [](AsyncWebServerRequest* request, JsonDocument& doc) {
          if (!doc.containsKey("mode")) { sendError(request, 400, "Missing mode"); return; }
          doc["cmd"] = "setMode";
          String err;
          if (!handleClientCommand(doc, err)) { sendError(request, 400, err); return; }
          StaticJsonDocument<64> out;
          out["mode"] = doc["mode"];
          sendEnvelopeDoc(request, out);
        });
    });

  // ---- POST /api/band ----
  server.on("/api/band", HTTP_POST, requireJsonBody, NULL,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
      // Body callbacks run per TCP fragment and before the auth middleware, so
      // they check the credentials themselves and stay silent; the middleware
      // sends the single 401.
      if (!isAuthenticated(request)) return;
      readJsonBody(request, data, len, index, total,
        [](AsyncWebServerRequest* request, JsonDocument& doc) {
          if (!doc.containsKey("band")) { sendError(request, 400, "Missing band"); return; }
          doc["cmd"] = "setBand";
          String err;
          if (!handleClientCommand(doc, err)) { sendError(request, 400, err); return; }

          CommandContext ctx = commandContext();
          uint8_t antenna = doc["antenna"] | 0;
          if (!isValidAntenna(antenna)) {
            antenna = isValidAntenna(ctx.antenna) ? ctx.antenna : ANTENNA_MIN;
          }
          StaticJsonDocument<96> out;
          out["band"] = doc["band"];
          out["antenna"] = antenna;
          sendEnvelopeDoc(request, out);
        });
    });

  // ---- POST /api/frequency (CAT / rig control feed) ----
  server.on("/api/frequency", HTTP_POST, requireJsonBody, NULL,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
      // Body callbacks run per TCP fragment and before the auth middleware, so
      // they check the credentials themselves and stay silent; the middleware
      // sends the single 401.
      if (!isAuthenticated(request)) return;
      readJsonBody(request, data, len, index, total,
        [](AsyncWebServerRequest* request, JsonDocument& doc) {
          uint32_t f = doc["frequency"] | 0UL;
          if (f == 0 || f > 65535UL) {
            sendError(request, 400, "Invalid frequency (kHz, 1-65535)");
            return;
          }

          externalFreq = (uint16_t)f;
          externalFreqTime = millis();

          StaticJsonDocument<128> out;
          out["frequency"] = f;
          out["band"] = getBandFromFrequency(externalFreq);
          out["autoBandFollow"] = cfgAutoBandFollow;
          sendEnvelopeDoc(request, out);
        });
    });

  // ---- GET/POST /api/config ----
  server.on("/api/config", HTTP_GET, [](AsyncWebServerRequest* request) {

    StaticJsonDocument<512> out;
    out["hostname"] = cfgHostname;
    out["autoBandFollow"] = cfgAutoBandFollow;
    out["logging"] = cfgLogEnabled;
    out["otaPasswordSet"] = cfgOtaPassword.length() > 0;

    // The SSID the controller is CONFIGURED to join, which is not the same
    // thing as the SSID it is currently serving. v6.0 reported the access
    // point's own name here whenever it was in AP mode, so the web form
    // offered to join the controller itself and the macOS app had to special
    // case the string "AcomControl".
    out["wifiSSID"] = cfgSsid;
    out["apMode"] = apMode;
    out["apSSID"] = apSSID;
    out["apPassword"] = cfgApPassword;
    out["apOpen"] = cfgApPassword.length() < MIN_WPA2_PASSWORD;
    out["authEnabled"] = cfgApiPassword.length() > 0;
    out["apiUser"] = cfgApiUser;
    sendEnvelopeDoc(request, out);
  });

  server.on("/api/config", HTTP_POST, requireJsonBody, NULL,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
      // Body callbacks run per TCP fragment and before the auth middleware, so
      // they check the credentials themselves and stay silent; the middleware
      // sends the single 401.
      if (!isAuthenticated(request)) return;
      readJsonBody(request, data, len, index, total,
        [](AsyncWebServerRequest* request, JsonDocument& doc) {
          bool needsReboot = false;

          if (!prefsLock()) {
            sendError(request, 503, "Settings are busy, try again");
            return;
          }
          preferences.begin("acom", false);

          if (doc.containsKey("autoBandFollow")) {
            cfgAutoBandFollow = doc["autoBandFollow"];
            preferences.putBool("bandfollow", cfgAutoBandFollow);
          }
          if (doc.containsKey("logging")) {
            cfgLogEnabled = doc["logging"];
            preferences.putBool("logging", cfgLogEnabled);
          }
          if (doc.containsKey("otaPassword")) {
            cfgOtaPassword = String((const char*)(doc["otaPassword"] | ""));
            preferences.putString("otapass", cfgOtaPassword);
            needsReboot = true;
          }
          if (doc.containsKey("apiUser")) {
            String u = String((const char*)(doc["apiUser"] | ""));
            u.trim();
            if (u.length() > 0 && u.length() <= 32) {
              cfgApiUser = u;
              preferences.putString("apiuser", cfgApiUser);
              needsReboot = true;
            }
          }
          if (doc.containsKey("apiPassword")) {
            cfgApiPassword = String((const char*)(doc["apiPassword"] | ""));
            preferences.putString("apipass", cfgApiPassword);
            // The handlers read the credentials once, at registration.
            needsReboot = true;
          }
          if (doc.containsKey("apPassword")) {
            String p = String((const char*)(doc["apPassword"] | ""));
            // Empty deliberately reopens the access point; anything else has
            // to be a passphrase WPA2 will actually accept.
            if (p.length() == 0 || p.length() >= MIN_WPA2_PASSWORD) {
              cfgApPassword = p;
              preferences.putString("appass", cfgApPassword);
              needsReboot = true;
            }
          }
          if (doc.containsKey("hostname")) {
            String h = String((const char*)(doc["hostname"] | ""));
            h.trim();
            if (h.length() > 0 && h.length() <= 32) {
              cfgHostname = h;
              preferences.putString("hostname", cfgHostname);
              needsReboot = true;
            }
          }
          preferences.end();
          prefsUnlock();

          if (needsReboot) rebootAt = millis() + 1000;

          StaticJsonDocument<320> out;
          out["autoBandFollow"] = cfgAutoBandFollow;
          out["logging"] = cfgLogEnabled;
          out["hostname"] = cfgHostname;
          out["authEnabled"] = cfgApiPassword.length() > 0;
          out["apOpen"] = cfgApPassword.length() < MIN_WPA2_PASSWORD;
          out["rebooting"] = needsReboot;
          sendEnvelopeDoc(request, out);
        });
    });

  // ---- POST /api/wifi ----
  server.on("/api/wifi", HTTP_POST, requireJsonBody, NULL,
    [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
      // Body callbacks run per TCP fragment and before the auth middleware, so
      // they check the credentials themselves and stay silent; the middleware
      // sends the single 401.
      if (!isAuthenticated(request)) return;
      readJsonBody(request, data, len, index, total,
        [](AsyncWebServerRequest* request, JsonDocument& doc) {
          const char* newSsid = doc["ssid"] | (const char*)nullptr;
          if (newSsid == nullptr || strlen(newSsid) == 0) {
            sendError(request, 400, "Missing ssid");
            return;
          }
          const char* newPass = doc["password"] | "";
          saveWiFiConfig(newSsid, newPass);

          // Reboot is deferred so this response is actually delivered. v5.0
          // restarted inside the callback, so the client usually saw a dropped
          // connection instead of the success reply.
          StaticJsonDocument<128> out;
          out["message"] = "Saved, rebooting";
          out["ssid"] = newSsid;
          sendEnvelopeDoc(request, out);
          rebootAt = millis() + 1000;
        });
    });

  // ---- GET /api/history ----
  server.on("/api/history", HTTP_GET, [](AsyncWebServerRequest* request) {

    long requested = -1;
    if (request->hasParam("points")) {
      requested = request->getParam("points")->value().toInt();
    }

    AsyncResponseStream* response = request->beginResponseStream("application/json");
    addCORSHeaders(response);

    response->print("{\"success\":true,\"timestamp\":");
    response->print(millis());
    response->print(",\"data\":{\"fields\":[\"t\",\"forwardPower\",\"reflectedPower\",\"swr\","
                    "\"temperature\",\"current\",\"frequency\",\"band\",\"tx\"],\"capacity\":");
    response->print(historyCapacity);
    response->print(",\"samples\":[");

    // v6.0 read historyCount outside the mutex to size the response and then
    // again inside it to walk the ring, so a sample recorded in between
    // produced a mismatched count.
    uint32_t emitted = 0;
    if (xSemaphoreTake(historyMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
      uint32_t wanted = historyCount;
      if (requested > 0 && (uint32_t)requested < wanted) wanted = (uint32_t)requested;

      uint32_t base = (historyCount < historyCapacity) ? 0 : historyHead;
      uint32_t start = historyCount - wanted;
      for (uint32_t i = 0; i < wanted; i++) {
        uint32_t idx = (base + start + i) % historyCapacity;
        const HistorySample& s = history[idx];
        if (i) response->print(',');
        char buf[80];
        snprintf(buf, sizeof(buf), "[%lu,%u,%u,%u,%u,%u,%u,%u,%u]",
                 (unsigned long)s.t, s.fwd, s.ref, s.swr, s.tempK, s.mA,
                 s.freq, s.band, (unsigned)(s.flags & 0x01));
        response->print(buf);
      }
      emitted = wanted;
      xSemaphoreGive(historyMutex);
    }

    response->print("],\"count\":");
    response->print(emitted);
    response->print("}}");
    request->send(response);
  });

  // ---- GET /api/history/download (CSV session log) ----
  server.on("/api/history/download", HTTP_GET, [](AsyncWebServerRequest* request) {
    if (!fsReady || !LittleFS.exists(LOG_PATH)) {
      sendError(request, 404, "No session log available");
      return;
    }
    AsyncWebServerResponse* response = request->beginResponse(LittleFS, LOG_PATH, "text/csv", true);
    addCORSHeaders(response);
    request->send(response);
  });

  // ---- POST /api/history/clear ----
  server.on("/api/history/clear", HTTP_POST, [](AsyncWebServerRequest* request) {
    if (xSemaphoreTake(historyMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
      historyCount = 0;
      historyHead = 0;
      xSemaphoreGive(historyMutex);
    }
    if (fsReady) {
      LittleFS.remove(LOG_PATH);
      LittleFS.remove(LOG_PATH_PREV);
      logBytes = 0;
    }
    StaticJsonDocument<64> out;
    out["message"] = "History cleared";
    sendEnvelopeDoc(request, out);
  });

  // ---- POST /api/ota (browser firmware upload) ----
  server.on("/api/ota", HTTP_POST,
    [](AsyncWebServerRequest* request) {
        bool ok = !Update.hasError();
      if (ok) {
        StaticJsonDocument<96> out;
        out["message"] = "Update applied, rebooting";
        sendEnvelopeDoc(request, out);
        rebootAt = millis() + 1500;
      } else {
        sendError(request, 500, "Update failed");
      }
    },
    [](AsyncWebServerRequest* request, String filename, size_t index, uint8_t* data,
       size_t len, bool final) {
      // Firmware upload is the most dangerous endpoint here, so it refuses
      // before a single byte reaches flash. v6.0 left it wide open.
      if (!isAuthenticated(request)) return;

      if (index == 0) {
        Serial.printf("OTA upload starting: %s\n", filename.c_str());
        // Stop driving the amplifier's UART while flash is being rewritten.
        if (serialTaskHandle) vTaskSuspend(serialTaskHandle);
        if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
          Update.printError(Serial);
          // Without this the serial task would stay suspended forever and the
          // amplifier link would go dead until the next power cycle.
          if (serialTaskHandle) vTaskResume(serialTaskHandle);
          return;
        }
      }
      if (len && Update.isRunning() && Update.write(data, len) != len) {
        Update.printError(Serial);
        Update.abort();
        if (serialTaskHandle) vTaskResume(serialTaskHandle);
        return;
      }
      if (final) {
        if (Update.end(true)) {
          Serial.printf("OTA upload complete: %u bytes\n", (unsigned)(index + len));
        } else {
          Update.printError(Serial);
          if (serialTaskHandle) vTaskResume(serialTaskHandle);
        }
      }
    });

  // ---- OPTIONS preflight ----
  // Never authenticated: a browser sends the preflight without credentials, so
  // challenging it would block the real request that follows.
  server.on("/api/*", HTTP_OPTIONS, [](AsyncWebServerRequest* request) {
    AsyncWebServerResponse* response = request->beginResponse(200);
    addCORSHeaders(response);
    request->send(response);
  });

  server.onNotFound([](AsyncWebServerRequest* request) {
    if (request->method() == HTTP_OPTIONS) {
      AsyncWebServerResponse* response = request->beginResponse(200);
      addCORSHeaders(response);
      request->send(response);
    } else {
      sendError(request, 404, "Not found");
    }
  });
}

// ============================================================================
// BROADCASTING
// ============================================================================

void broadcastState() {
  if (ws.count() == 0) return;

  // Skip this frame if any client's TX queue is backed up. v5.0 pushed at a
  // fixed 10 Hz regardless, which let one slow client exhaust the heap.
  if (!ws.availableForWriteAll()) return;

  ws.textAll(getStateJSON());
  wsUpdateCount++;
}

void broadcastSSE() {
  if (events.count() == 0) return;
  events.send(getStateJSON().c_str(), "state", millis());
  sseUpdateCount++;
}

// ============================================================================
// JSON SERIALISATION
// ============================================================================

String getModeString(uint8_t mode) {
  switch (mode & 0xF0) {
    case STATE_RESET:    return "RESET";
    case STATE_INIT:     return "INIT";
    case STATE_DEBUG:    return "DEBUG";
    case STATE_SERVICE:  return "SERVICE";
    case STATE_STB:      return "STB";
    case STATE_OPR_RX:   return "OPR";
    case STATE_OPR_TX:   return "TX";
    case STATE_ATAC:     return "ATAC";
    case STATE_MENU:     return "MENU";
    case STATE_POWEROFF: return "OFF";
    default:             return "UNK";
  }
}

// 60m shares the 40m low-pass filter (section 3.3.7 byte 13 covers "Bands 40m
// and 60m"), so band 3 carries both. v6.0 labelled band 2 as "80/60m".
String getBandString(uint8_t band) {
  switch (band) {
    case 1:  return "160m";
    case 2:  return "80m";
    case 3:  return "40/60m";
    case 4:  return "30m";
    case 5:  return "20m";
    case 6:  return "17m";
    case 7:  return "15m";
    case 8:  return "12m";
    case 9:  return "10m";
    case 10: return "6m";
    default: return "---";
  }
}

// Raw amplifier units are preserved here (SWR 100x, temperature in Kelvin,
// input power 10xW, current in mA, HV 10xV). Clients do the scaling.
String getStateJSON() {
  // Sized for every field plus a full 32-entry fault list. ArduinoJson 6 drops
  // members silently when a document overflows, which is exactly the failure
  // that makes a client decide the controller is not an AcomControl at all, so
  // the result is checked below rather than hoped for.
  DynamicJsonDocument doc(3072);

  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
    doc["connected"]      = ampState.connected;
    doc["mode"]           = getModeString(ampState.mode);
    doc["modeCode"]       = ampState.mode;
    doc["band"]           = getBandString(ampState.band);
    doc["bandCode"]       = ampState.band;
    doc["antenna"]        = ampState.antennaNum;
    doc["antennaType"]    = ampState.antennaType;
    doc["isTx"]           = ampState.isTx;
    doc["forwardPower"]   = ampState.forwardPower;
    doc["reflectedPower"] = ampState.reflectedPower;
    doc["swr"]            = ampState.swr;
    doc["temperature"]    = ampState.temperature;
    doc["inputPower"]     = ampState.inputPower;
    doc["current"]        = ampState.current;
    doc["frequency"]      = ampState.frequency;
    doc["fanLevel"]       = ampState.fanLevel;
    doc["fanLevelMax"]    = FAN_LEVEL_MAX;
    // Byte 69 carries a level, not a percentage. The specification gives the
    // range as 0..4; v5.0 published the raw level as "fanSpeed" and v6.0
    // scaled it by 15, so a fan at full speed reported 27%.
    doc["fanSpeed"]       = (uint8_t)((ampState.fanLevel * 100) / FAN_LEVEL_MAX);
    doc["hvVoltage"]      = ampState.hvVoltage;
    doc["vcc5"]           = ampState.vcc5;
    doc["vcc26"]          = ampState.vcc26;
    doc["pdcPower"]       = ampState.pdcPower;
    doc["disPower"]       = ampState.disPower;
    doc["lpfChannel"]     = ampState.lpfChannel;
    doc["errorCode"]      = ampState.errorCode;
    doc["errorParam"]     = ampState.errorParam;
    // Byte 70 bit 0: the amplifier tells us whether the live code belongs to a
    // hard fault, so no client has to infer severity from telemetry.
    doc["errorIsHardFault"] = ampState.errorIsHardFault;
    doc["errorSeverity"]  = ampState.errorCode
                            ? acomSeverityName(ampState.errorIsHardFault
                                               ? ACOM_HARD_FAULT
                                               : acomFaultSeverity(ampState.errorCode))
                            : "";
    doc["serialNumber"]   = ampState.serialNumber;
    doc["lastUpdate"]     = ampState.lastUpdate;
    doc["msgCount"]       = ampState.msgCount;
    doc["autoBandFollow"] = cfgAutoBandFollow;

    // Real fault code numbers, decoded from the message 0x21 bitfield. v6.0
    // published the ten raw bitmask words here, so a single active fault
    // appeared as a code like 0x0080.
    JsonArray errors = doc.createNestedArray("errors");
    for (uint8_t i = 0; i < ampState.faultCount; i++) {
      errors.add(ampState.faultCodes[i]);
    }

    xSemaphoreGive(stateMutex);
  } else {
    // Never emit a bare "{}" that clients would decode as an all-zero state
    doc["connected"] = false;
    doc["mode"] = "N/A";
    doc["band"] = "---";
    doc.createNestedArray("errors");
  }

  if (doc.overflowed()) {
    Serial.println("WARNING: state JSON overflowed its document and is incomplete");
  }

  String output;
  serializeJson(doc, output);
  return output;
}

String getSystemInfoJSON() {
  // 768 bytes was too tight once a 32-character SSID, a 32-character hostname
  // and an IP address all have to be copied in. An overflow here silently
  // drops members, and network discovery keys off chipModel being present.
  DynamicJsonDocument doc(1536);

  esp_chip_info_t chip;
  esp_chip_info(&chip);

  const char* model = "ESP32";
  switch (chip.model) {
    case CHIP_ESP32:   model = "ESP32"; break;
    case CHIP_ESP32S2: model = "ESP32-S2"; break;
    case CHIP_ESP32S3: model = "ESP32-S3"; break;
    case CHIP_ESP32C3: model = "ESP32-C3"; break;
    default: break;
  }

  doc["chipModel"]       = model;
  doc["chipRevision"]    = chip.revision;
  doc["cpuFreqMHz"]      = getCpuFrequencyMhz();
  doc["flashSize"]       = ESP.getFlashChipSize();
  doc["freeHeap"]        = ESP.getFreeHeap();
  doc["heapSize"]        = ESP.getHeapSize();
  doc["psramSize"]       = ESP.getPsramSize();
  doc["psramFree"]       = ESP.getFreePsram();
  doc["uptime"]          = millis();           // milliseconds, as documented
  doc["wifiMode"]        = apMode ? "AP" : "STA";
  doc["wifiSSID"]        = apMode ? String(apSSID) : WiFi.SSID();
  doc["ipAddress"]       = apMode ? WiFi.softAPIP().toString() : WiFi.localIP().toString();
  doc["rssi"]            = apMode ? 0 : WiFi.RSSI();
  doc["hostname"]        = cfgHostname;
  doc["firmwareVersion"] = FIRMWARE_VERSION;
  // True only while telemetry frames are genuinely arriving unprompted. v6.0
  // set this once at boot whether or not the amplifier was even powered.
  doc["telemetryEnabled"] = telemetryEnabled;
  doc["autoBandFollow"]  = cfgAutoBandFollow;
  doc["loggingEnabled"]  = cfgLogEnabled;
  doc["historyCount"]    = historyCount;
  doc["historyCapacity"] = historyCapacity;
  doc["logBytes"]        = logBytes;
  doc["fanLevelMax"]     = FAN_LEVEL_MAX;

  // So a client can say out loud that the controller is unprotected.
  doc["authEnabled"]     = cfgApiPassword.length() > 0;
  doc["apOpen"]          = apMode && cfgApPassword.length() < MIN_WPA2_PASSWORD;

  JsonObject perf = doc.createNestedObject("performance");
  perf["wsUpdateCount"] = wsUpdateCount;
  perf["sseUpdateCount"] = sseUpdateCount;
  perf["serialRxCount"] = serialRxCount;
  perf["wsClients"] = ws.count();
  perf["sseClients"] = events.count();

  if (doc.overflowed()) {
    Serial.println("WARNING: system JSON overflowed its document and is incomplete");
  }

  String output;
  serializeJson(doc, output);
  return output;
}
