//
//  E2EEEdwards.swift
//  XMPPChatCore
//
//  Ed25519 public key -> X25519 (Montgomery u) conversion for X3DH.
//  CryptoKit has no such map, so this is the one piece of field arithmetic in the
//  port. It computes u = (1 + y) / (1 - y) mod p, p = 2^255 - 19, the same formula
//  as noble-curves' ed25519.utils.toMontgomery. Numbers are little-endian arrays of
//  16-bit limbs held in UInt64, so every intermediate product stays exact.
//  Covered by known-answer vectors generated from the web implementation.
//

import Foundation

enum E2EEEdwards {

    private typealias Limbs = [UInt64]
    private static let mask16: UInt64 = 0xffff

    /// p = 2^255 - 19 as 16 limbs.
    private static let prime: Limbs = {
        var p = [UInt64](repeating: 0xffff, count: 16)
        p[0] = 0xffed   // 2^255 - 19: low limb 0xffff - 18
        p[15] = 0x7fff  // top limb holds bits 240..254
        return p
    }()

    /// The Montgomery u-coordinate of an Ed25519 public key, or nil when 1 - y = 0.
    static func montgomeryU(edwardsPublicKey pub: Data) -> Data? {
        guard pub.count == 32 else { return nil }
        // y is the little-endian encoding with the sign bit (bit 255) cleared.
        var yBytes = Array(pub)
        yBytes[31] &= 0x7f
        let y = reduce(limbs(fromLittleEndian: yBytes))

        let one: Limbs = [1]
        let numerator = reduce(add(one, y))
        // 1 - y mod p, computed as (p + 1) - y, which is always non-negative.
        let denominator = reduce(subtract(add(prime, one), y))
        if isZero(denominator) { return nil }
        let u = mulMod(numerator, invert(denominator))
        return littleEndian(from: u)
    }

    // MARK: - Limb arithmetic

    private static func limbs(fromLittleEndian bytes: [UInt8]) -> Limbs {
        var out = Limbs(repeating: 0, count: bytes.count / 2 + bytes.count % 2)
        for (index, byte) in bytes.enumerated() {
            out[index / 2] |= UInt64(byte) << (8 * UInt64(index % 2))
        }
        return out
    }

    private static func littleEndian(from value: Limbs) -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in 0..<32 {
            let limb = index / 2 < value.count ? value[index / 2] : 0
            bytes[index] = UInt8((limb >> (8 * UInt64(index % 2))) & 0xff)
        }
        return Data(bytes)
    }

    /// Carry-propagates so every limb is below 2^16.
    private static func normalize(_ input: Limbs) -> Limbs {
        var out = input
        var carry: UInt64 = 0
        var index = 0
        while index < out.count || carry > 0 {
            if index == out.count { out.append(0) }
            let total = out[index] + carry
            out[index] = total & mask16
            carry = total >> 16
            index += 1
        }
        return out
    }

    private static func add(_ a: Limbs, _ b: Limbs) -> Limbs {
        let length = max(a.count, b.count)
        var out = Limbs(repeating: 0, count: length)
        for index in 0..<length {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            out[index] = x + y
        }
        return normalize(out)
    }

    /// a - b for a >= b.
    private static func subtract(_ a: Limbs, _ b: Limbs) -> Limbs {
        let length = max(a.count, b.count)
        var out = Limbs(repeating: 0, count: length)
        var borrow: Int64 = 0
        for index in 0..<length {
            let x = Int64(index < a.count ? a[index] : 0)
            let y = Int64(index < b.count ? b[index] : 0)
            var diff = x - y - borrow
            if diff < 0 {
                diff += 1 << 16
                borrow = 1
            } else {
                borrow = 0
            }
            out[index] = UInt64(diff)
        }
        return out
    }

    private static func compare(_ a: Limbs, _ b: Limbs) -> Int {
        let length = max(a.count, b.count)
        var index = length - 1
        while index >= 0 {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x < y ? -1 : 1 }
            index -= 1
        }
        return 0
    }

    private static func isZero(_ a: Limbs) -> Bool {
        a.allSatisfy { $0 == 0 }
    }

    private static func multiply(_ a: Limbs, _ b: Limbs) -> Limbs {
        var out = Limbs(repeating: 0, count: a.count + b.count)
        for i in 0..<a.count where a[i] != 0 {
            for j in 0..<b.count {
                out[i + j] += a[i] * b[j]
            }
        }
        return normalize(out)
    }

    /// Reduces a value of any size below p. Uses 2^255 = 19 (mod p) to fold the high
    /// bits down, then subtracts p while the result is still at least p.
    private static func reduce(_ input: Limbs) -> Limbs {
        var value = normalize(input)
        while true {
            let high = shiftRight255(value)
            if isZero(high) { break }
            let low = mask255(value)
            value = add(low, multiplySmall(high, 19))
        }
        while compare(value, prime) >= 0 {
            value = subtract(value, prime)
        }
        return value
    }

    private static func multiplySmall(_ a: Limbs, _ factor: UInt64) -> Limbs {
        normalize(a.map { $0 * factor })
    }

    /// bits 255 and above, shifted down by 255.
    private static func shiftRight255(_ a: Limbs) -> Limbs {
        // 255 = 15 * 16 + 15
        var out = Limbs(repeating: 0, count: max(1, a.count - 15))
        for index in 0..<out.count {
            let low = index + 15 < a.count ? a[index + 15] : 0
            let high = index + 16 < a.count ? a[index + 16] : 0
            out[index] = ((low >> 15) | (high << 1)) & mask16
        }
        return out
    }

    /// bits 0..254 (the value modulo 2^255).
    private static func mask255(_ a: Limbs) -> Limbs {
        var out = Limbs(repeating: 0, count: 16)
        for index in 0..<15 where index < a.count {
            out[index] = a[index]
        }
        if a.count > 15 {
            out[15] = a[15] & 0x7fff
        }
        return out
    }

    private static func mulMod(_ a: Limbs, _ b: Limbs) -> Limbs {
        reduce(multiply(a, b))
    }

    /// a^(p-2) mod p, the Fermat inverse. p - 2 has every bit set from 0 to 254
    /// except bits 2 and 4 (since p - 2 = 2^255 - 21).
    private static func invert(_ a: Limbs) -> Limbs {
        var result: Limbs = [1]
        for bit in stride(from: 254, through: 0, by: -1) {
            result = mulMod(result, result)
            if bit != 2 && bit != 4 {
                result = mulMod(result, a)
            }
        }
        return result
    }
}
