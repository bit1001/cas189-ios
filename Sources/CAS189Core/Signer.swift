import Foundation

/// 与 APK `Cloud189Client.uploadRequestWithKey` 完全一致的请求签名。
///
/// 算法（源码实证）：
///   rnd       = (uuid1 去横线 + uuid2 去横线) 截断到 16...31 位
///   paramsStr = "k1=v1&k2=v2&..."            （保持参数插入顺序）
///   aesKey    = rnd 的前 16 个 UTF-8 字节
///   paramsHex = hexLower( AES-128-ECB-PKCS7( paramsStr, aesKey ) )
///   Signature = HMAC-SHA1( key: rnd,
///                  msg: "SessionKey=<sk>&Operate=<METHOD>&RequestURI=<uri>&Date=<ms>&params=<paramsHex>" )
///   EncryptionText = Base64( RSA-PKCS1v15( rnd ) )
public struct SignedRequest: Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let paramsHex: String
}

public enum Signer {

    public struct Inputs: Sendable {
        public var uri: String
        public var params: [(String, String)]
        public var sessionKey: String
        public var method: String
        public var baseURL: String
        public var rsaPubKeyB64: String
        public var rsaPkId: String

        public init(uri: String, params: [(String, String)], sessionKey: String,
                    method: String, baseURL: String = C.uploadURL,
                    rsaPubKeyB64: String, rsaPkId: String) {
            self.uri = uri
            self.params = params
            self.sessionKey = sessionKey
            self.method = method
            self.baseURL = baseURL
            self.rsaPubKeyB64 = rsaPubKeyB64
            self.rsaPkId = rsaPkId
        }
    }

    /// 生成随机串（长度 16...31）
    public static func makeRandomString() -> String {
        func hexUUID() -> String {
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let combined = hexUUID() + hexUUID()
        let length = 16 + Int.random(in: 0...15)
        return String(combined.prefix(length))
    }

    /// 参数拼接（保持顺序）
    public static func paramsString(_ pairs: [(String, String)]) -> String {
        pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    /// 纯本地可测的一部分：给定 rnd / date 生成签名（不涉及随机与 RSA 公钥解析）
    public static func signature(rnd: String, sessionKey: String, method: String,
                                 uri: String, dateMillis: String, paramsHex: String) -> String {
        let msg = "SessionKey=\(sessionKey)&Operate=\(method)&RequestURI=\(uri)"
            + "&Date=\(dateMillis)&params=\(paramsHex)"
        return CryptoTool.hmacSha1Hex(key: rnd, msg: msg, upper: false)
    }

    public static func build(_ input: Inputs,
                             rnd: String? = nil,
                             dateMillis: String? = nil,
                             requestId: String = UUID().uuidString) throws -> SignedRequest {
        let rndValue = rnd ?? makeRandomString()
        let date = dateMillis ?? String(Int(Date().timeIntervalSince1970 * 1000))

        let pStr = paramsString(input.params)
        let aesKey = String(rndValue.prefix(16))
        let paramsHex = AES128ECB.encryptHex(Data(pStr.utf8), key: aesKey)

        let sig = signature(rnd: rndValue, sessionKey: input.sessionKey, method: input.method,
                            uri: input.uri, dateMillis: date, paramsHex: paramsHex)
        let encryptionText = try CryptoTool.rsaEncryptBase64(x509PubKeyB64: input.rsaPubKeyB64,
                                                             plaintext: rndValue)

        let headers: [String: String] = [
            "SessionKey": input.sessionKey,
            "Signature": sig,
            "X-Request-Date": date,
            "X-Request-ID": requestId,
            "EncryptionText": encryptionText,
            "PkId": input.rsaPkId,
            "decodefields": C.decodeFields,
            "User-Agent": C.defaultUA,
            "Referer": C.referer,
            "Accept": "application/json;charset=UTF-8"
        ]

        guard let url = URL(string: input.baseURL + input.uri) else {
            throw CASError.missing("非法 URI: \(input.uri)")
        }
        return SignedRequest(url: url, method: input.method, headers: headers, paramsHex: paramsHex)
    }
}
