/*
 * acom_faults.h - ACOM fault code table
 *
 * Transcribed from "ACOM Protocol.pdf" section 3.4.1 (message 0x21), which
 * ships alongside this firmware. Message 0x21 is a BITFIELD, not a list of
 * code values: it carries ten 16-bit words, and bit `n` of word `k` means
 * fault code (k * 16) + n is active. Telemetry byte 66 reports the code
 * currently on the amplifier's screen using the same numbering.
 *
 * Two documentation errors in the PDF are corrected here. Word 9 prints its
 * codes as 0x80..0x8F, duplicating word 8; by bit position they are
 * 0x90..0x9F. Byte 14 bit 7 prints (0x3F); by position it is 0x5F, and is
 * unnamed. Codes are therefore derived from bit position throughout, never
 * from the printed label.
 *
 * GENERATED FILE - edit tools/gen_faults.py and re-run it instead.
 */


#ifndef ACOM_FAULTS_H
#define ACOM_FAULTS_H

#include <Arduino.h>

// Fault severity, as defined by the amplifier's three protection levels.
enum AcomFaultSeverity : uint8_t {
  ACOM_WARNING    = 0,  // transmission continues
  ACOM_SOFT_FAULT = 1,  // amplifier reverts to standby
  ACOM_HARD_FAULT = 2,  // amplifier shuts its supply down
};

struct AcomFault {
  uint8_t code;
  uint8_t severity;
  const char* text;
};

