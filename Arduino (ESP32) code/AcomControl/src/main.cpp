/*
 * AcomControl - ACOM 600S Amplifier Controller
 * Enhanced for ESP32-S3 with External API Support
 * VERSION: 5.0 - FIXED SERIAL PROTOCOL (PlatformIO)
 *
 * CRITICAL FIXES FROM v4:
 * 1. Start byte changed from 0xFE to 0x55 (per ACOM protocol)
 * 2. Checksum calculation fixed: CHKSUM = 256 - (SUM & 0xFF)
 * 3. Message structure fixed: Length byte = total message length
 * 4. Data field offsets corrected for 0x2F telemetry message
 * 5. Command message (0x81) structure corrected
 * 6. Added telemetry enable command (0x92)
 * 7. Fixed acknowledge message format
 *
 * HARDWARE: ESP32-S3 DevKit
 * - Uses UART2 for RS-232 communication with amplifier
 * - RX: GPIO16, TX: GPIO17 (configurable)
 * - 9600 baud, 8N1
 */

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <AsyncTCP.h>
#include <Preferences.h>
#include <ArduinoJson.h>

// ============================================================================
// ACOM PROTOCOL CONSTANTS (from official documentation)
// ============================================================================

// Start byte for all messages
#define ACOM_START_BYTE 0x55

// Message addresses - From Amplifier to Computer
#define MSG_ERROR_REPLY     0x01  // Reply to wrong received message
#define MSG_REQUEST         0x02  // Request for specific message
#define MSG_PCB_VERSIONS    0x11  // PCB Versions (30 bytes)
#define MSG_SETTINGS        0x12  // Amplifier settings (13 bytes)
#define MSG_SERIAL_NUMBER   0x13  // Serial number (16 bytes)
#define MSG_USER_SIGN_1     0x14  // User sign part 1 (19 bytes)
#define MSG_USER_SIGN_2     0x15  // User sign part 2 (19 bytes)
#define MSG_ATU_PARAMS      0x16  // ATU Parameters (19 bytes)
#define MSG_ASEL_PARAMS     0x17  // ASEL Parameters (19 bytes)
#define MSG_ANTENNA_NAMES   0x18  // Antenna names (19 bytes)
#define MSG_ERROR_CODES     0x21  // Error codes (24 bytes)
#define MSG_BAND_INFO       0x27  // Band info (17 bytes)
#define MSG_BAND_SEGMENTS   0x28  // Band segments (14 bytes)
#define MSG_TELEMETRY       0x2F  // Main telemetry (72 bytes)

// Message addresses - From Computer to Amplifier
#define MSG_CMD_AMPLIFIER   0x81  // Commands for amplifier management (8 bytes)
#define MSG_SET_SERIAL      0x82  // Set serial number (16 bytes)
#define MSG_SET_HELLO_1     0x83  // Set hello message part 1 (19 bytes)
#define MSG_SET_HELLO_2     0x84  // Set hello message part 2 (19 bytes)
#define MSG_SET_ANTENNA     0x85  // Set antenna names (19 bytes)
#define MSG_ACKNOWLEDGE     0x86  // Acknowledge message (5 bytes)
#define MSG_TELEMETRY_DIS   0x91  // Disable automatic telemetry (4 bytes)
#define MSG_TELEMETRY_EN    0x92  // Enable automatic telemetry (4 bytes)

// Amplifier modes (for command 0x02)
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
#define AMP_MODE_TX_PROHIBIT 0x40
#define AMP_MODE_TX_ALLOW   0x80

// Amplifier state codes (received in telemetry)
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
#define STATE_EXTRA_COOL    0xA2

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

// Amplifier state structure
struct AmplifierState {
  bool connected = false;
  uint8_t mode = 0;
  uint16_t forwardPower = 0;    // [W]
  uint16_t reflectedPower = 0;  // [W]
  uint16_t swr = 100;           // [100x] so 150 = 1.50
  uint16_t temperature = 273;   // [deg K]
  uint16_t inputPower = 0;      // [10 x W] so 253 = 25.3W
  uint16_t current = 0;         // [mA]
  uint16_t frequency = 0;       // [kHz]
  uint8_t band = 0;
  uint8_t antennaNum = 0;
  uint8_t antennaType = 0;
  bool isTx = false;
  uint16_t errorCodes[10] = {0};
  char serialNumber[13] = {0};
  uint8_t fanSpeed = 0;
  uint16_t hvVoltage = 0;       // [10 x V]
  uint16_t vcc5 = 0;            // [mV]
  uint16_t vcc26 = 0;           // [10 x V]
  uint16_t pdcPower = 0;        // [10 x W]
  uint16_t disPower = 0;        // [10 x W]
  uint8_t lpfChannel = 0;
  uint8_t errorCode = 0;
  uint16_t errorParam = 0;
  uint32_t lastUpdate = 0;
  uint32_t msgCount = 0;
} ampState;

// Mutexes for thread-safe access
SemaphoreHandle_t stateMutex;
SemaphoreHandle_t serialMutex;
SemaphoreHandle_t wsMutex;

// WiFi Configuration
String ssid = "";
String password = "";
bool apMode = true;
const char* apSSID = "AcomControl";

// Message buffers
uint8_t rxBuffer[128];
uint8_t txBuffer[128];
int rxIndex = 0;
unsigned long lastTelemetryRequest = 0;
unsigned long lastMessageTime = 0;
unsigned long lastRxTime = 0;
bool telemetryEnabled = false;

// Performance tuning
const int TELEMETRY_INTERVAL = 200;      // Request telemetry every 200ms
const int MESSAGE_DELAY = 15;            // Minimum 10ms between messages per spec
const int WS_BROADCAST_INTERVAL = 100;   // WebSocket broadcast at 10Hz
const int SSE_BROADCAST_INTERVAL = 200;  // SSE at 5Hz
const int CONNECTION_TIMEOUT = 5000;     // 5 seconds without data = disconnected

// Task handles
TaskHandle_t serialTaskHandle = NULL;

// Debug flags
#define DEBUG_SERIAL 0
#define DEBUG_RX 0
#define DEBUG_TX 0

