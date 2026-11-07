import Foundation

public struct CloudEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let size: Int64
    public let isFolder: Bool
    public let md5: String?
    public let parentId: String?
    /// 缩略图直链（listFiles 带 iconOption=5 时返回，可直接 GET，无需 Cookie）
    public let iconURL: String?

    public init(id: String, name: String, size: Int64, isFolder: Bool,
                md5: String? = nil, parentId: String? = nil, iconURL: String? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.isFolder = isFolder
        self.md5 = md5
        self.parentId = parentId
        self.iconURL = iconURL
    }
}

public struct CloudFolder: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let parentId: String?
}

public struct FamilyInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
}

/// 一个待秒传的文件（来自 BT 种子或本地文件）
public struct CasItem: Identifiable, Sendable, Equatable {
    public var id: String { fileMd5 + ":" + String(size) }
    public let name: String
    public let size: Int64
    public let fileMd5: String
    public let sliceMd5: String
    public let sliceSize: Int
    /// 每个分片的 MD5（大写），BT 种子场景下可直接复用
    public let parts: [String]

    public init(name: String, size: Int64, fileMd5: String, sliceMd5: String,
                sliceSize: Int = C.sliceSize, parts: [String] = []) {
        self.name = name
        self.size = size
        self.fileMd5 = fileMd5
        self.sliceMd5 = sliceMd5
        self.sliceSize = sliceSize
        self.parts = parts
    }
}

public struct RapidResult: Sendable, Equatable {
    public let ok: Bool
    public let message: String
    public let uploadFileId: String?
    public init(ok: Bool, message: String, uploadFileId: String? = nil) {
        self.ok = ok; self.message = message; self.uploadFileId = uploadFileId
    }
}

public struct ShareResult: Sendable, Equatable {
    public let ok: Bool
    public let message: String
    public let shareId: String?
    public init(ok: Bool, message: String, shareId: String? = nil) {
        self.ok = ok; self.message = message; self.shareId = shareId
    }
}

/// 登录状态：sessionKey 用于签名接口，cookie 用于 web 接口
public struct Session: Sendable, Equatable, Codable {
    public var sessionKey: String
    public var sessionSecret: String
    public var rsaPubKey: String
    public var rsaPkId: String
    public var loginName: String
    public var deviceId: String
    public var cookies: [String: String]

    public init(sessionKey: String = "", sessionSecret: String = "",
                rsaPubKey: String = "", rsaPkId: String = "",
                loginName: String = "", deviceId: String = "",
                cookies: [String: String] = [:]) {
        self.sessionKey = sessionKey
        self.sessionSecret = sessionSecret
        self.rsaPubKey = rsaPubKey
        self.rsaPkId = rsaPkId
        self.loginName = loginName
        self.deviceId = deviceId
        self.cookies = cookies
    }

    public var isLoggedIn: Bool { !sessionKey.isEmpty }
}
