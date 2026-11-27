/// 3270 data stream constants (IBM GA23-0059).
public enum DS {
    /// Inbound/outbound commands. Both the local (CCW) and SNA codes are accepted.
    public enum Command {
        public static let write: Set<UInt8> = [0x01, 0xF1]
        public static let eraseWrite: Set<UInt8> = [0x05, 0xF5]
        public static let eraseWriteAlternate: Set<UInt8> = [0x0D, 0x7E]
        public static let readBuffer: Set<UInt8> = [0x02, 0xF2]
        public static let readModified: Set<UInt8> = [0x06, 0xF6]
        public static let readModifiedAll: Set<UInt8> = [0x0E, 0x6E]
        public static let eraseAllUnprotected: Set<UInt8> = [0x0F, 0x6F]
        public static let writeStructuredField: Set<UInt8> = [0x11, 0xF3]
        public static let nop: UInt8 = 0x03
    }

    /// Orders embedded in Write data.
    public enum Order {
        public static let startField: UInt8 = 0x1D
        public static let startFieldExtended: UInt8 = 0x29
        public static let setBufferAddress: UInt8 = 0x11
        public static let setAttribute: UInt8 = 0x28
        public static let modifyField: UInt8 = 0x2C
        public static let insertCursor: UInt8 = 0x13
        public static let programTab: UInt8 = 0x05
        public static let repeatToAddress: UInt8 = 0x3C
        public static let eraseUnprotectedToAddress: UInt8 = 0x12
        public static let graphicEscape: UInt8 = 0x08
    }

    /// Write Control Character bits.
    public enum WCC {
        public static let reset: UInt8 = 0x40
        public static let soundAlarm: UInt8 = 0x04
        public static let keyboardRestore: UInt8 = 0x02
        public static let resetMDT: UInt8 = 0x01
    }

    /// Field attribute bits.
    public enum FieldAttribute {
        public static let protected: UInt8 = 0x20
        public static let numeric: UInt8 = 0x10
        public static let displayMask: UInt8 = 0x0C
        public static let intensified: UInt8 = 0x08
        public static let nonDisplay: UInt8 = 0x0C
        public static let modified: UInt8 = 0x01
    }

    /// Extended attribute types used by SFE / SA / MF.
    public enum ExtendedAttribute {
        public static let all: UInt8 = 0x00
        public static let fieldAttribute: UInt8 = 0xC0
        public static let highlighting: UInt8 = 0x41
        public static let foreground: UInt8 = 0x42
        public static let charset: UInt8 = 0x43
        public static let background: UInt8 = 0x45
        public static let transparency: UInt8 = 0x46
    }

    /// Attention identifiers.
    public enum AID {
        public static let none: UInt8 = 0x60
        public static let structuredField: UInt8 = 0x88
        public static let enter: UInt8 = 0x7D
        public static let clear: UInt8 = 0x6D
        public static let pa1: UInt8 = 0x6C
        public static let pa2: UInt8 = 0x6E
        public static let pa3: UInt8 = 0x6B
        public static let sysreq: UInt8 = 0xF0
        public static let pf: [UInt8] = [
            0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0x7A, 0x7B, 0x7C,
            0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0x4A, 0x4B, 0x4C,
        ]

        /// Short-read AIDs only transmit the AID byte on Read Modified.
        public static func isShortRead(_ aid: UInt8) -> Bool {
            aid == clear || aid == pa1 || aid == pa2 || aid == pa3 || aid == sysreq
        }
    }

    /// Structured field identifiers.
    public enum StructuredField {
        public static let readPartition: UInt8 = 0x01
        public static let eraseReset: UInt8 = 0x03
        public static let outbound3270DS: UInt8 = 0x40
        public static let queryReply: UInt8 = 0x81

        public static let readPartitionQuery: UInt8 = 0x02
        public static let readPartitionQueryList: UInt8 = 0x03
    }

    /// Query reply codes.
    public enum QueryCode {
        public static let summary: UInt8 = 0x80
        public static let usableArea: UInt8 = 0x81
        public static let characterSets: UInt8 = 0x85
        public static let color: UInt8 = 0x86
        public static let highlighting: UInt8 = 0x87
        public static let replyModes: UInt8 = 0x88
        public static let implicitPartition: UInt8 = 0xA6
        public static let null: UInt8 = 0xFF
    }

    /// The 6-bit translation table used for 12-bit addresses and attribute bytes.
    public static let codeTable: [UInt8] = [
        0x40, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F,
        0x50, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F,
        0x60, 0x61, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F,
        0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0x7A, 0x7B, 0x7C, 0x7D, 0x7E, 0x7F,
    ]

    /// Decodes a two byte 12/14-bit buffer address.
    public static func decodeAddress(_ high: UInt8, _ low: UInt8) -> Int {
        if high & 0xC0 == 0 {
            return (Int(high & 0x3F) << 8) | Int(low)
        }
        return (Int(high & 0x3F) << 6) | Int(low & 0x3F)
    }

    /// Encodes a buffer address. 12-bit encoding is used when the buffer
    /// fits in 4096 positions, otherwise 14-bit binary encoding.
    public static func encodeAddress(_ address: Int, bufferSize: Int) -> [UInt8] {
        if bufferSize <= 4096 {
            return [codeTable[(address >> 6) & 0x3F], codeTable[address & 0x3F]]
        }
        return [UInt8((address >> 8) & 0x3F), UInt8(address & 0xFF)]
    }
}