// Helper function to derive band from frequency
uint8_t getBandFromFrequency(uint16_t freqKHz) {
  if (freqKHz >= 1800 && freqKHz <= 2000) return 1;   // 160m
  if (freqKHz >= 3500 && freqKHz <= 4000) return 2;   // 80m
  if (freqKHz >= 5330 && freqKHz <= 5410) return 2;   // 60m -> uses 80m LPF
  if (freqKHz >= 7000 && freqKHz <= 7300) return 3;   // 40m
  if (freqKHz >= 10100 && freqKHz <= 10150) return 4; // 30m
  if (freqKHz >= 14000 && freqKHz <= 14350) return 5; // 20m
  if (freqKHz >= 18068 && freqKHz <= 18168) return 6; // 17m
  if (freqKHz >= 21000 && freqKHz <= 21450) return 7; // 15m
  if (freqKHz >= 24890 && freqKHz <= 24990) return 8; // 12m
  if (freqKHz >= 28000 && freqKHz <= 29700) return 9; // 10m
  if (freqKHz >= 50000 && freqKHz <= 54000) return 10; // 6m
  return 0;
}

// ============================================================================
// FUNCTION PROTOTYPES
// ============================================================================

void setupWiFi();
void setupWebServer();
void setupAPIEndpoints();
void serialTask(void* parameter);
void handleSerial();
void processMessage(uint8_t* msg, int len);
void sendMessage(uint8_t address, uint8_t* data, int dataLen);
uint8_t calculateChecksum(uint8_t* msg, int len);
bool verifyChecksum(uint8_t* msg, int len);
void sendAcknowledge(uint8_t msgAddr);
void requestTelemetry();
void enableTelemetry();
void disableTelemetry();
void sendAmplifierCommand(uint8_t cmd, uint8_t paramHW, uint8_t paramLW, uint8_t buttons);
void requestMessage(uint8_t msgNum);
void broadcastState();
void broadcastSSE();
String getModeString(uint8_t mode);
String getBandString(uint8_t band);
String getStateJSON();
String getSystemInfoJSON();
void addCORSHeaders(AsyncWebServerResponse *response);
String getWebPage();

// ============================================================================
// SETUP
// ============================================================================

void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println("\n\n========================================");
  Serial.println("  AcomControl ESP32-S3 v5.0 (FIXED)");
  Serial.println("  ACOM 600S Serial Protocol Controller");
  Serial.println("  PlatformIO Build");
  Serial.println("========================================");

  // Set CPU frequency to maximum
  setCpuFrequencyMhz(240);
  Serial.printf("CPU Frequency: %d MHz\n", getCpuFrequencyMhz());

  // Configure UART2 for ACOM communication
  Serial2.setRxBufferSize(1024);
  Serial2.setTxBufferSize(512);
  Serial2.begin(BAUD_RATE, SERIAL_8N1, RXD2, TXD2);
  Serial.printf("UART2 initialized: %d baud, RX=%d, TX=%d\n", BAUD_RATE, RXD2, TXD2);

  // Create mutexes
  stateMutex = xSemaphoreCreateMutex();
  serialMutex = xSemaphoreCreateMutex();
  wsMutex = xSemaphoreCreateMutex();

  if (stateMutex == NULL || serialMutex == NULL || wsMutex == NULL) {
    Serial.println("FATAL: Failed to create mutexes!");
    while(1) delay(1000);
  }

  // Load WiFi credentials
  preferences.begin("wifi", false);
  ssid = preferences.getString("ssid", "");
  password = preferences.getString("password", "");
  preferences.end();

  // Setup WiFi
  setupWiFi();
  delay(1000);

  // Setup web server
  setupWebServer();
  setupAPIEndpoints();
  server.addHandler(&events);
  server.begin();

  Serial.println("Web server started!");
  Serial.print("Access web interface at: http://");
  Serial.println(apMode ? WiFi.softAPIP() : WiFi.localIP());

  // Create serial task on Core 0
  xTaskCreatePinnedToCore(
    serialTask,
    "SerialTask",
    8192,
    NULL,
    2,
    &serialTaskHandle,
    0
  );

  Serial.println("\nSetup complete! Waiting for ACOM amplifier...\n");
}

// ============================================================================
// MAIN LOOP
// ============================================================================

void loop() {
  static unsigned long lastWsBroadcast = 0;
  static unsigned long lastSseBroadcast = 0;
  static unsigned long lastCleanup = 0;

  unsigned long now = millis();

  // WebSocket cleanup
  if (now - lastCleanup >= 1000) {
    if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
      ws.cleanupClients();
      xSemaphoreGive(wsMutex);
    }
    lastCleanup = now;
  }

  // Broadcast to WebSocket clients
  if (now - lastWsBroadcast >= WS_BROADCAST_INTERVAL) {
    broadcastState();
    lastWsBroadcast = now;
  }

  // Broadcast to SSE clients
  if (now - lastSseBroadcast >= SSE_BROADCAST_INTERVAL) {
    broadcastSSE();
    lastSseBroadcast = now;
  }

  delay(10);
}

// ============================================================================
// SERIAL TASK (Core 0)
// ============================================================================

void serialTask(void* parameter) {
  Serial.println("Serial task started on Core 0");

  // Wait a bit then enable telemetry
  delay(2000);
  enableTelemetry();
  
  // Also request the PCB versions/serial number for initial info
  delay(100);
  requestMessage(MSG_PCB_VERSIONS);
  
  // Request band info (antenna and band selection)
  delay(100);
  requestMessage(MSG_BAND_INFO);

  TickType_t xLastWakeTime = xTaskGetTickCount();
  const TickType_t xFrequency = pdMS_TO_TICKS(50); // 20Hz loop
  
  static unsigned long lastBandInfoRequest = 0;

  for(;;) {
    // Handle incoming serial data
    handleSerial();

    // Check connection status
    unsigned long now = millis();
    if (ampState.connected && (now - lastRxTime > CONNECTION_TIMEOUT)) {
      if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        ampState.connected = false;
        Serial.println("ACOM amplifier disconnected (timeout)");
        xSemaphoreGive(stateMutex);
      }
    }

    // Request telemetry if not receiving automatic updates
    if (now - lastTelemetryRequest >= TELEMETRY_INTERVAL) {
      if (!telemetryEnabled || (now - lastRxTime > 1000)) {
        requestTelemetry();
      }
      lastTelemetryRequest = now;
    }
    
    // Periodically request band info (every 10 seconds)
    if (now - lastBandInfoRequest >= 10000) {
      requestMessage(MSG_BAND_INFO);
      lastBandInfoRequest = now;
    }

    vTaskDelayUntil(&xLastWakeTime, xFrequency);
  }
}

