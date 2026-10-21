#!/usr/bin/env python3
"""Generate the ACOM fault-code tables for the firmware and the macOS app.

Single source of truth, transcribed from "ACOM Protocol.pdf" section 3.4.1
(message 0x21, Error Codes 0..9).  Message 0x21 carries ten 16-bit words; bit
`n` of word `k` means fault code (k * 16) + n is active.

Two documentation errors in the PDF are corrected here:
  * Word 9 (bytes 21/22) prints its codes as 0x80..0x8F, duplicating word 8.
    By position they are 0x90..0x9F.
  * Byte 14 bit 7 prints (0x3F); by position it is 0x5F (and is unnamed).
Codes are therefore derived from bit position, never from the printed label.

W = warning (transmission continues), S = soft fault (reverts to standby),
H = hard fault (supply shuts down).
"""

# code -> (severity, text)
FAULTS = {
    # --- Error Codes 0 (bytes 3/4) -----------------------------------------
    0x00: ("W", "Hot switching attempt"),
    0x01: ("W", "Output relay closed, it should be open"),
    0x02: ("H", "Output relay open, it should be closed"),
    0x03: ("H", "Drive power detected at wrong time"),
    0x04: ("W", "Reflected power warning"),
    0x05: ("S", "Excessive reflected power"),
    0x06: ("W", "Drive power too high"),
    0x07: ("S", "Excessive drive power"),
    0x08: ("S", "Hot switching attempt"),
    0x09: ("S", "Drive frequency out of range"),
    0x0A: ("S", "Frequency violation"),
    0x0B: ("S", "Output disbalance"),
    0x0C: ("W", "Detected RF power at wrong time"),
    0x0D: ("S", "PA load SWR too high"),
    0x0E: ("W", "Stop transmission first"),
    0x0F: ("W", "Remove drive power immediately"),
    # --- Error Codes 1 (bytes 5/6) -----------------------------------------
    0x10: ("H", "5 V too low"),
    0x11: ("H", "5 V too high"),
    0x12: ("H", "26 V too low"),
    0x13: ("H", "26 V too high"),
    # 0x14 unnamed in the specification
    0x15: ("H", "PAM1 fan speed too low"),
    0x16: ("H", "PAM2 fan speed too low"),
    0x17: ("H", "LPF fan speed too low"),
    0x18: ("S", "PAM1 dissipation power too high"),
    0x19: ("S", "PAM2 dissipation power too high"),
    0x1A: ("W", "PAM1 dissipation power warning"),
    0x1B: ("W", "PAM2 dissipation power warning"),
    0x1C: ("W", "PAM1 temperature too high"),
    0x1D: ("W", "PAM2 temperature too high"),
    0x1E: ("S", "PAM1 excessive temperature"),
    0x1F: ("S", "PAM2 excessive temperature"),
    # --- Error Codes 2 (bytes 7/8) -----------------------------------------
    0x20: ("H", "PAM1 HV too low"),
    0x21: ("H", "PAM1 HV too high"),
    0x22: ("S", "PAM1 current should be zero"),
    0x23: ("S", "PAM1 idle current too low"),
    0x24: ("W", "PAM1 current warning"),
    0x25: ("S", "PAM1 excessive current"),
    0x26: ("S", "BIAS_1A voltage error"),
    0x27: ("S", "BIAS_1B voltage error"),
    0x28: ("S", "BIAS_1C voltage error"),
    0x29: ("S", "BIAS_1D voltage error"),
    0x2A: ("H", "BIAS_1A should be zero"),
    0x2B: ("H", "BIAS_1B should be zero"),
    0x2C: ("H", "BIAS_1C should be zero"),
    0x2D: ("H", "BIAS_1D should be zero"),
    0x2E: ("S", "PAM1 gain too low"),
    0x2F: ("S", "PAM1 gain too high"),
    # --- Error Codes 3 (bytes 9/10) ----------------------------------------
    0x30: ("H", "PAM1 HV should be zero"),
    0x31: ("H", "PAM1 current should be zero"),
    0x32: ("H", "PAM1 excessive temperature"),
    0x33: ("W", "PAM1 temperature too high"),
    0x34: ("H", "BIAS_1A should be zero"),
    0x35: ("H", "BIAS_1B should be zero"),
    0x36: ("H", "BIAS_1C should be zero"),
    0x37: ("H", "BIAS_1D should be zero"),
    0x38: ("W", "PSU1 excessive temperature"),
    0x39: ("S", "PAM1 excessive current - check SWR or reduce drive power"),
    # 0x3A..0x3F unnamed in the specification
    # --- Error Codes 4 (bytes 11/12) ---------------------------------------
    0x40: ("H", "PAM2 HV too low"),
    0x41: ("H", "PAM2 HV too high"),
    0x42: ("S", "PAM2 current should be zero"),
    0x43: ("S", "PAM2 idle current too low"),
    0x44: ("W", "PAM2 current warning"),
    0x45: ("S", "PAM2 excessive current"),
    0x46: ("S", "BIAS_2A voltage error"),
    0x47: ("S", "BIAS_2B voltage error"),
    0x48: ("S", "BIAS_2C voltage error"),
    0x49: ("S", "BIAS_2D voltage error"),
    0x4A: ("H", "BIAS_2A should be zero"),
    0x4B: ("H", "BIAS_2B should be zero"),
    0x4C: ("H", "BIAS_2C should be zero"),
    0x4D: ("H", "BIAS_2D should be zero"),
    0x4E: ("S", "PAM2 gain too low"),
    0x4F: ("S", "PAM2 gain too high"),
    # --- Error Codes 5 (bytes 13/14) ---------------------------------------
    0x50: ("H", "PAM2 HV should be zero"),
    0x51: ("H", "PAM2 current should be zero"),
    0x52: ("H", "PAM2 excessive temperature"),
    0x53: ("W", "PAM2 temperature too high"),
    0x54: ("H", "BIAS_2A should be zero"),
    0x55: ("H", "BIAS_2B should be zero"),
    0x56: ("H", "BIAS_2C should be zero"),
    0x57: ("H", "BIAS_2D should be zero"),
    0x58: ("W", "PSU2 excessive temperature"),
    0x59: ("S", "PAM2 excessive current - check SWR or reduce drive power"),
    # 0x5A..0x5F unnamed in the specification
    # --- Error Codes 6 (bytes 15/16) ---------------------------------------
    0x60: ("H", "PSU1 / control malfunction"),
    0x61: ("H", "PSU2 / control malfunction"),
    0x62: ("S", "PSU1 excessive temperature"),
    0x63: ("S", "PSU2 excessive temperature"),
    0x64: ("W", "Display unit communication error"),
    0x65: ("W", "ATU modem excessive temperature"),
    0x66: ("W", "ATU power switch alarm"),
    0x67: ("W", "ATU power switch alarm at power on"),
    0x68: ("W", "Ethernet controller not responding"),
    0x69: ("W", "Audio memory not responding"),
    # 0x6A, 0x6B unnamed in the specification
    0x6C: ("W", "Loss of audio data"),
    0x6D: ("W", "Loss of Ethernet settings"),
    0x6E: ("W", "Loss of EEPROM data"),
    0x6F: ("S", "Loss of EEPROM data"),
    # --- Error Codes 7 (bytes 17/18) ---------------------------------------
    0x70: ("W", "CAT error"),
    # 0x71..0x7F unnamed in the specification
    # --- Error Codes 8 (bytes 19/20) ---------------------------------------
    0x80: ("W", "ATU not responding"),
    0x81: ("W", "ATU to amplifier communication error"),
    0x82: ("W", "Amplifier to ATU communication error"),
    0x83: ("W", "ASEL not responding"),
    0x84: ("W", "ASEL to amplifier communication error"),
    0x85: ("W", "Amplifier to ASEL communication error"),
    0x86: ("W", "No tuning settings prepared"),
    0x87: ("W", "No antenna settings prepared"),
    # The specification prints no severity for 0x88; it sits among warnings.
    0x88: ("W", "ATU cannot be re-tuned while RF power is present"),
    0x89: ("W", "Antenna cannot be changed while RF power is present"),
    0x8A: ("W", "ATU tuning cycle unsuccessful"),
    0x8B: ("W", "ATU memory fail"),
    # 0x8C..0x8F unnamed in the specification
    # --- Error Codes 9 (bytes 21/22) ---------------------------------------
    # Printed as 0x80..0x8F in the PDF; by bit position they are 0x90..0x9F.
    0x90: ("W", "BIAS_1A out of range - if correct, select OFF"),
    0x91: ("W", "BIAS_1B out of range - if correct, select OFF"),
    0x92: ("W", "BIAS_1C out of range - if correct, select OFF"),
    0x93: ("W", "BIAS_1D out of range - if correct, select OFF"),
    0x94: ("W", "BIAS_2A out of range - if correct, select OFF"),
    0x95: ("W", "BIAS_2B out of range - if correct, select OFF"),
    0x96: ("W", "BIAS_2C out of range - if correct, select OFF"),
    0x97: ("W", "BIAS_2D out of range - if correct, select OFF"),
    0x98: ("W", "BIAS_1A above upper threshold"),
    0x99: ("W", "BIAS_1B above upper threshold"),
    0x9A: ("W", "BIAS_1C above upper threshold"),
    0x9B: ("W", "BIAS_1D above upper threshold"),
    0x9C: ("W", "BIAS_2A above upper threshold"),
    0x9D: ("W", "BIAS_2B above upper threshold"),
    0x9E: ("W", "BIAS_2C above upper threshold"),
    0x9F: ("W", "BIAS_2D above upper threshold"),
}

