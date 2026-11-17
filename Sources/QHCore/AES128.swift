import Foundation

/// AES decryption (128/192/256, ECB block + CBC mode), pure Swift so the same code
/// runs on Linux CI, iOS and macOS without CommonCrypto/OpenSSL bridging.
/// Only decryption is implemented — clients never encrypt.
public struct AES {
    public let keySize: Int
    private let rounds: Int
    private let roundKeys: [UInt8]

    public init(key: [UInt8]) throws {
        switch key.count {
        case 16, 24, 32: break
        default: throw QHError.crypto("AES key must be 16/24/32 bytes, got \(key.count)")
        }
        keySize = key.count
        rounds = key.count / 4 + 6
        roundKeys = AES.expandKey(key)
    }

    public var blockSize: Int { 16 }

    public func decryptBlock(_ input: [UInt8]) throws -> [UInt8] {
        guard input.count == 16 else { throw QHError.crypto("block must be 16 bytes") }
        var s = input
        for i in 0..<16 { s[i] ^= roundKeys[rounds * 16 + i] }
        var round = rounds - 1
        while round >= 1 {
            invShiftRows(&s)
            invSubBytes(&s)
            for i in 0..<16 { s[i] ^= roundKeys[round * 16 + i] }
            invMixColumns(&s)
            round -= 1
        }
        invShiftRows(&s)
        invSubBytes(&s)
        for i in 0..<16 { s[i] ^= roundKeys[i] }
        return s
    }