// ============================================================================
// SERIAL COMMUNICATION - FIXED PROTOCOL IMPLEMENTATION
// ============================================================================

// Track when we started receiving current message
static unsigned long rxStartTime = 0;
const unsigned long RX_FRAME_TIMEOUT = 100; // 100ms timeout for incomplete frames

void handleSerial() {
  unsigned long now = millis();
  
  // Check for frame timeout - reset if we started receiving but haven't completed
  if (rxIndex > 0 && (now - rxStartTime > RX_FRAME_TIMEOUT)) {
    rxIndex = 0;
  }
  
  while (Serial2.available()) {
    uint8_t b = Serial2.read();

    // Wait for start byte (0x55)
    if (rxIndex == 0) {
      if (b != ACOM_START_BYTE) {
        continue;
      }
      rxStartTime = now;  // Start timing the frame
    }

    rxBuffer[rxIndex++] = b;

    // Once we have at least 3 bytes, we know the message length
    if (rxIndex >= 3) {
      uint8_t msgLen = rxBuffer[2]; // Length includes all bytes

      // Sanity check on length (ACOM max is 72 bytes per spec)
      if (msgLen < 4 || msgLen > 72) {
        if (DEBUG_SERIAL) {
          Serial.printf("Invalid message length: %d (addr=0x%02X), resetting. Buffer: ", 
                        msgLen, rxBuffer[1]);
          for (int i = 0; i < rxIndex; i++) {
            Serial.printf("%02X ", rxBuffer[i]);
          }
          Serial.println();
        }
        rxIndex = 0;
        continue;
      }

      // Check if we have complete message
      if (rxIndex >= msgLen) {
        // Verify checksum
        if (verifyChecksum(rxBuffer, msgLen)) {
          lastRxTime = millis();
          processMessage(rxBuffer, msgLen);
        } else {
          if (DEBUG_SERIAL) {
            Serial.printf("Checksum error for address 0x%02X, expected sum=0, got %d. Buffer: ", 
                          rxBuffer[1], (int)rxBuffer[msgLen-1]);
            for (int i = 0; i < msgLen; i++) {
              Serial.printf("%02X ", rxBuffer[i]);
            }
            Serial.println();
          }
        }
        rxIndex = 0;
      }
    }

    // Buffer overflow protection
    if (rxIndex >= sizeof(rxBuffer)) {
      Serial.println("RX buffer overflow, resetting");
      rxIndex = 0;
    }
  }
}

// Calculate ACOM checksum: CHKSUM = 256 - (SUM of bytes 0 to N-1) & 0xFF
// When message is received correctly: SUM(Byte0..ByteN) = 0
uint8_t calculateChecksum(uint8_t* msg, int len) {
  uint32_t sum = 0;
  for (int i = 0; i < len; i++) {
    sum += msg[i];
  }
  return (uint8_t)(256 - (sum & 0xFF));
}

// Verify checksum - sum of all bytes including checksum should be 0
bool verifyChecksum(uint8_t* msg, int len) {
  uint32_t sum = 0;
  for (int i = 0; i < len; i++) {
    sum += msg[i];
  }
  return (sum & 0xFF) == 0;
}

// Send message with proper ACOM protocol format
void sendMessage(uint8_t address, uint8_t* data, int dataLen) {
  if (xSemaphoreTake(serialMutex, pdMS_TO_TICKS(100)) != pdTRUE) {
    return;
  }

  // Ensure minimum delay between messages (10ms per spec)
  unsigned long now = millis();
  if (now - lastMessageTime < MESSAGE_DELAY) {
    delay(MESSAGE_DELAY - (now - lastMessageTime));
  }

  // Build message
  // Format: |Start(0x55)|Address|Length|...Data...|Checksum|
  // Length = total bytes including start and checksum

  int msgLen = 4 + dataLen; // Start + Address + Length + Data + Checksum

  txBuffer[0] = ACOM_START_BYTE;
  txBuffer[1] = address;
  txBuffer[2] = msgLen;

  if (dataLen > 0 && data != NULL) {
    memcpy(&txBuffer[3], data, dataLen);
  }

  txBuffer[3 + dataLen] = calculateChecksum(txBuffer, 3 + dataLen);

  // Send
  Serial2.write(txBuffer, msgLen);
  Serial2.flush();

  if (DEBUG_TX) {
    Serial.printf("TX [%d bytes]: ", msgLen);
    for (int i = 0; i < msgLen; i++) {
      Serial.printf("%02X ", txBuffer[i]);
    }
    Serial.println();
  }

  lastMessageTime = millis();
  xSemaphoreGive(serialMutex);
}

// Send acknowledge message (address 0x86)
// Format: |0x55|0x86|0x05|MsgAddr|Checksum|
void sendAcknowledge(uint8_t msgAddr) {
  uint8_t data[1] = {msgAddr};
  sendMessage(MSG_ACKNOWLEDGE, data, 1);
}

// Enable automatic telemetry (address 0x92)
// Format: |0x55|0x92|0x04|Checksum|
void enableTelemetry() {
  Serial.println("Enabling automatic telemetry...");
  sendMessage(MSG_TELEMETRY_EN, NULL, 0);
  telemetryEnabled = true;
}

// Disable automatic telemetry (address 0x91)
void disableTelemetry() {
  Serial.println("Disabling automatic telemetry...");
  sendMessage(MSG_TELEMETRY_DIS, NULL, 0);
  telemetryEnabled = false;
}

// Request specific message via command 0x81 with cmd=0x01
// Per ACOM protocol section 5.1: Command 0x01 = "Request for specific message"
void requestMessage(uint8_t msgNum) {
  sendAmplifierCommand(0x01, msgNum, msgNum, 0x00);
}

