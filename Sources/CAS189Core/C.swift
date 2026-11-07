import Foundation

/// 天翼云盘接口常量（对齐 APK 中 com.ty189.cas.C）
public enum C {
    public static let appId = "9317140619"
    public static let accountType = "02"
    public static let clientType = "10020"
    public static let pc = "TELEPC"
    public static let version = "7.2.4.0"
    public static let channelId = "web_cloud.189.cn"

    /// 秒传分片大小：10 MB
    public static let sliceSize = 10 * 1024 * 1024

    public static let webURL = "https://cloud.189.cn"
    public static let apiURL = "https://api.cloud.189.cn"
    /// 注意：秒传/上传签名接口打在 upload 子域，不是 api 子域
    public static let uploadURL = "https://upload.cloud.189.cn"
    public static let authURL = "https://open.e.189.cn"
    public static let returnURL = "https://m.cloud.189.cn/zhuanti/2020/loginErrorPc/index.html"

    public static let decodeFields =
        "familyId,parentFolderId,fileName,fileMd5,fileSize,sliceMd5,sliceSize,albumId,extend,lazyCheck,isLog"

    public static let defaultUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    public static let referer = "https://cloud.189.cn/web/main"
}

public enum CASError: LocalizedError {
    case http(Int, String)
    case api(code: String, message: String)
    case sessionExpired(String)
    case securityRejected(String)
    case notDecompilable(String)
    case missing(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .http(code, body): return "HTTP \(code): \(body.prefix(300))"
        case let .api(code, message): return "接口错误 \(code): \(message)"
        case let .sessionExpired(msg): return "登录已失效: \(msg)"
        case let .securityRejected(msg): return "云端安全校验未通过: \(msg)"
        case let .notDecompilable(what): return "计算失败: \(what)"
        case let .missing(what): return "缺少: \(what)"
        case let .unsupported(what): return "当前平台不支持: \(what)"
        }
    }
}