// Sorted by code so lookups can binary search.
const AcomFault ACOM_FAULTS[] PROGMEM = {
  {0x00, ACOM_WARNING,   "Hot switching attempt"},
  {0x01, ACOM_WARNING,   "Output relay closed, it should be open"},
  {0x02, ACOM_HARD_FAULT, "Output relay open, it should be closed"},
  {0x03, ACOM_HARD_FAULT, "Drive power detected at wrong time"},
  {0x04, ACOM_WARNING,   "Reflected power warning"},
  {0x05, ACOM_SOFT_FAULT, "Excessive reflected power"},
  {0x06, ACOM_WARNING,   "Drive power too high"},
  {0x07, ACOM_SOFT_FAULT, "Excessive drive power"},
  {0x08, ACOM_SOFT_FAULT, "Hot switching attempt"},
  {0x09, ACOM_SOFT_FAULT, "Drive frequency out of range"},
  {0x0A, ACOM_SOFT_FAULT, "Frequency violation"},
  {0x0B, ACOM_SOFT_FAULT, "Output disbalance"},
  {0x0C, ACOM_WARNING,   "Detected RF power at wrong time"},
  {0x0D, ACOM_SOFT_FAULT, "PA load SWR too high"},
  {0x0E, ACOM_WARNING,   "Stop transmission first"},
  {0x0F, ACOM_WARNING,   "Remove drive power immediately"},
  {0x10, ACOM_HARD_FAULT, "5 V too low"},
  {0x11, ACOM_HARD_FAULT, "5 V too high"},
  {0x12, ACOM_HARD_FAULT, "26 V too low"},
  {0x13, ACOM_HARD_FAULT, "26 V too high"},
  {0x15, ACOM_HARD_FAULT, "PAM1 fan speed too low"},
  {0x16, ACOM_HARD_FAULT, "PAM2 fan speed too low"},
  {0x17, ACOM_HARD_FAULT, "LPF fan speed too low"},
  {0x18, ACOM_SOFT_FAULT, "PAM1 dissipation power too high"},
  {0x19, ACOM_SOFT_FAULT, "PAM2 dissipation power too high"},
  {0x1A, ACOM_WARNING,   "PAM1 dissipation power warning"},
  {0x1B, ACOM_WARNING,   "PAM2 dissipation power warning"},
  {0x1C, ACOM_WARNING,   "PAM1 temperature too high"},
  {0x1D, ACOM_WARNING,   "PAM2 temperature too high"},
  {0x1E, ACOM_SOFT_FAULT, "PAM1 excessive temperature"},
  {0x1F, ACOM_SOFT_FAULT, "PAM2 excessive temperature"},
  {0x20, ACOM_HARD_FAULT, "PAM1 HV too low"},
  {0x21, ACOM_HARD_FAULT, "PAM1 HV too high"},
  {0x22, ACOM_SOFT_FAULT, "PAM1 current should be zero"},
  {0x23, ACOM_SOFT_FAULT, "PAM1 idle current too low"},
  {0x24, ACOM_WARNING,   "PAM1 current warning"},
  {0x25, ACOM_SOFT_FAULT, "PAM1 excessive current"},
  {0x26, ACOM_SOFT_FAULT, "BIAS_1A voltage error"},
  {0x27, ACOM_SOFT_FAULT, "BIAS_1B voltage error"},
  {0x28, ACOM_SOFT_FAULT, "BIAS_1C voltage error"},
  {0x29, ACOM_SOFT_FAULT, "BIAS_1D voltage error"},
  {0x2A, ACOM_HARD_FAULT, "BIAS_1A should be zero"},
  {0x2B, ACOM_HARD_FAULT, "BIAS_1B should be zero"},
  {0x2C, ACOM_HARD_FAULT, "BIAS_1C should be zero"},
  {0x2D, ACOM_HARD_FAULT, "BIAS_1D should be zero"},
  {0x2E, ACOM_SOFT_FAULT, "PAM1 gain too low"},
  {0x2F, ACOM_SOFT_FAULT, "PAM1 gain too high"},
  {0x30, ACOM_HARD_FAULT, "PAM1 HV should be zero"},
  {0x31, ACOM_HARD_FAULT, "PAM1 current should be zero"},
  {0x32, ACOM_HARD_FAULT, "PAM1 excessive temperature"},
  {0x33, ACOM_WARNING,   "PAM1 temperature too high"},
  {0x34, ACOM_HARD_FAULT, "BIAS_1A should be zero"},
  {0x35, ACOM_HARD_FAULT, "BIAS_1B should be zero"},
  {0x36, ACOM_HARD_FAULT, "BIAS_1C should be zero"},
  {0x37, ACOM_HARD_FAULT, "BIAS_1D should be zero"},
  {0x38, ACOM_WARNING,   "PSU1 excessive temperature"},
  {0x39, ACOM_SOFT_FAULT, "PAM1 excessive current - check SWR or reduce drive power"},
  {0x40, ACOM_HARD_FAULT, "PAM2 HV too low"},
  {0x41, ACOM_HARD_FAULT, "PAM2 HV too high"},
  {0x42, ACOM_SOFT_FAULT, "PAM2 current should be zero"},
  {0x43, ACOM_SOFT_FAULT, "PAM2 idle current too low"},
  {0x44, ACOM_WARNING,   "PAM2 current warning"},
  {0x45, ACOM_SOFT_FAULT, "PAM2 excessive current"},
  {0x46, ACOM_SOFT_FAULT, "BIAS_2A voltage error"},
  {0x47, ACOM_SOFT_FAULT, "BIAS_2B voltage error"},
  {0x48, ACOM_SOFT_FAULT, "BIAS_2C voltage error"},
  {0x49, ACOM_SOFT_FAULT, "BIAS_2D voltage error"},
  {0x4A, ACOM_HARD_FAULT, "BIAS_2A should be zero"},
  {0x4B, ACOM_HARD_FAULT, "BIAS_2B should be zero"},
  {0x4C, ACOM_HARD_FAULT, "BIAS_2C should be zero"},
  {0x4D, ACOM_HARD_FAULT, "BIAS_2D should be zero"},
  {0x4E, ACOM_SOFT_FAULT, "PAM2 gain too low"},
  {0x4F, ACOM_SOFT_FAULT, "PAM2 gain too high"},
  {0x50, ACOM_HARD_FAULT, "PAM2 HV should be zero"},
  {0x51, ACOM_HARD_FAULT, "PAM2 current should be zero"},
  {0x52, ACOM_HARD_FAULT, "PAM2 excessive temperature"},
  {0x53, ACOM_WARNING,   "PAM2 temperature too high"},
  {0x54, ACOM_HARD_FAULT, "BIAS_2A should be zero"},
  {0x55, ACOM_HARD_FAULT, "BIAS_2B should be zero"},
  {0x56, ACOM_HARD_FAULT, "BIAS_2C should be zero"},
  {0x57, ACOM_HARD_FAULT, "BIAS_2D should be zero"},
  {0x58, ACOM_WARNING,   "PSU2 excessive temperature"},
  {0x59, ACOM_SOFT_FAULT, "PAM2 excessive current - check SWR or reduce drive power"},
  {0x60, ACOM_HARD_FAULT, "PSU1 / control malfunction"},
  {0x61, ACOM_HARD_FAULT, "PSU2 / control malfunction"},
  {0x62, ACOM_SOFT_FAULT, "PSU1 excessive temperature"},
  {0x63, ACOM_SOFT_FAULT, "PSU2 excessive temperature"},
  {0x64, ACOM_WARNING,   "Display unit communication error"},
  {0x65, ACOM_WARNING,   "ATU modem excessive temperature"},
  {0x66, ACOM_WARNING,   "ATU power switch alarm"},
  {0x67, ACOM_WARNING,   "ATU power switch alarm at power on"},
  {0x68, ACOM_WARNING,   "Ethernet controller not responding"},
  {0x69, ACOM_WARNING,   "Audio memory not responding"},
  {0x6C, ACOM_WARNING,   "Loss of audio data"},
  {0x6D, ACOM_WARNING,   "Loss of Ethernet settings"},
  {0x6E, ACOM_WARNING,   "Loss of EEPROM data"},
  {0x6F, ACOM_SOFT_FAULT, "Loss of EEPROM data"},
  {0x70, ACOM_WARNING,   "CAT error"},
  {0x80, ACOM_WARNING,   "ATU not responding"},
  {0x81, ACOM_WARNING,   "ATU to amplifier communication error"},
  {0x82, ACOM_WARNING,   "Amplifier to ATU communication error"},
  {0x83, ACOM_WARNING,   "ASEL not responding"},
  {0x84, ACOM_WARNING,   "ASEL to amplifier communication error"},
  {0x85, ACOM_WARNING,   "Amplifier to ASEL communication error"},
  {0x86, ACOM_WARNING,   "No tuning settings prepared"},
  {0x87, ACOM_WARNING,   "No antenna settings prepared"},
  {0x88, ACOM_WARNING,   "ATU cannot be re-tuned while RF power is present"},
  {0x89, ACOM_WARNING,   "Antenna cannot be changed while RF power is present"},
  {0x8A, ACOM_WARNING,   "ATU tuning cycle unsuccessful"},
  {0x8B, ACOM_WARNING,   "ATU memory fail"},
  {0x90, ACOM_WARNING,   "BIAS_1A out of range - if correct, select OFF"},
  {0x91, ACOM_WARNING,   "BIAS_1B out of range - if correct, select OFF"},
  {0x92, ACOM_WARNING,   "BIAS_1C out of range - if correct, select OFF"},
  {0x93, ACOM_WARNING,   "BIAS_1D out of range - if correct, select OFF"},
  {0x94, ACOM_WARNING,   "BIAS_2A out of range - if correct, select OFF"},
  {0x95, ACOM_WARNING,   "BIAS_2B out of range - if correct, select OFF"},
  {0x96, ACOM_WARNING,   "BIAS_2C out of range - if correct, select OFF"},
  {0x97, ACOM_WARNING,   "BIAS_2D out of range - if correct, select OFF"},
  {0x98, ACOM_WARNING,   "BIAS_1A above upper threshold"},
  {0x99, ACOM_WARNING,   "BIAS_1B above upper threshold"},
  {0x9A, ACOM_WARNING,   "BIAS_1C above upper threshold"},
  {0x9B, ACOM_WARNING,   "BIAS_1D above upper threshold"},
  {0x9C, ACOM_WARNING,   "BIAS_2A above upper threshold"},
  {0x9D, ACOM_WARNING,   "BIAS_2B above upper threshold"},
  {0x9E, ACOM_WARNING,   "BIAS_2C above upper threshold"},
  {0x9F, ACOM_WARNING,   "BIAS_2D above upper threshold"},
};