// Request telemetry data
void requestTelemetry() {
  requestMessage(MSG_TELEMETRY);
}

// Send amplifier command (address 0x81)
// Format: |0x55|0x81|0x08|Cmd|ParamHW|ParamLW|Buttons|Checksum|
void sendAmplifierCommand(uint8_t cmd, uint8_t paramHW, uint8_t paramLW, uint8_t buttons) {
  uint8_t data[4];
  data[0] = cmd;
  data[1] = paramHW;
  data[2] = paramLW;
  data[3] = buttons;
  sendMessage(MSG_CMD_AMPLIFIER, data, 4);

  if (DEBUG_TX) {
    Serial.printf("Sent command: cmd=0x%02X, paramHW=0x%02X, paramLW=0x%02X\n",
                  cmd, paramHW, paramLW);
  }
}

// ============================================================================
// MESSAGE PROCESSING - Fixed offsets per ACOM protocol
// ============================================================================

void processMessage(uint8_t* msg, int len) {
  uint8_t address = msg[1];

  if (DEBUG_RX) {
    Serial.printf("RX [0x%02X, %d bytes]: ", address, len);
    for (int i = 0; i < min(len, 20); i++) {
      Serial.printf("%02X ", msg[i]);
    }
    if (len > 20) Serial.print("...");
    Serial.println();
  }

  // Send acknowledge for messages that require it
  if (address == MSG_TELEMETRY || address == MSG_ERROR_CODES ||
      address == MSG_BAND_INFO || address == MSG_PCB_VERSIONS) {
    sendAcknowledge(address);
  }

  // Lock state for updates
  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(100)) != pdTRUE) {
    return;
  }

  ampState.connected = true;
  ampState.msgCount++;

  // Process message based on address
  switch (address) {
    case MSG_TELEMETRY:  // 0x2F - Main telemetry (72 bytes)
      if (len >= 72) {
        // Byte 3: Amplifier mode
        ampState.mode = msg[3];
        ampState.isTx = (ampState.mode & 0xF0) == STATE_OPR_TX;

        // Bytes 4-5: Amplifier Flags 1 (not currently used)
        // Bytes 6-7: Amplifier Flags 2 (not currently used)

        // Bytes 8-9: P_DC1 [10 x W] (Low, High)
        ampState.pdcPower = msg[8] | (msg[9] << 8);

        // Bytes 10-11: P_DC2 (not used for 600S)

        // Bytes 12-15: System Clock (not currently used)

        // Bytes 16-17: Temperature of PAM1 [deg K] (Low, High)
        ampState.temperature = msg[16] | (msg[17] << 8);

        // Bytes 18-19: Temperature of PAM2 (not used for 600S)

        // Bytes 20-21: Input Power [10 x W] (Low, High)
        ampState.inputPower = msg[20] | (msg[21] << 8);

        // Bytes 22-23: Forward Power [W] (Low, High)
        ampState.forwardPower = msg[22] | (msg[23] << 8);

        // Bytes 24-25: Reflected Power [W] (Low, High)
        ampState.reflectedPower = msg[24] | (msg[25] << 8);

        // Bytes 26-27: SWR [100x] (Low, High)
        ampState.swr = msg[26] | (msg[27] << 8);

        // Bytes 28-29: PAM1 Dissipation Power [10 x W] (Low, High)
        ampState.disPower = msg[28] | (msg[29] << 8);

        // Bytes 30-31: PAM2 Dissipation Power (not used for 600S)

        // Bytes 32-33: bdata [mV] (not currently used)

        // Bytes 34-35: disbalance [mV] (not used for 600S)

        // Bytes 36-37: VCC5 [mV] (Low, High)
        ampState.vcc5 = msg[36] | (msg[37] << 8);

        // Bytes 38-39: VCC26 [10 x V] (Low, High)
        ampState.vcc26 = msg[38] | (msg[39] << 8);

        // Bytes 40-41: HV1 [10 x V] (Low, High)
        ampState.hvVoltage = msg[40] | (msg[41] << 8);

        // Bytes 42-43: HV2 (not used for 600S)

        // Bytes 44-45: ID1 [mA] (Low, High)
        ampState.current = msg[44] | (msg[45] << 8);

        // Bytes 46-47: ID2 (not used for 600S)

        // Bytes 48-49: Frequency [kHz] (Low, High)
        ampState.frequency = msg[48] | (msg[49] << 8);

        // Bytes 50-65: Bias voltages (not currently displayed)

        // Byte 66: Error code
        ampState.errorCode = msg[66];

        // Bytes 67-68: Error parameter
        ampState.errorParam = msg[67] | (msg[68] << 8);

        // Byte 69: Status flags (Fan speed in bits 4-7, LPF channel in bits 0-3)
        ampState.fanSpeed = (msg[69] >> 4) & 0x0F;
        ampState.lpfChannel = msg[69] & 0x0F;

        // Byte 70: System status flags

        // Update band from LPF channel
        // LPF channels are 1-10: 1=160m, 2=80/60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m, 9=10m, 10=6m
        // This matches our display band codes directly
        if (ampState.lpfChannel >= 1 && ampState.lpfChannel <= 10) {
          ampState.band = ampState.lpfChannel;
        } else if (ampState.frequency > 0) {
          // Fallback to frequency-based detection
          ampState.band = getBandFromFrequency(ampState.frequency);
        }
        
        // If antenna not set, default to 1
        if (ampState.antennaNum == 0) {
          ampState.antennaNum = 1;
        }

        ampState.lastUpdate = millis();

        if (DEBUG_SERIAL) {
          Serial.printf("Telemetry: Mode=0x%02X, Fwd=%dW, Ref=%dW, SWR=%d, Temp=%dK, Freq=%dkHz, LPF=%d\n",
                        ampState.mode, ampState.forwardPower, ampState.reflectedPower,
                        ampState.swr, ampState.temperature, ampState.frequency, ampState.lpfChannel);
        }
      }
      break;

    case MSG_BAND_INFO:  // 0x27 - Band info (17 bytes)
      if (len >= 17) {
        // Byte 3: Antenna number [1..10]
        uint8_t antNum = msg[3];
        
        // Byte 4: Antenna type [1-Default, 2-Exact, 3-Narrow, 4-Wide]
        uint8_t antType = msg[4];

        // Byte 5: Band number
        uint8_t bandNum = msg[5];
        
        // Only update if we got valid data (non-zero)
        if (antNum > 0) ampState.antennaNum = antNum;
        if (antType > 0) ampState.antennaType = antType;
        // Band from MSG_BAND_INFO takes priority if non-zero
        if (bandNum > 0) ampState.band = bandNum;

        if (DEBUG_SERIAL) {
          Serial.printf("Band info: Ant=%d, Type=%d, Band=%d\n",
                        ampState.antennaNum, ampState.antennaType, ampState.band);
        }
      }
      break;

    case MSG_ERROR_CODES:  // 0x21 - Error codes (24 bytes)
      if (len >= 24) {
        // Bytes 3-22: Error codes (10 x 2 bytes)
        for (int i = 0; i < 10; i++) {
          int offset = 3 + (i * 2);
          ampState.errorCodes[i] = msg[offset] | (msg[offset + 1] << 8);
        }

        if (DEBUG_SERIAL) {
          Serial.print("Error codes: ");
          for (int i = 0; i < 10; i++) {
            if (ampState.errorCodes[i] != 0) {
              Serial.printf("0x%04X ", ampState.errorCodes[i]);
            }
          }
          Serial.println();
        }
      }
      break;

    case MSG_PCB_VERSIONS:  // 0x11 - PCB Versions (30 bytes)
      if (len >= 30) {
        // Bytes 16-27: Serial number (12 bytes)
        memcpy(ampState.serialNumber, &msg[16], 12);
        ampState.serialNumber[12] = '\0';

        if (DEBUG_SERIAL) {
          Serial.printf("PCB Versions received, S/N: %s\n", ampState.serialNumber);
        }
      }
      break;

    case MSG_SERIAL_NUMBER:  // 0x13 - Serial number (16 bytes)
      if (len >= 16) {
        memcpy(ampState.serialNumber, &msg[3], 12);
        ampState.serialNumber[12] = '\0';

        if (DEBUG_SERIAL) {
          Serial.printf("Serial number: %s\n", ampState.serialNumber);
        }
      }
      break;

    default:
      if (DEBUG_SERIAL) {
        Serial.printf("Unhandled message address: 0x%02X\n", address);
      }
      break;
  }

  xSemaphoreGive(stateMutex);
}