SEV_ENUM = {"W": "ACOM_WARNING", "S": "ACOM_SOFT_FAULT", "H": "ACOM_HARD_FAULT"}
SEV_SWIFT = {"W": ".warning", "S": ".softFault", "H": ".hardFault"}

HEADER_DOC = """/*
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
"""


def c_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def gen_header():
    out = [HEADER_DOC, "", "#ifndef ACOM_FAULTS_H", "#define ACOM_FAULTS_H", "",
           "#include <Arduino.h>", "",
           "// Fault severity, as defined by the amplifier's three protection levels.",
           "enum AcomFaultSeverity : uint8_t {",
           "  ACOM_WARNING    = 0,  // transmission continues",
           "  ACOM_SOFT_FAULT = 1,  // amplifier reverts to standby",
           "  ACOM_HARD_FAULT = 2,  // amplifier shuts its supply down",
           "};", "",
           "struct AcomFault {",
           "  uint8_t code;",
           "  uint8_t severity;",
           "  const char* text;",
           "};", "",
           "// Sorted by code so lookups can binary search.",
           "const AcomFault ACOM_FAULTS[] PROGMEM = {"]
    for code in sorted(FAULTS):
        sev, text = FAULTS[code]
        out.append('  {0x%02X, %-15s "%s"},' % (code, SEV_ENUM[sev] + ",", c_escape(text)))
    out += ["};", "",
            "const size_t ACOM_FAULT_COUNT = sizeof(ACOM_FAULTS) / sizeof(ACOM_FAULTS[0]);",
            "",
            "// Highest fault code the amplifier can report: word 9, bit 15.",
            "#define ACOM_FAULT_CODE_MAX 0x9F",
            "",
            "inline const AcomFault* acomFaultFor(uint8_t code) {",
            "  size_t low = 0, high = ACOM_FAULT_COUNT;",
            "  while (low < high) {",
            "    size_t mid = low + (high - low) / 2;",
            "    uint8_t midCode = ACOM_FAULTS[mid].code;",
            "    if (midCode == code) return &ACOM_FAULTS[mid];",
            "    if (midCode < code) low = mid + 1;",
            "    else high = mid;",
            "  }",
            "  return NULL;",
            "}",
            "",
            "inline const char* acomFaultText(uint8_t code) {",
            "  const AcomFault* f = acomFaultFor(code);",
            "  return f ? f->text : NULL;",
            "}",
            "",
            "inline uint8_t acomFaultSeverity(uint8_t code) {",
            "  const AcomFault* f = acomFaultFor(code);",
            "  return f ? f->severity : ACOM_WARNING;",
            "}",
            "",
            "inline const char* acomSeverityName(uint8_t severity) {",
            "  switch (severity) {",
            "    case ACOM_SOFT_FAULT: return \"soft\";",
            "    case ACOM_HARD_FAULT: return \"hard\";",
            "    default:              return \"warning\";",
            "  }",
            "}",
            "",
            "#endif  // ACOM_FAULTS_H"]
    return "\n".join(out) + "\n"