const size_t ACOM_FAULT_COUNT = sizeof(ACOM_FAULTS) / sizeof(ACOM_FAULTS[0]);

// Highest fault code the amplifier can report: word 9, bit 15.
#define ACOM_FAULT_CODE_MAX 0x9F

inline const AcomFault* acomFaultFor(uint8_t code) {
  size_t low = 0, high = ACOM_FAULT_COUNT;
  while (low < high) {
    size_t mid = low + (high - low) / 2;
    uint8_t midCode = ACOM_FAULTS[mid].code;
    if (midCode == code) return &ACOM_FAULTS[mid];
    if (midCode < code) low = mid + 1;
    else high = mid;
  }
  return NULL;
}

inline const char* acomFaultText(uint8_t code) {
  const AcomFault* f = acomFaultFor(code);
  return f ? f->text : NULL;
}

inline uint8_t acomFaultSeverity(uint8_t code) {
  const AcomFault* f = acomFaultFor(code);
  return f ? f->severity : ACOM_WARNING;
}

inline const char* acomSeverityName(uint8_t severity) {
  switch (severity) {
    case ACOM_SOFT_FAULT: return "soft";
    case ACOM_HARD_FAULT: return "hard";
    default:              return "warning";
  }
}

#endif  // ACOM_FAULTS_H