// ============================================================================
// WIFI SETUP
// ============================================================================

void setupWiFi() {
  WiFi.mode(WIFI_MODE_NULL);
  delay(100);

  if (ssid.length() > 0) {
    Serial.printf("Connecting to WiFi: %s\n", ssid.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid.c_str(), password.c_str());

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
  WiFi.softAP(apSSID);
  delay(100);

  Serial.print("AP SSID: ");
  Serial.println(apSSID);
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());
}

// ============================================================================
// WEB SERVER SETUP
// ============================================================================

void setupWebServer() {
  // Root endpoint
  server.on("/", HTTP_GET, [](AsyncWebServerRequest *request){
    request->send(200, "text/html", getWebPage());
  });

  // WebSocket setup
  ws.onEvent([](AsyncWebSocket *server, AsyncWebSocketClient *client,
                AwsEventType type, void *arg, uint8_t *data, size_t len) {

    if (type == WS_EVT_CONNECT) {
      Serial.printf("WebSocket client #%u connected\n", client->id());
      if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        String json = getStateJSON();
        client->text(json);
        xSemaphoreGive(wsMutex);
      }

    } else if (type == WS_EVT_DISCONNECT) {
      Serial.printf("WebSocket client #%u disconnected\n", client->id());

    } else if (type == WS_EVT_DATA) {
      AwsFrameInfo *info = (AwsFrameInfo*)arg;
      if (info->final && info->index == 0 && info->len == len && info->opcode == WS_TEXT) {
        data[len] = 0;

        StaticJsonDocument<256> doc;
        DeserializationError error = deserializeJson(doc, (char*)data);

        if (!error) {
          const char* cmd = doc["cmd"];

          if (strcmp(cmd, "setMode") == 0) {
            uint8_t mode = doc["mode"];
            // Command 0x02: Request for amplifier mode change
            sendAmplifierCommand(0x02, 0x00, mode, 0x00);

          } else if (strcmp(cmd, "setBand") == 0) {
            uint8_t band = doc["band"];
            uint8_t antenna = doc["antenna"] | 1;
            // Command 0x09: Manual changing of antenna and band
            // UI band codes: 1=160m, 2=80/60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m, 9=10m, 10=6m
            // Amplifier band codes: 1=160m, 2=80m, 4=40m, 5=30m, 6=20m, 7=17m, 8=15m, 9=12m, 10=10m, 11=6m
            // The amplifier skips band code 3 (was reserved for 60m)
            uint8_t ampBand = band;
            if (band >= 3) {
              ampBand = band + 1;  // Shift 3->4, 4->5, etc.
            }
            Serial.printf("setBand: UI band=%d, amp band=%d, antenna=%d\n", band, ampBand, antenna);
            sendAmplifierCommand(0x09, antenna, ampBand, 0x00);

          } else if (strcmp(cmd, "clearErrors") == 0) {
            // Command 0x08: Clear SOFT FAULT errors
            sendAmplifierCommand(0x08, 0x00, 0x00, 0x00);

          } else if (strcmp(cmd, "saveWiFi") == 0) {
            const char* newSsid = doc["ssid"];
            const char* newPass = doc["password"];

            preferences.begin("wifi", false);
            preferences.putString("ssid", newSsid);
            preferences.putString("password", newPass);
            preferences.end();

            delay(500);
            ESP.restart();

          } else if (strcmp(cmd, "requestInfo") == 0) {
            // Request PCB versions (includes serial number)
            requestMessage(MSG_PCB_VERSIONS);
          }
        }
      }
    }
  });

  server.addHandler(&ws);
}