def swift_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def gen_swift():
    out = ["//",
           "//  FaultCodes.swift",
           "//  AcomControl",
           "//",
           "//  The ACOM fault code table, transcribed from \"ACOM Protocol.pdf\"",
           "//  section 3.4.1 (message 0x21), which ships with the firmware in this",
           "//  repository. v2.0 of this app claimed the table was unavailable and asked",
           "//  the operator to supply their own; it was sitting next to main.cpp.",
           "//",
           "//  Message 0x21 is a bitfield: ten 16-bit words where bit `n` of word `k`",
           "//  means code (k * 16) + n is active. The controller decodes it and sends",
           "//  plain code numbers, so this table only has to name them.",
           "//",
           "//  Two documentation errors in the PDF are corrected here: word 9 prints its",
           "//  codes as 0x80...0x8F, duplicating word 8 (by bit position they are",
           "//  0x90...0x9F), and byte 14 bit 7 prints 0x3F where position gives 0x5F.",
           "//",
           "//  GENERATED FILE - edit tools/gen_faults.py and re-run it instead.",
           "//",
           "",
           "import Foundation",
           "",
           "/// Fault code names and severities defined by the ACOM RS-232 specification.",
           "enum ACOMFaultCodes {",
           "",
           "    struct Entry {",
           "        let text: String",
           "        let severity: FaultSeverity",
           "    }",
           "",
           "    /// Highest code the amplifier can report: message 0x21 word 9, bit 15.",
           "    static let maxCode = 0x9F",
           "",
           "    static let table: [Int: Entry] = ["]
    for code in sorted(FAULTS):
        sev, text = FAULTS[code]
        out.append('        0x%02X: Entry(text: "%s", severity: %s),'
                   % (code, swift_escape(text), SEV_SWIFT[sev]))
    out += ["    ]",
            "",
            "    /// Specification text for a code, or nil when the code is one the",
            "    /// specification leaves unnamed.",
            "    static func text(for code: Int) -> String? { table[code]?.text }",
            "",
            "    /// Severity for a code. Unnamed codes are treated as warnings, which is",
            "    /// how the amplifier groups every code the specification does not label.",
            "    static func severity(for code: Int) -> FaultSeverity {",
            "        table[code]?.severity ?? .unknown",
            "    }",
            "}"]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    import os
    import sys

    root = sys.argv[1]
    header = os.path.join(root, "Arduino (ESP32) code/AcomControl/src/acom_faults.h")
    swift = os.path.join(root, "Mac OSX (Xcode) app/AcomControl/FaultCodes.swift")
    tools = os.path.join(root, "tools")
    os.makedirs(tools, exist_ok=True)

    with open(header, "w") as f:
        f.write(gen_header())
    with open(swift, "w") as f:
        f.write(gen_swift())

    print("named codes: %d" % len(FAULTS))
    counts = {}
    for sev, _ in FAULTS.values():
        counts[sev] = counts.get(sev, 0) + 1
    print("by severity: %s" % counts)
    print("wrote %s" % header)
    print("wrote %s" % swift)
