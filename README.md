# 189秒传 iOS 复刻 (CAS189)

把 Android 版「189云盘秒传 v1.51」的核心逻辑（天翼云盘 PC 接口 + SS2022 风格签名 + 秒传两段式）用 Swift 重写。
逆向依据见 `189秒传-逆向报告与iOS复刻方案.md` 与 `189秒传-v1.51-反编译源码.zip`。

## 目录

```
Package.swift              # CAS189Core 跨平台包（Linux 可编译可测）
Sources/CAS189Core/
  C.swift                  # 常量（appId / 版本 / 分片 10MB / 域名）
  Crypto.swift             # MD5、SHA1、HMAC-SHA1、分片指纹、RSA(PKCS1 v1.5)
  AES.swift                # 纯 Swift AES-128/ECB/PKCS7（CryptoKit 不提供 ECB）
  Signer.swift             # 与 uploadRequestWithKey 一致的请求签名
  Transport.swift          # URLSession + 自管 Cookie + 302 拦截
  Cloud189Client.swift     # 登录 / 会话 / 目录 / 列表 / 签名接口
  Rapid.swift              # 秒传：initMultiUpload → commitMultiUploadFile
  Models.swift
Tests/CAS189CoreTests/     # 标准向量测试（MD5/SHA1/HMAC/AES/FIPS-197）
App/                       # SwiftUI 外壳（xcodegen 生成 Xcode 工程）
.github/workflows/ios.yml  # CI：Linux 跑单测 + macOS 编译未签名 app
```

## 本地跑（Linux，无 Xcode）

```bash
# 需要 Swift 6 工具链
swift test
```

## 出 app（需要 macOS 或 GitHub Actions）

```bash
brew install xcodegen
cd App && xcodegen generate
open CAS189.xcodeproj        # 或用 xcodebuild 编译
```

CI 里 `build-app` job 会产出未签名的 `CAS189.app`（模拟器架构），可从 artifacts 下载。

## 已实现

- [x] Cookie 登录（`COOKIE_LOGIN_USER` → `getUserBriefInfo.action` 换 sessionKey）
- [x] 账号密码登录（RSA/PKCS1 + 图形验证码 + `getSessionForPC.action`，仅 Apple 平台可跑 RSA）
- [x] 签名接口（AES-128-ECB + HMAC-SHA1 + RSA(EncryptionText) + `decodefields`）
- [x] 目录浏览 / 新建目录（web 通道，只要 Cookie）
- [x] 本地文件指纹（10MB 分片 MD5，并发）+ 秒传命中判定
- [x] SwiftUI：登录 / 云盘浏览 / 选文件秒传 / 日志

## 未实现 / 已知限制

- [ ] 真实分片上传（秒传未命中时的 `uploadPart` 兜底）——当前会明确提示"需要真实上传"
- [ ] 分享链接转存（`shareEntries` / `shareOne`，含 9 次重试与频控）
- [ ] BT 种子 / 磁力解析（`Bencode` + 分片 MD5 复用）
- [ ] 压缩包解包（rar/7z，需要第三方 C 库）
- [ ] WKWebView 内嵌登录（当前是粘贴 Cookie）
- [ ] 家庭云（`familyId` / `/family/*` 接口）
- [ ] Keychain 持久化会话（当前仅内存）

## 关键算法（与服务端对齐）

```
sliceSize = 10MB
每个分片 MD5（大写） → 拼接后 MD5（大写）= sliceMd5；单分片时 sliceMd5 = 该分片 MD5
initMultiUpload 返回 fileDataExists==1 → 云端已有内容
commitMultiUploadFile = 落库，0 字节流量完成

签名：
  rnd        = 随机 16~31 位
  paramsHex  = hex(AES-128-ECB-PKCS7(paramsString, key=rnd[0:16]))
  Signature  = HMAC-SHA1(key=rnd,
                 "SessionKey=..&Operate=..&RequestURI=..&Date=<ms>&params=<paramsHex>")
  EncryptionText = Base64(RSA-PKCS1(rnd))
请求地址：https://upload.cloud.189.cn + /person|/family + /initMultiUpload|/commitMultiUploadFile
```