void setupAPIEndpoints() {
  // GET /api/status
  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request){
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", getStateJSON());
    addCORSHeaders(response);
    request->send(response);
  });

  // POST /api/mode
  server.on("/api/mode", HTTP_POST, [](AsyncWebServerRequest *request){}, NULL,
    [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
      StaticJsonDocument<128> doc;
      deserializeJson(doc, (char*)data);

      if (doc.containsKey("mode")) {
        uint8_t mode = doc["mode"];
        sendAmplifierCommand(0x02, 0x00, mode, 0x00);

        String output = "{\"success\":true,\"mode\":" + String(mode) + "}";
        AsyncWebServerResponse *resp = request->beginResponse(200, "application/json", output);
        addCORSHeaders(resp);
        request->send(resp);
      } else {
        request->send(400, "application/json", "{\"success\":false,\"error\":\"Missing mode\"}");
      }
    });

  // POST /api/band
  server.on("/api/band", HTTP_POST, [](AsyncWebServerRequest *request){}, NULL,
    [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
      StaticJsonDocument<128> doc;
      deserializeJson(doc, (char*)data);

      if (doc.containsKey("band")) {
        uint8_t band = doc["band"];
        uint8_t antenna = doc["antenna"] | 1;
        // Convert UI band code to amplifier band code (amplifier skips code 3)
        uint8_t ampBand = band;
        if (band >= 3) {
          ampBand = band + 1;
        }
        sendAmplifierCommand(0x09, antenna, ampBand, 0x00);

        String output = "{\"success\":true,\"band\":" + String(band) + ",\"antenna\":" + String(antenna) + "}";
        AsyncWebServerResponse *resp = request->beginResponse(200, "application/json", output);
        addCORSHeaders(resp);
        request->send(resp);
      } else {
        request->send(400, "application/json", "{\"success\":false,\"error\":\"Missing band\"}");
      }
    });

  // POST /api/wifi
  server.on("/api/wifi", HTTP_POST, [](AsyncWebServerRequest *request){}, NULL,
    [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
      StaticJsonDocument<256> doc;
      deserializeJson(doc, (char*)data);

      if (doc.containsKey("ssid")) {
        const char* newSsid = doc["ssid"];
        const char* newPass = doc["password"] | "";

        preferences.begin("wifi", false);
        preferences.putString("ssid", newSsid);
        preferences.putString("password", newPass);
        preferences.end();

        request->send(200, "application/json", "{\"success\":true,\"message\":\"Rebooting...\"}");
        delay(500);
        ESP.restart();
      } else {
        request->send(400, "application/json", "{\"success\":false,\"error\":\"Missing ssid\"}");
      }
    });

  // GET /api/system
  server.on("/api/system", HTTP_GET, [](AsyncWebServerRequest *request){
    AsyncWebServerResponse *response = request->beginResponse(200, "application/json", getSystemInfoJSON());
    addCORSHeaders(response);
    request->send(response);
  });

  // OPTIONS for CORS
  server.on("/api/*", HTTP_OPTIONS, [](AsyncWebServerRequest *request){
    AsyncWebServerResponse *response = request->beginResponse(200);
    addCORSHeaders(response);
    request->send(response);
  });
}

void addCORSHeaders(AsyncWebServerResponse *response) {
  response->addHeader("Access-Control-Allow-Origin", "*");
  response->addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  response->addHeader("Access-Control-Allow-Headers", "Content-Type");
}

// ============================================================================
// BROADCASTING
// ============================================================================

