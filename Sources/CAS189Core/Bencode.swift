import Foundation

/// 极简 bencode 编解码（BitTorrent 用），纯 Swift，Linux / iOS 通用。
/// 只支持 torrent 需要的四种类型：整数、字节串、列表、字典。
public enum Bencode {

    public indirect enum Value: Equatable, Sendable {
        public static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case let (.int(a), .int(b)): return a == b
            case let (.bytes(a), .bytes(b)): return a == b
            case let (.list(a), .list(b)): return a == b
            case let (.dict(a), .dict(b)):
                guard a.count == b.count else { return false }
                for (i, pair) in a.enumerated() where pair.0 != b[i].0 || pair.1 != b[i].1 { return false }
                return true
            default: return false
            }
        }

        case int(Int)
        case bytes(Data)
        case list([Value])
        case dict([(String, Value)])

        public var stringValue: String? {
            if case let .bytes(d) = self { return String(data: d, encoding: .utf8) }
            return nil
        }
        public var intValue: Int? {
            if case let .int(i) = self { return i }
            return nil
        }
        public var listValue: [Value]? {
            if case let .list(l) = self { return l }
            return nil
        }
        public var dictValue: [(String, Value)]? {
            if case let .dict(d) = self { return d }
            return nil
        }

        /// 便捷构造：字符串 → bytes（供字典里的 `.str("x")` 简写使用）
        public static func str(_ s: String) -> Value { .bytes(Data(s.utf8)) }
        /// 字典取键（bencode 字典无序，这里按 key 线性查）
        public func get(_ key: String) -> Value? {
            guard case let .dict(pairs) = self else { return nil }
            for (k, v) in pairs where k == key { return v }
            return nil
        }
    }

    // MARK: - Decode

    public struct DecodeError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static func decode(_ data: Data) throws -> Value {
        var idx = data.startIndex
        let value = try parse(data, &idx)
        return value
    }

    private static func parse(_ data: Data, _ idx: inout Data.Index) throws -> Value {
        guard idx < data.endIndex else {
            throw DecodeError(message: "bencode 意外结束")
        }
        let c = data[idx]

        switch c {
        case UInt8(ascii: "i"):                       // i123e
            idx = data.index(after: idx)
            let start = idx
            while idx < data.endIndex, data[idx] != UInt8(ascii: "e") { idx = data.index(after: idx) }
            guard idx < data.endIndex else { throw DecodeError(message: "整数缺少结尾 e") }
            let text = String(decoding: data[start..<idx], as: UTF8.self)
            idx = data.index(after: idx)
            guard let n = Int(text) else { throw DecodeError(message: "非法整数：\(text)") }
            return .int(n)

        case UInt8(ascii: "l"):                       // l...e
            idx = data.index(after: idx)
            var items: [Value] = []
            while idx < data.endIndex, data[idx] != UInt8(ascii: "e") {
                items.append(try parse(data, &idx))
            }
            guard idx < data.endIndex else { throw DecodeError(message: "列表缺少结尾 e") }
            idx = data.index(after: idx)
            return .list(items)

        case UInt8(ascii: "d"):                       // d...e
            idx = data.index(after: idx)
            var pairs: [(String, Value)] = []
            while idx < data.endIndex, data[idx] != UInt8(ascii: "e") {
                let key = try parse(data, &idx)
                guard let k = key.stringValue else {
                    throw DecodeError(message: "字典 key 不是字节串")
                }
                let value = try parse(data, &idx)
                pairs.append((k, value))
            }
            guard idx < data.endIndex else { throw DecodeError(message: "字典缺少结尾 e") }
            idx = data.index(after: idx)
            return .dict(pairs)

        case UInt8(ascii: "0")...UInt8(ascii: "9"):   // 4:spam
            var len = 0
            while idx < data.endIndex, data[idx] != UInt8(ascii: ":") {
                guard let digit = Int(String(UnicodeScalar(data[idx]))), data[idx] >= 48, data[idx] <= 57 else {
                    throw DecodeError(message: "非法字节串长度")
                }
                len = len * 10 + digit
                idx = data.index(after: idx)
            }
            guard idx < data.endIndex else { throw DecodeError(message: "字节串缺少冒号") }
            idx = data.index(after: idx)              // skip ':'
            guard let end = data.index(idx, offsetBy: len, limitedBy: data.endIndex) else {
                throw DecodeError(message: "字节串长度越界（要 \(len)）")
            }
            let bytes = Data(data[idx..<end])
            idx = end
            return .bytes(bytes)

        default:
            throw DecodeError(message: "未知的 bencode 前缀：0x\(String(c, radix: 16))")
        }
    }

    // MARK: - Encode

    public static func encode(_ value: Value) -> Data {
        var out = Data()
        encodeInto(value, &out)
        return out
    }

    private static func encodeInto(_ value: Value, _ out: inout Data) {
        switch value {
        case let .int(i):
            out.append(contentsOf: Array("i\(i)e".utf8))
        case let .bytes(d):
            out.append(contentsOf: Array("\(d.count):".utf8))
            out.append(d)
        case let .list(items):
            out.append(UInt8(ascii: "l"))
            for item in items { encodeInto(item, &out) }
            out.append(UInt8(ascii: "e"))
        case let .dict(pairs):
            out.append(UInt8(ascii: "d"))
            // bencode 字典按 key 的字典序编码
            for (k, v) in pairs.sorted(by: { $0.0 < $1.0 }) {
                encodeInto(.bytes(Data(k.utf8)), &out)
                encodeInto(v, &out)
            }
            out.append(UInt8(ascii: "e"))
        }
    }

    /// 便捷构造
    public static func dict(_ pairs: [(String, Value)]) -> Value { .dict(pairs) }
    public static func str(_ s: String) -> Value { .bytes(Data(s.utf8)) }
}
