//
//  FaultCodes.swift
//  AcomControl
//
//  The ACOM fault code table, transcribed from "ACOM Protocol.pdf"
//  section 3.4.1 (message 0x21), which ships with the firmware in this
//  repository. v2.0 of this app claimed the table was unavailable and asked
//  the operator to supply their own; it was sitting next to main.cpp.
//
//  Message 0x21 is a bitfield: ten 16-bit words where bit `n` of word `k`
//  means code (k * 16) + n is active. The controller decodes it and sends
//  plain code numbers, so this table only has to name them.
//
//  Two documentation errors in the PDF are corrected here: word 9 prints its
//  codes as 0x80...0x8F, duplicating word 8 (by bit position they are
//  0x90...0x9F), and byte 14 bit 7 prints 0x3F where position gives 0x5F.
//
//  GENERATED FILE - edit tools/gen_faults.py and re-run it instead.
//

import Foundation

/// Fault code names and severities defined by the ACOM RS-232 specification.
enum ACOMFaultCodes {

    struct Entry {
        let text: String
        let severity: FaultSeverity
    }

    /// Highest code the amplifier can report: message 0x21 word 9, bit 15.
    static let maxCode = 0x9F

    static let table: [Int: Entry] = [
        0x00: Entry(text: "Hot switching attempt", severity: .warning),
        0x01: Entry(text: "Output relay closed, it should be open", severity: .warning),
        0x02: Entry(text: "Output relay open, it should be closed", severity: .hardFault),
        0x03: Entry(text: "Drive power detected at wrong time", severity: .hardFault),
        0x04: Entry(text: "Reflected power warning", severity: .warning),
        0x05: Entry(text: "Excessive reflected power", severity: .softFault),
        0x06: Entry(text: "Drive power too high", severity: .warning),
        0x07: Entry(text: "Excessive drive power", severity: .softFault),
        0x08: Entry(text: "Hot switching attempt", severity: .softFault),
        0x09: Entry(text: "Drive frequency out of range", severity: .softFault),
        0x0A: Entry(text: "Frequency violation", severity: .softFault),
        0x0B: Entry(text: "Output disbalance", severity: .softFault),
        0x0C: Entry(text: "Detected RF power at wrong time", severity: .warning),
        0x0D: Entry(text: "PA load SWR too high", severity: .softFault),
        0x0E: Entry(text: "Stop transmission first", severity: .warning),
        0x0F: Entry(text: "Remove drive power immediately", severity: .warning),
        0x10: Entry(text: "5 V too low", severity: .hardFault),
        0x11: Entry(text: "5 V too high", severity: .hardFault),
        0x12: Entry(text: "26 V too low", severity: .hardFault),
        0x13: Entry(text: "26 V too high", severity: .hardFault),
        0x15: Entry(text: "PAM1 fan speed too low", severity: .hardFault),
        0x16: Entry(text: "PAM2 fan speed too low", severity: .hardFault),
        0x17: Entry(text: "LPF fan speed too low", severity: .hardFault),
        0x18: Entry(text: "PAM1 dissipation power too high", severity: .softFault),
        0x19: Entry(text: "PAM2 dissipation power too high", severity: .softFault),
        0x1A: Entry(text: "PAM1 dissipation power warning", severity: .warning),
        0x1B: Entry(text: "PAM2 dissipation power warning", severity: .warning),
        0x1C: Entry(text: "PAM1 temperature too high", severity: .warning),
        0x1D: Entry(text: "PAM2 temperature too high", severity: .warning),
        0x1E: Entry(text: "PAM1 excessive temperature", severity: .softFault),
        0x1F: Entry(text: "PAM2 excessive temperature", severity: .softFault),
        0x20: Entry(text: "PAM1 HV too low", severity: .hardFault),
        0x21: Entry(text: "PAM1 HV too high", severity: .hardFault),
        0x22: Entry(text: "PAM1 current should be zero", severity: .softFault),
        0x23: Entry(text: "PAM1 idle current too low", severity: .softFault),
        0x24: Entry(text: "PAM1 current warning", severity: .warning),
        0x25: Entry(text: "PAM1 excessive current", severity: .softFault),
        0x26: Entry(text: "BIAS_1A voltage error", severity: .softFault),
        0x27: Entry(text: "BIAS_1B voltage error", severity: .softFault),
        0x28: Entry(text: "BIAS_1C voltage error", severity: .softFault),
        0x29: Entry(text: "BIAS_1D voltage error", severity: .softFault),
        0x2A: Entry(text: "BIAS_1A should be zero", severity: .hardFault),
        0x2B: Entry(text: "BIAS_1B should be zero", severity: .hardFault),
        0x2C: Entry(text: "BIAS_1C should be zero", severity: .hardFault),
        0x2D: Entry(text: "BIAS_1D should be zero", severity: .hardFault),
        0x2E: Entry(text: "PAM1 gain too low", severity: .softFault),
        0x2F: Entry(text: "PAM1 gain too high", severity: .softFault),
        0x30: Entry(text: "PAM1 HV should be zero", severity: .hardFault),
        0x31: Entry(text: "PAM1 current should be zero", severity: .hardFault),
        0x32: Entry(text: "PAM1 excessive temperature", severity: .hardFault),
        0x33: Entry(text: "PAM1 temperature too high", severity: .warning),
        0x34: Entry(text: "BIAS_1A should be zero", severity: .hardFault),
        0x35: Entry(text: "BIAS_1B should be zero", severity: .hardFault),
        0x36: Entry(text: "BIAS_1C should be zero", severity: .hardFault),
        0x37: Entry(text: "BIAS_1D should be zero", severity: .hardFault),
        0x38: Entry(text: "PSU1 excessive temperature", severity: .warning),
        0x39: Entry(text: "PAM1 excessive current - check SWR or reduce drive power", severity: .softFault),
        0x40: Entry(text: "PAM2 HV too low", severity: .hardFault),
        0x41: Entry(text: "PAM2 HV too high", severity: .hardFault),
        0x42: Entry(text: "PAM2 current should be zero", severity: .softFault),
        0x43: Entry(text: "PAM2 idle current too low", severity: .softFault),
        0x44: Entry(text: "PAM2 current warning", severity: .warning),
        0x45: Entry(text: "PAM2 excessive current", severity: .softFault),
        0x46: Entry(text: "BIAS_2A voltage error", severity: .softFault),
        0x47: Entry(text: "BIAS_2B voltage error", severity: .softFault),
        0x48: Entry(text: "BIAS_2C voltage error", severity: .softFault),
        0x49: Entry(text: "BIAS_2D voltage error", severity: .softFault),
        0x4A: Entry(text: "BIAS_2A should be zero", severity: .hardFault),
        0x4B: Entry(text: "BIAS_2B should be zero", severity: .hardFault),
        0x4C: Entry(text: "BIAS_2C should be zero", severity: .hardFault),
        0x4D: Entry(text: "BIAS_2D should be zero", severity: .hardFault),
        0x4E: Entry(text: "PAM2 gain too low", severity: .softFault),
        0x4F: Entry(text: "PAM2 gain too high", severity: .softFault),
        0x50: Entry(text: "PAM2 HV should be zero", severity: .hardFault),
        0x51: Entry(text: "PAM2 current should be zero", severity: .hardFault),
        0x52: Entry(text: "PAM2 excessive temperature", severity: .hardFault),
        0x53: Entry(text: "PAM2 temperature too high", severity: .warning),
        0x54: Entry(text: "BIAS_2A should be zero", severity: .hardFault),
        0x55: Entry(text: "BIAS_2B should be zero", severity: .hardFault),
        0x56: Entry(text: "BIAS_2C should be zero", severity: .hardFault),
        0x57: Entry(text: "BIAS_2D should be zero", severity: .hardFault),
        0x58: Entry(text: "PSU2 excessive temperature", severity: .warning),
        0x59: Entry(text: "PAM2 excessive current - check SWR or reduce drive power", severity: .softFault),
        0x60: Entry(text: "PSU1 / control malfunction", severity: .hardFault),
        0x61: Entry(text: "PSU2 / control malfunction", severity: .hardFault),
        0x62: Entry(text: "PSU1 excessive temperature", severity: .softFault),
        0x63: Entry(text: "PSU2 excessive temperature", severity: .softFault),
        0x64: Entry(text: "Display unit communication error", severity: .warning),
        0x65: Entry(text: "ATU modem excessive temperature", severity: .warning),
        0x66: Entry(text: "ATU power switch alarm", severity: .warning),
        0x67: Entry(text: "ATU power switch alarm at power on", severity: .warning),
        0x68: Entry(text: "Ethernet controller not responding", severity: .warning),
        0x69: Entry(text: "Audio memory not responding", severity: .warning),
        0x6C: Entry(text: "Loss of audio data", severity: .warning),
        0x6D: Entry(text: "Loss of Ethernet settings", severity: .warning),
        0x6E: Entry(text: "Loss of EEPROM data", severity: .warning),
        0x6F: Entry(text: "Loss of EEPROM data", severity: .softFault),
        0x70: Entry(text: "CAT error", severity: .warning),
        0x80: Entry(text: "ATU not responding", severity: .warning),
        0x81: Entry(text: "ATU to amplifier communication error", severity: .warning),
        0x82: Entry(text: "Amplifier to ATU communication error", severity: .warning),
        0x83: Entry(text: "ASEL not responding", severity: .warning),
        0x84: Entry(text: "ASEL to amplifier communication error", severity: .warning),
        0x85: Entry(text: "Amplifier to ASEL communication error", severity: .warning),
        0x86: Entry(text: "No tuning settings prepared", severity: .warning),
        0x87: Entry(text: "No antenna settings prepared", severity: .warning),
        0x88: Entry(text: "ATU cannot be re-tuned while RF power is present", severity: .warning),
        0x89: Entry(text: "Antenna cannot be changed while RF power is present", severity: .warning),
        0x8A: Entry(text: "ATU tuning cycle unsuccessful", severity: .warning),
        0x8B: Entry(text: "ATU memory fail", severity: .warning),
        0x90: Entry(text: "BIAS_1A out of range - if correct, select OFF", severity: .warning),
        0x91: Entry(text: "BIAS_1B out of range - if correct, select OFF", severity: .warning),
        0x92: Entry(text: "BIAS_1C out of range - if correct, select OFF", severity: .warning),
        0x93: Entry(text: "BIAS_1D out of range - if correct, select OFF", severity: .warning),
        0x94: Entry(text: "BIAS_2A out of range - if correct, select OFF", severity: .warning),
        0x95: Entry(text: "BIAS_2B out of range - if correct, select OFF", severity: .warning),
        0x96: Entry(text: "BIAS_2C out of range - if correct, select OFF", severity: .warning),
        0x97: Entry(text: "BIAS_2D out of range - if correct, select OFF", severity: .warning),
        0x98: Entry(text: "BIAS_1A above upper threshold", severity: .warning),
        0x99: Entry(text: "BIAS_1B above upper threshold", severity: .warning),
        0x9A: Entry(text: "BIAS_1C above upper threshold", severity: .warning),
        0x9B: Entry(text: "BIAS_1D above upper threshold", severity: .warning),
        0x9C: Entry(text: "BIAS_2A above upper threshold", severity: .warning),
        0x9D: Entry(text: "BIAS_2B above upper threshold", severity: .warning),
        0x9E: Entry(text: "BIAS_2C above upper threshold", severity: .warning),
        0x9F: Entry(text: "BIAS_2D above upper threshold", severity: .warning),
    ]

    /// Specification text for a code, or nil when the code is one the
    /// specification leaves unnamed.
    static func text(for code: Int) -> String? { table[code]?.text }

    /// Severity for a code. Unnamed codes are treated as warnings, which is
    /// how the amplifier groups every code the specification does not label.
    static func severity(for code: Int) -> FaultSeverity {
        table[code]?.severity ?? .unknown
    }
}
