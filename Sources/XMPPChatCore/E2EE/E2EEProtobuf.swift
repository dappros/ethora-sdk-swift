//
//  E2EEProtobuf.swift
//  XMPPChatCore
//
//  Hand-written codec for the three OMEMO 2 protobuf messages (XEP-0384 section 7).
//  Byte-compatible with ethora-chat-component/src/e2ee/protobuf.ts.
//
//  message OMEMOMessage { required uint32 n = 1; required uint32 pn = 2;
//    required bytes dh_pub = 3; optional bytes ciphertext = 4; }
//  message OMEMOAuthenticatedMessage { required bytes mac = 1; required bytes message = 2; }
//  message OMEMOKeyExchange { required uint32 pk_id = 1; required uint32 spk_id = 2;
//    required bytes ik = 3; required bytes ek = 4; required OMEMOAuthenticatedMessage message = 5; }
//

import Foundation

enum E2EEProtobufError: Error, LocalizedError, Equatable {
    case truncated
    case varintTooLong
    case unsupportedWireType(Int)
    case missingField(Int)
    case invalidUint32(Int)

    var errorDescription: String? {
        switch self {
        case .truncated: return "Truncated protobuf message"
        case .varintTooLong: return "Protobuf varint too long"
        case .unsupportedWireType(let type): return "Unsupported protobuf wire type \(type)"
        case .missingField(let field): return "Missing protobuf field \(field)"
        case .invalidUint32(let value): return "Invalid uint32 \(value)"
        }
    }
}

struct E2EEOmemoMessage: Equatable {
    var n: UInt32
    var pn: UInt32
    var dhPub: Data
    var ciphertext: Data?
}

struct E2EEAuthenticatedMessage: Equatable {
    var mac: Data
    var message: Data
}

struct E2EEKeyExchangeMessage: Equatable {
    var pkId: UInt32
    var spkId: UInt32
    var ik: Data
    var ek: Data
    var message: Data
}

enum E2EEProtobuf {

    private static let varintWire = 0
    private static let fixed64Wire = 1
    private static let bytesWire = 2
    private static let fixed32Wire = 5

    // MARK: - Writer

    private struct Writer {
        var out = Data()

        mutating func uint(_ field: Int, _ value: UInt32) {
            appendVarint(UInt64((field << 3) | varintWire))
            appendVarint(UInt64(value))
        }

        mutating func bytes(_ field: Int, _ value: Data?) {
            guard let value else { return }
            appendVarint(UInt64((field << 3) | bytesWire))
            appendVarint(UInt64(value.count))
            out.append(value)
        }

        private mutating func appendVarint(_ value: UInt64) {
            var v = value
            while v > 0x7f {
                out.append(UInt8(v & 0x7f) | 0x80)
                v >>= 7
            }
            out.append(UInt8(v))
        }
    }

    // MARK: - Reader

    /// Last value of each field; unknown fields are skipped.
    private enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private static func read(_ buf: Data) throws -> [Int: Value] {
        var fields: [Int: Value] = [:]
        let bytes = [UInt8](buf)
        var pos = 0

        func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            for _ in 0..<10 {
                guard pos < bytes.count else { throw E2EEProtobufError.truncated }
                let b = bytes[pos]
                pos += 1
                result |= UInt64(b & 0x7f) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
            throw E2EEProtobufError.varintTooLong
        }

        func skip(_ length: Int) throws {
            guard length >= 0, pos + length <= bytes.count else { throw E2EEProtobufError.truncated }
            pos += length
        }

        while pos < bytes.count {
            let tag = try readVarint()
            let field = Int(tag >> 3)
            switch Int(tag & 7) {
            case varintWire:
                fields[field] = .varint(try readVarint())
            case bytesWire:
                let length = try readVarint()
                guard length <= UInt64(bytes.count) else { throw E2EEProtobufError.truncated }
                let start = pos
                try skip(Int(length))
                fields[field] = .bytes(Data(bytes[start..<pos]))
            case fixed64Wire:
                try skip(8)
            case fixed32Wire:
                try skip(4)
            default:
                throw E2EEProtobufError.unsupportedWireType(Int(tag & 7))
            }
        }
        return fields
    }

    private static func requireUInt(_ fields: [Int: Value], _ field: Int) throws -> UInt32 {
        guard case .varint(let value)? = fields[field], value <= UInt64(UInt32.max) else {
            throw E2EEProtobufError.missingField(field)
        }
        return UInt32(value)
    }

    private static func requireBytes(_ fields: [Int: Value], _ field: Int) throws -> Data {
        guard case .bytes(let value)? = fields[field] else { throw E2EEProtobufError.missingField(field) }
        return value
    }

    private static func optionalBytes(_ fields: [Int: Value], _ field: Int) -> Data? {
        if case .bytes(let value)? = fields[field] { return value }
        return nil
    }

    // MARK: - OMEMOMessage

    static func encodeMessage(_ message: E2EEOmemoMessage) -> Data {
        var w = Writer()
        w.uint(1, message.n)
        w.uint(2, message.pn)
        w.bytes(3, message.dhPub)
        w.bytes(4, message.ciphertext)
        return w.out
    }

    static func decodeMessage(_ buf: Data) throws -> E2EEOmemoMessage {
        let f = try read(buf)
        return E2EEOmemoMessage(
            n: try requireUInt(f, 1),
            pn: try requireUInt(f, 2),
            dhPub: try requireBytes(f, 3),
            ciphertext: optionalBytes(f, 4)
        )
    }

    // MARK: - OMEMOAuthenticatedMessage

    static func encodeAuthenticated(_ message: E2EEAuthenticatedMessage) -> Data {
        var w = Writer()
        w.bytes(1, message.mac)
        w.bytes(2, message.message)
        return w.out
    }

    static func decodeAuthenticated(_ buf: Data) throws -> E2EEAuthenticatedMessage {
        let f = try read(buf)
        return E2EEAuthenticatedMessage(
            mac: try requireBytes(f, 1),
            message: try requireBytes(f, 2)
        )
    }

    // MARK: - OMEMOKeyExchange

    static func encodeKeyExchange(_ message: E2EEKeyExchangeMessage) -> Data {
        var w = Writer()
        w.uint(1, message.pkId)
        w.uint(2, message.spkId)
        w.bytes(3, message.ik)
        w.bytes(4, message.ek)
        w.bytes(5, message.message)
        return w.out
    }

    static func decodeKeyExchange(_ buf: Data) throws -> E2EEKeyExchangeMessage {
        let f = try read(buf)
        return E2EEKeyExchangeMessage(
            pkId: try requireUInt(f, 1),
            spkId: try requireUInt(f, 2),
            ik: try requireBytes(f, 3),
            ek: try requireBytes(f, 4),
            message: try requireBytes(f, 5)
        )
    }
}