    /// CBC decryption. When `removePadding` is true, validates and strips PKCS#7.
    public func decryptCBC(_ data: [UInt8], iv: [UInt8], removePadding: Bool = false) throws -> [UInt8] {
        guard iv.count == 16 else { throw QHError.crypto("IV must be 16 bytes") }
        let usable = data.count - (data.count % 16)
        guard usable > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: usable)
        var prev = iv
        var offset = 0
        while offset < usable {
            let block = Array(data[offset..<(offset + 16)])
            let dec = try decryptBlock(block)
            for i in 0..<16 { out[offset + i] = dec[i] ^ prev[i] }
            prev = block
            offset += 16
        }
        guard removePadding, let pad = out.last else { return out }
        let n = Int(pad)
        guard n >= 1, n <= 16, n <= out.count, out.suffix(n).allSatisfy({ $0 == pad }) else {
            throw QHError.crypto("bad PKCS#7 padding")
        }
        return Array(out.dropLast(n))
    }


    // MARK: - encryption (Douyin needs AES-192-CBC in both directions)

    public func encryptBlock(_ input: [UInt8]) throws -> [UInt8] {
        guard input.count == 16 else { throw QHError.crypto("block must be 16 bytes") }
        var s = input
        for i in 0..<16 { s[i] ^= roundKeys[i] }
        for round in 1..<rounds {
            subBytes(&s)
            shiftRows(&s)
            mixColumns(&s)
            for i in 0..<16 { s[i] ^= roundKeys[round * 16 + i] }
        }
        subBytes(&s)
        shiftRows(&s)
        for i in 0..<16 { s[i] ^= roundKeys[rounds * 16 + i] }
        return s
    }

    /// CBC encryption with PKCS#7 padding (Java's AES/CBC/PKCS5Padding is the same for 16-byte blocks).
    public func encryptCBC(_ data: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        guard iv.count == 16 else { throw QHError.crypto("IV must be 16 bytes") }
        var input = data
        let pad = 16 - (data.count % 16)
        input.append(contentsOf: [UInt8](repeating: UInt8(pad), count: pad))
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        var prev = iv
        var offset = 0
        while offset < input.count {
            var block = Array(input[offset..<(offset + 16)])
            for i in 0..<16 { block[i] ^= prev[i] }
            let enc = try encryptBlock(block)
            out.append(contentsOf: enc)
            prev = enc
            offset += 16
        }
        return out
    }

    private func subBytes(_ s: inout [UInt8]) {
        for i in 0..<16 { s[i] = AES.sbox[Int(s[i])] }
    }

    private func shiftRows(_ s: inout [UInt8]) {
        var t = s
        for r in 0..<4 {
            for c in 0..<4 {
                t[c * 4 + r] = s[((c + r) % 4) * 4 + r]
            }
        }
        s = t
    }

    private func mixColumns(_ s: inout [UInt8]) {
        for c in 0..<4 {
            let i = c * 4
            let a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3]
            s[i]     = AES.mul(a0, 2) ^ AES.mul(a1, 3) ^ a2 ^ a3
            s[i + 1] = a0 ^ AES.mul(a1, 2) ^ AES.mul(a2, 3) ^ a3
            s[i + 2] = a0 ^ a1 ^ AES.mul(a2, 2) ^ AES.mul(a3, 3)
            s[i + 3] = AES.mul(a0, 3) ^ a1 ^ a2 ^ AES.mul(a3, 2)
        }
    }

    // MARK: - key schedule

    private static let sbox: [UInt8] = [
        0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
        0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
        0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
        0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
        0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
        0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
        0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
        0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
        0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
        0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
        0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
        0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
        0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
        0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
        0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
        0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
    ]

    private static let invSbox: [UInt8] = {
        var inv = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { inv[Int(sbox[i])] = UInt8(i) }
        return inv
    }()

    private static let rcon: [UInt8] = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]

    private static func expandKey(_ key: [UInt8]) -> [UInt8] {
        let nk = key.count / 4
        let total = 16 * (nk + 7)
        var w = [UInt8](repeating: 0, count: total)
        for i in 0..<key.count { w[i] = key[i] }
        var i = key.count
        var rconIndex = 0
        while i < total {
            var temp = Array(w[(i - 4)..<i])
            if i % key.count == 0 {
                temp = [temp[1], temp[2], temp[3], temp[0]]
                for j in 0..<4 { temp[j] = sbox[Int(temp[j])] }
                temp[0] ^= rcon[rconIndex]
                rconIndex += 1
            } else if nk > 6 && i % key.count == 16 {
                for j in 0..<4 { temp[j] = sbox[Int(temp[j])] }
            }
            for j in 0..<4 {
                w[i + j] = w[i + j - key.count] ^ temp[j]
            }
            i += 4
        }
        return w
    }

    private func invSubBytes(_ s: inout [UInt8]) {
        for i in 0..<16 { s[i] = AES.invSbox[Int(s[i])] }
    }

    private func invShiftRows(_ s: inout [UInt8]) {
        // state is column-major: s[c*4 + r]
        var t = s
        for r in 0..<4 {
            for c in 0..<4 {
                t[((c + r) % 4) * 4 + r] = s[c * 4 + r]
            }
        }
        s = t
    }

    private func invMixColumns(_ s: inout [UInt8]) {
        for c in 0..<4 {
            let i = c * 4
            let a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3]
            s[i]     = AES.mul(a0, 14) ^ AES.mul(a1, 11) ^ AES.mul(a2, 13) ^ AES.mul(a3, 9)
            s[i + 1] = AES.mul(a0, 9)  ^ AES.mul(a1, 14) ^ AES.mul(a2, 11) ^ AES.mul(a3, 13)
            s[i + 2] = AES.mul(a0, 13) ^ AES.mul(a1, 9)  ^ AES.mul(a2, 14) ^ AES.mul(a3, 11)
            s[i + 3] = AES.mul(a0, 11) ^ AES.mul(a1, 13) ^ AES.mul(a2, 9)  ^ AES.mul(a3, 14)
        }
    }

    private static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var x = a
        var y = b
        while y > 0 {
            if y & 1 == 1 { result ^= x }
            let hi = x & 0x80
            x <<= 1
            if hi != 0 { x ^= 0x1b }
            y >>= 1
        }
        return result
    }
}

/// Backwards-compatible alias for the HLS path (AES-128 only there).
public typealias AES128 = AES