void broadcastState() {
  if (ws.count() == 0) return;

  if (xSemaphoreTake(wsMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
    String json = getStateJSON();
    ws.textAll(json);
    xSemaphoreGive(wsMutex);
  }
}

void broadcastSSE() {
  if (events.count() == 0) return;

  String json = getStateJSON();
  events.send(json.c_str(), "state", millis());
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

String getModeString(uint8_t mode) {
  uint8_t modeHigh = mode & 0xF0;
  switch(modeHigh) {
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

String getBandString(uint8_t band) {
  // Band codes match LPF channels (1-10)
  // 1=160m, 2=80/60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m, 9=10m, 10=6m
  switch(band) {
    case 1:  return "160m";
    case 2:  return "80/60m";
    case 3:  return "40m";
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

String getStateJSON() {
  StaticJsonDocument<1024> doc;

  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
    doc["connected"] = ampState.connected;
    doc["mode"] = getModeString(ampState.mode);
    doc["modeCode"] = ampState.mode;
    doc["band"] = getBandString(ampState.band);
    doc["bandCode"] = ampState.band;
    doc["antenna"] = ampState.antennaNum;
    doc["isTx"] = ampState.isTx;
    doc["forwardPower"] = ampState.forwardPower;
    doc["reflectedPower"] = ampState.reflectedPower;
    doc["swr"] = ampState.swr;
    doc["temperature"] = ampState.temperature;
    doc["inputPower"] = ampState.inputPower;
    doc["current"] = ampState.current;
    doc["frequency"] = ampState.frequency;
    doc["fanSpeed"] = ampState.fanSpeed;
    doc["hvVoltage"] = ampState.hvVoltage;
    doc["vcc5"] = ampState.vcc5;
    doc["vcc26"] = ampState.vcc26;
    doc["pdcPower"] = ampState.pdcPower;
    doc["disPower"] = ampState.disPower;
    doc["lpfChannel"] = ampState.lpfChannel;
    doc["errorCode"] = ampState.errorCode;
    doc["errorParam"] = ampState.errorParam;
    doc["serialNumber"] = ampState.serialNumber;
    doc["lastUpdate"] = ampState.lastUpdate;
    doc["msgCount"] = ampState.msgCount;

    JsonArray errors = doc.createNestedArray("errors");
    for (int i = 0; i < 10; i++) {
      if (ampState.errorCodes[i] != 0) {
        errors.add(ampState.errorCodes[i]);
      }
    }

    xSemaphoreGive(stateMutex);
  }

  String output;
  serializeJson(doc, output);
  return output;
}

String getSystemInfoJSON() {
  StaticJsonDocument<512> doc;

  doc["version"] = "5.0";
  doc["chip"] = "ESP32-S3";
  doc["cpuFreqMHz"] = getCpuFrequencyMhz();
  doc["freeHeap"] = ESP.getFreeHeap();
  doc["heapSize"] = ESP.getHeapSize();
  doc["uptime"] = millis() / 1000;
  doc["wifiMode"] = apMode ? "AP" : "STA";
  doc["ip"] = apMode ? WiFi.softAPIP().toString() : WiFi.localIP().toString();
  doc["rssi"] = apMode ? 0 : WiFi.RSSI();
  doc["wsClients"] = ws.count();
  doc["sseClients"] = events.count();
  doc["telemetryEnabled"] = telemetryEnabled;

  String output;
  serializeJson(doc, output);
  return output;
}

// ============================================================================
// WEB PAGE
// ============================================================================

String getWebPage() {
  return R"rawliteral(
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AcomControl v5.0</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: #e8e8e8;
      min-height: 100vh;
      padding: 20px;
    }
    .container { max-width: 900px; margin: 0 auto; }
    h1 { text-align: center; margin-bottom: 10px; color: #4a9eff; }
    .version { text-align: center; font-size: 12px; color: #666; margin-bottom: 20px; }

    .connection-status {
      position: fixed; top: 10px; right: 10px;
      padding: 8px 16px; border-radius: 20px;
      font-size: 12px; font-weight: bold;
      background: #dc3545; color: white;
    }
    .connection-status.connected { background: #28a745; }

    .status {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 15px;
      margin-bottom: 25px;
    }
    .status-item {
      background: rgba(255,255,255,0.05);
      padding: 15px;
      border-radius: 10px;
      text-align: center;
    }
    .status-label { font-size: 12px; color: #888; margin-bottom: 5px; }
    .status-value { font-size: 24px; font-weight: bold; color: #4a9eff; }
    .status-value.tx { color: #ff6b6b; }
    .status-value.rx { color: #51cf66; }

    .meters { display: grid; grid-template-columns: repeat(2, 1fr); gap: 15px; margin-bottom: 25px; }
    .meter {
      background: rgba(255,255,255,0.05);
      padding: 15px;
      border-radius: 10px;
    }
    .meter-label {
      display: flex;
      justify-content: space-between;
      margin-bottom: 8px;
      font-size: 14px;
    }
    .meter-bar {
      height: 20px;
      background: rgba(0,0,0,0.3);
      border-radius: 10px;
      overflow: hidden;
    }
    .meter-fill {
      height: 100%;
      background: linear-gradient(90deg, #4a9eff, #00d4ff);
      border-radius: 10px;
      transition: width 0.3s ease;
    }
    .meter-fill.warning { background: linear-gradient(90deg, #ffc107, #ff8c00); }
    .meter-fill.danger { background: linear-gradient(90deg, #dc3545, #ff6b6b); }

    .controls {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-bottom: 20px;
    }
    button {
      padding: 12px 24px;
      font-size: 14px;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      background: #4a9eff;
      color: white;
      transition: all 0.2s;
    }
    button:hover { transform: translateY(-2px); opacity: 0.9; }
    button:active { transform: translateY(0); }
    .btn-warning { background: #ffc107; color: #000; }
    .btn-danger { background: #dc3545; }
    .btn-secondary { background: #6c757d; }

    .band-grid {
      display: grid;
      grid-template-columns: repeat(6, 1fr);
      gap: 8px;
      margin-bottom: 25px;
    }
    .band-btn {
      padding: 10px;
      font-size: 12px;
      background: rgba(255,255,255,0.1);
    }
    .band-btn.active { background: #4a9eff; }

    h3 { margin: 20px 0 10px; color: #888; font-size: 14px; text-transform: uppercase; }

    .debug-info {
      background: rgba(0,0,0,0.3);
      padding: 15px;
      border-radius: 10px;
      font-family: monospace;
      font-size: 11px;
      margin-top: 20px;
    }

    .wifi-config {
      background: rgba(255,255,255,0.05);
      padding: 20px;
      border-radius: 10px;
      margin-top: 20px;
    }
    .wifi-config input {
      width: 100%;
      padding: 10px;
      margin: 5px 0 10px;
      border: none;
      border-radius: 5px;
      background: rgba(0,0,0,0.3);
      color: #fff;
    }

    @media (max-width: 600px) {
      .status { grid-template-columns: repeat(2, 1fr); }
      .meters { grid-template-columns: 1fr; }
      .band-grid { grid-template-columns: repeat(4, 1fr); }
    }
  </style>
</head>
<body>
  <div class="connection-status" id="connStatus">OFFLINE</div>

  <div class="container">
    <h1>⚡ AcomControl</h1>
    <div class="version">v5.0 - ACOM 600S Controller (Fixed Protocol)</div>

    <div class="status">
      <div class="status-item">
        <div class="status-label">Mode</div>
        <div class="status-value" id="mode">---</div>
      </div>
      <div class="status-item">
        <div class="status-label">Band</div>
        <div class="status-value" id="band">---</div>
      </div>
      <div class="status-item">
        <div class="status-label">Status</div>
        <div class="status-value rx" id="txrx">RX</div>
      </div>
    </div>

    <div class="meters">
      <div class="meter">
        <div class="meter-label">
          <span>Forward Power</span>
          <span id="fwdValue">0 W</span>
        </div>
        <div class="meter-bar">
          <div class="meter-fill" id="fwdBar" style="width: 0%"></div>
        </div>
      </div>
      <div class="meter">
        <div class="meter-label">
          <span>Reflected Power</span>
          <span id="refValue">0 W</span>
        </div>
        <div class="meter-bar">
          <div class="meter-fill" id="refBar" style="width: 0%"></div>
        </div>
      </div>
      <div class="meter">
        <div class="meter-label">
          <span>SWR</span>
          <span id="swrValue">1.00</span>
        </div>
        <div class="meter-bar">
          <div class="meter-fill" id="swrBar" style="width: 0%"></div>
        </div>
      </div>
      <div class="meter">
        <div class="meter-label">
          <span>Temperature</span>
          <span id="tempValue">--°C</span>
        </div>
        <div class="meter-bar">
          <div class="meter-fill" id="tempBar" style="width: 0%"></div>
        </div>
      </div>
      <div class="meter">
        <div class="meter-label">
          <span>Input Power</span>
          <span id="inValue">0 W</span>
        </div>
        <div class="meter-bar">
          <div class="meter-fill" id="inBar" style="width: 0%"></div>
        </div>
      </div>
      <div class="meter">
        <div class="meter-label">
          <span>Current</span>
          <span id="curValue">0 A</span>
        </div>
        <div class="meter-bar">
          <div class="meter-fill" id="curBar" style="width: 0%"></div>
        </div>
      </div>
    </div>

    <h3>Mode Control</h3>
    <div class="controls">
      <button onclick="setMode(5)">Standby</button>
      <button onclick="setMode(6)" class="btn-warning">Operate</button>
      <button onclick="setMode(10)" class="btn-danger">Power Off</button>
      <button onclick="clearErrors()" class="btn-secondary">Clear Errors</button>
      <button onclick="requestInfo()" class="btn-secondary">Get Info</button>
    </div>

    <h3>Band Selection</h3>
    <div class="band-grid">
      <button class="band-btn" onclick="setBand(1)">160m</button>
      <button class="band-btn" onclick="setBand(2)">80/60m</button>
      <button class="band-btn" onclick="setBand(3)">40m</button>
      <button class="band-btn" onclick="setBand(4)">30m</button>
      <button class="band-btn" onclick="setBand(5)">20m</button>
      <button class="band-btn" onclick="setBand(6)">17m</button>
      <button class="band-btn" onclick="setBand(7)">15m</button>
      <button class="band-btn" onclick="setBand(8)">12m</button>
      <button class="band-btn" onclick="setBand(9)">10m</button>
      <button class="band-btn" onclick="setBand(10)">6m</button>
    </div>

    <div class="debug-info" id="debugInfo">
      Waiting for data...
    </div>

    <div class="wifi-config">
      <h3>WiFi Configuration</h3>
      <input type="text" id="wifiSsid" placeholder="WiFi SSID">
      <input type="password" id="wifiPass" placeholder="WiFi Password">
      <button onclick="saveWiFi()">Save & Reboot</button>
    </div>
  </div>

  <script>
    let ws;
    let reconnectTimer;
    const maxFwd = 600, maxRef = 100, maxSwr = 3, maxTemp = 100, maxIn = 100, maxCur = 30;

    function connect() {
      ws = new WebSocket('ws://' + location.host + '/ws');

      ws.onopen = () => {
        console.log('Connected');
        document.getElementById('connStatus').textContent = 'CONNECTED';
        document.getElementById('connStatus').className = 'connection-status connected';
        clearTimeout(reconnectTimer);
      };

      ws.onclose = () => {
        console.log('Disconnected');
        document.getElementById('connStatus').textContent = 'OFFLINE';
        document.getElementById('connStatus').className = 'connection-status';
        reconnectTimer = setTimeout(connect, 2000);
      };

      ws.onerror = (e) => console.error('WebSocket error:', e);

      ws.onmessage = (e) => {
        try {
          const data = JSON.parse(e.data);
          updateDisplay(data);
        } catch (err) {
          console.error('Parse error:', err);
        }
      };
    }

    function updateDisplay(d) {
      // Connection status
      const connStatus = document.getElementById('connStatus');
      if (d.connected) {
        connStatus.textContent = 'CONNECTED';
        connStatus.className = 'connection-status connected';
      } else {
        connStatus.textContent = 'NO AMP';
        connStatus.className = 'connection-status';
      }

      // Status items
      if (d.mode) document.getElementById('mode').textContent = d.mode;
      if (d.band) document.getElementById('band').textContent = d.band;

      const txrx = document.getElementById('txrx');
      txrx.textContent = d.isTx ? 'TX' : 'RX';
      txrx.className = 'status-value ' + (d.isTx ? 'tx' : 'rx');

      // Meters
      updateMeter('fwd', d.forwardPower || 0, maxFwd, ' W');
      updateMeter('ref', d.reflectedPower || 0, maxRef, ' W');

      // SWR is in 100x format, so 150 = 1.50
      const swr = (d.swr || 100) / 100;
      updateMeter('swr', swr, maxSwr, '');
      document.getElementById('swrValue').textContent = swr.toFixed(2);

      // Temperature is in Kelvin
      const tempC = (d.temperature || 273) - 273;
      updateMeter('temp', tempC, maxTemp, '°C');

      // Input power is in 10xW format
      const inputW = (d.inputPower || 0) / 10;
      updateMeter('in', inputW, maxIn, ' W');

      // Current is in mA
      const currentA = (d.current || 0) / 1000;
      updateMeter('cur', currentA, maxCur, ' A');

      // Debug info
      document.getElementById('debugInfo').innerHTML =
        `Mode: 0x${(d.modeCode || 0).toString(16).toUpperCase().padStart(2, '0')} | ` +
        `Freq: ${d.frequency || 0} kHz | ` +
        `HV: ${((d.hvVoltage || 0) / 10).toFixed(1)}V | ` +
        `Vcc5: ${((d.vcc5 || 0) / 1000).toFixed(2)}V | ` +
        `Msgs: ${d.msgCount || 0} | ` +
        `S/N: ${d.serialNumber || 'N/A'}`;
    }

    function updateMeter(id, value, max, unit) {
      const percent = Math.min((value / max) * 100, 100);
      const bar = document.getElementById(id + 'Bar');
      const valueEl = document.getElementById(id + 'Value');

      bar.style.width = percent + '%';
      bar.className = 'meter-fill';
      if (percent > 80) bar.className += ' danger';
      else if (percent > 60) bar.className += ' warning';

      if (id !== 'swr') {
        valueEl.textContent = value.toFixed(id === 'cur' ? 2 : 0) + unit;
      }
    }

    function send(cmd, data) {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({cmd, ...data}));
      }
    }

    function setMode(mode) { send('setMode', {mode}); }
    function setBand(band) { send('setBand', {band, antenna: 1}); }
    function clearErrors() { send('clearErrors', {}); }
    function requestInfo() { send('requestInfo', {}); }

    function saveWiFi() {
      const ssid = document.getElementById('wifiSsid').value;
      const password = document.getElementById('wifiPass').value;
      if (!ssid) { alert('Enter WiFi SSID'); return; }
      send('saveWiFi', {ssid, password});
      alert('WiFi saved. Rebooting...');
    }

    connect();
  </script>
</body>
</html>
)rawliteral";
}
